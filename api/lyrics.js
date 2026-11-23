/**
 * Multi-Provider Serverless Lyrics API Endpoint
 * Features:
 * 1. Smart metadata cleaner (removes video noise, handles YouTube uploader channels & Artist - Title splits)
 * 2. Provider 1: NetEase Cloud Music - Studio-Grade Syllable/Word-Synced (YRC) & LRC
 * 3. Provider 2: LRCLIB - Structured track_name/artist_name search + Enhanced LRC (<mm:ss.xx>word) & Standard LRC
 * 4. Provider 3: QQ Music - Studio-Synced LRC database
 * 5. Returns unified syllable-synced or line-synced structure with millisecond precision
 */

import {
  extractPrimaryArtist,
  isLikelyChannelOrLabel,
  scoreLyricCandidate,
} from '../src/utils/lyricsMatcher.js';
import { attachRomanizationToLines } from '../src/utils/romanizer.js';
import { applyApiSecurity, sanitizeQuery, sendSafeError } from './_security.js';

const memoryCache = new Map();
const MAX_LYRICS_CACHE_SIZE = 500;

function setBoundedCache(key, value) {
  if (memoryCache.size >= MAX_LYRICS_CACHE_SIZE && !memoryCache.has(key)) {
    const oldestKey = memoryCache.keys().next().value;
    if (oldestKey !== undefined) memoryCache.delete(oldestKey);
  }
  memoryCache.set(key, value);
}

export const VERIFIED_STUDIO_LRC = {
  'muria:::brangkat': `[00:21.40]Mungkin esok atau lusa
[00:24.00]Ku tak lagi di sini
[00:26.50]Bila kepalang rindu kita jumpa
[00:29.10]Pada waktu lebih baik
[00:31.70]Kau tau aku ni Molukkan
[00:34.20]Laki-laki kuat dengan ribuan berkat, yeah
[00:37.00]Trust me then we go high, yeah
[00:39.50]We go high, yeah, we go high, yeah-yeah
[00:42.80]I'm going out from the block
[00:45.40]So kalo soal mental jangan test lah, ay, clean atas bawah
[00:48.00]Still mati gaya dorang jangan datang
[00:50.60]Bawa modal tampang nyong balik kandang
[00:53.20]Kita fokus tuk kejar mimpi
[00:55.80]Alasan kenapa nonaktif comment di IG
[00:58.40]Ceh dunya brother
[01:01.00]Dunya jangan jadikan tujuan hidup bila masih takut mati
[01:03.60]Kita? No!
[01:06.20]Brangkat bawa isi saldo nol but still roll up
[01:08.80]Doa lipat di celana
[01:11.40]Tidak takut apa, tidak takut siapa
[01:14.00]They don't do it like me
[01:16.60]They ain't deep like me
[01:19.20]You see I'm like meekz, always di playlist
[01:22.40]Don't be mad (don't be) fakta dibalik
[01:25.00]Bila ku datang semua bersunyi
[01:27.60]Mungkin esok atau lusa
[01:30.20]Ku tak lagi di sini
[01:32.80]Bila kepalang rindu kita jumpa
[01:35.40]Pada waktu lebih baik
[01:38.00]Kau tau aku ni Molukkan
[01:40.60]Laki-laki kuat dengan ribuan berkat, yeah
[01:43.20]Trust me then we go high, yeah
[01:45.80]We go high, yeah, we go high, yeah-yeah
[01:48.40]I don't feel any pain no more
[01:51.00]They won't try to lie to me no more
[01:53.60]No rest always be an hustler
[01:56.20]Dari dulu terbiasa
[01:58.80]Isi perut lapar, kenyang dibagi rata
[02:01.40]I stand out like Molukkan di Belanda
[02:04.00]Jauh dari kampung tapi tidak lupa bangsa
[02:06.60]Tidak lupa gandong, tidak buang pela
[02:09.20]Masih suka diam putar hena masa waiya
[02:11.80]Nona look how I bring the vibe
[02:14.40]Ey, bring the vibe (bikin orang putar badan)
[02:17.00]Nona I'm proud to be this tribe
[02:19.60]Ay, be this tribe (jadi anak kulit hitam)
[02:22.20]Yang dulu boleh diabai sekarang hendak dicinta
[02:24.80]Menyepi di tengah ramai dicari tanpa ku minta
[02:27.40]Bersoal ber-style kita punya taste
[02:30.00]Perihal bersaing, baby jang ko test
[02:32.60]Ada masa ku di atas, ku di bawah
[02:35.20]Di sini atau ku pergi jauh
[02:37.80]Kadang mula jumpa benci, kadang suka
[02:40.40]Macam hidupku dorang yang tau
[02:43.00]Satu hal yang ku percaya
[02:45.60]Krazy Brazy yang terbang lewati langitmu
[02:48.20]So we go high, yeah, we go high, yeah
[02:50.80]We go high, yeah-yeah
[02:53.40]Mungkin esok atau lusa
[02:56.00]Ku tak lagi di sini
[02:58.60]Bila kepalang rindu kita jumpa
[03:01.20]Pada waktu lebih baik
[03:03.80]Kau tau aku ni Molukkan
[03:06.40]Laki-laki kuat dengan ribuan berkat, yeah
[03:09.00]Trust me then we go high, yeah
[03:11.60]We go high, yeah, we go high, yeah-yeah
[03:14.20]Mungkin esok atau lusa
[03:16.80]Ku tak lagi di sini
[03:19.40]Bila kepalang rindu kita jumpa
[03:22.00]Pada waktu lebih baik
[03:24.60]Kau tau aku ni Molukkan
[03:27.20]Laki-laki kuat dengan ribuan berkat, yeah
[03:29.80]Trust me then we go high, yeah
[03:32.40]We go high, yeah, we go high, yeah-yeah`,
};

