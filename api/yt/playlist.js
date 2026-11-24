import { Innertube } from 'youtubei.js';
import {
  applyApiSecurity,
  isValidVideoId,
  isValidYoutubePlaylistId,
  sendSafeError,
} from '../_security.js';

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create({
      location: 'ID',
      enable_session_cache: false,
    });
  }
  return ytPromise;
}

export function toHighResUrl(url, fallbackVideoId = '') {
  const cleanUrl = typeof url === 'string' ? url.trim() : '';
  const hasBadPlaceholder =
    !cleanUrl ||
    cleanUrl.includes('no_thumbnail') ||
    cleanUrl.includes('default_playlist');

  if (!hasBadPlaceholder && cleanUrl.includes('googleusercontent.com')) {
    if (/=w\d+-h\d+/i.test(cleanUrl)) {
      return cleanUrl.replace(/=w\d+-h\d+[^?#]*/i, '=w544-h544-l90-rj');
    }
    if (/=s\d+/i.test(cleanUrl)) {
      return cleanUrl.replace(/=s\d+[^?#]*/i, '=w544-h544-l90-rj');
    }
    if (!cleanUrl.includes('=')) {
      return `${cleanUrl}=w544-h544-l90-rj`;
    }
    return cleanUrl;
  }

  if (isValidVideoId(fallbackVideoId)) {
    return `https://i.ytimg.com/vi/${fallbackVideoId.trim()}/hqdefault.jpg`;
  }

  if (!hasBadPlaceholder && cleanUrl.includes('ytimg.com')) {
    const viMatch = cleanUrl.match(/\/vi(?:_webp)?\/([a-zA-Z0-9_-]{11})\//);
    if (viMatch) {
      return `https://i.ytimg.com/vi/${viMatch[1]}/hqdefault.jpg`;
    }
    return cleanUrl
      .split('?')[0]
      .replace(
        /(hqhq720|hq720|maxresdefault|sddefault|mqdefault|hqdefault|default)\.(jpg|webp)/i,
        'hqdefault.jpg'
      );
  }

  if (hasBadPlaceholder) return '';
  return cleanUrl.startsWith('https://') ? cleanUrl : '';
}

function scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration = 0) {
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
  if (isRemixOrAlt) {
    score -= 4500;
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

async function resolveOriginalTrack(yt, rawTitle, rawArtist, targetDuration = 0) {
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
      score: scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration),
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
      score: scoreCandidate(item, idx, targetTitle, targetArtist, targetDuration),
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

const VERSION_SUFFIX_REGEX =
  /^(acoustic|remix|live|radio\s*edit|official|remaster|version|instrumental|sped\s*up|slowed|reverb|feat\.?|ft\.?|edit|mix|demo|extended|explicit|clean|deluxe|session|pt\.?\s*\d|part\s*\d|bonus|original|audio|lyric|video|mv|hd|4k|mono|stereo|unplugged|stripped)/i;

function parseDurationText(text) {
  if (!text || typeof text !== 'string') return 0;
  const parts = text
    .trim()
    .split(':')
    .map((p) => parseInt(p, 10));
  if (parts.some((n) => !Number.isFinite(n) || n < 0)) return 0;
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return 0;
}

export function parseTitleAndArtist(rawTitle, rawArtist, playlistAuthor = '') {
  let title = (rawTitle || '').trim();
  let artist = (rawArtist || '')
    .replace(/\s*-\s*Topic$/i, '')
    .replace(/\s*VEVO$/i, '')
    .trim();
  const cleanPlaylistAuthor = (playlistAuthor || '').trim();

  if (title.includes(' - ')) {
    const parts = title.split(' - ');
    const p0 = (parts[0] || '').trim();
    const p1 = parts.slice(1).join(' - ').trim();
    const isVersionSuffix = VERSION_SUFFIX_REGEX.test(p1);
    const artistLower = artist.toLowerCase();
    const p0Lower = p0.toLowerCase();
    const authorIsGeneric =
      !artist ||
      artistLower === cleanPlaylistAuthor.toLowerCase() ||
      artistLower === 'youtube';
    const p0MatchesArtist =
      artistLower &&
      (p0Lower.includes(artistLower) || artistLower.includes(p0Lower));

    if (parts.length >= 2 && p0 && p1 && !isVersionSuffix && (authorIsGeneric || p0MatchesArtist)) {
      if (authorIsGeneric) {
        artist = p0.replace(/\s*-\s*Topic$/i, '').replace(/\s*VEVO$/i, '').trim();
      }
      title = p1;
    }
  }

  return {
    title: title || (rawTitle || '').trim(),
    artist: artist || cleanPlaylistAuthor || 'YouTube',
  };
}

function isUnavailableTitle(title) {
  const t = (title || '').trim().toLowerCase();
  return t === '[deleted video]' || t === '[private video]' || t === 'deleted video' || t === 'private video';
}

export default async function handler(req, res) {
  if (!applyApiSecurity(req, res)) return;

  try {
    const url = new URL(req.url, `http://${req.headers?.host || 'localhost'}`);
    let playlistId = (url.searchParams.get('id') || req.query?.id || '').trim();
    const rawUrl = (url.searchParams.get('url') || req.query?.url || '').trim();

    if (playlistId.includes('list=')) {
      const match = playlistId.match(/[?&]list=([^#&?]+)/);
      if (match) playlistId = match[1].trim();
    } else if (!playlistId && rawUrl) {
      const match = rawUrl.match(/[?&]list=([^#&?]+)/);
      if (match) playlistId = match[1].trim();
    }

    if (!isValidYoutubePlaylistId(playlistId)) {
      res.statusCode = 400;
      res.setHeader('Content-Type', 'application/json');
      return res.end(JSON.stringify({ error: 'Invalid or missing YouTube playlist ID or list parameter' }));
    }

    const yt = await getYT();
    let playlistTitle = 'YouTube Playlist';
    let playlistAuthor = 'YouTube';
    let playlistCover = '';
    const tracks = [];
    const seenVideoIds = new Set();
    const MAX_TRACKS = 200;

    // Fetch both YouTube Music & Standard YouTube in parallel to guarantee complete track list
    // (Standard YouTube has full ordered video list, while YouTube Music provides high-res audio metadata)
    const [musicRes, stdRes] = await Promise.allSettled([
      yt.music.getPlaylist(playlistId),
      yt.getPlaylist(playlistId),
    ]);

    const musicPl = musicRes.status === 'fulfilled' ? musicRes.value : null;
    const stdPl = stdRes.status === 'fulfilled' ? stdRes.value : null;

    if (!musicPl && !stdPl) {
      const err = musicRes.status === 'rejected' ? musicRes.reason : stdRes.reason;
      throw err || new Error('Gagal mengambil playlist dari YouTube');
    }

    // Determine playlist metadata (title, author, cover)
    playlistTitle =
      musicPl?.header?.title?.text ||
      musicPl?.header?.title?.toString() ||
      stdPl?.info?.title ||
      playlistTitle;

    playlistAuthor =
      musicPl?.header?.author?.name ||
      musicPl?.header?.subtitle?.text ||
      stdPl?.info?.author?.name ||
      playlistAuthor;

    const musicHeaderThumb =
      musicPl?.header?.thumbnail?.contents?.[musicPl.header.thumbnail.contents.length - 1]?.url ||
      musicPl?.header?.thumbnails?.[musicPl.header.thumbnails.length - 1]?.url ||
      '';
    const stdHeaderThumb =
      stdPl?.info?.thumbnails && stdPl.info.thumbnails.length > 0
        ? stdPl.info.thumbnails[stdPl.info.thumbnails.length - 1]?.url || stdPl.info.thumbnails[0]?.url
        : '';
    playlistCover = toHighResUrl(musicHeaderThumb || stdHeaderThumb);

    // 1. Collect Standard YouTube tracks first (authoritative YouTube playlist ordering & videoIds)
    const stdTracksList = [];
    if (stdPl) {
      try {
        let pl = stdPl;
        for (let page = 0; page < 10 && stdTracksList.length < MAX_TRACKS; page++) {
          const rawVideos = pl.videos || [];
          for (const v of rawVideos) {
            if (stdTracksList.length >= MAX_TRACKS) break;
            const videoId = (v.content_id || v.id || v.videoId || '').trim();
            if (!isValidVideoId(videoId)) continue;

            const rawTitle =
              v.metadata?.title?.text ||
              v.title?.text ||
              (typeof v.title === 'string' ? v.title : '') ||
              '';
            if (!rawTitle || isUnavailableTitle(rawTitle)) continue;

            const rawArtist =
              v.metadata?.metadata?.metadata_rows?.[0]?.metadata_parts?.[0]?.text?.text ||
              v.author?.name ||
              '';
            const { title, artist } = parseTitleAndArtist(rawTitle, rawArtist, playlistAuthor);

            const durationSec =
              v.duration?.seconds ||
              parseDurationText(v.duration?.text) ||
              parseDurationText(v.content_image?.overlays?.[0]?.badges?.[0]?.text) ||
              200;

            const thumbUrl =
              v.content_image?.image?.[v.content_image.image.length - 1]?.url ||
              v.thumbnails?.[v.thumbnails.length - 1]?.url ||
              v.thumbnails?.[0]?.url ||
              '';

            stdTracksList.push({
              id: `yt_${videoId}`,
              videoId,
              title,
              artist,
              album: playlistTitle,
              duration: durationSec,
              artwork: toHighResUrl(thumbUrl, videoId),
            });
          }

          if (!pl.has_continuation || stdTracksList.length >= MAX_TRACKS) break;
          pl = await pl.getContinuation();
        }
      } catch (stdErr) {
        console.warn('yt.getPlaylist pagination notice:', stdErr?.message);
      }
    }

    // 2. Collect YouTube Music tracks (with continuation up to MAX_TRACKS)
    const musicTracksMap = new Map();
    const musicTracksList = [];
    if (musicPl) {
      try {
        let current = musicPl;
        let itemIndex = 0;
        for (let page = 0; page < 10 && musicTracksList.length < MAX_TRACKS; page++) {
          const items = current.items || current.contents || [];
          for (const item of items) {
            if (musicTracksList.length >= MAX_TRACKS) break;

            const rawTitle = typeof item.title === 'string'
              ? item.title
              : (item.title?.text || item.title?.runs?.map(r => r.text).join('') || item.title?.toString() || item.metadata?.title?.text || item.flex_columns?.[0]?.title?.text || '');
            if (!rawTitle || isUnavailableTitle(rawTitle)) {
              itemIndex++;
              continue;
            }

            const rawArtist =
              item.artists?.map((a) => a.name).filter(Boolean).join(', ') ||
              item.author?.name ||
              item.flex_columns?.[1]?.title?.runs?.map(r => r.text).join('') ||
              item.flex_columns?.[1]?.title?.text ||
              '';
            let { title, artist } = parseTitleAndArtist(rawTitle, rawArtist, playlistAuthor);
            let durationSec = item.duration?.seconds ||
              parseDurationText(item.duration?.text) ||
              parseDurationText(item.fixed_columns?.[0]?.title?.text) ||
              200;

            let videoId = (item.id || item.video_id || item.videoId || item.endpoint?.payload?.videoId || item.overlay?.content?.endpoint?.payload?.videoId || '').trim();

            if (!isValidVideoId(videoId)) {
              // 1. Direct match with standard YouTube playlist item at the same index (if title aligns)
              const stdCandidate = stdTracksList[itemIndex];
              const normRawTitle = rawTitle.toLowerCase().replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '').trim();
              const normStdTitle = (stdCandidate?.title || '').toLowerCase().replace(/\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]/gi, '').trim();
              const isTitleMatch = stdCandidate && (normStdTitle.includes(normRawTitle) || normRawTitle.includes(normStdTitle));
              if (isTitleMatch && isValidVideoId(stdCandidate.videoId)) {
                videoId = stdCandidate.videoId;
                if (!artist && stdCandidate.artist) artist = stdCandidate.artist;
                if (stdCandidate.duration) durationSec = stdCandidate.duration;
              } else {
                // 2. Fallback to original track resolver via search core
                try {
                  const searchResult = await resolveOriginalTrack(yt, rawTitle, rawArtist, durationSec);
                  if (searchResult && isValidVideoId(searchResult.videoId)) {
                    videoId = searchResult.videoId;
                    if (searchResult.title) title = searchResult.title;
                    if (searchResult.artist) artist = searchResult.artist;
                    if (searchResult.duration) durationSec = searchResult.duration;
                  }
                } catch (e) {
                  console.warn('Auto-resolve failed for track:', rawTitle, e?.message);
                }
              }
            }
            itemIndex++;

            if (!isValidVideoId(videoId)) continue;

            const rawThumb =
              item.thumbnail?.contents?.[item.thumbnail.contents.length - 1]?.url ||
              item.thumbnails?.[item.thumbnails.length - 1]?.url ||
              '';

            const trackObj = {
              id: `yt_${videoId}`,
              videoId,
              title,
              artist,
              album: playlistTitle,
              duration: durationSec,
              artwork: toHighResUrl(rawThumb, videoId),
            };

            if (!musicTracksMap.has(videoId)) {
              musicTracksMap.set(videoId, trackObj);
              musicTracksList.push(trackObj);
            }
          }

          if (!current.has_continuation || musicTracksList.length >= MAX_TRACKS) break;
          current = await current.getContinuation();
        }
      } catch (musicErr) {
        console.warn('yt.music.getPlaylist pagination notice:', musicErr?.message);
      }
    }

    // 3. Assemble unified playlist:
    // Choose primary list (whichever retrieved the most tracks) to preserve authentic playlist track order
    const primaryList = musicTracksList.length >= stdTracksList.length ? musicTracksList : stdTracksList;
    const secondaryList = primaryList === musicTracksList ? stdTracksList : musicTracksList;

    for (const track of primaryList) {
      if (tracks.length >= MAX_TRACKS) break;
      if (seenVideoIds.has(track.videoId)) continue;
      seenVideoIds.add(track.videoId);

      if (primaryList === stdTracksList) {
        const musicTrack = musicTracksMap.get(track.videoId);
        if (musicTrack) {
          tracks.push({
            ...track,
            title: musicTrack.title || track.title,
            artist: musicTrack.artist || track.artist,
            artwork: musicTrack.artwork || track.artwork,
            duration: musicTrack.duration || track.duration,
            album: musicTrack.album || track.album,
          });
          continue;
        }
      }
      tracks.push(track);
    }

    for (const extra of secondaryList) {
      if (tracks.length >= MAX_TRACKS) break;
      if (!seenVideoIds.has(extra.videoId)) {
        seenVideoIds.add(extra.videoId);
        tracks.push(extra);
      }
    }

    if (
      (!playlistCover ||
        playlistCover.includes('default.jpg') ||
        playlistCover.includes('sqp=') ||
        playlistCover.includes('no_thumbnail') ||
        playlistCover.includes('default_playlist')) &&
      tracks.length > 0
    ) {
      playlistCover =
        tracks[0].artwork ||
        (tracks[0].videoId ? `https://i.ytimg.com/vi/${tracks[0].videoId}/hqdefault.jpg` : '');
    }

    res.setHeader('Content-Type', 'application/json; charset=utf-8');
    res.setHeader(
      'Cache-Control',
      'no-store, no-cache, must-revalidate, proxy-revalidate'
    );
    return res.end(
      JSON.stringify({
        id: playlistId,
        name: playlistTitle,
        author: playlistAuthor,
        cover: playlistCover,
        totalTracks: tracks.length,
        tracks,
      })
    );
  } catch (e) {
    return sendSafeError(res, 500, 'Gagal memproses YouTube playlist', e);
  }
}
