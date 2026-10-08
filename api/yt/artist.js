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
    if (/default\.jpg/i.test(url)) return url.replace(/(default|mqdefault|sddefault)\.jpg/i, 'hq720.jpg').split('?')[0];
  }
  if (url.includes('mzstatic.com')) {
    return url.replace(/\/\d+x\d+bb\./i, '/1000x1000bb.');
  }
  return url;
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
    const id = url.searchParams.get('id') || req.query?.id;
    const name = url.searchParams.get('name') || req.query?.name || '';
    if (!id && !name) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing id or name' }));
    }

    const yt = await getYT();
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
    console.error('API /api/yt/artist error:', e);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: e.message }));
  }
}
