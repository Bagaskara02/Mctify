import { Innertube } from 'youtubei.js';

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create();
  }
  return ytPromise;
}

const toHighResUrl = (url) => {
  if (!url || typeof url !== 'string') return '';
  if (url.includes('googleusercontent.com')) {
    if (/=w\d+-h\d+/i.test(url)) return url.replace(/=w\d+-h\d+[^?#]*/i, '=w800-h800-l90-rj');
    if (/=s\d+/i.test(url)) return url.replace(/=s\d+[^?#]*/i, '=w800-h800-l90-rj');
    if (!url.includes('=')) return `${url}=w800-h800-l90-rj`;
  }
  if (url.includes('ytimg.com')) {
    if (/default\.jpg/i.test(url)) {
      return url.replace(/(default|mqdefault|sddefault)\.jpg/i, 'hq720.jpg').split('?')[0];
    }
  }
  if (url.includes('mzstatic.com')) {
    return url.replace(/\/\d+x\d+bb\./i, '/1000x1000bb.');
  }
  return url;
};

const getBestThumbnail = (item) => {
  if (!item?.thumbnails || item.thumbnails.length === 0) return '';
  const sorted = [...item.thumbnails].sort((a, b) => (b.width || 0) - (a.width || 0));
  const rawUrl = sorted[0]?.url || item.thumbnails[0]?.url || '';
  return toHighResUrl(rawUrl);
};

export default async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    return res.end();
  }

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    const q = url.searchParams.get('q') || req.query?.q;
    if (!q) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing query' }));
    }

    const yt = await getYT();
    const [songResults, artistResults] = await Promise.all([
      yt.music.search(q, { type: 'song' }).catch(() => ({})),
      yt.music.search(q, { type: 'artist' }).catch(() => ({})),
    ]);

    const rawSongs = songResults.songs?.contents || songResults.results || [];
    const rawArtists = artistResults.artists?.contents || artistResults.results || [];

    const qLower = q.toLowerCase();
    const isKaraokeReq = qLower.includes('karaoke');
    const isInstrumentalReq = qLower.includes('instrumental');
    const isCoverReq = qLower.includes('cover');
    const isVideoReq = qLower.includes('video') || qLower.includes('mv');

    const filteredSongs = rawSongs.filter(s => {
      const titleStr = (typeof s.title === 'string' ? s.title : (s.title?.text || '')).toLowerCase();
      const artistStr = (s.artists?.[0]?.name || s.author?.name || '').toLowerCase();
      const combined = `${titleStr} ${artistStr}`;

      if (!isKaraokeReq && (combined.includes('karaoke') || combined.includes('made popular by') || combined.includes('backing track'))) {
        return false;
      }
      if (!isInstrumentalReq && combined.includes('instrumental')) {
        return false;
      }
      if (!isCoverReq && (combined.includes('guitar cover') || combined.includes('piano cover') || combined.includes('drum cover'))) {
        return false;
      }
      if (!isVideoReq && (combined.includes('music video') || combined.includes('official music video') || combined.includes('video klip'))) {
        return false;
      }
      if (combined.includes('parodi') || combined.includes('parody')) {
        return false;
      }
      return true;
    });

    const songs = filteredSongs.map(s => {
      let durationSec = 180;
      if (s.duration?.seconds) {
        durationSec = s.duration.seconds;
      } else if (s.duration?.text) {
        const parts = s.duration.text.split(':').map(Number);
        durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      const thumb = getBestThumbnail(s);
      const titleStr = typeof s.title === 'string' ? s.title : (s.title?.text || '');
      const artistStr = s.artists?.[0]?.name || s.author?.name || '';
      const albumStr = typeof s.album === 'string' ? s.album : (s.album?.name || 'Single');
      return {
        id: s.id,
        videoId: s.id,
        title: titleStr,
        artist: artistStr,
        album: albumStr,
        artwork: thumb,
        duration: durationSec,
      };
    });

    const artists = rawArtists.map(a => {
      const thumb = toHighResUrl(a.thumbnails?.[a.thumbnails.length - 1]?.url || a.thumbnails?.[0]?.url || '');
      return {
        id: a.id,
        name: a.name,
        artwork: thumb,
        subscribers: a.subscribers?.text || '',
      };
    });

    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, s-maxage=43200, stale-while-revalidate=86400');
    return res.end(JSON.stringify({ songs, artists }));
  } catch (e) {
    console.error('API /api/yt/search-multi error:', e);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: e.message }));
  }
}
