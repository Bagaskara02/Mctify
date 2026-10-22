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
  res.setHeader('Cache-Control', 'public, s-maxage=43200, stale-while-revalidate=86400');

  if (req.method === 'OPTIONS') {
    res.statusCode = 200;
    return res.end();
  }

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    const q = url.searchParams.get('q') || req.query?.q || '';
    const rawTitle = url.searchParams.get('title') || req.query?.title || '';
    const rawArtist = url.searchParams.get('artist') || req.query?.artist || '';
    if (!q && !rawTitle) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing query' }));
    }

    const yt = await getYT();
    const targetDuration = parseInt(url.searchParams.get('duration') || req.query?.duration || '0', 10);
    const searchQuery = q || `${rawTitle} ${rawArtist}`.trim();
    const qLower = searchQuery.toLowerCase();

    const extractCoreTitle = (str) => {
      return str
        .replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '')
        .replace(/\s*-\s*(acoustic|live|remix|version|official).*/gi, '')
        .trim();
    };

    const targetTitle = rawTitle ? extractCoreTitle(rawTitle.toLowerCase()) : extractCoreTitle(qLower);
    const targetArtist = rawArtist
      ? rawArtist.toLowerCase().split(',')[0].split('ft.')[0].split('feat.')[0].trim()
      : '';

    const isAcousticRequested = qLower.includes('acoustic') || (rawTitle && rawTitle.toLowerCase().includes('acoustic'));
    const isRemixRequested = qLower.includes('remix');
    const isLiveRequested = qLower.includes('live') || qLower.includes('concert') || qLower.includes('konser');
    const isSessionRequested = qLower.includes('session');
    const isStrippedRequested = qLower.includes('stripped') || qLower.includes('piano');

    const unwantedKeywords = [
      'karaoke', 'instrumental', 'made popular by', 'tribute', 'terjemahan',
      'cover', 'guitar cover', 'drum cover', 'piano cover', 'reaction',
      'slowed', 'reverb', 'sped up', 'speed up', 'backing track',
      'originally performed', 'in the style of', 'parodi', 'parody', 'mashup', 'acapella'
    ];
    if (!isAcousticRequested && !isSessionRequested) {
      unwantedKeywords.push('brooklyn session', 'session');
    }

    const activeUnwanted = unwantedKeywords.filter(kw => !qLower.includes(kw));

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
        const authorStr = (item.artists?.[0]?.name || item.author?.name || '').toLowerCase();
        const combined = `${normTitle} ${authorStr}`;
        let score = 1000;

        // 1. Core title check:
        if (targetTitle && normTitle.includes(targetTitle)) {
          score += 800;
        } else if (targetTitle) {
          const coreTokens = targetTitle.split(' ').filter(w => w.length > 2);
          const matched = coreTokens.filter(tok => normTitle.includes(tok)).length;
          if (coreTokens.length > 0 && matched === coreTokens.length) {
            score += 500;
          } else {
            score -= 3000; // WRONG SONG!
          }
        }

        // 2. Artist check:
        if (targetArtist) {
          if (authorStr.includes(targetArtist) || targetArtist.includes(authorStr)) {
            score += 800;
          } else if (combined.includes(targetArtist)) {
            score += 300;
          } else {
            score -= 1000;
          }
        }

        // 3. Reject unwanted junk (Karaoke, instrumental, covers, tributes, parody)
        for (const kw of activeUnwanted) {
          if (combined.includes(kw)) {
            score -= 4000;
          }
        }

        // Two-way symmetric version matching
        if (isAcousticRequested) {
          if (combined.includes('acoustic')) {
            score += 900;
            if (authorStr.includes('- topic') || normTitle.includes('- topic') || combined.includes('official audio') || !combined.includes('live')) {
              score += 350;
            }
          } else {
            score -= 1500;
          }
        } else {
          if (combined.includes('acoustic')) score -= 1000;
        }

        if (isRemixRequested) {
          if (combined.includes('remix')) score += 750;
          else score -= 900;
        } else {
          if (combined.includes('remix')) score -= 850;
        }

        if (isLiveRequested) {
          if (combined.includes('live') || combined.includes('concert') || combined.includes('konser')) score += 750;
          else score -= 900;
        } else if (!isAcousticRequested) {
          if (combined.includes('live') || combined.includes('concert') || combined.includes('konser')) score -= 850;
        }

        if (isSessionRequested || isStrippedRequested) {
          if (combined.includes('session') || combined.includes('stripped')) score += 750;
        } else if (!isAcousticRequested && combined.includes('session')) {
          score -= 600;
        }

        // Heavy boost for clean studio audio (Topic track, Official Audio)
        if (authorStr.includes('- topic') || normTitle.includes('- topic') || combined.includes('official audio') || combined.includes('provided to youtube by')) {
          score += 650;
        }

        // Heavy penalty for Music Videos (skits, pool dialogue, film intros desync lyrics & ruin listening!)
        const isMv = combined.includes('music video') ||
          combined.includes('official video') ||
          combined.includes('official music video') ||
          combined.includes('video klip') ||
          combined.includes('clip officiel') ||
          combined.includes('visualizer') ||
          /\b(mv|official mv)\b/i.test(normTitle);

        if (isMv) {
          score -= 750;
        }

        // Duration matching
        if (targetDuration > 0) {
          const dur = getDurationSec(item);
          const diff = Math.abs(dur - targetDuration);
          if (diff <= 2) score += 350;
          else if (diff <= 5) score += 150;
          else if (diff <= 10) score += 50;
          else if (diff > 12) score -= 450;
          if (diff > 25) score -= 1200;
        }

        return { item, score };
      }).sort((a, b) => b.score - a.score);
    };

    // Search YouTube Music first
    const search = await yt.music.search(searchQuery, { type: 'song' });
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
