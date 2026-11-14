/**
 * Romanizer Utility for McTify Lyrics
 * Provides Romanization ("Huruf Biasa" / Latin script) for:
 * 1. Korean (Hangul -> Revised Romanization of Korean)
 * 2. Japanese (Hiragana & Katakana -> Romaji)
 * 3. Studio-grade NetEase romalrc alignment & syllable/word retiming
 */

// Consonants & Vowels for Korean Hangul Syllable Decomposing (Unicode 0xAC00 - 0xD7A3)
const CHOSEONG = [
  'g', 'kk', 'n', 'd', 'tt', 'r', 'm', 'b', 'pp', 's', 'ss', '', 'j', 'jj', 'ch', 'k', 't', 'p', 'h'
];

const JUNGSEONG = [
  'a', 'ae', 'ya', 'yae', 'eo', 'e', 'yeo', 'ye', 'o', 'wa', 'wae', 'oe', 'yo', 'u', 'wo', 'we', 'wi', 'yu', 'eu', 'ui', 'i'
];

const JONGSEONG = [
  '', 'k', 'k', 'ks', 'n', 'nj', 'nh', 't', 'l', 'lg', 'lm', 'lb', 'ls', 'lt', 'lp', 'lh', 'm', 'p', 'ps', 's', 'ss', 'ng', 't', 'ch', 'k', 't', 'p', 'h'
];

// Japanese Kana Map (Hiragana & Katakana -> Romaji)
const KANA_MAP = {
  // Digraphs (Hiragana)
  'きゃ': 'kya', 'きゅ': 'kyu', 'きょ': 'kyo',
  'しゃ': 'sha', 'しゅ': 'shu', 'しょ': 'sho',
  'ちゃ': 'cha', 'ちゅ': 'chu', 'ちょ': 'cho',
  'にゃ': 'nya', 'にゅ': 'nyu', 'にょ': 'nyo',
  'ひゃ': 'hya', 'ひゅ': 'hyu', 'ひょ': 'hyo',
  'みゃ': 'mya', 'みゅ': 'myu', 'みょ': 'myo',
  'りゃ': 'rya', 'りゅ': 'ryu', 'りょ': 'ryo',
  'ぎゃ': 'gya', 'ぎゅ': 'gyu', 'ぎょ': 'gyo',
  'じゃ': 'ja', 'じゅ': 'ju', 'じょ': 'jo',
  'びゃ': 'bya', 'びゅ': 'byu', 'びょ': 'byo',
  'ぴゃ': 'pya', 'ぴゅ': 'pyu', 'ぴょ': 'pyo',
  // Digraphs (Katakana)
  'キャ': 'kya', 'キュ': 'kyu', 'キョ': 'kyo',
  'シャ': 'sha', 'シュ': 'shu', 'ショ': 'sho',
  'チャ': 'cha', 'チュ': 'chu', 'チョ': 'cho',
  'ニャ': 'nya', 'ニュ': 'nyu', 'ニョ': 'nyo',
  'ヒャ': 'hya', 'ヒュ': 'hyu', 'ヒョ': 'hyo',
  'ミャ': 'mya', 'ミュ': 'myu', 'ミョ': 'myo',
  'リャ': 'rya', 'リュ': 'ryu', 'リョ': 'ryo',
  'ギャ': 'gya', 'ギュ': 'gyu', 'ギョ': 'gyo',
  'ジャ': 'ja', 'ジュ': 'ju', 'ジョ': 'jo',
  'ビャ': 'bya', 'ビュ': 'byu', 'ビョ': 'byo',
  'ピャ': 'pya', 'ピュ': 'pyu', 'ピョ': 'pyo',
  // Hiragana
  'あ': 'a', 'い': 'i', 'う': 'u', 'え': 'e', 'お': 'o',
  'か': 'ka', 'き': 'ki', 'く': 'ku', 'け': 'ke', 'こ': 'ko',
  'さ': 'sa', 'し': 'shi', 'す': 'su', 'せ': 'se', 'そ': 'so',
  'た': 'ta', 'ち': 'chi', 'つ': 'tsu', 'て': 'te', 'と': 'to',
  'な': 'na', 'に': 'ni', 'ぬ': 'nu', 'ね': 'ne', 'の': 'no',
  'は': 'ha', 'ひ': 'hi', 'ふ': 'fu', 'へ': 'he', 'ほ': 'ho',
  'ま': 'ma', 'み': 'mi', 'む': 'mu', 'め': 'me', 'も': 'mo',
  'や': 'ya', 'ゆ': 'yu', 'よ': 'yo',
  'ら': 'ra', 'り': 'ri', 'る': 'ru', 'れ': 're', 'ろ': 'ro',
  'わ': 'wa', 'を': 'wo', 'ん': 'n',
  'が': 'ga', 'ぎ': 'gi', 'ぐ': 'gu', 'げ': 'ge', 'ご': 'go',
  'ざ': 'za', 'じ': 'ji', 'ず': 'zu', 'ぜ': 'ze', 'ぞ': 'zo',
  'だ': 'da', 'ぢ': 'ji', 'づ': 'zu', 'で': 'de', 'ど': 'do',
  'ば': 'ba', 'び': 'bi', 'ぶ': 'bu', 'べ': 'be', 'ぼ': 'bo',
  'ぱ': 'pa', 'ぴ': 'pi', 'ぷ': 'pu', 'ぺ': 'pe', 'ぽ': 'po',
  // Katakana
  'ア': 'a', 'イ': 'i', 'ウ': 'u', 'エ': 'e', 'オ': 'o',
  'カ': 'ka', 'キ': 'ki', 'ク': 'ku', 'ケ': 'ke', 'コ': 'ko',
  'サ': 'sa', 'シ': 'shi', 'ス': 'su', 'セ': 'se', 'ソ': 'so',
  'タ': 'ta', 'チ': 'chi', 'ツ': 'tsu', 'テ': 'te', 'ト': 'to',
  'ナ': 'na', 'ニ': 'ni', 'ヌ': 'nu', 'ネ': 'ne', 'ノ': 'no',
  'ハ': 'ha', 'ヒ': 'hi', 'フ': 'fu', 'ヘ': 'he', 'ほ': 'ho',
  'マ': 'ma', 'ミ': 'mi', 'ム': 'mu', 'メ': 'me', 'モ': 'mo',
  'ヤ': 'ya', 'ユ': 'yu', 'ヨ': 'yo',
  'ラ': 'ra', 'リ': 'ri', 'ル': 'ru', 'レ': 're', 'ロ': 'ro',
  'ワ': 'wa', 'ヲ': 'wo', 'ン': 'n',
  'ガ': 'ga', 'ギ': 'gi', 'グ': 'gu', 'ゲ': 'ge', 'ゴ': 'go',
  'ザ': 'za', 'ジ': 'ji', 'ズ': 'zu', 'ゼ': 'ze', 'ゾ': 'zo',
  'ダ': 'da', 'ヂ': 'ji', 'ヅ': 'zu', 'デ': 'de', 'ド': 'do',
  'バ': 'ba', 'ビ': 'bi', 'ブ': 'bu', 'ベ': 'be', 'ボ': 'bo',
  'パ': 'pa', 'ピ': 'pi', 'プ': 'pu', 'ペ': 'pe', 'ぽ': 'po'
};

