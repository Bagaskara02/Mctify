import {
  applyApiSecurity,
  isValidSpotifyPlaylistId,
  sendSafeError,
} from '../_security.js';

export default async function handler(req, res) {
  if (!applyApiSecurity(req, res)) return;

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    let playlistId = (url.searchParams.get('id') || req.query?.id || '').trim();
    
    // Extract playlist ID if full URL passed
    const matchId = playlistId.match(/playlist[\/:]([a-zA-Z0-9]+)/);
    if (matchId) playlistId = matchId[1];

    if (!isValidSpotifyPlaylistId(playlistId)) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Invalid or missing Spotify playlist ID' }));
    }

    const targetUrl = `https://open.spotify.com/embed/playlist/${playlistId}`;
    let html = '';
    const fetchHeaders = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'en-US,en;q=0.9',
    };

    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), 3500);
        const spotifyRes = await fetch(targetUrl, {
          headers: fetchHeaders,
          signal: controller.signal,
        });
        clearTimeout(timeoutId);
        if (spotifyRes.ok) {
          html = await spotifyRes.text();
          break;
        }
      } catch (err) {
        console.warn(`Attempt ${attempt + 1} to fetch Spotify embed failed:`, err.message);
        await new Promise(r => setTimeout(r, 300));
      }
    }

    if (!html) {
      res.statusCode = 502;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Gagal mengambil data playlist Spotify (timeout atau diblokir pihak Spotify).' }));
    }

    const match = html.match(/<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>/s);
    if (!match) {
      res.statusCode = 404;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Could not extract Spotify track metadata' }));
    }

    const data = JSON.parse(match[1]);
    const entity = data.props?.pageProps?.state?.data?.entity;

    const playlistName = entity?.name || 'Spotify Playlist';
    const coverArt = entity?.coverArt?.sources?.[0]?.url || '';
    const rawTracks = entity?.trackList || [];

    const tracks = rawTracks.map(t => ({
      title: t.title,
      artist: t.subtitle,
      duration: Math.round((t.duration || 180000) / 1000),
    })).filter(t => t.title && t.artist);

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=43200');
    return res.end(JSON.stringify({
      id: playlistId,
      name: playlistName,
      cover: coverArt,
      tracks,
    }));
  } catch (e) {
    return sendSafeError(res, 500, 'Gagal memproses playlist Spotify', e);
  }
}
