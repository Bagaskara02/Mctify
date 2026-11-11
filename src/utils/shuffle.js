/**
 * Spotify-style Balanced Bucket-Spaced Fisher-Yates Shuffle Deck Builder
 * Inspired by Spotify Engineering ("How to shuffle songs"):
 * - Groups tracks by primary artist and Fisher-Yates shuffles within each artist bucket.
 * - Spaces each artist's tracks evenly across [0, 1) with random offset + jitter so an artist
 *   never clusters together when other artists exist.
 * - Runs a local non-adjacent swap pass to respect anchorTrack (index 0) and neighbors.
 * - Guarantees 100% coverage: every track plays once before repeating.
 */
function primaryArtistKey(track) {
  return String(track?.artist || '').split(',')[0].trim().toLowerCase() || '__unknown__';
}

function fisherYatesShuffle(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}

export function buildSpotifyShuffleDeck(tracks = [], anchorTrack = null) {
  if (!Array.isArray(tracks) || tracks.length === 0) return [];

  let resolvedAnchor = null;
  const remaining = [];

  for (const t of tracks) {
    if (!t) continue;
    if (anchorTrack && t.id === anchorTrack.id && !resolvedAnchor) {
      resolvedAnchor = t;
    } else {
      remaining.push(t);
    }
  }

  if (remaining.length <= 1) {
    return resolvedAnchor ? [resolvedAnchor, ...remaining] : remaining;
  }

  // Group by primary artist and Fisher-Yates shuffle each bucket
  const buckets = new Map();
  for (const t of remaining) {
    const key = primaryArtistKey(t);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(t);
  }

  // Distribute each artist's tracks evenly across [0, 1) with random phase & jitter
  const weighted = [];
  for (const group of buckets.values()) {
    fisherYatesShuffle(group);
    const step = 1 / group.length;
    const phase = Math.random() * step;
    for (let k = 0; k < group.length; k++) {
      const jitter = (Math.random() - 0.5) * step * 0.35;
      weighted.push({ track: group[k], pos: phase + k * step + jitter });
    }
  }

  weighted.sort((a, b) => a.pos - b.pos);
  const deck = weighted.map((item) => item.track);

  // Repair any remaining adjacent same-artist pair (including after anchorTrack) when possible
  const anchorKey = resolvedAnchor ? primaryArtistKey(resolvedAnchor) : null;
  for (let i = 0; i < deck.length; i++) {
    const curKey = primaryArtistKey(deck[i]);
    const prevKey = i === 0 ? anchorKey : primaryArtistKey(deck[i - 1]);
    if (prevKey && curKey === prevKey) {
      for (let j = i + 1; j < deck.length; j++) {
        const candKey = primaryArtistKey(deck[j]);
        const jPrev = primaryArtistKey(deck[j - 1]);
        const jNext = j + 1 < deck.length ? primaryArtistKey(deck[j + 1]) : null;
        if (candKey !== prevKey && curKey !== jPrev && curKey !== jNext) {
          [deck[i], deck[j]] = [deck[j], deck[i]];
          break;
        }
      }
    }
  }

  return resolvedAnchor ? [resolvedAnchor, ...deck] : deck;
}
