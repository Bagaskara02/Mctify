import { musicApi, DEFAULT_ARTWORK } from './musicApi.js';
import { sanitizeMediaUrl } from './storageService.js';

/**
 * Multi-Platform Playlist Importer
 * Supports Spotify URLs, YouTube Music URLs, Plain Text, and JSON backups.
 * Resolves full-song duration and YouTube video IDs.
 */
export const playlistImporter = {
  /**
   * Import playlist from Spotify URL
   */
  async importFromSpotify(url, onProgress = () => {}) {
    onProgress({ status: 'analyzing', message: 'Analyzing Spotify playlist link...' });

    const playlistIdMatch = url.match(/playlist[\/:]([a-zA-Z0-9]+)/);
    if (!playlistIdMatch) {
      throw new Error('Invalid Spotify playlist URL. Please check the link format.');
    }
    const playlistId = playlistIdMatch[1];

    let playlistTitle = 'Spotify Playlist';
    let playlistCover = DEFAULT_ARTWORK;
    let extractedTracks = [];

    // Method 1: Internal Backend Proxy (/api/spotify/playlist) - 100% reliable
    try {
      onProgress({ status: 'fetching', message: 'Connecting to Spotify and extracting tracklist...' });
      const res = await fetch(`/api/spotify/playlist?id=${playlistId}`);
      if (res.ok) {
        const data = await res.json();
        if (data && Array.isArray(data.tracks) && data.tracks.length > 0) {
          playlistTitle = data.name || playlistTitle;
          playlistCover = data.cover || playlistCover;
          extractedTracks = data.tracks;
        }
      }
    } catch (e) {
      console.warn('Backend Spotify proxy failed, trying oEmbed fallback', e);
    }

    // Fallback if backend proxy didn't return tracks: try CORS proxies
    if (extractedTracks.length === 0) {
      try {
        const embedUrl = `https://open.spotify.com/embed/playlist/${playlistId}`;
        const proxyRes = await fetch(`https://api.allorigins.win/raw?url=${encodeURIComponent(embedUrl)}`);
        if (proxyRes.ok) {
          const html = await proxyRes.text();
          const match = html.match(/<script id="__NEXT_DATA__"[^>]*>(.*?)<\/script>/s);
          if (match) {
            const parsed = JSON.parse(match[1]);
            const entity = parsed.props?.pageProps?.state?.data?.entity;
            if (entity?.name) playlistTitle = entity.name;
            if (entity?.coverArt?.sources?.[0]?.url) playlistCover = entity.coverArt.sources[0].url;
            const rawTracks = entity?.trackList || [];
            extractedTracks = rawTracks.map(t => ({
              title: t.title,
              artist: t.subtitle,
            })).filter(t => t.title && t.artist);
          }
        }
      } catch {
        // Fallback failed
      }
    }

    if (extractedTracks.length === 0) {
      throw new Error(
        'Could not retrieve tracks from this Spotify link. Please check that the playlist is public, or paste the track titles in the "Paste Tracklist" tab.'
      );
    }

    onProgress({ status: 'resolving', message: `Found ${extractedTracks.length} tracks. Resolving full songs...` });
    return await this.resolveTrackList(extractedTracks, playlistTitle, playlistCover, 'spotify', onProgress);
  },

  /**
   * Import playlist from YouTube / YouTube Music URL
   */
  async importFromYouTube(url, onProgress = () => {}) {
    onProgress({ status: 'analyzing', message: 'Menganalisis link YouTube playlist...' });

    let playlistId = '';
    const listMatch = url.match(/[?&]list=([^#&?]+)/);
    if (listMatch) {
      playlistId = listMatch[1];
    } else if (/^[a-zA-Z0-9_-]{12,}$/.test(url.trim())) {
      playlistId = url.trim();
    } else {
      throw new Error('Link YouTube playlist tidak valid. URL harus memiliki parameter ?list=...');
    }

    onProgress({ status: 'fetching', message: 'Menghubungkan ke YouTube dan mengambil daftar lagu...' });
    const res = await fetch(`/api/yt/playlist?id=${encodeURIComponent(playlistId)}`);
    if (!res.ok) {
      const errData = await res.json().catch(() => ({}));
      throw new Error(errData.error || `Gagal mengambil playlist dari YouTube (Status ${res.status})`);
    }

    const data = await res.json();
    if (!data.tracks || data.tracks.length === 0) {
      throw new Error('Tidak ada lagu yang ditemukan di dalam playlist YouTube ini. Pastikan playlist bersifat publik.');
    }

    const playlistTitle = data.name || 'YouTube Playlist';
    const seenVids = new Set();
    const mappedTracks = [];
    for (let idx = 0; idx < data.tracks.length; idx++) {
      const t = data.tracks[idx];
      const vid = typeof t.videoId === 'string' ? t.videoId.trim() : '';
      if (vid) {
        if (seenVids.has(vid)) continue;
        seenVids.add(vid);
      }
      let art = sanitizeMediaUrl(t.artwork || '', '');
      if (art && art.includes('googleusercontent.com') && !art.includes('no_thumbnail') && !art.includes('default_playlist')) {
        art = art.replace(/=w\d+-h\d+[^?#]*/i, '=w544-h544-l90-rj').replace(/=s\d+[^?#]*/i, '=w544-h544-l90-rj');
      } else if (vid) {
        art = `https://i.ytimg.com/vi/${vid}/hqdefault.jpg`;
      } else if (art) {
        art = art.split('?')[0].replace(/hq(hq)?720\.jpg/gi, 'hqdefault.jpg');
      } else {
        art = DEFAULT_ARTWORK;
      }
      mappedTracks.push({
        id: t.id || (vid ? `yt_${vid}` : `yt-${idx}`),
        videoId: vid || null,
        title: t.title,
        artist: t.artist,
        album: t.album || playlistTitle,
        duration: t.duration || 180,
        artwork: art || DEFAULT_ARTWORK,
        audioUrl: '',
        genre: 'Music',
        releaseYear: '2024',
      });
    }

    let playlistCover = sanitizeMediaUrl(data.cover || '', '');
    if (
      !playlistCover ||
      playlistCover.includes('no_thumbnail') ||
      playlistCover.includes('default_playlist') ||
      playlistCover.includes('sqp=') ||
      playlistCover.includes('default.jpg')
    ) {
      playlistCover = mappedTracks[0]?.artwork || DEFAULT_ARTWORK;
    }

    onProgress({ status: 'done', message: `Berhasil mengambil ${mappedTracks.length} lagu!` });

    return {
      id: 'pl-yt-' + playlistId,
      name: playlistTitle,
      description: `Diimpor dari YouTube Playlist (${mappedTracks.length} lagu)`,
      cover: playlistCover,
      source: 'youtube',
      tracks: mappedTracks,
      createdAt: Date.now(),
    };
  },

  /**
   * Import from plain text
   */
  async importFromPlainText(text, customTitle = 'Custom Playlist', onProgress = () => {}) {
    onProgress({ status: 'parsing', message: 'Parsing track list...' });

    const lines = text.split('\n').map(l => l.trim()).filter(l => l.length > 2);
    if (lines.length === 0) {
      throw new Error('No songs found in the pasted text.');
    }

    const parsedItems = [];
    for (const line of lines) {
      let clean = line.replace(/^\d+[\.\)\-]\s*/, '').trim();

      let artist = '';
      let title = '';

      if (clean.includes(' - ')) {
        const parts = clean.split(' - ');
        artist = parts[0].trim();
        title = parts.slice(1).join(' - ').trim();
      } else if (clean.toLowerCase().includes(' by ')) {
        const parts = clean.split(/ by /i);
        title = parts[0].trim();
        artist = parts.slice(1).join(' by ').trim();
      } else if (clean.includes(' : ')) {
        const parts = clean.split(' : ');
        artist = parts[0].trim();
        title = parts.slice(1).join(' : ').trim();
      } else {
        title = clean;
      }

      if (title) {
        parsedItems.push({ title, artist });
      }
    }

    return await this.resolveTrackList(parsedItems, customTitle, DEFAULT_ARTWORK, 'text', onProgress);
  },

  /**
   * Import from exported JSON file
   */
  importFromJson(jsonContent) {
    try {
      if (typeof jsonContent === 'string' && jsonContent.length > 2 * 1024 * 1024) {
        throw new Error('Backup JSON file exceeds 2 MB safety limit.');
      }
      const data = typeof jsonContent === 'string' ? JSON.parse(jsonContent) : jsonContent;
      if (!data || typeof data !== 'object' || Array.isArray(data) || !Array.isArray(data.tracks)) {
        throw new Error('Invalid playlist JSON format. Expected object with "tracks" array.');
      }
      const safeTracks = data.tracks
        .filter((t) => t && typeof t === 'object' && !Array.isArray(t))
        .slice(0, 500)
        .map((t, idx) => {
          const vid = typeof t.videoId === 'string' && /^[a-zA-Z0-9_-]{11}$/.test(t.videoId.trim()) ? t.videoId.trim() : null;
          const fallbackArt = vid ? `https://i.ytimg.com/vi/${vid}/hqdefault.jpg` : DEFAULT_ARTWORK;
          return {
            id: typeof t.id === 'string' && t.id.trim() ? t.id.trim().slice(0, 128) : `imp-json-${Date.now()}-${idx}`,
            videoId: vid,
            title: typeof t.title === 'string' ? t.title.slice(0, 200) : 'Imported Track',
            artist: typeof t.artist === 'string' ? t.artist.slice(0, 200) : 'Unknown Artist',
            album: typeof t.album === 'string' ? t.album.slice(0, 200) : 'Single',
            duration: Number.isFinite(Number(t.duration)) ? Math.max(1, Math.min(7200, Math.round(Number(t.duration)))) : 180,
            artwork: sanitizeMediaUrl(t.artwork, fallbackArt) || fallbackArt,
            audioUrl: '',
            genre: typeof t.genre === 'string' ? t.genre.slice(0, 64) : 'Music',
            releaseYear: typeof t.releaseYear === 'string' ? t.releaseYear.slice(0, 16) : '2024',
          };
        });
      return {
        id: 'pl-json-' + Date.now(),
        name: typeof data.name === 'string' && data.name.trim() ? data.name.trim().slice(0, 120) : 'Imported Playlist',
        description: typeof data.description === 'string' ? data.description.trim().slice(0, 400) : 'Imported from JSON backup',
        cover: sanitizeMediaUrl(data.cover, safeTracks[0]?.artwork || DEFAULT_ARTWORK) || safeTracks[0]?.artwork || DEFAULT_ARTWORK,
        source: 'json',
        tracks: safeTracks,
        createdAt: Date.now(),
      };
    } catch (e) {
      throw new Error('Failed to parse JSON playlist: ' + e.message);
    }
  },

  /**
   * Export playlist to downloadable JSON file
   */
  exportToJson(playlist) {
    const dataStr = 'data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(playlist, null, 2));
    const downloadAnchor = document.createElement('a');
    downloadAnchor.setAttribute('href', dataStr);
    downloadAnchor.setAttribute('download', `${(playlist.name || 'playlist').toLowerCase().replace(/\s+/g, '_')}.json`);
    document.body.appendChild(downloadAnchor);
    downloadAnchor.click();
    downloadAnchor.remove();
  },

  /**
   * Resolve an array of {title, artist} into full playable tracks with audio & artwork
   */
  async resolveTrackList(items, playlistTitle, cover, source, onProgress) {
    const resolvedTracks = [];
    const total = items.length;

    for (let i = 0; i < total; i++) {
      const item = items[i];
      onProgress({
        status: 'resolving',
        current: i + 1,
        total,
        message: `Matching full song (${i + 1}/${total}): "${item.title}"...`,
      });

      try {
        // Step 1: Match metadata & artwork via iTunes
        let trackObj = await musicApi.findTrackMatch(item.title, item.artist);
        
        // Step 2: Try resolving full YouTube video ID & full duration
        const ytMatch = await musicApi.resolveYouTubeMatch(item.title, item.artist);
        
        if (trackObj) {
          if (ytMatch && ytMatch.videoId) {
            trackObj.videoId = ytMatch.videoId;
            trackObj.duration = ytMatch.duration || trackObj.duration;
          }
          resolvedTracks.push(trackObj);
        } else if (ytMatch && ytMatch.videoId) {
          resolvedTracks.push({
            id: 'yt-' + ytMatch.videoId,
            title: ytMatch.title || item.title,
            artist: ytMatch.artist || item.artist || 'Unknown Artist',
            album: 'YouTube Music',
            artwork: ytMatch.thumbnail || cover || DEFAULT_ARTWORK,
            audioUrl: '',
            videoId: ytMatch.videoId,
            duration: ytMatch.duration || 210,
            genre: 'Music',
            releaseYear: '2024',
          });
        } else {
          resolvedTracks.push({
            id: 'imp-' + Math.random().toString(36).substr(2, 9),
            title: item.title,
            artist: item.artist || 'Unknown Artist',
            album: 'Imported Track',
            artwork: cover || DEFAULT_ARTWORK,
            audioUrl: '',
            videoId: null,
            duration: 180,
            genre: 'Music',
            releaseYear: '2024',
          });
        }
      } catch {
        resolvedTracks.push({
          id: 'imp-' + Math.random().toString(36).substr(2, 9),
          title: item.title,
          artist: item.artist || 'Unknown Artist',
          album: 'Imported Track',
          artwork: cover || DEFAULT_ARTWORK,
          audioUrl: '',
          videoId: null,
          duration: 180,
          genre: 'Music',
          releaseYear: '2024',
        });
      }

      if (i < total - 1 && i % 3 === 0) {
        await new Promise(r => setTimeout(r, 60));
      }
    }

    onProgress({ status: 'done', message: `Imported ${resolvedTracks.length} tracks successfully!` });

    return {
      id: 'pl-' + Date.now(),
      name: playlistTitle,
      description: `Imported with ${resolvedTracks.length} full songs from ${source.toUpperCase()}`,
      cover: resolvedTracks[0]?.artwork || cover || DEFAULT_ARTWORK,
      source,
      tracks: resolvedTracks,
      createdAt: Date.now(),
    };
  },

  /**
   * Quick-import sample presets
   */
  getPresetPlaylists() {
    return [
      {
        id: 'preset-today-top-hits',
        name: "Today's Top Hits (Spotify)",
        source: 'spotify',
        description: 'The biggest songs right now across the globe',
        cover: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
        text: `Taylor Swift - Cruel Summer
Billie Eilish - Birds of a Feather
Lady Gaga & Bruno Mars - Die With A Smile
The Weeknd - Blinding Lights
Coldplay - Yellow
Sabrina Carpenter - Espresso
Kendrick Lamar - Not Like Us
Chappell Roan - Good Luck, Babe!`,
      },
      {
        id: 'preset-yt-music-pop',
        name: 'Trending Hits (YouTube Music)',
        source: 'youtube',
        description: 'Viral hits and chart toppers trending on YouTube',
        cover: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
        text: `The Weeknd - Save Your Tears
Coldplay - Fix You
Dua Lipa - Levitating
Post Malone - Circles
Harry Styles - As It Was
Ed Sheeran - Shape of You`,
      },
      {
        id: 'preset-indo-hits',
        name: 'Hits Pop Indonesia',
        source: 'spotify',
        description: 'Lagu pop Indonesia terfavorit & viral',
        cover: 'https://images.unsplash.com/photo-1493225255756-d9584f8606e9?auto=format&fit=crop&q=80&w=400',
        text: `Bernadya - Satu Bulan
Nadin Amizah - Rayuan Perempuan Gila
Mahalini - Sial
Sal Priadi - Dari planet lain
Tulus - Hati-Hati di Jalan
Tiara Andini - Kupu-Kupu`,
      },
    ];
  },
};
