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
    if (/=w\d+-h\d+/i.test(url)) {
      return url.replace(/=w\d+-h\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (/=s\d+/i.test(url)) {
      return url.replace(/=s\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (!url.includes('=')) {
      return `${url}=w800-h800-l90-rj`;
    }
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
    const targetDuration = parseInt(url.searchParams.get('duration') || req.query?.duration || '0', 10);
    const unwantedKeywords = ['brooklyn session', 'session', 'live', 'acoustic', 'remix', '10 years', 'tribute', 'karaoke', 'terjemahan', 'cover'];
    const activeUnwanted = unwantedKeywords.filter(kw => !q.toLowerCase().includes(kw));

    const getDurationSec = (item) => {
      if (item.duration?.seconds) return item.duration.seconds;
      if (item.duration?.text) {
        const parts = item.duration.text.split(':').map(Number);
        return parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      return 180;
    };

    const rankCandidates = (items) => {
      return items.map(item => {
        const titleStr = typeof item.title === 'string' ? item.title : (item.title?.text || '');
        const normTitle = titleStr.toLowerCase();
        let score = 100;

        for (const kw of activeUnwanted) {
          if (normTitle.includes(kw)) {
            score -= 90;
          }
        }

        if (normTitle.includes('official audio') || normTitle.includes('official') || normTitle.includes('original')) {
          score += 25;
        }

        if (targetDuration > 0) {
          const dur = getDurationSec(item);
          const diff = Math.abs(dur - targetDuration);
          if (diff <= 3) score += 60;
          else if (diff <= 10) score += 30;
          else if (diff > 35) score -= 50;
        }

        return { item, score };
      }).sort((a, b) => b.score - a.score);
    };

    // Search YouTube Music first
    const search = await yt.music.search(q, { type: 'song' });
    const songs = search.songs?.contents || search.results || [];

    let best = null;
    if (songs.length > 0) {
      const ranked = rankCandidates(songs);
      best = ranked[0]?.item;
    }

    if (best && best.id) {
      const durationSec = getDurationSec(best);
      const titleStr = typeof best.title === 'string' ? best.title : (best.title?.text || '');
      const artistStr = best.artists?.[0]?.name || best.author?.name || '';
      const thumbUrl = getBestThumbnail(best);

      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({
        videoId: best.id,
        title: titleStr,
        artist: artistStr,
        duration: durationSec,
        thumbnail: thumbUrl,
      }));
    }

    // Fallback 1: general YouTube search with official audio
    const general = await yt.search(q + ' official audio');
    const videos = general.videos || [];
    if (videos.length > 0) {
      const ranked = rankCandidates(videos);
      const video = ranked[0]?.item;
      if (video && video.id) {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({
          videoId: video.id,
          title: video.title?.text || '',
          artist: video.author?.name || '',
          duration: video.duration?.seconds || 180,
          thumbnail: toHighResUrl(video.thumbnails?.[video.thumbnails.length - 1]?.url || video.thumbnails?.[0]?.url || ''),
        }));
      }
    }

    // Fallback 2: general search
    const generalAny = await yt.search(q);
    const anyVideos = generalAny.videos || [];
    if (anyVideos.length > 0) {
      const ranked = rankCandidates(anyVideos);
      const anyVideo = ranked[0]?.item;
      if (anyVideo && anyVideo.id) {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({
          videoId: anyVideo.id,
          title: anyVideo.title?.text || '',
          artist: anyVideo.author?.name || '',
          duration: anyVideo.duration?.seconds || 180,
          thumbnail: toHighResUrl(anyVideo.thumbnails?.[anyVideo.thumbnails.length - 1]?.url || anyVideo.thumbnails?.[0]?.url || ''),
        }));
      }
    }

    res.statusCode = 404;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: 'Song not found' }));
  } catch (e) {
    console.error('API /api/yt/search error:', e);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: e.message }));
  }
}