/**
 * Checks if a string contains Korean Hangul, Japanese Kana, or CJK characters
 */
export function isNonLatin(text) {
  if (!text || typeof text !== 'string') return false;
  // Hangul (AC00-D7AF, 1100-11FF, 3130-318F)
  // Hiragana (3040-309F)
  // Katakana (30A0-30FF)
  // CJK Unified Ideographs (4E00-9FFF)
  return /[\uac00-\ud7af\u1100-\u11ff\u3130-\u318f\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]/.test(text);
}

/**
 * Convert Korean Hangul to standard Revised Romanization
 */
export function romanizeKorean(text) {
  if (!text) return '';
  let result = '';

  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i) - 0xAC00;
    if (code >= 0 && code <= 11171) {
      const cho = Math.floor(code / 588);
      const jung = Math.floor((code % 588) / 28);
      const jong = code % 28;

      let choChar = CHOSEONG[cho] || '';
      let jungChar = JUNGSEONG[jung] || '';
      let jongChar = JONGSEONG[jong] || '';

      // Phonetic adjustment for initial 'r' vs 'l'
      if (choChar === 'r' && (i === 0 || text[i - 1] === ' ' || text[i - 1] === '\n')) {
        choChar = 'r';
      }

      result += choChar + jungChar + jongChar;
    } else {
      result += text[i];
    }
  }

  return result;
}

/**
 * Convert Japanese Hiragana/Katakana to Romaji
 */