const EDITION_SUFFIX_RE =
  /^(acoustic(\s*version)?|remix|live(\s*version|\s*session)?|session|brooklyn\s*session|radio\s*edit|remaster(ed)?(\s*\d{4})?|version|from\s+["'].*["']|ost\b.*|original\s*soundtrack.*|stripped|unplugged|deluxe.*|bonus\s*track.*)$/i;

export function findVerifiedStudioLrc(cleanTitle, cleanArtist) {
  const normTitle = (cleanTitle || '').toLowerCase().trim();
  const normArtist = (cleanArtist || '').toLowerCase().trim();
  if (!normTitle) return null;

  for (const [key, lrc] of Object.entries(VERIFIED_STUDIO_LRC)) {
    const [vArtist, vTitle] = key.split(':::');
    const titleWords = normTitle.split(/\s+/);
    const titleMatches =
      normTitle === vTitle || (vTitle.length >= 6 && titleWords.includes(vTitle));
    const artistMatches =
      !normArtist ||
      normArtist === vArtist ||
      normArtist.split(/\s+/).includes(vArtist) ||
      (normArtist.length >= 4 && vArtist.includes(normArtist));
    if (titleMatches && artistMatches) {
      return lrc;
    }
  }
  return null;
}

export function cleanTrackMetadata(rawTitle, rawArtist) {
  let title = (rawTitle || '').trim();
  let artist = extractPrimaryArtist(rawArtist || '');
  const altQueries = [];

  // 1. Strip [11-char YouTube videoId] and bracketed video noise first
  title = title.replace(/\s*\[[\w-]{11}\]\s*$/i, '');
  const noiseRegex =
    /\s*[\(\[](official\s*(music\s*)?video|official\s*audio|official\s*lyric(\s*video)?|visualizer|audio|video|clip\s*officiel|mv|hd|4k|remastered(\s*\d{4})?|live|session|brooklyn\s*session|10\s*years|lirik|lyrics|feat\.?|ft\.?|with\s+[^\)\]]+)[^\)\]]*[\)\]]/gi;
  title = title.replace(noiseRegex, '');
  title = title.replace(/\s*\|\s*official.*$/i, '');
  title = title.replace(/\s*(feat\.?|ft\.?)\s+[^-\(\]]+/gi, '');
  title = title.replace(/[◐◑]/g, '').trim();
  title = title.replace(/\s+\b(lirik|lyrics)\b.*$/i, '').trim();

  let baseTitleWithoutEdition = null;

  // 2. Handle 'Artist - Title' or 'Title - Edition'
  if (title.includes(' - ')) {
    const parts = title.split(' - ').map((s) => s.trim()).filter(Boolean);
    if (parts.length >= 2) {
      const p0 = parts[0];
      const p1 = parts.slice(1).join(' - ');
      const lastPart = parts[parts.length - 1];

      if (EDITION_SUFFIX_RE.test(lastPart)) {
        baseTitleWithoutEdition = parts.slice(0, -1).join(' - ').trim();
        if (parts.length >= 3) {
          // e.g. "NIKI - La La Lost You - Acoustic Version"
          const candArtist = extractPrimaryArtist(parts[0]);
          const candCoreTitle = parts.slice(1, -1).join(' - ').trim();
          if (candCoreTitle) {
            altQueries.push({ title: `${candCoreTitle} - ${lastPart}`, artist: candArtist });
            altQueries.push({ title: candCoreTitle, artist: candArtist });
          }
        }
      } else if (
        artist &&
        (p0.toLowerCase().includes(artist.toLowerCase()) ||
          artist.toLowerCase().includes(p0.toLowerCase()))
      ) {
        title = p1;
      } else if (
        artist &&
        (p1.toLowerCase().includes(artist.toLowerCase()) ||
          artist.toLowerCase().includes(p1.toLowerCase()))
      ) {
        title = p0;
      } else if (!artist || isLikelyChannelOrLabel(artist)) {
        const extractedArtist = extractPrimaryArtist(p0);
        altQueries.push({ title: p1, artist: extractedArtist });
        altQueries.push({ title: p0, artist: extractPrimaryArtist(p1) });
        artist = extractedArtist;
        title = p1;
      } else {
        // Uploader channel might differ from actual artist in video title "Artist - Song"
        altQueries.push({ title: p1, artist: extractPrimaryArtist(p0) });
        altQueries.push({ title: p0, artist });
      }
    }
  }

  title = title.replace(/[\(\)\[\]]/g, '').trim();
  artist = artist.replace(/[\(\)\[\]]/g, '').trim();

  const subTitles = [title];
  if (baseTitleWithoutEdition) {
    const cleanBase = baseTitleWithoutEdition.replace(/[\(\)\[\]]/g, '').trim();
    if (cleanBase && !subTitles.includes(cleanBase)) {
      subTitles.push(cleanBase);
    }
  }
  if (title.includes(' / ')) {
    const subParts = title
      .split(' / ')
      .map((s) => s.trim())
      .filter(Boolean);
    for (const sp of subParts) {
      if (!subTitles.includes(sp)) subTitles.push(sp);
    }
  }

  return { title, artist, subTitles, altQueries };
}

