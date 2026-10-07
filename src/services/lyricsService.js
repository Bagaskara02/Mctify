/**
 * LRCLIB Synced Lyrics Service & Word-by-Word Karaoke Engine
 * Inspired by surfbryce/beautiful-lyrics & Apple Music
 */

const lyricsMemoryCache = new Map();

export const lyricsService = {
  /**
   * Clean titles and artists of streaming/YouTube noise
   */
  cleanTitleAndArtist(rawTitle, rawArtist) {
    let title = (rawTitle || '').trim();
    let artist = (rawArtist || '').trim();

    // Strip common YouTube & streaming tags
    title = title.replace(/\s*[\(\[](official\s*(music\s*)?video|audio|mv|visualizer|lyric(s)?(\s*video)?|remastered|single|hd|4k|session|brooklyn session|10 years)[\)\]]/gi, '');
    title = title.replace(/\s*(feat\.|ft\.)\s+[^-\(\]]+/gi, '');
    title = title.replace(/[◐◑]/g, '').trim();

    if (title.includes(' - ')) {
      const parts = title.split(' - ');
      if (parts.length === 2) {
        if (artist && parts[0].toLowerCase().includes(artist.toLowerCase())) {
          title = parts[1].trim();
        } else if (artist && parts[1].toLowerCase().includes(artist.toLowerCase())) {
          title = parts[0].trim();
        }
      }
    }

    title = title.replace(/\(.*?\)|\[.*?\]/g, '').replace(/[\(\)\[\]]/g, '').trim();
    artist = artist.replace(/\(.*?\)|\[.*?\]/g, '').replace(/[\(\)\[\]]/g, '').trim();
    return { title, artist };
  },

  /**
   * Fetch synced or plain lyrics from LRCLIB with 0ms in-memory cache
   */
  async fetchLyrics(rawArtist, rawTitle, duration) {
    if (!rawTitle) return null;

    const { title: cleanTitle, artist: cleanArtist } = this.cleanTitleAndArtist(rawTitle, rawArtist);
    const cacheKey = `${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}`;

    if (lyricsMemoryCache.has(cacheKey)) {
      return lyricsMemoryCache.get(cacheKey);
    }

    // 1. Try exact match first without duration (duration mismatch causes LRCLIB 503)
    try {
      const params = new URLSearchParams({
        track_name: cleanTitle,
        artist_name: cleanArtist,
      });

      const res = await fetch(`https://lrclib.net/api/get?${params.toString()}`);
      if (res.ok) {
        const data = await res.json();
        if (data && (data.syncedLyrics || data.plainLyrics)) {
          const result = {
            synced: !!data.syncedLyrics,
            lines: data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlain(data.plainLyrics),
            source: 'LRCLIB',
            instrumental: data.instrumental || false,
          };
          lyricsMemoryCache.set(cacheKey, result);
          return result;
        }
      }
    } catch (e) {
      console.warn('LRCLIB exact lookup failed, trying search fallback', e);
    }

    // 2. Try search query fallback
    try {
      const q = encodeURIComponent(`${cleanTitle} ${cleanArtist}`.trim());
      const res = await fetch(`https://lrclib.net/api/search?q=${q}`);
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          const best = list.find(item => item.syncedLyrics) || list[0];
          if (best && (best.syncedLyrics || best.plainLyrics)) {
            const result = {
              synced: !!best.syncedLyrics,
              lines: best.syncedLyrics ? this.parseLrc(best.syncedLyrics) : this.parsePlain(best.plainLyrics),
              source: 'LRCLIB (Search)',
              instrumental: best.instrumental || false,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB search lookup failed', e);
    }

    return null;
  },

  /**
   * Parse timestamped LRC string into structured line objects
   * Computes precise word-by-word karaoke timing tokens for every line!
   */
  parseLrc(lrcText) {
    if (!lrcText) return [];

    const rawLines = lrcText.split('\n');
    const parsed = [];
    const timeRegex = /\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]/g;

    for (let i = 0; i < rawLines.length; i++) {
      const rawLine = rawLines[i].trim();
      if (!rawLine) continue;

      const timestamps = [];
      let match;
      timeRegex.lastIndex = 0;

      while ((match = timeRegex.exec(rawLine)) !== null) {
        const min = parseInt(match[1], 10);
        const sec = parseInt(match[2], 10);
        const msStr = match[3] || '0';
        const ms = msStr.length === 2 ? parseInt(msStr, 10) * 10 : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
        const totalSeconds = min * 60 + sec + ms / 1000;
        timestamps.push(totalSeconds);
      }

      if (timestamps.length === 0) continue;

      const cleanText = rawLine.replace(/\[\d{2}:\d{2}(?:\.\d{2,3})?\]/g, '').trim();
      if (!cleanText) continue;

      const isBackgroundVocal = /^\(.*\)$/.test(cleanText) || /^\[.*\]$/.test(cleanText);

      timestamps.forEach(time => {
        parsed.push({
          id: `line-${time}-${i}`,
          time,
          text: cleanText.replace(/<\d{2}:\d{2}(?:\.\d{2,3})?>/g, '').trim(),
          rawText: cleanText,
          isBackgroundVocal,
        });
      });
    }

    parsed.sort((a, b) => a.time - b.time);

    // Compute line durations and word-level karaoke intervals
    const withWordTimings = [];
    for (let i = 0; i < parsed.length; i++) {
      const curr = parsed[i];
      const next = parsed[i + 1];

      // Instrumental intro check
      if (i === 0 && curr.time > 7) {
        withWordTimings.push({
          id: 'instrumental-intro',
          time: 1,
          endTime: curr.time - 0.5,
          text: '♪  Intro  ♪',
          isInstrumental: true,
          words: [],
        });
      }

      const lineDuration = next ? Math.min(8, Math.max(1.2, next.time - curr.time)) : 5;
      curr.duration = lineDuration;
      curr.endTime = curr.time + lineDuration;

      // Tokenize line into animated word objects
      curr.words = this.computeWordTimings(curr.text, curr.time, lineDuration);
      withWordTimings.push(curr);

      // Instrumental break between lines if gap > 8 seconds
      if (next && (next.time - curr.endTime) > 7) {
        withWordTimings.push({
          id: `instrumental-${curr.time}`,
          time: curr.endTime + 0.5,
          endTime: next.time - 0.5,
          text: '♪  Instrumental  ♪',
          isInstrumental: true,
          words: [],
        });
      }
    }

    return withWordTimings;
  },

  /**
   * Compute word-by-word timestamps for Apple Music / Beautiful Lyrics karaoke
   */
  computeWordTimings(lineText, lineStart, lineDuration) {
    if (!lineText) return [];

    const rawWords = lineText.split(/\s+/).filter(w => w.length > 0);
    if (rawWords.length === 0) return [];

    // Calculate weight based on character count
    const totalChars = rawWords.reduce((sum, w) => sum + Math.max(1, w.length), 0);
    const activeSingingDuration = Math.max(0.8, lineDuration * 0.92); // leave small pause at end

    let currentOffset = 0;
    return rawWords.map((word, idx) => {
      const wordWeight = Math.max(1, word.length) / totalChars;
      const wordDuration = Math.max(0.2, activeSingingDuration * wordWeight);
      const startTime = lineStart + currentOffset;
      const endTime = startTime + wordDuration;
      currentOffset += wordDuration;

      return {
        id: `word-${idx}-${startTime}`,
        word,
        startTime,
        endTime,
        duration: wordDuration,
      };
    });
  },

  /**
   * Parse plain lyrics
   */
  parsePlain(plainText) {
    if (!plainText) return [];
    return plainText.split('\n').map((line, idx) => {
      const time = idx * 4;
      return {
        id: `plain-${idx}`,
        time,
        text: line.trim(),
        duration: 4,
        words: this.computeWordTimings(line.trim(), time, 4),
        isPlain: true,
      };
    }).filter(l => l.text.length > 0);
  },
};
