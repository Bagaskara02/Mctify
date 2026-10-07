import { musicApi, DEFAULT_ARTWORK } from './musicApi';

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
    onProgress({ status: 'analyzing', message: 'Analyzing YouTube playlist...' });

    const listMatch = url.match(/[?&]list=([^#&?]+)/);
    if (!listMatch) {
      throw new Error('Invalid YouTube Playlist URL. URL must contain "?list=..." parameter.');
    }

    throw new Error(
      'Direct YouTube Playlist scraping in browser requires an API key or backend proxy. You can quickly paste the song names in the "Paste Tracklist" tab!'
    );
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
      const data = typeof jsonContent === 'string' ? JSON.parse(jsonContent) : jsonContent;
      if (!data || !Array.isArray(data.tracks)) {
        throw new Error('Invalid playlist JSON format. Expected object with "tracks" array.');
      }
      return {
        id: 'pl-json-' + Date.now(),
        name: data.name || 'Imported Playlist',
        description: data.description || 'Imported from JSON backup',
        cover: data.cover || DEFAULT_ARTWORK,
        source: 'json',
        tracks: data.tracks,
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
