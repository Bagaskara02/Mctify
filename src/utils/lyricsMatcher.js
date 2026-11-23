/**
 * Strict Lyric Candidate Scoring & Metadata Normalization
 * Prevents wrong-artist, live/remix, and duration-mismatched lyrics from being served on Web.
 * Preserves all Unicode scripts (Latin, Korean Hangul, Japanese Kana/Kanji, Chinese, Cyrillic, etc.).
 */

const ARTIST_STOPWORDS = new Set([
  'the',
  'dj',
  'mc',
  'mr',
  'mrs',
  'ms',
  'dr',
  'st',
  'lil',
  'young',
  'big',
  'kid',
  'and',
  'with',
  'feat',
  'ft',
  'band',
  'music',
  'official',
  'topic',
  'vevo',
  'records',
  'record',
  'recordings',
  'entertainment',
  'production',
  'productions',
  'label',
  'labels',
  'channel',
  'tv',
  'audio',
  'video',
  'indonesia',
  'musikindo',
  'optima',
  'trinity',
  'aquarius',
  'musica',
  'studios',
  'hits',
  'smtown',
  'hybe',
  'jyp',
  'yg',
  'avex',
  'sony',
  'warner',
  'universal',
]);

const CHANNEL_OR_LABEL_RE =
  /\b(musikindo|records|recordings|entertainment|production|productions|studios|official\s*channel|smtown|hybe\s*labels|jyp\s*entertainment|yg\s*entertainment|trinity\s*optima|aquarius\s*musikindo|musica\s*studio|hits\s*records|nagaswara|pelangi\s*records|le\s*moraes|1thek|stone\s*music|genie\s*music|bugs|melon|88rising|vevo|youtube)\b/i;

export function isLikelyChannelOrLabel(artist = '') {
  const raw = String(artist || '').trim();
  if (!raw) return true;
  return CHANNEL_OR_LABEL_RE.test(raw);
}

export function normalizeLyricText(str = '') {
  return String(str)
    .toLowerCase()
    .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function extractPrimaryArtist(artist = '') {
  return String(artist)
    .replace(/\s*-\s*Topic$/i, '')
    .replace(/\s*VEVO$/i, '')
    .replace(/\s*Official(\s*Channel|\s*Music)?$/i, '')
    .split(/,|&|\bfeat\.?\b|\bft\.?\b|\bwith\b|\bx\b/i)[0]
    .trim();
}

function getDistinctiveTokens(normStr, filterStopwords = false) {
  if (!normStr) return [];
  const all = normStr.split(' ').filter((w) => w.length >= 2 || /[^\u0000-\u007f]/.test(w));
  if (!filterStopwords) return all;
  const filtered = all.filter((w) => !ARTIST_STOPWORDS.has(w));
  return filtered.length > 0 ? filtered : all;
}

export function scoreLyricCandidate({
  candTitle = '',
  candArtist = '',
  candDurationSec = 0,
  targetTitle = '',
  targetArtist = '',
  targetDurationSec = 0,
  isSynced = true,
  isSyllable = false,
}) {
  const normCandTitle = normalizeLyricText(candTitle);
  const normTargetTitle = normalizeLyricText(targetTitle);
  const normCandArtist = normalizeLyricText(candArtist);
  const normTargetArtist = normalizeLyricText(extractPrimaryArtist(targetArtist) || targetArtist);

  if (!normCandTitle || !normTargetTitle) return -9999;

  let score = 0;
  let isExactTitle = false;
  let isExactArtist = false;

  // 1. Strict Artist verification (using whole-token matching, ignoring stopwords like "the" / "dj")
  const targetIsGenericLabel = isLikelyChannelOrLabel(targetArtist);
  if (normTargetArtist && !targetIsGenericLabel) {
    const candArtistTokens = new Set(getDistinctiveTokens(normCandArtist, false));
    const targetArtistTokens = getDistinctiveTokens(normTargetArtist, true);

    const hasExactArtist =
      normCandArtist === normTargetArtist ||
      (normTargetArtist.length >= 4 &&
        (normCandArtist.split(' ').join('') === normTargetArtist.split(' ').join('') ||
          (targetArtistTokens.length > 0 &&
            targetArtistTokens.every((tok) => candArtistTokens.has(tok)))));

    const matchedTokenCount = targetArtistTokens.filter((tok) => candArtistTokens.has(tok)).length;

    if (hasExactArtist) {
      score += 750;
      isExactArtist = true;
    } else if (targetArtistTokens.length > 0 && matchedTokenCount > 0) {
      score += Math.round(350 * (matchedTokenCount / targetArtistTokens.length));
    } else {
      // Unrelated artist -> reject completely
      return -5000;
    }
  }

  // 2. Title match scoring (whole-token boundary aware so "Stay" doesn't match "Don't Stay")
  const candTitleTokens = getDistinctiveTokens(normCandTitle, false);
  const targetTitleTokens = getDistinctiveTokens(normTargetTitle, false);
  const candTitleTokenSet = new Set(candTitleTokens);

  if (normCandTitle === normTargetTitle) {
    score += 900;
    isExactTitle = true;
  } else if (
    targetTitleTokens.length > 0 &&
    targetTitleTokens.every((tok) => candTitleTokenSet.has(tok))
  ) {
    const extraTokens = candTitleTokens.length - targetTitleTokens.length;
    if (extraTokens === 0) {
      score += 850;
      isExactTitle = true;
    } else if (extraTokens <= 2) {
      score += 520;
    } else {
      score += 320;
    }
  } else if (
    normTargetTitle.length >= 5 &&
    (normCandTitle.startsWith(normTargetTitle + ' ') ||
      normTargetTitle.startsWith(normCandTitle + ' '))
  ) {
    score += 480;
  } else {
    const matched = targetTitleTokens.filter((tok) => candTitleTokenSet.has(tok)).length;
    if (targetTitleTokens.length >= 2 && matched >= Math.ceil(targetTitleTokens.length * 0.75)) {
      score += 280;
    } else {
      return -3000;
    }
  }

  // 3. Anti-remix / live / karaoke / cover guard unless target asks for it
  const rawLowerCand = `${candTitle} ${candArtist}`.toLowerCase();
  const rawLowerTarget = `${targetTitle} ${targetArtist}`.toLowerCase();
  const guardTerms = [
    'remix',
    'live',
    'acoustic',
    'slowed',
    'reverb',
    'sped up',
    'karaoke',
    'instrumental',
    'cover',
    'nightcore',
  ];
  for (const term of guardTerms) {
    if (rawLowerCand.includes(term) && !rawLowerTarget.includes(term)) {
      score -= 2200;
    }
  }

  // 4. Duration proximity validation
  // Note: If targetDurationSec is a 180/210 placeholder or MV duration, never let duration penalty
  // disqualify an otherwise verified exact title + exact artist match, while still ranking closest duration #1!
  if (targetDurationSec > 10 && candDurationSec > 10) {
    const diff = Math.abs(candDurationSec - targetDurationSec);
    if (diff <= 3) {
      score += 600;
    } else if (diff <= 6) {
      score += 350;
    } else if (diff <= 10) {
      score += 80;
    } else if (diff <= 16) {
      score -= 350;
    } else if (isExactTitle && isExactArtist) {
      // Soft penalty so exact studio song still passes threshold (>= 600) if no closer duration exists,
      // but loses to another candidate of the same song that matches the exact duration!
      score -= Math.min(850, 250 + Math.round((diff - 16) * 12));
    } else {
      score -= 2400;
    }
  }

  // 5. Sync quality bonus
  if (isSynced) score += 250;
  if (isSyllable) score += 180;

  return score;
}