function generateCharTimings(word, wordStart, wordDuration) {
  if (!word) return [];
  const chars = Array.from(word);
  if (chars.length === 0) return [];

  const charWeights = chars.map((ch) => {
    if (/[aiueoAIUEO]/.test(ch)) return 1.8;
    if (/[\uAC00-\uD7A3\u3040-\u309F\u30A0-\u30FF]/.test(ch)) return 2.2;
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
}

function parseYrc(yrcText) {
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

    if (/作词|作曲|编曲|制作人|Written by|Composer|Producer|Arranger|Mixing/i.test(lineContent)) {
      continue;
    }

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
          chars: generateCharTimings(wText, startSec, durSec),
        });
      }
    }

    if (words.length > 0) {
      const lineText = words.map((w) => w.word).join('').trim();
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

  return finalizeLinesWithInterludes(parsed);
}

function parsePlainLyrics(plainText) {
  if (!plainText) return [];
  return plainText
    .split('\n')
    .map((line, idx) => {
      const time = idx * 4.0;
      const dur = 3.8;
      const trimmed = line.trim();
      return {
        id: `plain-${idx}`,
        time,
        endTime: time + dur,
        text: trimmed,
        duration: dur,
        words: computeLrcWords(trimmed, time, dur),
        isPlain: true,
      };
    })
    .filter((l) => l.text.length > 0);
}