export function romanizeJapanese(text) {
  if (!text) return '';
  let res = '';

  for (let i = 0; i < text.length; i++) {
    const two = text.slice(i, i + 2);
    if (KANA_MAP[two]) {
      res += KANA_MAP[two];
      i++;
      continue;
    }

    const one = text[i];

    // Sokuon (small tsu: double following consonant)
    if (one === 'っ' || one === 'ッ') {
      const nextTwo = text.slice(i + 1, i + 3);
      const nextOne = text[i + 1];
      const nextRoma = KANA_MAP[nextTwo] || KANA_MAP[nextOne] || '';
      if (nextRoma && nextRoma.length > 0) {
        res += nextRoma[0];
      }
      continue;
    }

    // Chōonpu (prolonged sound mark: extend vowel)
    if (one === 'ー') {
      const lastChar = res[res.length - 1];
      if (lastChar && /[aiueo]/i.test(lastChar)) {
        res += lastChar;
      }
      continue;
    }

    res += KANA_MAP[one] || one;
  }

  return res;
}

/**
 * Unified text romanizer for any non-Latin string (Korean, Japanese, or mixed)
 */
export function romanizeText(text) {
  if (!text || !isNonLatin(text)) return text || '';
  let converted = romanizeKorean(text);
  converted = romanizeJapanese(converted);
  return converted;
}

/**
 * Generate sub-character micro-timings for words in a lyric line
 */
export function generateCharTimings(word, wordStart, wordDuration) {
  if (!word) return [];
  const chars = Array.from(word);
  if (chars.length === 0) return [];

  // Vowels and Asian phonemes carry longer phonation in audio singing
  const charWeights = chars.map(ch => {
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

/**
 * Parse standard LRC format string into array of timestamped lines
 */
export function parseLrcTimestamps(lrcText) {
  if (!lrcText) return [];
  const rawLines = lrcText.split('\n');
  const entries = [];
  const timeRegex = /\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

  for (let i = 0; i < rawLines.length; i++) {
    const raw = rawLines[i].trim();
    if (!raw) continue;

    let match;
    timeRegex.lastIndex = 0;
    while ((match = timeRegex.exec(raw)) !== null) {
      const min = parseInt(match[1], 10);
      const sec = parseInt(match[2], 10);
      const msStr = match[3] || '0';
      const ms = msStr.length === 2 ? parseInt(msStr, 10) * 10 : parseInt(msStr.padEnd(3, '0').slice(0, 3), 10);
      const time = min * 60 + sec + ms / 1000;
      const text = raw.replace(/\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]/g, '').trim();

      if (text && !/^(作词|作曲|Written by|Composer):/i.test(text)) {
        entries.push({ time, text });
      }
    }
  }

  return entries.sort((a, b) => a.time - b.time);
}

/**
 * Attaches Romanized text and retimed romanized words to an array of lyric lines
 * 1. Prioritizes studio NetEase romalrc if supplied
 * 2. Falls back to algorithmic Korean/Japanese romanization
 */
export function attachRomanizationToLines(lines, romalrcText = null) {
  if (!Array.isArray(lines) || lines.length === 0) return lines;

  const studioRomaEntries = romalrcText ? parseLrcTimestamps(romalrcText) : [];

  return lines.map((line) => {
    // Skip instrumental interlude lines
    if (line.isInstrumental || line.isInterlude) {
      return line;
    }

    let romanized = '';

    // 1. Try matching with studio romalrc by closest timestamp (within 1.2 seconds)
    if (studioRomaEntries.length > 0) {
      const match = studioRomaEntries.find((entry) => Math.abs(entry.time - line.time) <= 1.2);
      if (match && match.text) {
        romanized = match.text;
      }
    }

    // 2. Algorithmic fallback if no studio romalrc or text is still non-Latin
    if (!romanized || isNonLatin(romanized)) {
      romanized = romanizeText(line.text);
    }

    const hasRomanization = romanized && romanized.trim() !== line.text.trim();

    // 3. Generate romanized words with sub-character timings for syllable karaoke wipe
    let romanizedWords = null;
    if (hasRomanization && Array.isArray(line.words) && line.words.length > 0) {
      romanizedWords = line.words.map((w, wIdx) => {
        const romWord = romanizeText(w.word);
        return {
          ...w,
          id: `rom-w-${wIdx}-${w.startTime}`,
          word: romWord,
          originalWord: w.word,
          chars: generateCharTimings(romWord, w.startTime, w.duration),
        };
      });
    }

    return {
      ...line,
      romanizedText: hasRomanization ? romanized : line.text,
      romanizedWords: romanizedWords || line.words,
      hasRomanization: hasRomanization,
    };
  });
}
