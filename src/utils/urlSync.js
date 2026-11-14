/**
 * URL Sync Utility for McTify "Dengarkan Bareng" / Discord RPC / Shared Listening
 * Supports URL parameters: ?song=...&artist=...&t=... (and ?track=..., ?q=..., ?id=...)
 */

export function parseTargetSeconds(timeParam) {
  if (timeParam === null || timeParam === undefined || timeParam === '') return 0;
  
  if (typeof timeParam === 'number') {
    return Math.max(0, timeParam);
  }

  const str = String(timeParam).trim().toLowerCase();
  
  // Format: 1m30s, 2m, 45s
  if (str.includes('m') || str.includes('s')) {
    const minMatch = str.match(/(\d+(?:\.\d+)?)\s*m/);
    const secMatch = str.match(/(\d+(?:\.\d+)?)\s*s/);
    const mins = minMatch ? parseFloat(minMatch[1]) : 0;
    const secs = secMatch ? parseFloat(secMatch[1]) : 0;
    return Math.max(0, Math.round(mins * 60 + secs));
  }

  // Format: 1:30 or 01:30:00
  if (str.includes(':')) {
    const parts = str.split(':').map(Number);
    if (parts.length === 2 && !isNaN(parts[0]) && !isNaN(parts[1])) {
      return Math.max(0, parts[0] * 60 + parts[1]);
    }
    if (parts.length === 3 && !isNaN(parts[0]) && !isNaN(parts[1]) && !isNaN(parts[2])) {
      return Math.max(0, parts[0] * 3600 + parts[1] * 60 + parts[2]);
    }
  }

  const parsed = parseFloat(str);
  return !isNaN(parsed) && Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}

export function parseUrlSyncParams(search) {
  if (!search) return null;
  const searchStr = search.startsWith('?') ? search.slice(1) : search;
  const params = new URLSearchParams(searchStr);

  const song = params.get('song') || params.get('track') || params.get('q');
  const artist = params.get('artist') || '';
  const videoId = params.get('videoId') || params.get('id') || params.get('yt');
  const timeRaw = params.get('t') || params.get('time') || params.get('seek');

  if (!song && !videoId) return null;

  return {
    song: song ? decodeURIComponent(song).trim() : null,
    artist: artist ? decodeURIComponent(artist).trim() : '',
    videoId: videoId ? decodeURIComponent(videoId).trim() : null,
    targetSeconds: parseTargetSeconds(timeRaw),
  };
}

export function generateUrlSyncLink({ song, artist, videoId, seconds = 0, baseUrl = '' }) {
  const origin = baseUrl || (typeof window !== 'undefined' ? window.location.origin : 'https://mctify.vercel.app');
  const params = new URLSearchParams();

  if (song) params.set('song', song);
  if (artist) params.set('artist', artist);
  if (videoId) params.set('videoId', videoId);
  const roundedSecs = Math.floor(seconds || 0);
  if (roundedSecs > 0) params.set('t', String(roundedSecs));

  return `${origin}/?${params.toString()}`;
}

export function formatPlaybackSeconds(seconds) {
  const s = Math.max(0, Math.floor(seconds || 0));
  const mins = Math.floor(s / 60);
  const remSecs = s % 60;
  return `${mins}:${remSecs < 10 ? '0' : ''}${remSecs}`;
}
