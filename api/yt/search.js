import { Innertube } from 'youtubei.js';
import {
  applyApiSecurity,
  isValidVideoId,
  sanitizeQuery,
  sendSafeError,
} from '../_security.js';

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create({
      gl: 'ID',
      hl: 'id',
      enable_session_cache: false,
    });
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
  if (!applyApiSecurity(req, res)) return;
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    const q = sanitizeQuery(url.searchParams.get('q') || req.query?.q || '', 200);
    const rawTitle = sanitizeQuery(url.searchParams.get('title') || req.query?.title || '', 200);
    const rawArtist = sanitizeQuery(url.searchParams.get('artist') || req.query?.artist || '', 200);
    const excludeParam = url.searchParams.get('exclude') || req.query?.exclude || '';
    const excludeIds = new Set(
      excludeParam
        .split(',')
        .map((s) => s.trim())
        .filter((s) => isValidVideoId(s))
        .slice(0, 20)
    );
    if (!q && !rawTitle) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Missing query' }));
    }

    const yt = await getYT();
    const rawDuration = parseInt(url.searchParams.get('duration') || req.query?.duration || '0', 10);
    const targetDuration = Number.isFinite(rawDuration) ? Math.max(0, Math.min(7200, rawDuration)) : 0;
    const cleanText = (s) => s
      .replace(/[\u00a0\u2000-\u200b\u202f\u205f\u3000]/g, ' ')
      .replace(/◐/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    const searchQuery = cleanText(q || `${rawTitle} ${rawArtist}`);
    const qLower = searchQuery.toLowerCase();

    const extractCoreTitle = (str) => {
      return cleanText(str)
        .replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '')
        .replace(/\s*-\s*(acoustic|live|remix|version|official|remastered.*).*/gi, '')
        .trim();
    };

    const targetTitle = rawTitle ? extractCoreTitle(rawTitle.toLowerCase()) : extractCoreTitle(qLower);
    const targetArtist = rawArtist
      ? cleanText(rawArtist).toLowerCase().split(',')[0].split('ft.')[0].split('feat.')[0].trim()
      : '';

    const isAcousticRequested = qLower.includes('acoustic') || (rawTitle && rawTitle.toLowerCase().includes('acoustic'));
    const isRemixRequested = qLower.includes('remix');
    const isLiveRequested = qLower.includes('live') || qLower.includes('concert') || qLower.includes('konser');
    const isSessionRequested = qLower.includes('session');
    const isStrippedRequested = qLower.includes('stripped') || qLower.includes('piano');

    const unwantedKeywords = [
      'karaoke', 'instrumental', 'instrument', 'instr.', 'made popular by', 'tribute', 'terjemahan',
      'cover', 'guitar cover', 'drum cover', 'piano cover', 'reaction',
      'slowed', 'reverb', 'sped up', 'speed up', 'nightcore', 'backing track',
      'minus one', 'no vocals', 'vocal guide', 'sing-along', 'sing along',
      'type beat', 'rap beat', 'free beat',
      'originally performed', 'in the style of', 'parodi', 'parody', 'mashup', 'acapella',
      'ombre2choc'
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
      return items.map((item, idx) => {
        const titleStr = typeof item.title === 'string' ? item.title : (item.title?.text || '');
        const normTitle = titleStr.toLowerCase();
        const authorStr = (item.artists?.[0]?.name || item.author?.name || '').toLowerCase();
        const combined = `${normTitle} ${authorStr}`;
        let score = 1000;

        // Preserve YouTube Music natural search engine rank (worldwide hit songs rank highest)
        if (idx === 0) score += 1200;
        else if (idx === 1) score += 800;
        else if (idx === 2) score += 500;
        else if (idx === 3) score += 300;
        else if (idx < 6) score += 150;

        // Clean Core Title match:
        // Strip "(feat. ...)", "[feat. ...]", etc. to get the pure song title
        const cleanNormTitle = normTitle
          .replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '')
          .replace(/\s*-\s*(acoustic|live|remix|version|official|remastered.*).*/gi, '')
          .trim();

        // 1. Core title check:
        if (targetTitle) {
          if (cleanNormTitle === targetTitle) {
            score += 2500; // Exact match to clean title (e.g. "no promises (feat. demi lovato)" matches "no promises")
          } else if (cleanNormTitle.startsWith(targetTitle)) {
            score += 1400;
          } else if (normTitle.includes(targetTitle) || (!rawTitle && combined.includes(targetTitle))) {
            score += 800;
          } else {
            const coreTokens = targetTitle.split(' ').filter(w => w.length > 1);
            const searchPool = rawTitle ? normTitle : combined;
            const matched = coreTokens.filter(tok => searchPool.includes(tok)).length;
            if (coreTokens.length > 0 && matched === coreTokens.length) {
              score += 800;
            } else if (coreTokens.length > 0 && matched / coreTokens.length >= 0.5) {
              score += 200;
            } else {
              score -= 3000; // WRONG SONG for specific title resolution!
            }
          }
        }

        // 2. Strict Artist check:
        if (targetArtist) {
          const targetTokens = targetArtist.split(/[\s,&]+/).filter(w => w.length > 1);
          const hasArtistMatch = Boolean(authorStr) && authorStr.trim().length > 1 && (
            authorStr.includes(targetArtist) ||
            targetArtist.includes(authorStr) ||
            combined.includes(targetArtist) ||
            (targetTokens.length > 0 && targetTokens.some(tok => authorStr.includes(tok) || normTitle.includes(tok)))
          );
          if (hasArtistMatch) {
            score += 1500;
          } else {
            score -= 5000; // WRONG ARTIST: Completely disqualifies different artist tracks!
          }
        }

        // 3. Reject unwanted junk (Karaoke, instrumental, covers, tributes, parody, scraper)
        for (const kw of activeUnwanted) {
          if (combined.includes(kw)) {
            score -= 4500;
          }
        }

        if (authorStr.includes('ombre2choc') || authorStr.includes('karaoke') || authorStr.includes('tribute band')) {
          score -= 5000;
        }

        // Strict Anti-Slowed / Anti-Reverb check if not explicitly requested
        const isSlowedRequested = qLower.includes('slowed') || qLower.includes('reverb') || qLower.includes('sped up');
        if (!isSlowedRequested) {
          if (/\b(slowed|reverb|slowed \+ reverb|slowed and reverb|sped up|speed up|nightcore|8d audio)\b/i.test(combined)) {
            score -= 4500;
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
          if (combined.includes('acoustic')) score -= 1500;
        }

        // Strict Remix & Alternate version detection:
        // Any title with brackets/words like [Eden Prince], [Club Edit], [Bassjackers], [Ashworth], Remix, Mix, VIP, etc.
        const isRemixOrAlt = /\b(remix|mix|club edit|radio edit|vip|extended|stripped|acoustic|live|eden prince|bassjackers|ashworth|fitness dance)\b/i.test(normTitle) ||
                             /\[(eden prince|club edit|radio edit|vip|extended|stripped|ashworth|bassjackers)\]/i.test(titleStr);

        if (isRemixRequested) {
          if (isRemixOrAlt) score += 1000;
          else score -= 1200;
        } else {
          if (isRemixOrAlt) score -= 3500; // Heavily penalizes remixes/alts when original is requested!
        }

        if (isLiveRequested) {
          if (combined.includes('live') || combined.includes('concert') || combined.includes('konser')) score += 750;
          else score -= 900;
        } else if (!isAcousticRequested) {
          if (combined.includes('live') || combined.includes('concert') || combined.includes('konser')) score -= 1200;
        }

        if (isSessionRequested || isStrippedRequested) {
          if (combined.includes('session') || combined.includes('stripped')) score += 750;
        } else if (!isAcousticRequested && (combined.includes('session') || combined.includes('stripped'))) {
          score -= 1200;
        }

        // Heavy boost for clean studio original audio (Topic track, Official Audio, Album Audio)
        if (authorStr.includes('- topic') || normTitle.includes('- topic') || combined.includes('official audio') || combined.includes('provided to youtube by') || combined.includes('original track')) {
          score += 1500;
        }

        // Heavy penalty for Music Videos (skits, dialogue, car sounds, movie scenes that ruin audio listening)
        const isMv = combined.includes('music video') ||
          combined.includes('official video') ||
          combined.includes('official music video') ||
          combined.includes('video klip') ||
          combined.includes('clip officiel') ||
          combined.includes('visualizer') ||
          /\b(mv|official mv)\b/i.test(normTitle);

        if (isMv) {
          score -= 2500;
        }

        // Duration matching
        if (targetDuration > 0) {
          const dur = getDurationSec(item);
          const diff = Math.abs(dur - targetDuration);
          if (diff <= 2) score += 350;
          else if (diff <= 5) score += 150;
          else if (diff <= 10) score += 50;
          else if (diff > 12) score -= 450;
          if (diff > 25) score -= 1500;
        }

        return { item, score };
      }).sort((a, b) => b.score - a.score);
    };

    const pickBestPlayable = (items, minScore = (rawTitle || rawArtist) ? 400 : -200) => {
      if (!items || items.length === 0) return null;
      const ranked = rankCandidates(items).filter((entry) => {
        const id = (entry?.item?.id || entry?.item?.content_id || entry?.item?.videoId || '').trim();
        return isValidVideoId(id) && !excludeIds.has(id);
      });
      if (ranked.length === 0) return null;
      return ranked[0].score >= minScore ? ranked[0].item : null;
    };

    // Search YouTube Music first
    const search = await yt.music.search(searchQuery, { type: 'song' }).catch(() => ({}));
    const songs = search.songs?.contents || search.results || [];

    const best = pickBestPlayable(songs);
    if (best) {
      const vid = (best.id || best.content_id || best.videoId || '').trim();
      if (isValidVideoId(vid)) {
        const durationSec = getDurationSec(best);
        const titleStr = typeof best.title === 'string' ? best.title : (best.title?.text || '');
        const artistStr = best.artists?.[0]?.name || best.author?.name || '';
        const thumbUrl = getBestThumbnail(best);

        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({
          videoId: vid,
          title: titleStr,
          artist: artistStr,
          duration: durationSec,
          thumbnail: thumbUrl,
        }));
      }
    }

    // Fallback 1: general YouTube search with type: video
    const general = await yt.search(`${searchQuery} official audio`, { type: 'video' }).catch(() => ({}));
    const videos = general.videos || [];
    const video = pickBestPlayable(videos);
    if (video) {
      const vid = (video.id || video.content_id || video.videoId || '').trim();
      if (isValidVideoId(vid)) {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({
          videoId: vid,
          title: video.title?.text || (typeof video.title === 'string' ? video.title : ''),
          artist: video.author?.name || '',
          duration: video.duration?.seconds || 180,
          thumbnail: toHighResUrl(video.thumbnails?.[video.thumbnails.length - 1]?.url || video.thumbnails?.[0]?.url || '', vid),
        }));
      }
    }

    // Fallback 2: general search
    const generalAny = await yt.search(searchQuery, { type: 'video' }).catch(() => ({}));
    const anyVideos = generalAny.videos || [];
    const anyVideo = pickBestPlayable(anyVideos);
    if (anyVideo) {
      const vid = (anyVideo.id || anyVideo.content_id || anyVideo.videoId || '').trim();
      if (isValidVideoId(vid)) {
        res.setHeader('Content-Type', 'application/json');
        return res.end(JSON.stringify({
          videoId: vid,
          title: anyVideo.title?.text || (typeof anyVideo.title === 'string' ? anyVideo.title : ''),
          artist: anyVideo.author?.name || '',
          duration: anyVideo.duration?.seconds || 180,
          thumbnail: toHighResUrl(anyVideo.thumbnails?.[anyVideo.thumbnails.length - 1]?.url || anyVideo.thumbnails?.[0]?.url || '', vid),
        }));
      }
    }

    res.statusCode = 404;
    res.setHeader('Content-Type', 'application/json');
    return res.end(JSON.stringify({ error: 'Song not found' }));
  } catch (e) {
    return sendSafeError(res, 500, 'Gagal mencari lagu', e);
  }
}