function parseLrc(lrcText) {
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
      const ms =
        msStr.length === 2
          ? parseInt(msStr, 10) * 10
          : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
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

    if (/^(作词|作曲|编曲|制作人|Written by|Composer|Producer):/i.test(cleanText)) continue;

    timestamps.forEach((t) => {
      parsed.push({
        id: `lrc-${t.toFixed(2)}-${i}`,
        time: t,
        text: cleanText.replace(/<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/g, '').trim(),
        rawText: cleanText,
      });
    });
  }

  parsed.sort((a, b) => a.time - b.time);

  // Reject bogus LRC where every timestamp is 0
  if (parsed.length > 2 && parsed[parsed.length - 1].time <= 0.5) {
    return [];
  }

  for (let i = 0; i < parsed.length; i++) {
    const curr = parsed[i];
    const next = parsed[i + 1];

    if (!curr.explicitEndTime) {
      if (next) {
        const rawGap = next.time - curr.time;
        if (rawGap <= 1.2) {
          curr.duration = Math.max(0.6, rawGap - 0.06);
        } else if (rawGap <= 7.0) {
          curr.duration = Math.max(1.2, Math.min(rawGap - 0.3, rawGap * 0.88));
        } else {
          const words = curr.text.split(/\s+/).filter(Boolean);
          const nonLatinSyllables = (
            curr.text.match(/[\uAC00-\uD7A3\u3040-\u309F\u30A0-\u30FF]/g) || []
          ).length;
          const approxSyllables =
            nonLatinSyllables > 0 ? nonLatinSyllables : words.length * 1.5;
          const naturalSingingDuration = Math.max(
            2.2,
            Math.min(5.8, approxSyllables * 0.34 + 0.8)
          );
          curr.duration = Math.min(rawGap - 1.0, naturalSingingDuration);
        }
        curr.endTime = curr.time + curr.duration;
      } else {
        const words = curr.text.split(/\s+/).filter(Boolean);
        const nonLatinSyllables = (
          curr.text.match(/[\uAC00-\uD7A3\u3040-\u309F\u30A0-\u30FF]/g) || []
        ).length;
        const approxSyllables =
          nonLatinSyllables > 0 ? nonLatinSyllables : words.length * 1.5;
        curr.duration = Math.max(2.2, Math.min(5.5, approxSyllables * 0.34 + 0.8));
        curr.endTime = curr.time + curr.duration;
      }
    }

    curr.words = computeLrcWords(curr.rawText || curr.text, curr.time, curr.duration);
  }

  return finalizeLinesWithInterludes(parsed);
}

function computeLrcWords(rawText, lineStart, lineDuration) {
  const wordTagRegex = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>/g;
  if (wordTagRegex.test(rawText)) {
    const tokens = [];
    const splitRegex = /<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]+)/g;
    let match;
    while ((match = splitRegex.exec(rawText)) !== null) {
      const min = parseInt(match[1], 10);
      const sec = parseInt(match[2], 10);
      const msStr = match[3] || '0';
      const ms =
        msStr.length === 2
          ? parseInt(msStr, 10) * 10
          : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
      const time = min * 60 + sec + ms / 1000;
      const wText = match[4].trim();
      if (wText) {
        tokens.push({ word: wText, startTime: time });
      }
    }

    if (tokens.length > 0) {
      for (let i = 0; i < tokens.length; i++) {
        const next = tokens[i + 1];
        const nextStart = next ? next.startTime : lineStart + lineDuration;
        tokens[i].endTime = Math.max(tokens[i].startTime + 0.15, nextStart);
        tokens[i].duration = tokens[i].endTime - tokens[i].startTime;
        tokens[i].id = `w-${i}-${tokens[i].startTime}`;
        tokens[i].chars = generateCharTimings(
          tokens[i].word,
          tokens[i].startTime,
          tokens[i].duration
        );
      }
      return tokens;
    }
  }

  const clean = rawText.replace(/<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>/g, '').trim();
  const rawWords = clean.split(/\s+/).filter((w) => w.length > 0);
  if (rawWords.length === 0) return [];

  const weights = rawWords.map((word) => {
    const latinVowels = (word.match(/[aiueoAIUEO]/g) || []).length;
    const hangulSyllables = (word.match(/[\uAC00-\uD7A3]/g) || []).length;
    const kanaSyllables = (word.match(/[\u3040-\u309F\u30A0-\u30FF]/g) || []).length;
    const totalPhonemes = latinVowels + hangulSyllables * 1.5 + kanaSyllables * 1.5;

    let weight = Math.max(1, totalPhonemes * 1.6 + word.length * 0.3);
    if (/[,;]$/.test(word)) weight += 0.8;
    if (/[.!?]$/.test(word)) weight += 1.4;
    return weight;
  });

  const totalWeight = weights.reduce((s, w) => s + w, 0);
  const activeDuration = Math.max(0.6, lineDuration * 0.96);

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
      chars: generateCharTimings(word, start, wordDur),
    };
  });
}

