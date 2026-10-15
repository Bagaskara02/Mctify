/**
 * Mctify Spicy Lyrics Service & Adaptive Karaoke Engine
 * Features:
 * 1. Enhanced LRC parsing (<mm:ss.xx>word) & Smart Word + Character Timing Generator
 * 2. Character-level interpolation with punctuation pause weighting
 * 3. Instrumental interlude detection (intro > 4s or gap > 4.5s)
 * 4. Adaptive Song Style & Vibe Auto-Detector (Ballad, Pop, Kinetic/Rap, Chill)
 * 5. High-accuracy multi-tier search matching & duration proximity scoring
 */

const lyricsMemoryCache = new Map();
const STORAGE_KEY_SYNC_OFFSETS = 'mcmusic_lyrics_sync_offsets';

export const lyricsService = {
  /**
   * Get persistent sync calibration offset for a specific track.
   */
  getTrackSyncOffset(trackKey) {
    try {
      if (!trackKey) return null;
      const raw = localStorage.getItem(STORAGE_KEY_SYNC_OFFSETS);
      if (raw) {
        const map = JSON.parse(raw);
        if (typeof map[trackKey] === 'number') {
          return map[trackKey];
        }
      }
      return null;
    } catch {
      return null;
    }
  },

  /**
   * Save persistent sync calibration offset for a specific track
   */
  saveTrackSyncOffset(trackKey, offset) {
    try {
      if (!trackKey) return;
      const raw = localStorage.getItem(STORAGE_KEY_SYNC_OFFSETS);
      const map = raw ? JSON.parse(raw) : {};
      map[trackKey] = Math.round(offset * 10) / 10;
      localStorage.setItem(STORAGE_KEY_SYNC_OFFSETS, JSON.stringify(map));
    } catch (e) {
      console.warn('Failed to save track sync offset', e);
    }
  },

  /**
   * Remove persistent sync calibration offset to return to Auto-Sync
   */
  removeTrackSyncOffset(trackKey) {
    try {
      if (!trackKey) return;
      const raw = localStorage.getItem(STORAGE_KEY_SYNC_OFFSETS);
      if (raw) {
        const map = JSON.parse(raw);
        delete map[trackKey];
        localStorage.setItem(STORAGE_KEY_SYNC_OFFSETS, JSON.stringify(map));
      }
    } catch (e) {
      console.warn('Failed to remove track sync offset', e);
    }
  },

  /**
   * Calculate intelligent auto-sync offset based on LRC [offset: xxx] tags
   * and YouTube audio stream vs studio metadata duration differential.
   */
  calculateAutoSyncOffset(syncedLyrics, targetDuration, trackDuration) {
    let offset = 0;
    if (syncedLyrics) {
      const match = syncedLyrics.match(/\[offset:\s*([+-]?\d+)\]/i);
      if (match) {
        offset += parseInt(match[1], 10) / 1000;
      }
    }
    if (targetDuration && trackDuration) {
      const diff = targetDuration - trackDuration;
      if (diff >= 0.3 && diff <= 3.5) {
        offset -= Math.min(0.4, diff * 0.2);
      } else if (diff <= -0.3 && diff >= -3.5) {
        offset += Math.min(0.4, Math.abs(diff) * 0.2);
      }
    }
    return Math.round(offset * 10) / 10;
  },

  /**
   * Clean titles and artists of streaming/YouTube noise
   */
  cleanTitleAndArtist(rawTitle, rawArtist) {
    let title = (rawTitle || '').trim();
    let artist = (rawArtist || '').trim();

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
   * Detect song style to provide adaptive lyric animations
   * Returns: 'ballad' | 'pop' | 'kinetic' | 'chill'
   */
  detectSongStyle(title = '', artist = '', lines = [], duration = 180) {
    const text = `${title} ${artist}`.toLowerCase();

    // 1. Keyword overrides
    if (/\b(acoustic|akustik|piano|orchestra|slowed|sad|gundah|galau|heartbreak|sleep|lullaby)\b/i.test(text)) {
      return 'ballad';
    }
    if (/\b(rap|hip[\s-]?hop|drill|trap|freestyle|diss|sped up|rock|metal|punk)\b/i.test(text)) {
      return 'kinetic';
    }
    if (/\b(chill|lofi|lo-fi|r&b|soul|jazz|indie|night|vibes|ambient|relaxed)\b/i.test(text)) {
      return 'chill';
    }
    if (/\b(remix|dance|edm|party|club|upbeat|disco|electronic|house|pop)\b/i.test(text)) {
      return 'pop';
    }

    // 2. Cadence analysis (Words per second across synced lines)
    if (lines && lines.length > 2) {
      let totalWords = 0;
      let activeSingingSeconds = 0;
      for (const line of lines) {
        if (!line.isInstrumental && line.words?.length > 0) {
          totalWords += line.words.length;
          activeSingingSeconds += Math.max(0.5, line.duration || 2.0);
        }
      }

      const wordsPerSec = activeSingingSeconds > 0 ? (totalWords / activeSingingSeconds) : 1.2;
      if (wordsPerSec >= 2.8) return 'kinetic'; // Rap / fast lyrics
      if (wordsPerSec >= 1.6) return 'pop';     // Standard energetic pop
      if (wordsPerSec <= 0.95) return 'ballad';  // Slow emotional ballad
      return 'chill';                           // Medium relaxed groove
    }

    return 'pop';
  },

  /**
   * Fetch synced or plain lyrics from LRCLIB with multi-tier duration-aware matching
   */
  async fetchLyrics(rawArtist, rawTitle, duration) {
    if (!rawTitle) return null;

    const { title: cleanTitle, artist: cleanArtist } = this.cleanTitleAndArtist(rawTitle, rawArtist);
    const targetDuration = (typeof duration === 'number' && Number.isFinite(duration) && duration > 5)
      ? Math.round(duration)
      : null;

    const cacheKey = `${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}:::${targetDuration || 0}`;

    if (lyricsMemoryCache.has(cacheKey)) {
      return lyricsMemoryCache.get(cacheKey);
    }

    // TIER 1: Exact lookup with Duration parameter
    if (targetDuration) {
      try {
        const params = new URLSearchParams({
          track_name: cleanTitle,
          artist_name: cleanArtist,
          duration: String(targetDuration),
        });

        const res = await fetch(`https://lrclib.net/api/get?${params.toString()}`);
        if (res.ok) {
          const data = await res.json();
          if (data && (data.syncedLyrics || data.plainLyrics)) {
            const autoOffset = this.calculateAutoSyncOffset(data.syncedLyrics, targetDuration, data.duration);
            const parsedLines = data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlain(data.plainLyrics);
            const detectedStyle = this.detectSongStyle(cleanTitle, cleanArtist, parsedLines, targetDuration);

            const result = {
              synced: !!data.syncedLyrics,
              lines: parsedLines,
              source: 'LRCLIB (Exact Duration Match)',
              instrumental: data.instrumental || false,
              trackDuration: data.duration,
              autoOffset,
              detectedStyle,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      } catch (e) {
        console.warn('LRCLIB exact lookup with duration failed, continuing to Tier 2', e);
      }
    }

    // TIER 2: Exact lookup without duration
    try {
      const params = new URLSearchParams({
        track_name: cleanTitle,
        artist_name: cleanArtist,
      });

      const res = await fetch(`https://lrclib.net/api/get?${params.toString()}`);
      if (res.ok) {
        const data = await res.json();
        if (data && (data.syncedLyrics || data.plainLyrics)) {
          const isDurationAcceptable = !targetDuration || !data.duration || Math.abs(data.duration - targetDuration) <= 12;
          if (isDurationAcceptable) {
            const autoOffset = this.calculateAutoSyncOffset(data.syncedLyrics, targetDuration, data.duration);
            const parsedLines = data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlain(data.plainLyrics);
            const detectedStyle = this.detectSongStyle(cleanTitle, cleanArtist, parsedLines, targetDuration);

            const result = {
              synced: !!data.syncedLyrics,
              lines: parsedLines,
              source: 'LRCLIB (Exact Name Match)',
              instrumental: data.instrumental || false,
              trackDuration: data.duration,
              autoOffset,
              detectedStyle,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB exact lookup without duration failed, continuing to search', e);
    }

    // TIER 3: Smart Search with Duration-Ranked Scoring
    try {
      const q = encodeURIComponent(`${cleanTitle} ${cleanArtist}`.trim());
      const res = await fetch(`https://lrclib.net/api/search?q=${q}`);
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          const best = this.pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration);
          if (best && (best.syncedLyrics || best.plainLyrics)) {
            const autoOffset = this.calculateAutoSyncOffset(best.syncedLyrics, targetDuration, best.duration);
            const parsedLines = best.syncedLyrics ? this.parseLrc(best.syncedLyrics) : this.parsePlain(best.plainLyrics);
            const detectedStyle = this.detectSongStyle(cleanTitle, cleanArtist, parsedLines, targetDuration);

            const result = {
              synced: !!best.syncedLyrics,
              lines: parsedLines,
              source: 'LRCLIB (Ranked Match)',
              instrumental: best.instrumental || false,
              trackDuration: best.duration,
              autoOffset,
              detectedStyle,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB combined search failed', e);
    }

    return null;
  },

  pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration) {
    if (!list || list.length === 0) return null;

    const normTitle = cleanTitle.toLowerCase();
    const normArtist = cleanArtist.toLowerCase();

    const scored = list.map(item => {
      let score = 0;
      if (item.syncedLyrics) score += 100;
      if (item.plainLyrics) score += 20;

      if (targetDuration && item.duration) {
        const diff = Math.abs(item.duration - targetDuration);
        if (diff <= 2) score += 90;
        else if (diff <= 5) score += 70;
        else if (diff <= 10) score += 40;
        else if (diff <= 18) score += 15;
        else if (diff > 35) score -= 60;
        else if (diff > 60) score -= 120;
      }

      const itemTitle = (item.trackName || '').toLowerCase();
      if (itemTitle === normTitle) {
        score += 50;
      } else if (itemTitle.includes(normTitle) || normTitle.includes(itemTitle)) {
        score += 30;
      }

      const itemArtist = (item.artistName || '').toLowerCase();
      if (itemArtist === normArtist) {
        score += 50;
      } else if (itemArtist.includes(normArtist) || normArtist.includes(itemArtist)) {
        score += 30;
      }

      return { item, score };
    });

    scored.sort((a, b) => b.score - a.score);
    return scored[0]?.item || null;
  },

  /**
   * Parse timestamped LRC string into structured line & word & character objects
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

      // Empty text timestamp marks the explicit vocal end-time of previous line
      if (!cleanText) {
        if (parsed.length > 0) {
          const prev = parsed[parsed.length - 1];
          const endTime = timestamps[0];
          if (!prev.explicitEndTime && endTime > prev.time) {
            prev.explicitEndTime = endTime;
            prev.endTime = endTime;
            prev.duration = Math.max(0.8, endTime - prev.time);
          }
        }
        continue;
      }

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

    // Compute line durations and word & character-level intervals
    const withWordTimings = [];
    for (let i = 0; i < parsed.length; i++) {
      const curr = parsed[i];
      const next = parsed[i + 1];

      // Instrumental intro check (> 4s)
      if (i === 0 && curr.time > 4.2) {
        withWordTimings.push({
          id: 'instrumental-intro',
          time: 0.5,
          endTime: curr.time - 0.2,
          text: '• • •',
          isInstrumental: true,
          isInterlude: true,
          words: [],
        });
      }

      // Calculate line duration with Smart Cap
      if (!curr.explicitEndTime) {
        if (next) {
          const rawGap = next.time - curr.time;
          // activeDuration capped intelligently so the last word doesn't stretch during long music breaks
          const activeDuration = Math.min(rawGap - 0.15, Math.max(1.8, curr.text.length * 0.11));
          curr.duration = Math.max(0.8, Math.min(activeDuration, 9.5));
          curr.endTime = curr.time + curr.duration;
        } else {
          curr.duration = Math.max(1.8, Math.min(curr.text.length * 0.11, 4.5));
          curr.endTime = curr.time + curr.duration;
        }
      }

      // Tokenize line into animated words & characters (Enhanced LRC or Syllabic Generator)
      curr.words = this.computeWordAndCharTimings(curr.rawText || curr.text, curr.time, curr.duration);
      withWordTimings.push(curr);

      // Instrumental interlude between lines if gap > 4.5 seconds
      if (next && (next.time - curr.endTime) > 4.5) {
        withWordTimings.push({
          id: `interlude-${curr.time}`,
          time: curr.endTime + 0.15,
          endTime: next.time - 0.2,
          text: '• • •',
          isInstrumental: true,
          isInterlude: true,
          words: [],
        });
      }
    }

    return withWordTimings;
  },

  /**
   * Compute word and character-level timings with punctuation pause weights
   */
  computeWordAndCharTimings(rawText, lineStart, lineDuration) {
    if (!rawText) return [];

    // 1. Check for Enhanced LRC inline timestamps (<00:12.34>word)
    const wordTagRegex = /<(\d{2}):(\d{2})(?:\.(\d{2,3}))?>/g;
    if (wordTagRegex.test(rawText)) {
      const tokens = [];
      const splitRegex = /<(\d{2}):(\d{2})(?:\.(\d{2,3}))?>([^<]+)/g;
      let match;
      while ((match = splitRegex.exec(rawText)) !== null) {
        const min = parseInt(match[1], 10);
        const sec = parseInt(match[2], 10);
        const msStr = match[3] || '0';
        const ms = msStr.length === 2 ? parseInt(msStr, 10) * 10 : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
        const time = min * 60 + sec + ms / 1000;
        const wordText = match[4].trim();
        if (wordText) {
          tokens.push({ word: wordText, startTime: time });
        }
      }

      if (tokens.length > 0) {
        for (let i = 0; i < tokens.length; i++) {
          const next = tokens[i + 1];
          const nextStart = next ? next.startTime : (lineStart + lineDuration);
          tokens[i].endTime = Math.max(tokens[i].startTime + 0.15, nextStart);
          tokens[i].duration = tokens[i].endTime - tokens[i].startTime;
          tokens[i].id = `word-${i}-${tokens[i].startTime}`;
          tokens[i].chars = this.generateCharTimings(tokens[i].word, tokens[i].startTime, tokens[i].duration);
        }
        return tokens;
      }
    }

    // 2. Standard LRC: Smart Syllabic & Character Weight Generator
    const clean = rawText.replace(/<\d{2}:\d{2}(?:\.\d{2,3})?>/g, '').trim();
    const rawWords = clean.split(/\s+/).filter(w => w.length > 0);
    if (rawWords.length === 0) return [];

    // Vowel & punctuation weights
    const calculateWordWeight = (word) => {
      const vowels = (word.match(/[aiueoAIUEO]/g) || []).length;
      let weight = Math.max(1, vowels * 1.6 + word.length * 0.4);
      // Extra weight for punctuation pauses at end of words
      if (/[,;]$/.test(word)) weight += 0.8;
      if (/[.!?]$/.test(word)) weight += 1.4;
      return weight;
    };

    const weights = rawWords.map(calculateWordWeight);
    const totalWeight = weights.reduce((sum, w) => sum + w, 0);
    const activeSingingDuration = Math.max(0.6, lineDuration * 0.94);

    let currentOffset = 0;
    return rawWords.map((word, idx) => {
      const wordWeight = weights[idx] / totalWeight;
      const wordDuration = Math.max(0.18, activeSingingDuration * wordWeight);
      const startTime = lineStart + currentOffset;
      const endTime = startTime + wordDuration;
      currentOffset += wordDuration;

      return {
        id: `word-${idx}-${startTime.toFixed(2)}`,
        word,
        startTime,
        endTime,
        duration: wordDuration,
        chars: this.generateCharTimings(word, startTime, wordDuration),
      };
    });
  },

  /**
   * Break each word down into individual characters with micro-timestamps
   */
  generateCharTimings(word, wordStart, wordDuration) {
    if (!word) return [];
    const chars = Array.from(word);
    if (chars.length === 0) return [];

    // Vowels carry longer phonation than consonants
    const charWeights = chars.map(ch => {
      if (/[aiueoAIUEO]/.test(ch)) return 1.8;
      if (/[,.!?]/.test(ch)) return 0.6;
      return 1.0;
    });

    const totalWeight = charWeights.reduce((s, w) => s + w, 0);
    let curOffset = 0;

    return chars.map((char, cIdx) => {
      const charDur = (charWeights[cIdx] / totalWeight) * wordDuration;
      const start = wordStart + curOffset;
      const end = start + charDur;
      curOffset += charDur;
      return {
        char,
        startTime: start,
        endTime: end,
        duration: charDur,
      };
    });
  },

  /**
   * Parse plain lyrics
   */
  parsePlain(plainText) {
    if (!plainText) return [];
    return plainText.split('\n').map((line, idx) => {
      const time = idx * 3.8;
      return {
        id: `plain-${idx}`,
        time,
        endTime: time + 3.6,
        text: line.trim(),
        duration: 3.6,
        words: this.computeWordAndCharTimings(line.trim(), time, 3.6),
        isPlain: true,
      };
    }).filter(l => l.text.length > 0);
  },
};
