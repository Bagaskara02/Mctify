import { Innertube } from 'youtubei.js';
import { resolveOriginalTrack } from '../_searchCore.js';
import {
  applyApiSecurity,
  isValidVideoId,
  isValidYoutubePlaylistId,
  sendSafeError,
} from '../_security.js';

let ytPromise = null;
async function getYT() {
  if (!ytPromise) {
    ytPromise = Innertube.create();
  }
  return ytPromise;
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

    // 1. Collect YouTube Music tracks (with continuation up to MAX_TRACKS)
    const musicTracksMap = new Map();
    const musicTracksList = [];
    if (musicPl) {
      try {
        let current = musicPl;
        for (let page = 0; page < 10 && musicTracksList.length < MAX_TRACKS; page++) {
          const items = current.items || current.contents || [];
          for (const item of items) {
            if (musicTracksList.length >= MAX_TRACKS) break;

            const rawTitle = typeof item.title === 'string'
              ? item.title
              : (item.title?.text || item.title?.runs?.map(r => r.text).join('') || item.title?.toString() || item.metadata?.title?.text || item.flex_columns?.[0]?.title?.text || '');
            if (!rawTitle || isUnavailableTitle(rawTitle)) continue;

            const rawArtist =
              item.artists?.map((a) => a.name).filter(Boolean).join(', ') ||
              item.author?.name ||
              item.flex_columns?.[1]?.title?.runs?.map(r => r.text).join('') ||
              item.flex_columns?.[1]?.title?.text ||
              '';
            let { title, artist } = parseTitleAndArtist(rawTitle, rawArtist, playlistAuthor);
            const durationSec = item.duration?.seconds ||
              parseDurationText(item.duration?.text) ||
              parseDurationText(item.fixed_columns?.[0]?.title?.text) ||
              200;

            let videoId = (item.id || item.video_id || item.videoId || item.endpoint?.payload?.videoId || item.overlay?.content?.endpoint?.payload?.videoId || '').trim();

            if (!isValidVideoId(videoId)) {
              // Resolve missing videoId via search core (handles YTM US datacenter masking)
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

    // 2. Collect Standard YouTube tracks (authoritative YouTube playlist ordering & LockupView items)
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

    // 3. Assemble unified playlist:
    // Choose primary list (whichever retrieved the most tracks) to preserve authentic playlist track order
    const primaryList = musicTracksList.length >= stdTracksList.length ? musicTracksList : stdTracksList;
    const secondaryList = primaryList === musicTracksList ? stdTracksList : musicTracksList;

    for (const track of primaryList) {
      if (tracks.length >= MAX_TRACKS) break;
      if (seenVideoIds.has(track.videoId)) continue;
      seenVideoIds.add(track.videoId);

      // If primary was stdTracks, enrich with musicTrack if available
      if (primaryList === stdTracksList) {
        const musicTrack = musicTracksMap.get(track.videoId);
        if (musicTrack) {
          tracks.push({
            ...track,
            title: musicTrack.title || track.title,
            artist: musicTrack.artist || track.artist,
            artwork: musicTrack.artwork || track.artwork,
            duration: musicTrack.duration || track.duration,
          });
          continue;
        }
      }
      tracks.push(track);
    }

    for (const track of secondaryList) {
      if (tracks.length >= MAX_TRACKS) break;
      if (seenVideoIds.has(track.videoId)) continue;
      seenVideoIds.add(track.videoId);
      tracks.push(track);
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