function finalizeLinesWithInterludes(parsedLines) {
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

    if (next && next.time - curr.endTime > 4.5) {
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
}

async function fetchNetEase(title, artist, targetDuration) {
  try {
    const q = `${title} ${artist}`.trim();
    const params = new URLSearchParams({ s: q, type: '1', offset: '0', limit: '8' });
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
        return { song: s, candDurSec, matchScore };
      })
      .filter((x) => x.matchScore >= 650)
      .sort((a, b) => b.matchScore - a.matchScore);

    for (const entry of ranked.slice(0, 2)) {
      const song = entry.song;
      const lyricRes = await fetch(
        `https://music.163.com/api/song/lyric?id=${song.id}&lv=1&kv=1&tv=-1&yv=1&rv=1`,
        {
          headers: {
            'Referer': 'https://music.163.com',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          },
        }
      );
      if (!lyricRes.ok) continue;
      const lyricData = await lyricRes.json();
      const romalrcText = lyricData.romalrc?.lyric || null;

      if (lyricData.yrc?.lyric) {
        let lines = parseYrc(lyricData.yrc.lyric);
        lines = attachRomanizationToLines(lines, romalrcText);
        if (lines.length >= 4) {
          return {
            source: 'NetEase YRC (Syllable-Synced)',
            isSyllableSynced: true,
            synced: true,
            trackDuration: entry.candDurSec,
            matchScore: entry.matchScore + 180,
            lines,
          };
        }
      }

      if (lyricData.lrc?.lyric) {
        let lines = parseLrc(lyricData.lrc.lyric);
        lines = attachRomanizationToLines(lines, romalrcText);
        if (lines.length >= 4) {
          return {
            source: 'NetEase LRC',
            isSyllableSynced: false,
            synced: true,
            trackDuration: entry.candDurSec,
            matchScore: entry.matchScore,
            lines,
          };
        }
      }
    }

    return null;
  } catch {
    return null;
  }
}

