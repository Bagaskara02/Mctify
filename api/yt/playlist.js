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
      return url.replace(/=w\d+-h\d+[^?#]*/i, '=w544-h544-l90-rj');
    }
    if (/=s\d+/i.test(url)) {
      return url.replace(/=s\d+[^?#]*/i, '=w544-h544-l90-rj');
    }
    if (!url.includes('=')) {
      return `${url}=w544-h544-l90-rj`;
    }
  }
  if (url.includes('ytimg.com')) {
    const viMatch = url.match(/\/vi\/([a-zA-Z0-9_-]+)\//);
    if (viMatch) {
      return `https://i.ytimg.com/vi/${viMatch[1]}/hqdefault.jpg`;
    }
    return url.replace(/(hqdefault|mqdefault|sddefault|maxresdefault|default)\.jpg/i, 'hqdefault.jpg').split('?')[0];
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
    let playlistId = url.searchParams.get('id') || req.query?.id || '';
    const rawUrl = url.searchParams.get('url') || req.query?.url || '';

    if (!playlistId && rawUrl) {
      const match = rawUrl.match(/[?&]list=([^#&?]+)/);
      if (match) playlistId = match[1];
    }

    if (!playlistId) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing YouTube playlist ID or list parameter' }));
    }

    const yt = await getYT();
    const pl = await yt.getPlaylist(playlistId);

    const playlistTitle = pl.info?.title || 'YouTube Playlist';
    const playlistAuthor = pl.info?.author?.name || 'YouTube';
    const rawThumb = pl.info?.thumbnails?.[0]?.url || '';
    const playlistCover = toHighResUrl(rawThumb);

    const rawVideos = pl.videos || [];
    const tracks = rawVideos.map((v, idx) => {
      const videoId = v.content_id || v.id || v.videoId || '';
      let title = v.metadata?.title?.text || v.title?.text || v.title?.toString() || '';
      let artist = v.metadata?.metadata?.metadata_rows?.[0]?.metadata_parts?.[0]?.text?.text || 
                   v.author?.name || v.author?.toString() || playlistAuthor;
      
      if (title.includes(' - ')) {
        const parts = title.split(' - ');
        if (!artist || artist === playlistAuthor) {
          artist = parts[0].trim();
        }
        title = parts.slice(1).join(' - ').trim();
      }

      // Duration
      let durationSec = 200;
      if (v.duration?.seconds) {
        durationSec = v.duration.seconds;
      } else if (v.duration?.text) {
        const parts = v.duration.text.split(':').map(Number);
        durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
      }

      const thumbUrl = v.content_image?.image?.[0]?.url || 
                       v.thumbnails?.[v.thumbnails.length - 1]?.url || 
                       v.thumbnails?.[0]?.url || 
                       (videoId ? `https://i.ytimg.com/vi/${videoId}/hqdefault.jpg` : '');

      return {
        id: videoId || `yt-track-${idx}-${Date.now()}`,
        videoId,
        title: title.trim(),
        artist: artist.trim(),
        album: playlistTitle,
        duration: durationSec,
        artwork: toHighResUrl(thumbUrl),
      };
    }).filter(t => t.title && t.videoId);

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader('Cache-Control', 'public, s-maxage=86400, stale-while-revalidate=43200');
    return res.end(JSON.stringify({
      id: playlistId,
      name: playlistTitle,
      author: playlistAuthor,
      cover: playlistCover,
      totalTracks: tracks.length,
      tracks,
    }));
  } catch (e) {
    console.error('API /api/yt/playlist error:', e);
    res.statusCode = 500;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: e.message || 'Gagal memproses YouTube playlist' }));
  }
}
