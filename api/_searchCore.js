import { isValidVideoId } from './_security.js';

export const toHighResUrl = (url) => {
  if (!url || typeof url !== 'string') return '';
  if (url.includes('googleusercontent.com')) {
    if (/=w\d+-h\d+/i.test(url)) return url.replace(/=w\d+-h\d+[^?#]*/i, '=w544-h544-l90-rj');
    if (/=s\d+/i.test(url)) return url.replace(/=s\d+[^?#]*/i, '=w544-h544-l90-rj');
    if (!url.includes('=')) return `${url}=w544-h544-l90-rj`;
  }
  if (url.includes('ytimg.com')) {
    const viMatch = url.match(/\/vi\/([a-zA-Z0-9_-]+)\//);
    if (viMatch) return `https://i.ytimg.com/vi/${viMatch[1]}/hqdefault.jpg`;
    return url.replace(/(hqdefault|mqdefault|sddefault|maxresdefault|default)\.jpg/i, 'hqdefault.jpg').split('?')[0];
  }
  if (url.includes('mzstatic.com')) {
    return url.replace(/\/\d+x\d+bb\./i, '/1000x1000bb.');
  }
  return url;
};

export function scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration = 0, isRemixRequested = false) {
  const titleStr = typeof item.title === 'string' ? item.title : (item.title?.text || '');
  const normTitle = titleStr.toLowerCase();
  const authorStr = (item.artists?.[0]?.name || item.author?.name || '').toLowerCase();
  const combined = `${normTitle} ${authorStr}`;
  let score = 1000;

  if (idx === 0) score += 1200;
  else if (idx === 1) score += 800;
  else if (idx === 2) score += 500;
  else if (idx === 3) score += 300;
  else if (idx < 6) score += 150;

  const cleanNormTitle = normTitle
    .replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '')
    .replace(/\s*-\s*(acoustic|live|remix|version|official|remastered.*).*/gi, '')
    .trim();

  if (targetTitle) {
    if (cleanNormTitle === targetTitle) {
      score += 2500;
    } else if (cleanNormTitle.startsWith(targetTitle)) {
      score += 1400;
    } else if (normTitle.includes(targetTitle)) {
      score += 800;
    } else {
      const coreTokens = targetTitle.split(' ').filter(w => w.length > 2);
      const matched = coreTokens.filter(tok => normTitle.includes(tok)).length;
      if (coreTokens.length > 0 && matched === coreTokens.length) {
        score += 500;
      } else {
        score -= 3000;
      }
    }
  }

  if (targetArtist) {
    const targetTokens = targetArtist.split(/[\s,&]+/).filter(w => w.length > 1);
    const hasArtistMatch = authorStr.includes(targetArtist) ||
                           targetArtist.includes(authorStr) ||
                           combined.includes(targetArtist) ||
                           (targetTokens.length > 0 && targetTokens.some(tok => authorStr.includes(tok) || normTitle.includes(tok)));
    if (hasArtistMatch) {
      score += 1500;
    } else {
      score -= 5000;
    }
  }

  if (/\b(karaoke|instrumental|instrument|cover|tribute|parodi|parody|mashup|slowed|reverb|sped up|kidz bop)\b/i.test(combined)) {
    score -= 5000;
  }

  const isRemixOrAlt = /\b(remix|mix|club edit|radio edit|vip|extended|stripped|acoustic|live|eden prince|bassjackers|ashworth|fitness dance)\b/i.test(normTitle) ||
                       /\[(eden prince|club edit|radio edit|vip|extended|stripped|ashworth|bassjackers)\]/i.test(titleStr);

  if (isRemixRequested) {
    if (isRemixOrAlt) score += 1000;
    else score -= 1200;
  } else {
    if (isRemixOrAlt) score -= 4500;
  }

  if (authorStr.includes('- topic') || normTitle.includes('- topic') || combined.includes('official audio') || combined.includes('provided to youtube by') || combined.includes('original track')) {
    score += 1500;
  }

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

  if (targetDuration > 0) {
    let dur = 180;
    if (item.duration?.seconds) dur = item.duration.seconds;
    else if (item.duration?.text) {
      const parts = item.duration.text.split(':').map(Number);
      dur = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
    }
    const diff = Math.abs(dur - targetDuration);
    if (diff <= 3) score += 350;
    else if (diff <= 10) score += 100;
    else if (diff > 25) score -= 1500;
  }

  return score;
}

export async function resolveOriginalTrack(yt, rawTitle, rawArtist, targetDuration = 0) {
  const cleanTitle = (rawTitle || '')
    .replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '')
    .replace(/\s*-\s*(acoustic|live|remix|version|official|remastered.*).*/gi, '')
    .trim();
  const cleanArtist = (rawArtist || '').split('&')[0].split(',')[0].trim();
  const targetTitle = cleanTitle.toLowerCase();
  const targetArtist = cleanArtist.toLowerCase();

  // 1. Try YouTube Music song search
  try {
    const musicRes = await yt.music.search(`${cleanTitle} ${cleanArtist}`.trim(), { type: 'song' });
    const candidates = musicRes.songs?.contents || musicRes.results || [];
    const ranked = candidates.map((item, idx) => ({
      item,
      score: scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration, false),
    })).filter(entry => isValidVideoId(entry.item?.id)).sort((a, b) => b.score - a.score);

    if (ranked.length > 0 && ranked[0].score > 0) {
      const best = ranked[0].item;
      let durationSec = targetDuration || 180;
      if (best.duration?.seconds) durationSec = best.duration.seconds;
      else if (best.duration?.text) {
        const parts = best.duration.text.split(':').map(Number);
        durationSec = parts.length === 2 ? parts[0] * 60 + parts[1] : parts[0] * 3600 + parts[1] * 60 + parts[2];
      }
      return {
        videoId: best.id,
        title: typeof best.title === 'string' ? best.title : (best.title?.text || cleanTitle),
        artist: best.artists?.map(a => a.name).filter(Boolean).join(', ') || best.author?.name || cleanArtist,
        duration: durationSec,
        artwork: toHighResUrl(best.thumbnails?.[best.thumbnails.length - 1]?.url || best.thumbnails?.[0]?.url || '', best.id),
      };
    }
  } catch (_) {}

  // 2. Fallback to general YouTube search with official audio
  try {
    const generalRes = await yt.search(`${cleanTitle} ${cleanArtist} official audio`.trim());
    const videos = generalRes.videos || [];
    const ranked = videos.map((item, idx) => ({
      item,
      score: scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration, false),
    })).filter(entry => {
      const vid = (entry.item?.content_id || entry.item?.id || entry.item?.videoId || '').trim();
      return isValidVideoId(vid);
    }).sort((a, b) => b.score - a.score);

    if (ranked.length > 0 && ranked[0].score > -1000) {
      const best = ranked[0].item;
      const vid = (best.content_id || best.id || best.videoId || '').trim();
      return {
        videoId: vid,
        title: best.title?.text || (typeof best.title === 'string' ? best.title : cleanTitle),
        artist: best.author?.name || cleanArtist,
        duration: best.duration?.seconds || targetDuration || 180,
        artwork: toHighResUrl(best.thumbnails?.[best.thumbnails.length - 1]?.url || '', vid),
      };
    }
  } catch (_) {}

  return null;
}
