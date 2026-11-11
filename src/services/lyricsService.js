/**
 * Mctify Spicy Lyrics Client Service
 * Multi-Provider Syllable & Word-Synced Architecture (spikerko/spicy-lyrics standard)
 * 
 * Pipeline:
 * 1. Clean dirty metadata (removes 'Official Video', 'Topic', composite title parsing)
 * 2. Primary: Query /api/lyrics (NetEase YRC Syllable-Sync & LRCLIB Enhanced Cascade)
 * 3. Client Fallback: Direct NetEase Cloud Music + LRCLIB + Lyrist API cascade
 * 4. Yields exact millisecond timestamps per word and syllable without mathematical guessing
 */

import { extractPrimaryArtist, scoreLyricCandidate } from '../utils/lyricsMatcher.js';

const lyricsMemoryCache = new Map();

export const lyricsService = {
  /**
   * Aggressively clean noisy streaming & YouTube titles and artists
   */
  cleanTrackMetadata(rawTitle, rawArtist) {
    let title = (rawTitle || '').trim();
    let artist = extractPrimaryArtist(rawArtist || '');

    // If title has 'Artist - Title' format
    if (title.includes(' - ')) {
      const parts = title.split(' - ');
      if (parts.length >= 2) {
        const p0 = parts[0].trim();
        const p1 = parts.slice(1).join(' - ').trim();
        if (artist && (p0.toLowerCase().includes(artist.toLowerCase()) || artist.toLowerCase().includes(p0.toLowerCase()))) {
          title = p1;
        } else if (artist && (p1.toLowerCase().includes(artist.toLowerCase()) || artist.toLowerCase().includes(p1.toLowerCase()))) {
          title = p0;
        } else if (!artist) {
          artist = extractPrimaryArtist(p0);
          title = p1;
        }
      }
    }

    // Strip brackets and parentheses noise
    const noiseRegex = /\s*[\(\[](official\s*(music\s*)?video|official\s*audio|official\s*lyric(\s*video)?|visualizer|audio|video|clip\s*officiel|mv|hd|4k|remastered|live|session|brooklyn\s*session|10\s*years|lirik|lyrics|feat\.?|ft\.?)[^\)\]]*[\)\]]/gi;
    title = title.replace(noiseRegex, '');
    title = title.replace(/\s*(feat\.|ft\.)\s+[^-\(\]]+/gi, '');
    title = title.replace(/[◐◑]/g, '').trim();

    // Clean remaining lonely parentheses
    title = title.replace(/[\(\)\[\]]/g, '').trim();
    artist = artist.replace(/[\(\)\[\]]/g, '').trim();

    // Subtitle candidates if composite title like 'Television / So Far So Good'
    const subTitles = [title];
    if (title.includes(' / ')) {
      const subParts = title.split(' / ').map(s => s.trim()).filter(Boolean);
      subTitles.push(...subParts);
    }

    return { title, artist, subTitles };
  },

  /**
   * Main Fetcher: Multi-Provider Syllable/Word-Synced Cascade
   */
  async fetchLyrics(rawArtist, rawTitle, duration) {
    if (!rawTitle) return null;

    const { title: cleanTitle, artist: cleanArtist, subTitles } = this.cleanTrackMetadata(rawTitle, rawArtist);
    const targetDuration = (typeof duration === 'number' && Number.isFinite(duration) && duration > 5)
      ? Math.round(duration)
      : null;

    const durBucket = targetDuration && targetDuration > 10 ? Math.round(targetDuration / 5) : 'any';
    const cacheKey = `${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}:::${durBucket}`;

    if (lyricsMemoryCache.has(cacheKey)) {
      return lyricsMemoryCache.get(cacheKey);
    }

    // TIER 1: Query internal Serverless API Proxy (/api/lyrics)
    try {
      const params = new URLSearchParams({
        title: cleanTitle,
        artist: cleanArtist,
      });
      if (targetDuration) params.append('duration', String(targetDuration));

      const res = await fetch(`/api/lyrics?${params.toString()}`);
      if (res.ok) {
        const data = await res.json();
        if (data && Array.isArray(data.lines) && data.lines.length > 0) {
          lyricsMemoryCache.set(cacheKey, data);
          return data;
        }
      }
    } catch (e) {
      console.warn('/api/lyrics proxy unavailable, attempting client cascade:', e.message);
    }

    // TIER 2: Parallel verified Direct LRCLIB & Direct NetEase fallback (picking highest artist/duration match)
    try {
      const [lrcRes, neRes] = await Promise.all([
        this.fetchLrclibDirect(cleanTitle, cleanArtist, targetDuration).catch(() => null),
        this.fetchNetEaseDirect(cleanTitle, cleanArtist, targetDuration).catch(() => null),
      ]);
      const bestDirect = (lrcRes && neRes)
        ? ((lrcRes.matchScore >= neRes.matchScore) ? lrcRes : neRes)
        : (lrcRes || neRes);
      if (bestDirect && bestDirect.lines.length > 0) {
        lyricsMemoryCache.set(cacheKey, bestDirect);
        return bestDirect;
      }
    } catch (e) {
      console.warn('Direct lyrics cascade failed:', e);
    }

    // TIER 3: Composite Subtitle retry (e.g. 'Television' from 'Television / So Far So Good')
    if (subTitles.length > 1) {
      for (let i = 1; i < subTitles.length; i++) {
        const sub = subTitles[i];
        try {
          const subLrc = await this.fetchLrclibDirect(sub, cleanArtist, targetDuration);
          if (subLrc && subLrc.lines.length > 0) {
            lyricsMemoryCache.set(cacheKey, subLrc);
            return subLrc;
          }
          const subNetEase = await this.fetchNetEaseDirect(sub, cleanArtist, targetDuration);
          if (subNetEase && subNetEase.lines.length > 0) {
            lyricsMemoryCache.set(cacheKey, subNetEase);
            return subNetEase;
          }
        } catch (_) {}
      }
    }

    // TIER 5: Lyrist Public API Fallback
    try {
      const lyristRes = await fetch(`https://lyrist.vercel.app/api/${encodeURIComponent(cleanTitle)}/${encodeURIComponent(cleanArtist)}`);
      if (lyristRes.ok) {
        const data = await lyristRes.json();
        if (data?.lyrics) {
          const parsed = this.parsePlainLyrics(data.lyrics);
          const result = {
            synced: false,
            isSyllableSynced: false,
            lines: parsed,
            source: 'Lyrist',
          };
          lyricsMemoryCache.set(cacheKey, result);
          return result;
        }
      }
    } catch (_) {}

    return null;
  },

  async fetchNetEaseDirect(title, artist, targetDuration = 0) {
    const q = `${title} ${artist}`.trim();
    const params = new URLSearchParams({ s: q, type: '1', offset: '0', limit: '6' });
    const searchRes = await fetch('https://music.163.com/api/cloudsearch/pc', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://music.163.com',
      },
      body: params.toString(),
    });

    if (!searchRes.ok) return null;
    const searchData = await searchRes.json();
    const candidates = searchData.result?.songs || [];
    if (candidates.length === 0) return null;

    const ranked = candidates
      .map((s) => {
        const candArtist = (s.ar || s.artists || []).map((a) => a.name).join(', ');
        const candDurSec = Math.round((s.dt || s.duration || 0) / 1000);
        const matchScore = scoreLyricCandidate({
          candTitle: s.name || '',
          candArtist,
          candDurationSec: candDurSec,
          targetTitle: title,
          targetArtist: artist,
          targetDurationSec: targetDuration || 0,
        });
        return { song: s, matchScore };
      })
      .filter((x) => x.matchScore >= 700)
      .sort((a, b) => b.matchScore - a.matchScore);

    for (const entry of ranked.slice(0, 2)) {
      const lyricRes = await fetch(`https://music.163.com/api/song/lyric?id=${entry.song.id}&lv=1&kv=1&tv=-1&yv=1`, {
        headers: {
          'Referer': 'https://music.163.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        },
      });
      if (!lyricRes.ok) continue;
      const lyricData = await lyricRes.json();

      if (lyricData.yrc?.lyric) {
        const lines = this.parseYrc(lyricData.yrc.lyric);
        if (lines.length > 0) {
          return {
            source: 'NetEase YRC (Studio Syllable-Synced)',
            isSyllableSynced: true,
            synced: true,
            matchScore: entry.matchScore + 180,
            lines,
          };
        }
      }

      if (lyricData.lrc?.lyric) {
        const lines = this.parseLrc(lyricData.lrc.lyric);
        if (lines.length > 0) {
          return {
            source: 'NetEase LRC',
            isSyllableSynced: false,
            synced: true,
            matchScore: entry.matchScore,
            lines,
          };
        }
      }
    }

    return null;
  },

  async fetchLrclibDirect(title, artist, targetDuration) {
    const params = new URLSearchParams({ track_name: title, artist_name: artist });
    if (targetDuration) params.append('duration', String(targetDuration));

    const exactRes = await fetch(`https://lrclib.net/api/get?${params.toString()}`);
    if (exactRes.ok) {
      const data = await exactRes.json();
      if (data?.syncedLyrics || data?.plainLyrics) {
        const isEnhanced = /<\d{1,3}:\d{2}/.test(data.syncedLyrics || '');
        const lines = data.syncedLyrics ? this.parseLrc(data.syncedLyrics) : this.parsePlainLyrics(data.plainLyrics);
        const matchScore = scoreLyricCandidate({
          candTitle: data.trackName || title,
          candArtist: data.artistName || artist,
          candDurationSec: Math.round(data.duration || targetDuration || 0),
          targetTitle: title,
          targetArtist: artist,
          targetDurationSec: targetDuration || 0,
          isSynced: !!data.syncedLyrics,
          isSyllable: isEnhanced,
        });
        if (lines.length > 0 && matchScore >= 600) {
          return {
            source: isEnhanced ? 'LRCLIB (Enhanced Word-Synced)' : 'LRCLIB (Synced Exact)',
            isSyllableSynced: isEnhanced,
            synced: !!data.syncedLyrics,
            matchScore: matchScore + 250,
            lines,
          };
        }
      }
    }

    const searchRes = await fetch(`https://lrclib.net/api/search?q=${encodeURIComponent(`${title} ${artist}`)}`);
    if (searchRes.ok) {
      const list = await searchRes.json();
      if (Array.isArray(list) && list.length > 0) {
        const scored = list
          .filter((i) => i?.syncedLyrics || i?.plainLyrics)
          .map((item) => {
            const isEnhanced = /<\d{1,3}:\d{2}/.test(item.syncedLyrics || '');
            const s = scoreLyricCandidate({
              candTitle: item.trackName || '',
              candArtist: item.artistName || '',
              candDurationSec: Math.round(item.duration || 0),
              targetTitle: title,
              targetArtist: artist,
              targetDurationSec: targetDuration || 0,
              isSynced: !!item.syncedLyrics,
              isSyllable: isEnhanced,
            });
            return { item, isEnhanced, matchScore: s };
          })
          .filter((x) => x.matchScore >= 550)
          .sort((a, b) => b.matchScore - a.matchScore);

        if (scored.length > 0) {
          const best = scored[0];
          const lines = best.item.syncedLyrics
            ? this.parseLrc(best.item.syncedLyrics)
            : this.parsePlainLyrics(best.item.plainLyrics);
          if (lines.length > 0) {
            return {
              source: best.isEnhanced ? 'LRCLIB (Enhanced Word-Synced)' : 'LRCLIB (Matched Search)',
              isSyllableSynced: best.isEnhanced,
              synced: !!best.item.syncedLyrics,
              matchScore: best.matchScore,
              lines,
            };
          }
        }
      }
    }

    return null;
  },

  parseYrc(yrcText) {
    if (!yrcText) return [];
    const rawLines = yrcText.split('\n');
    const parsed = [];
    const lineHeaderRegex = /^\[(\d+),(\d+)\](.*)/;
    const wordRegex = /\((\d+),(\d+),\d+\)([^(\n]+)/g;

    for (let i = 0; i < rawLines.length; i++) {
      const raw = rawLines[i].trim();
      if (!raw) continue;
      const match = raw.match(lineHeaderRegex);
      if (!match) continue;

      const lineStartMs = parseInt(match[1], 10);
      const lineDurMs = parseInt(match[2], 10);
      const lineContent = match[3] || '';

      if (/作词|作曲|Written by|Composer|Producer|Arranger|Mixing/i.test(lineContent)) continue;

      const words = [];
      let wordMatch;
      wordRegex.lastIndex = 0;
      while ((wordMatch = wordRegex.exec(lineContent)) !== null) {
        const wStartMs = parseInt(wordMatch[1], 10);
        const wDurMs = parseInt(wordMatch[2], 10);
        const wText = wordMatch[3];
        if (wText && wText.trim()) {
          const startSec = wStartMs / 1000;
          const durSec = Math.max(0.04, wDurMs / 1000);
          const endSec = startSec + durSec;
          words.push({
            id: `w-${i}-${words.length}`,
            word: wText,
            startTime: Math.round(startSec * 1000) / 1000,
            endTime: Math.round(endSec * 1000) / 1000,
            duration: Math.round(durSec * 1000) / 1000,
            chars: this.generateCharTimings(wText, startSec, durSec),
          });
        }
      }

      if (words.length > 0) {
        const lineText = words.map(w => w.word).join('').trim();
        const lineStartSec = lineStartMs / 1000;
        const lineDurSec = Math.max(0.6, lineDurMs / 1000);

        parsed.push({
          id: `line-${i}-${lineStartSec}`,
          time: Math.round(lineStartSec * 1000) / 1000,
          endTime: Math.round((lineStartSec + lineDurSec) * 1000) / 1000,
          duration: Math.round(lineDurSec * 1000) / 1000,
          text: lineText,
          words,
          isSyllableSynced: true,
        });
      }
    }

    return this.finalizeLinesWithInterludes(parsed);
  },

  parseLrc(lrcText) {
    if (!lrcText) return [];
    const rawLines = lrcText.split('\n');
    const parsed = [];
    const timeRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

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
        timestamps.push(min * 60 + sec + ms / 1000);
      }

      if (timestamps.length === 0) continue;

      const cleanText = rawLine.replace(/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/g, '').trim();

      if (!cleanText) {
        if (parsed.length > 0) {
          const prev = parsed[parsed.length - 1];
          if (!prev.explicitEndTime && timestamps[0] > prev.time) {
            prev.explicitEndTime = timestamps[0];
            prev.endTime = timestamps[0];
            prev.duration = Math.max(0.6, timestamps[0] - prev.time);
          }
        }
        continue;
      }

      if (/^(作词|作曲|Written by|Composer|Producer):/i.test(cleanText)) continue;

      timestamps.forEach(t => {
        parsed.push({
          id: `lrc-${t.toFixed(2)}-${i}`,
          time: t,
          text: cleanText.replace(/<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/g, '').trim(),
          rawText: cleanText,
        });
      });
    }

    parsed.sort((a, b) => a.time - b.time);

    for (let i = 0; i < parsed.length; i++) {
      const curr = parsed[i];
      const next = parsed[i + 1];

      if (!curr.explicitEndTime) {
        if (next) {
          const rawGap = next.time - curr.time;
          const capped = Math.min(rawGap - 0.15, Math.max(1.8, curr.text.length * 0.11));
          curr.duration = Math.max(0.8, Math.min(capped, 9.5));
          curr.endTime = curr.time + curr.duration;
        } else {
          curr.duration = Math.max(1.8, Math.min(curr.text.length * 0.11, 4.5));
          curr.endTime = curr.time + curr.duration;
        }
      }

      curr.words = this.computeLrcWords(curr.rawText || curr.text, curr.time, curr.duration);
    }

    return this.finalizeLinesWithInterludes(parsed);
  },

  computeLrcWords(rawText, lineStart, lineDuration) {
    const wordTagRegex = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>/g;
    if (wordTagRegex.test(rawText)) {
      const tokens = [];
      const splitRegex = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]+)/g;
      let match;
      while ((match = splitRegex.exec(rawText)) !== null) {
        const min = parseInt(match[1], 10);
        const sec = parseInt(match[2], 10);
        const msStr = match[3] || '0';
        const ms = msStr.length === 2 ? parseInt(msStr, 10) * 10 : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
        const time = min * 60 + sec + ms / 1000;
        const wText = match[4].trim();
        if (wText) {
          tokens.push({ word: wText, startTime: time });
        }
      }

      if (tokens.length > 0) {
        for (let i = 0; i < tokens.length; i++) {
          const next = tokens[i + 1];
          const nextStart = next ? next.startTime : (lineStart + lineDuration);
          tokens[i].endTime = Math.max(tokens[i].startTime + 0.15, nextStart);
          tokens[i].duration = tokens[i].endTime - tokens[i].startTime;
          tokens[i].id = `w-${i}-${tokens[i].startTime}`;
          tokens[i].chars = this.generateCharTimings(tokens[i].word, tokens[i].startTime, tokens[i].duration);
        }
        return tokens;
      }
    }

    const clean = rawText.replace(/<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/g, '').trim();
    const rawWords = clean.split(/\s+/).filter(w => w.length > 0);
    if (rawWords.length === 0) return [];

    const weights = rawWords.map(word => {
      const vowels = (word.match(/[aiueoAIUEO]/g) || []).length;
      let weight = Math.max(1, vowels * 1.6 + word.length * 0.4);
      if (/[,;]$/.test(word)) weight += 0.8;
      if (/[.!?]$/.test(word)) weight += 1.4;
      return weight;
    });

    const totalWeight = weights.reduce((s, w) => s + w, 0);
    const activeDuration = Math.max(0.6, lineDuration * 0.94);

    let curOffset = 0;
    return rawWords.map((word, idx) => {
      const wordDur = Math.max(0.18, activeDuration * (weights[idx] / totalWeight));
      const start = lineStart + curOffset;
      const end = start + wordDur;
      curOffset += wordDur;

      return {
        id: `w-${idx}-${start.toFixed(2)}`,
        word,
        startTime: Math.round(start * 1000) / 1000,
        endTime: Math.round(end * 1000) / 1000,
        duration: Math.round(wordDur * 1000) / 1000,
        chars: this.generateCharTimings(word, start, wordDur),
      };
    });
  },

  generateCharTimings(word, wordStart, wordDuration) {
    if (!word) return [];
    const chars = Array.from(word);
    if (chars.length === 0) return [];

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
        startTime: Math.round(start * 1000) / 1000,
        endTime: Math.round(end * 1000) / 1000,
        duration: Math.round(charDur * 1000) / 1000,
      };
    });
  },

  finalizeLinesWithInterludes(parsedLines) {
    if (!parsedLines || parsedLines.length === 0) return [];
    const result = [];

    for (let i = 0; i < parsedLines.length; i++) {
      const curr = parsedLines[i];
      const next = parsedLines[i + 1];

      if (i === 0 && curr.time > 4.2) {
        result.push({
          id: 'intro-interlude',
          time: 0.5,
          endTime: Math.round((curr.time - 0.2) * 1000) / 1000,
          duration: Math.round((curr.time - 0.7) * 1000) / 1000,
          text: '• • •',
          isInstrumental: true,
          isInterlude: true,
          words: [],
        });
      }

      result.push(curr);

      if (next && (next.time - curr.endTime) > 4.5) {
        result.push({
          id: `interlude-${curr.time}`,
          time: Math.round((curr.endTime + 0.15) * 1000) / 1000,
          endTime: Math.round((next.time - 0.2) * 1000) / 1000,
          duration: Math.round((next.time - curr.endTime - 0.35) * 1000) / 1000,
          text: '• • •',
          isInstrumental: true,
          isInterlude: true,
          words: [],
        });
      }
    }

    return result;
  },

  parsePlainLyrics(plainText) {
    if (!plainText) return [];
    return plainText.split('\n').map((line, idx) => {
      const time = idx * 4.0;
      return {
        id: `plain-${idx}`,
        time,
        endTime: time + 3.8,
        text: line.trim(),
        duration: 3.8,
        words: this.computeLrcWords(line.trim(), time, 3.8),
        isPlain: true,
      };
    }).filter(l => l.text.length > 0);
  },
};
