/**
 * LRCLIB Synced Lyrics Service & Word-by-Word Karaoke Engine
 * High-accuracy multi-tier matching with duration proximity scoring,
 * Enhanced LRC word timestamps, empty line end-times, and persistent sync calibration.
 */

const lyricsMemoryCache = new Map();
const STORAGE_KEY_SYNC_OFFSETS = 'mcmusic_lyrics_sync_offsets';
const STORAGE_KEY_GLOBAL_OFFSET = 'mcmusic_lyrics_global_offset';

export const lyricsService = {
  /**
   * Get persistent sync calibration offset for a specific track.
   * Returns null if no manual adjustment was made, indicating Auto-Sync should be active.
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

    // --- TIER 1: Exact lookup with Duration parameter (Matches the exact track version!) ---
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
            const result = {
              synced: !!data.syncedLyrics,
              lines: data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlain(data.plainLyrics),
              source: 'LRCLIB (Exact Duration Match)',
              instrumental: data.instrumental || false,
              trackDuration: data.duration,
              autoOffset,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      } catch (e) {
        console.warn('LRCLIB exact lookup with duration failed, continuing to Tier 2', e);
      }
    }

    // --- TIER 2: Exact lookup without duration (verify returned duration is within tolerance) ---
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
            const result = {
              synced: !!data.syncedLyrics,
              lines: data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlain(data.plainLyrics),
              source: 'LRCLIB (Exact Name Match)',
              instrumental: data.instrumental || false,
              trackDuration: data.duration,
              autoOffset,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB exact lookup without duration failed, continuing to search', e);
    }

    // --- TIER 3: Smart Search with Duration-Ranked Scoring ---
    try {
      const q = encodeURIComponent(`${cleanTitle} ${cleanArtist}`.trim());
      const res = await fetch(`https://lrclib.net/api/search?q=${q}`);
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          const best = this.pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration);
          if (best && (best.syncedLyrics || best.plainLyrics)) {
            const autoOffset = this.calculateAutoSyncOffset(best.syncedLyrics, targetDuration, best.duration);
            const result = {
              synced: !!best.syncedLyrics,
              lines: best.syncedLyrics ? this.parseLrc(best.syncedLyrics) : this.parsePlain(best.plainLyrics),
              source: 'LRCLIB (Ranked Match)',
              instrumental: best.instrumental || false,
              trackDuration: best.duration,
              autoOffset,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB combined search failed', e);
    }

    // --- TIER 4: Fallback search by title alone if combined query yielded nothing ---
    try {
      const q = encodeURIComponent(cleanTitle);
      const res = await fetch(`https://lrclib.net/api/search?q=${q}`);
      if (res.ok) {
        const list = await res.json();
        if (Array.isArray(list) && list.length > 0) {
          const best = this.pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration);
          if (best && (best.syncedLyrics || best.plainLyrics)) {
            const autoOffset = this.calculateAutoSyncOffset(best.syncedLyrics, targetDuration, best.duration);
            const result = {
              synced: !!best.syncedLyrics,
              lines: best.syncedLyrics ? this.parseLrc(best.syncedLyrics) : this.parsePlain(best.plainLyrics),
              source: 'LRCLIB (Title Search)',
              instrumental: best.instrumental || false,
              trackDuration: best.duration,
              autoOffset,
            };
            lyricsMemoryCache.set(cacheKey, result);
            return result;
          }
        }
      }
    } catch (e) {
      console.warn('LRCLIB title fallback search failed', e);
    }

    return null;
  },

  /**
   * Rank search results to select the exact version matching the audio duration and metadata
   */
  pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration) {
    if (!list || list.length === 0) return null;

    const normTitle = cleanTitle.toLowerCase();
    const normArtist = cleanArtist.toLowerCase();

    const scored = list.map(item => {
      let score = 0;
      if (item.syncedLyrics) score += 100;
      if (item.plainLyrics) score += 20;

      // Duration match scoring (Prevents selecting live/acoustic/remix versions with wrong timings!)
      if (targetDuration && item.duration) {
        const diff = Math.abs(item.duration - targetDuration);
        if (diff <= 2) score += 90;
        else if (diff <= 5) score += 70;
        else if (diff <= 10) score += 40;
        else if (diff <= 18) score += 15;
        else if (diff > 35) score -= 60; // Penalty for large duration mismatch
        else if (diff > 60) score -= 120; // Severe penalty for completely different version
      }

      // Title match scoring
      const itemTitle = (item.trackName || '').toLowerCase();
      if (itemTitle === normTitle) {
        score += 50;
      } else if (itemTitle.includes(normTitle) || normTitle.includes(itemTitle)) {
        score += 30;
      }

      // Artist match scoring
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
   * Parse timestamped LRC string into structured line objects
   * Handles empty line end-timestamps and extracts precise word-by-word karaoke timing!
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

      // Empty text timestamp marks the explicit vocal end-time of the previous line!
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

    // Compute line durations and word-level karaoke intervals
    const withWordTimings = [];
    for (let i = 0; i < parsed.length; i++) {
      const curr = parsed[i];
      const next = parsed[i + 1];

      // Instrumental intro check
      if (i === 0 && curr.time > 6) {
        withWordTimings.push({
          id: 'instrumental-intro',
          time: 0.5,
          endTime: curr.time - 0.4,
          text: '♪  Intro  ♪',
          isInstrumental: true,
          words: [],
        });
      }

      // Calculate line duration if not explicitly marked by empty line timestamp
      if (!curr.explicitEndTime) {
        const lineDuration = next
          ? Math.min(8.0, Math.max(1.2, (next.time - curr.time) * 0.94))
          : 4.5;
        curr.duration = lineDuration;
        curr.endTime = curr.time + lineDuration;
      }

      // Tokenize line into animated word objects (Enhanced or Syllabic)
      curr.words = this.computeWordTimings(curr.rawText || curr.text, curr.time, curr.duration);
      withWordTimings.push(curr);

      // Instrumental break between lines if gap > 4 seconds
      if (next && (next.time - curr.endTime) > 3.8) {
        withWordTimings.push({
          id: `instrumental-${curr.time}`,
          time: curr.endTime + 0.3,
          endTime: next.time - 0.4,
          text: '♪  Musik  ♪',
          isInstrumental: true,
          words: [],
        });
      }
    }

    return withWordTimings;
  },

  /**
   * Compute word-by-word timestamps for Apple Music / Beautiful Lyrics karaoke
   * Supports inline enhanced LRC tags <mm:ss.xx> or high-precision syllabic weights
   */
  computeWordTimings(rawText, lineStart, lineDuration) {
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
        }
        return tokens;
      }
    }

    // 2. Standard LRC: Realistic Syllabic & Vowel Weight Calculation (Indonesian & Global cadence)
    const clean = rawText.replace(/<\d{2}:\d{2}(?:\.\d{2,3})?>/g, '').trim();
    const rawWords = clean.split(/\s+/).filter(w => w.length > 0);
    if (rawWords.length === 0) return [];

    // Count vowel clusters (singers hold vowels, not consonants)
    const countSyllables = (word) => {
      const cleaned = word.toLowerCase().replace(/[^a-z0-9]/g, '');
      if (!cleaned) return 1;
      const matches = cleaned.match(/[aiueo]+/g);
      return matches ? Math.max(1, matches.length) : 1;
    };

    const weights = rawWords.map(w => {
      const syl = countSyllables(w);
      return Math.max(1, syl * 1.5 + w.length * 0.4);
    });

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
        endTime: time + 3.8,
        text: line.trim(),
        duration: 3.8,
        words: this.computeWordTimings(line.trim(), time, 3.8),
        isPlain: true,
      };
    }).filter(l => l.text.length > 0);
  },
};
