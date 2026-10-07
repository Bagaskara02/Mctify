import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

function musicBackendPlugin() {
  let ytPromise = null;

  return {
    name: 'music-backend-plugin',
    configureServer(server) {
      // 1. YouTube Search & Full-Song Resolver Endpoint
      server.middlewares.use('/api/yt/search', async (req, res) => {
        try {
          const url = new URL(req.url, 'http://localhost');
          const q = url.searchParams.get('q');
          if (!q) {
            res.statusCode = 400;
            return res.end(JSON.stringify({ error: 'Missing query' }));
          }

          if (!ytPromise) {
            const { Innertube } = await import('youtubei.js');
            ytPromise = Innertube.create();
          }
          const yt = await ytPromise;

          // Search YouTube Music first
          const search = await yt.music.search(q, { type: 'song' });
          const songs = search.songs?.contents || search.results || [];
          const best = songs[0];

          if (best && best.id) {
            let durationSec = 180;
            if (best.duration?.seconds) {
              durationSec = best.duration.seconds;
            } else if (best.duration?.text) {
              const parts = best.duration.text.split(':').map(Number);
              durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
            }

            const titleStr = typeof best.title === 'string' ? best.title : (best.title?.text || '');
            const artistStr = best.artists?.[0]?.name || best.author?.name || '';
            const thumbUrl = best.thumbnails?.[best.thumbnails.length - 1]?.url || best.thumbnails?.[0]?.url || '';

            res.setHeader('Content-Type', 'application/json');
            return res.end(JSON.stringify({
              videoId: best.id,
              title: titleStr,
              artist: artistStr,
              duration: durationSec,
              thumbnail: thumbUrl,
            }));
          }

          // Fallback 1 to general YouTube search with official audio
          const general = await yt.search(q + ' official audio');
          const video = general.videos?.[0];
          if (video && video.id) {
            res.setHeader('Content-Type', 'application/json');
            return res.end(JSON.stringify({
              videoId: video.id,
              title: video.title?.text || '',
              artist: video.author?.name || '',
              duration: video.duration?.seconds || 180,
              thumbnail: video.thumbnails?.[0]?.url || '',
            }));
          }

          // Fallback 2 to general search with query
          const generalAny = await yt.search(q);
          const anyVideo = generalAny.videos?.[0];
          if (anyVideo && anyVideo.id) {
            res.setHeader('Content-Type', 'application/json');
            return res.end(JSON.stringify({
              videoId: anyVideo.id,
              title: anyVideo.title?.text || '',
              artist: anyVideo.author?.name || '',
              duration: anyVideo.duration?.seconds || 180,
              thumbnail: anyVideo.thumbnails?.[0]?.url || '',
            }));
          }

          res.statusCode = 404;
          res.end(JSON.stringify({ error: 'Song not found' }));
        } catch (e) {
          console.error('YouTube search error:', e);
          res.statusCode = 500;
          res.end(JSON.stringify({ error: e.message }));
        }
      });

      // 2. Multi-Result Search for Songs & Artists
      server.middlewares.use('/api/yt/search-multi', async (req, res) => {
        try {
          const url = new URL(req.url, 'http://localhost');
          const q = url.searchParams.get('q');
          if (!q) {
            res.statusCode = 400;
            return res.end(JSON.stringify({ error: 'Missing query' }));
          }

          if (!ytPromise) {
            const { Innertube } = await import('youtubei.js');
            ytPromise = Innertube.create();
          }
          const yt = await ytPromise;

          const [songResults, artistResults] = await Promise.all([
            yt.music.search(q, { type: 'song' }).catch(() => ({})),
            yt.music.search(q, { type: 'artist' }).catch(() => ({})),
          ]);

          const rawSongs = songResults.songs?.contents || songResults.results || [];
          const rawArtists = artistResults.artists?.contents || artistResults.results || [];

          const songs = rawSongs.map(s => {
            let durationSec = 180;
            if (s.duration?.seconds) {
              durationSec = s.duration.seconds;
            } else if (s.duration?.text) {
              const parts = s.duration.text.split(':').map(Number);
              durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
            }
            const thumb = s.thumbnails?.[s.thumbnails.length - 1]?.url || s.thumbnails?.[0]?.url || '';
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
            const thumb = a.thumbnails?.[0]?.url || '';
            return {
              id: a.id,
              name: a.name,
              artwork: thumb,
              subscribers: a.subscribers?.text || '',
            };
          });

          res.setHeader('Content-Type', 'application/json');
          return res.end(JSON.stringify({ songs, artists }));
        } catch (e) {
          console.error('YouTube multi search error:', e);
          res.statusCode = 500;
          res.end(JSON.stringify({ error: e.message }));
        }
      });

      // 3. Artist Details & Popular Singles Endpoint
      server.middlewares.use('/api/yt/artist', async (req, res) => {
        try {
          const url = new URL(req.url, 'http://localhost');
          const id = url.searchParams.get('id');
          const name = url.searchParams.get('name') || '';
          if (!id && !name) {
            res.statusCode = 400;
            return res.end(JSON.stringify({ error: 'Missing id or name' }));
          }

          if (!ytPromise) {
            const { Innertube } = await import('youtubei.js');
            ytPromise = Innertube.create();
          }
          const yt = await ytPromise;

          let topSongs = [];
          let headerBanner = '';
          let avatar = '';
          let artistName = name;

          if (id && id.startsWith('UC')) {
            try {
              const artistObj = await yt.music.getArtist(id);
              artistName = artistObj.header?.title?.text || artistObj.name || name;
              headerBanner = artistObj.header?.thumbnail?.contents?.[0]?.url || '';
              avatar = artistObj.header?.thumbnails?.[0]?.url || '';

              const shelf = artistObj.sections?.find(s => s.type === 'MusicShelf');
              if (shelf?.contents) {
                topSongs = shelf.contents.map(c => {
                  let durationSec = 180;
                  if (c.duration?.seconds) {
                    durationSec = c.duration.seconds;
                  } else if (c.duration?.text) {
                    const parts = c.duration.text.split(':').map(Number);
                    durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
                  }
                  return {
                    id: c.id,
                    videoId: c.id,
                    title: c.title,
                    artist: c.artists?.[0]?.name || artistName,
                    artwork: c.thumbnails?.[c.thumbnails.length - 1]?.url || c.thumbnails?.[0]?.url || '',
                    duration: durationSec,
                  };
                });
              }
            } catch (err) {
              console.warn('Failed to get artist by ID, falling back to search:', err.message);
            }
          }

          // Fetch additional songs from artist search
          const searchSongRes = await yt.music.search(artistName || name, { type: 'song' }).catch(() => ({}));
          const searchedSongsRaw = searchSongRes.songs?.contents || [];
          const searchedSongs = searchedSongsRaw.map(s => {
            let durationSec = 180;
            if (s.duration?.seconds) {
              durationSec = s.duration.seconds;
            } else if (s.duration?.text) {
              const parts = s.duration.text.split(':').map(Number);
              durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
            }
            return {
              id: s.id,
              videoId: s.id,
              title: s.title,
              artist: s.artists?.[0]?.name || artistName,
              artwork: s.thumbnails?.[s.thumbnails.length - 1]?.url || s.thumbnails?.[0]?.url || '',
              duration: durationSec,
            };
          });

          // Deduplicate
          const seenIds = new Set();
          const finalSongs = [];
          for (const s of [...topSongs, ...searchedSongs]) {
            if (!seenIds.has(s.id)) {
              seenIds.add(s.id);
              finalSongs.push(s);
            }
          }

          if (!avatar && finalSongs[0]?.artwork) {
            avatar = finalSongs[0].artwork;
          }
          if (!headerBanner) {
            headerBanner = avatar;
          }

          res.setHeader('Content-Type', 'application/json');
          return res.end(JSON.stringify({
            artist: {
              id: id || 'art-' + encodeURIComponent(artistName),
              name: artistName,
              headerBanner,
              avatar,
              monthlyListeners: '4,9 jt pendengar bulanan',
              verified: true,
            },
            topSongs: finalSongs.slice(0, 5),
            allSongs: finalSongs,
          }));
        } catch (e) {
          console.error('YouTube artist fetch error:', e);
          res.statusCode = 500;
          res.end(JSON.stringify({ error: e.message }));
        }
      });

      // 4. Spotify Playlist Resolver Endpoint (Direct Node bypasses browser CORS)
      server.middlewares.use('/api/spotify/playlist', async (req, res) => {
        try {
          const url = new URL(req.url, 'http://localhost');
          let playlistId = url.searchParams.get('id') || '';
          
          // Extract playlist ID if full URL passed
          const matchId = playlistId.match(/playlist[\/:]([a-zA-Z0-9]+)/);
          if (matchId) playlistId = matchId[1];

          if (!playlistId) {
            res.statusCode = 400;
            return res.end(JSON.stringify({ error: 'Missing Spotify playlist ID' }));
          }

          const targetUrl = `https://open.spotify.com/embed/playlist/${playlistId}`;
          let html = '';
          const fetchHeaders = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'en-US,en;q=0.9',
          };

          for (let attempt = 0; attempt < 3; attempt++) {
            try {
              const controller = new AbortController();
              const timeoutId = setTimeout(() => controller.abort(), 15000);
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
              await new Promise(r => setTimeout(r, 600));
            }
          }

          if (!html) {
            res.statusCode = 502;
            return res.end(JSON.stringify({ error: 'Failed to fetch Spotify playlist from embed after multiple attempts' }));
          }

          const match = html.match(/<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>/s);

          if (!match) {
            res.statusCode = 404;
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

          res.setHeader('Content-Type', 'application/json');
          return res.end(JSON.stringify({
            id: playlistId,
            name: playlistName,
            cover: coverArt,
            tracks,
          }));
        } catch (e) {
          console.error('Spotify playlist fetch error:', e);
          res.statusCode = 500;
          res.end(JSON.stringify({ error: e.message }));
        }
      });
    },
  };
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    tailwindcss(),
    react(),
    musicBackendPlugin(),
  ],
})