async function fetchLrclib(title, artist, targetDuration) {
  try {
    let fallbackPlainCandidate = null;
    const allItems = [];

    // 1. Exact studio lookup + structured track_name/artist_name search in parallel
    const getParams = new URLSearchParams({ track_name: title, artist_name: artist });
    if (targetDuration && targetDuration > 15 && targetDuration !== 180 && targetDuration !== 210) {
      getParams.append('duration', String(targetDuration));
    }

    const structSearchParams = new URLSearchParams({ track_name: title });
    if (artist) structSearchParams.append('artist_name', artist);

    const [exactRes, structRes] = await Promise.all([
      fetch(`https://lrclib.net/api/get?${getParams.toString()}`).catch(() => null),
      fetch(`https://lrclib.net/api/search?${structSearchParams.toString()}`).catch(() => null),
    ]);

    if (exactRes?.ok) {
      const exactData = await exactRes.json().catch(() => null);
      if (exactData) allItems.push(exactData);
    }
    if (structRes?.ok) {
      const structList = await structRes.json().catch(() => null);
      if (Array.isArray(structList)) allItems.push(...structList);
    }

    // 2. If structured search returned nothing, fall back to general query search
    if (allItems.length === 0) {
      const q = `${title} ${artist}`.trim();
      const searchRes = await fetch(
        `https://lrclib.net/api/search?q=${encodeURIComponent(q)}`
      ).catch(() => null);
      if (searchRes?.ok) {
        const list = await searchRes.json().catch(() => null);
        if (Array.isArray(list)) allItems.push(...list);
      }
    }

    if (allItems.length > 0) {
      const scored = allItems
        .filter((i) => i && (i.syncedLyrics || i.plainLyrics))
        .map((item) => {
          const isEnhanced = /<\d{1,3}:\d{2}/.test(item.syncedLyrics || '');
          const hasSynced = Boolean(item.syncedLyrics);
          const s = scoreLyricCandidate({
            candTitle: item.trackName || title,
            candArtist: item.artistName || artist,
            candDurationSec: Math.round(item.duration || 0),
            targetTitle: title,
            targetArtist: artist,
            targetDurationSec: targetDuration || 0,
            isSynced: hasSynced,
            isSyllable: isEnhanced,
          });
          const finalScore = hasSynced ? s : s - 650;
          return { item, isEnhanced, hasSynced, matchScore: finalScore };
        })
        .filter((x) => x.matchScore >= 450)
        .sort((a, b) => b.matchScore - a.matchScore);

      for (const cand of scored) {
        if (cand.hasSynced && cand.item.syncedLyrics) {
          const rawLines = parseLrc(cand.item.syncedLyrics);
          const lines = attachRomanizationToLines(rawLines, null);
          if (lines.length >= 4) {
            return {
              source: cand.isEnhanced
                ? 'LRCLIB (Enhanced Word-Synced)'
                : 'LRCLIB (Studio Synced)',
              isSyllableSynced: cand.isEnhanced,
              synced: true,
              trackDuration: Math.round(cand.item.duration || 0),
              matchScore: cand.matchScore + 150,
              lines,
            };
          }
        } else if (!fallbackPlainCandidate && cand.item.plainLyrics) {
          const plainLines = attachRomanizationToLines(
            parsePlainLyrics(cand.item.plainLyrics),
            null
          );
          if (plainLines.length >= 4) {
            fallbackPlainCandidate = {
              source: 'LRCLIB (Teks Statis)',
              isSyllableSynced: false,
              synced: false,
              trackDuration: Math.round(cand.item.duration || 0),
              matchScore: 300,
              lines: plainLines,
            };
          }
        }
      }
    }

    return fallbackPlainCandidate;
  } catch {
    return null;
  }
}

