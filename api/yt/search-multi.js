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

const parseSubCount = (str) => {
  if (!str) return 0;
  const s = String(str).toLowerCase().replace(',', '.');
  const m = s.match(/([\d.]+)\s*(jt|m|rb|k)?/);
  if (!m) return 0;
  let val = parseFloat(m[1]) || 0;
  if (m[2] === 'jt' || m[2] === 'm') val *= 1000000;
  else if (m[2] === 'rb' || m[2] === 'k') val *= 1000;
  return Math.round(val);
};

const cleanSuggestions = (sections, qLower) => {
  const out = [];
  const wantsJunk = qLower.includes('karaoke') || qLower.includes('lirik') || qLower.includes('lyrics');
  for (const sec of sections || []) {
    for (const item of sec?.contents || []) {
      const text = (item?.suggestion?.text || item?.title?.text || '').trim();
      if (!text) continue;
      if (!wantsJunk && /\b(karaoke|minus one|backing track|slowed|reverb|lyrics video)\b/i.test(text)) continue;
      if (!out.includes(text)) out.push(text);
      if (out.length >= 8) return out;
    }
  }
  return out;
};

const formatFans = (n) => {
  const num = Number(n) || 0;
  if (num >= 1000000) return `${(num / 1000000).toFixed(1).replace('.', ',')} jt pendengar`;
  if (num >= 1000) return `${Math.round(num / 1000)} rb pendengar`;
  return num > 0 ? `${num} pendengar` : '';
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
    const q = (url.searchParams.get('q') || req.query?.q || '').trim();
    const mode = url.searchParams.get('mode') || req.query?.mode || 'full';

    if (!q) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing query' }));
    }

    const yt = await getYT();

    // Fast typeahead autocomplete endpoint (?mode=suggest)
    if (mode === 'suggest') {
      const sugSections = await yt.music.getSearchSuggestions(q).catch(() => []);
      const suggestions = cleanSuggestions(sugSections, q.toLowerCase());
      res.setHeader('Content-Type', 'application/json');
      res.setHeader('Cache-Control', 'public, s-maxage=3600, stale-while-revalidate=7200');
      return res.end(JSON.stringify({ suggestions }));
    }

    const [songResults, artistResults, albumResults, deezerArtistData, sugSections] = await Promise.all([
      yt.music.search(q, { type: 'song' }).catch(() => ({})),
      yt.music.search(q, { type: 'artist' }).catch(() => ({})),
      yt.music.search(q, { type: 'album' }).catch(() => ({})),
      fetch(`https://api.deezer.com/search/artist?q=${encodeURIComponent(q)}&limit=8`)
        .then((r) => (r.ok ? r.json() : { data: [] }))
        .catch(() => ({ data: [] })),
      yt.music.getSearchSuggestions(q).catch(() => []),
    ]);

    const rawSongs = songResults.songs?.contents || songResults.results || [];
    const rawArtists = artistResults.artists?.contents || artistResults.results || [];
    const rawAlbums = albumResults.albums?.contents || albumResults.results || [];

    const qLower = q.toLowerCase();
    const isKaraokeReq = qLower.includes('karaoke');
    const isInstrumentalReq = qLower.includes('instrumental') || qLower.includes('instrumen');
    const isCoverReq = qLower.includes('cover');
    const isVideoReq = qLower.includes('video') || qLower.includes('mv');
    const isSlowedReq = qLower.includes('slowed') || qLower.includes('reverb') || qLower.includes('sped up');

    const filteredSongs = rawSongs.filter((s) => {
      const titleStr = (typeof s.title === 'string' ? s.title : s.title?.text || '').toLowerCase();
      const artistStr = (s.artists?.[0]?.name || s.author?.name || '').toLowerCase();
      const combined = `${titleStr} ${artistStr}`;

      if (!isKaraokeReq && (combined.includes('karaoke') || combined.includes('made popular by') || combined.includes('backing track') || combined.includes('minus one') || combined.includes('no vocals') || combined.includes('vocal guide'))) {
        return false;
      }
      if (!isInstrumentalReq && (combined.includes('instrumental') || combined.includes('instrument') || /\binstr\.?\b/i.test(combined))) {
        return false;
      }
      if (!isCoverReq && (combined.includes('guitar cover') || combined.includes('piano cover') || combined.includes('drum cover') || combined.includes('acoustic cover') || combined.includes('violin cover'))) {
        return false;
      }
      if (!isSlowedReq && /\b(slowed|reverb|slowed \+ reverb|slowed and reverb|sped up|speed up|nightcore|8d audio)\b/i.test(combined)) {
        return false;
      }
      if (!isVideoReq && (combined.includes('music video') || combined.includes('official music video') || combined.includes('video klip'))) {
        return false;
      }
      if (combined.includes('parodi') || combined.includes('parody')) {
        return false;
      }
      if (/\b(type beat|free beat|instrumental beat|rap beat|trap beat)\b/i.test(combined)) {
        return false;
      }
      if (artistStr.includes('ombre2choc') || artistStr.includes('karaoke') || artistStr.includes('tribute band')) {
        return false;
      }
      return true;
    });

    const songs = filteredSongs.map((s) => {
      let durationSec = 180;
      if (s.duration?.seconds) {
        durationSec = s.duration.seconds;
      } else if (s.duration?.text) {
        const parts = s.duration.text.split(':').map(Number);
        durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      const thumb = getBestThumbnail(s);
      const titleStr = typeof s.title === 'string' ? s.title : s.title?.text || '';
      const artistStr = s.artists?.[0]?.name || s.author?.name || '';
      const albumStr = typeof s.album === 'string' ? s.album : s.album?.name || 'Single';
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

    // Deduplicate & verify real artists (Deezer fan-ranked + YouTube Music verified)
    const artistMap = new Map();

    // First register YouTube Music verified artists with parsed fan counts
    for (const a of rawArtists) {
      const name = (a.name || '').trim();
      const key = name.toLowerCase();
      if (!name || name.endsWith('...') || name.includes(' - Topic')) continue;
      const thumb = toHighResUrl(a.thumbnails?.[a.thumbnails.length - 1]?.url || a.thumbnails?.[0]?.url || '');
      if (!thumb) continue;
      const subsText = a.subscribers?.text || '';
      const fans = parseSubCount(subsText) || 50000;
      if (!artistMap.has(key)) {
        artistMap.set(key, {
          id: a.id || `yt_art_${key}`,
          name,
          artwork: thumb,
          subscribers: subsText || formatFans(fans),
          fans,
        });
      }
    }

    // Merge Deezer artists sorted by real fan count (preferring higher popularity portrait)
    for (const d of deezerArtistData?.data || []) {
      const name = (d.name || '').trim();
      const key = name.toLowerCase();
      if (!name || name.endsWith('...') || !d.picture_big) continue;
      const dzFans = Number(d.nb_fan) || 0;
      const existing = artistMap.get(key);
      if (!existing) {
        artistMap.set(key, {
          id: `dz_art_${d.id}`,
          name,
          artwork: d.picture_xl || d.picture_big || d.picture_medium,
          subscribers: formatFans(dzFans),
          fans: dzFans,
        });
      } else if (dzFans > existing.fans) {
        artistMap.set(key, {
          ...existing,
          artwork: d.picture_xl || d.picture_big || existing.artwork,
          subscribers: formatFans(dzFans),
          fans: dzFans,
        });
      }
    }

    const artists = Array.from(artistMap.values())
      .sort((a, b) => {
        const an = a.name.toLowerCase();
        const bn = b.name.toLowerCase();
        const aExact = an === qLower ? 2 : an.startsWith(qLower) ? 1 : 0;
        const bExact = bn === qLower ? 2 : bn.startsWith(qLower) ? 1 : 0;
        if (aExact !== bExact) return bExact - aExact;
        return (b.fans || 0) - (a.fans || 0);
      })
      .slice(0, 12);

    const albums = rawAlbums
      .map((alb) => ({
        id: alb.id || `alb_${(alb.title?.text || alb.title || '').toLowerCase()}`,
        title: typeof alb.title === 'string' ? alb.title : alb.title?.text || '',
        artist: alb.artists?.[0]?.name || alb.author?.name || '',
        year: alb.year || '',
        artwork: getBestThumbnail(alb),
      }))
      .filter((a) => a.title && a.artwork)
      .slice(0, 10);

    const suggestions = cleanSuggestions(sugSections, qLower);

    res.setHeader('Content-Type', 'application/json');
    res.setHeader('Cache-Control', 'public, s-maxage=43200, stale-while-revalidate=86400');
    return res.end(JSON.stringify({ songs, artists, albums, suggestions }));
  } catch (e) {
    console.error('API /api/yt/search-multi error:', e);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: e.message }));
  }
}
