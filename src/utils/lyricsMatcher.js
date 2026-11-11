/**
 * Strict Lyric Candidate Scoring & Metadata Normalization
 * Prevents wrong-artist, live/remix, and duration-mismatched lyrics from being served on Web.
 */

export function normalizeLyricText(str = '') {
  return String(str)
    .toLowerCase()
    .replace(/\([^)]*\)|\[[^\]]*\]/g, ' ')
    .replace(/[^a-z0-9\s\u00c0-\u024f]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function extractPrimaryArtist(artist = '') {
  return String(artist)
    .replace(/\s*-\s*Topic$/i, '')
    .replace(/\s*VEVO$/i, '')
    .replace(/\s*Official$/i, '')
    .split(/,|&|\bfeat\.?\b|\bft\.?\b|\bx\b/i)[0]
    .trim();
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

  // 1. Strict Artist verification
  if (normTargetArtist) {
    const targetTokens = normTargetArtist.split(' ').filter((w) => w.length > 1);
    const hasExactArtist =
      normCandArtist === normTargetArtist ||
      normCandArtist.includes(normTargetArtist) ||
      normTargetArtist.includes(normCandArtist);
    const hasAnyArtistToken =
      targetTokens.length > 0 && targetTokens.some((tok) => normCandArtist.includes(tok));

    if (hasExactArtist) {
      score += 750;
    } else if (hasAnyArtistToken) {
      score += 350;
    } else {
      // Unrelated artist -> reject completely
      return -5000;
    }
  }

  // 2. Title match scoring
  if (normCandTitle === normTargetTitle) {
    score += 900;
  } else if (normCandTitle.includes(normTargetTitle) || normTargetTitle.includes(normCandTitle)) {
    score += 500;
  } else {
    const tTokens = normTargetTitle.split(' ').filter((w) => w.length > 1);
    const matched = tTokens.filter((tok) => normCandTitle.includes(tok)).length;
    if (tTokens.length > 0 && matched === tTokens.length) {
      score += 350;
    } else {
      return -3000;
    }
  }

  // 3. Anti-remix / live / karaoke / cover guard unless target asks for it
  const rawLowerCand = `${candTitle} ${candArtist}`.toLowerCase();
  const rawLowerTarget = targetTitle.toLowerCase();
  const guardTerms = ['remix', 'live', 'acoustic', 'slowed', 'reverb', 'sped up', 'karaoke', 'instrumental', 'cover'];
  for (const term of guardTerms) {
    if (rawLowerCand.includes(term) && !rawLowerTarget.includes(term)) {
      score -= 2200;
    }
  }

  // 4. Duration proximity validation (prevents MV/Radio Edit timing drift)
  if (targetDurationSec > 10 && candDurationSec > 10) {
    const diff = Math.abs(candDurationSec - targetDurationSec);
    if (diff <= 3) {
      score += 600;
    } else if (diff <= 6) {
      score += 350;
    } else if (diff <= 10) {
      score += 50;
    } else if (diff <= 16) {
      score -= 450;
    } else {
      score -= 2400;
    }
  }

  // 5. Sync quality bonus
  if (isSynced) score += 250;
  if (isSyllable) score += 180;

  return score;
}