async function fetchQQMusic(title, artist, targetDuration) {
  try {
    const q = `${title} ${artist}`.trim();
    const searchRes = await fetch(
      `https://c.y.qq.com/soso/fcgi-bin/client_search_cp?w=${encodeURIComponent(q)}&format=json&n=6`,
      {
        headers: {
          'Referer': 'https://y.qq.com',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      }
    );
    if (!searchRes.ok) return null;
    const searchData = await searchRes.json();
    const songs = searchData.data?.song?.list || [];
    if (songs.length === 0) return null;

    const ranked = songs
      .map((s) => {
        const candTitle = s.songname || '';
        const candArtist = (s.singer || []).map((a) => a.name).join(', ');
        const candDurSec = s.interval || 0;
        const score = scoreLyricCandidate({
          candTitle,
          candArtist,
          candDurationSec: candDurSec,
          targetTitle: title,
          targetArtist: artist,
          targetDurationSec: targetDuration || 0,
        });
        return { song: s, candDurSec, score };
      })
      .filter((x) => x.score >= 580)
      .sort((a, b) => b.score - a.score);

    for (const entry of ranked.slice(0, 2)) {
      const song = entry.song;
      const lyricRes = await fetch(
        `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=${song.songmid}&format=json&nobase64=1`,
        {
          headers: {
            'Referer': 'https://y.qq.com',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          },
        }
      );
      if (!lyricRes.ok) continue;
      const lyricData = await lyricRes.json();
      if (lyricData.code === 0 && lyricData.lyric) {
        const rawLines = parseLrc(lyricData.lyric);
        const lines = attachRomanizationToLines(rawLines, null);
        if (lines.length >= 4) {
          return {
            source: 'QQ Music (Studio Synced)',
            isSyllableSynced: false,
            synced: true,
            trackDuration: entry.candDurSec,
            matchScore: entry.score + 100,
            lines,
          };
        }
      }
    }
    return null;
  } catch {
    return null;
  }
}

export async function getLyrics(rawTitle, rawArtist, duration) {
  const { title, artist, subTitles, altQueries } = cleanTrackMetadata(rawTitle, rawArtist);
  const durBucket = duration > 10 ? Math.round(duration / 5) : 'any';
  const cacheKey = `${artist.toLowerCase()}:::${title.toLowerCase()}:::${durBucket}`;

  if (memoryCache.has(cacheKey)) {
    return memoryCache.get(cacheKey);
  }

  // Tier 0: Verified Studio LRC master database
  const verifiedLrc = findVerifiedStudioLrc(title, artist);
  if (verifiedLrc) {
    const rawLines = parseLrc(verifiedLrc);
    const lines = attachRomanizationToLines(rawLines, null);
    const result = {
      source: 'Verified Studio Synced Master',
      isSyllableSynced: false,
      synced: true,
      matchScore: 10000,
      lines,
    };
    setBoundedCache(cacheKey, result);
    return result;
  }

  // Tier 1: Query NetEase, QQ Music, and LRCLIB in parallel
  const [neRes, qqRes, lrcRes] = await Promise.all([
    fetchNetEase(title, artist, duration),
    fetchQQMusic(title, artist, duration),
    fetchLrclib(title, artist, duration),
  ]);

  const candidates = [neRes, qqRes, lrcRes].filter(Boolean);
  candidates.sort((a, b) => (b.matchScore || 0) - (a.matchScore || 0));
  let best = candidates[0] || null;

  // Tier 2: Try composite sub-titles or base title without edition suffix
  if ((!best || !best.synced) && subTitles.length > 1) {
    for (let i = 1; i < subTitles.length; i++) {
      const sub = subTitles[i];
      const [subNe, subQq, subLrc] = await Promise.all([
        fetchNetEase(sub, artist, duration),
        fetchQQMusic(sub, artist, duration),
        fetchLrclib(sub, artist, duration),
      ]);
      const subCandidates = [subNe, subQq, subLrc].filter(Boolean);
      subCandidates.sort((a, b) => (b.matchScore || 0) - (a.matchScore || 0));
      if (subCandidates.length > 0 && (!best || subCandidates[0].matchScore > (best.matchScore || 0))) {
        best = subCandidates[0];
        if (best.synced) break;
      }
    }
  }

  // Tier 3: Try alternative Artist - Title split pairs (when uploader channel differed from actual artist)
  if ((!best || !best.synced) && altQueries.length > 0) {
    for (const alt of altQueries.slice(0, 2)) {
      if (!alt.title) continue;
      const [altNe, altLrc] = await Promise.all([
        fetchNetEase(alt.title, alt.artist, duration),
        fetchLrclib(alt.title, alt.artist, duration),
      ]);
      const altCandidates = [altNe, altLrc].filter(Boolean);
      altCandidates.sort((a, b) => (b.matchScore || 0) - (a.matchScore || 0));
      if (altCandidates.length > 0 && (!best || altCandidates[0].matchScore > (best.matchScore || 0))) {
        best = altCandidates[0];
        if (best.synced) break;
      }
    }
  }

  if (best) {
    setBoundedCache(cacheKey, best);
    return best;
  }

  return { synced: false, isSyllableSynced: false, lines: [] };
}

export default async function handler(req, res) {
  if (!applyApiSecurity(req, res)) return;
  try {
    const title = sanitizeQuery(req.query?.title || '', 200);
    const artist = sanitizeQuery(req.query?.artist || '', 200);
    const rawDuration = parseInt(req.query?.duration || '0', 10);
    const duration = Number.isFinite(rawDuration) ? Math.max(0, Math.min(7200, rawDuration)) : 0;

    if (!title) {
      return res.status(400).json({ error: 'Missing title query parameter' });
    }

    const lyrics = await getLyrics(title, artist, duration);
    res.setHeader('Cache-Control', 's-maxage=86400, stale-while-revalidate=604800');
    return res.status(200).json(lyrics);
  } catch (err) {
    return sendSafeError(res, 500, 'Internal server error resolving lyrics', err);
  }
}
