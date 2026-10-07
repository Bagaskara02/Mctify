const STORAGE_KEYS = {
  PLAYLISTS: 'mcmusic_playlists_v2',
  LIKED_TRACKS: 'mcmusic_liked_tracks_v2',
  HISTORY: 'mcmusic_history_v2',
  SETTINGS: 'mcmusic_settings_v2',
};

const DEFAULT_PLAYLISTS = [
  {
    id: 'pl-favorites',
    name: 'Liked Songs',
    description: 'Your favorite tracks',
    cover: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=400',
    source: 'local',
    tracks: [],
    createdAt: Date.now(),
  },
  {
    id: 'pl-chill-vibes',
    name: 'Late Night Chill',
    description: 'Mellow melodies, ambient beats, and soothing vocals',
    cover: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
    source: 'curated',
    tracks: [],
    createdAt: Date.now() - 100000,
  },
];

export const storageService = {
  getPlaylists() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.PLAYLISTS);
      if (saved) return JSON.parse(saved);
      this.savePlaylists(DEFAULT_PLAYLISTS);
      return DEFAULT_PLAYLISTS;
    } catch {
      return DEFAULT_PLAYLISTS;
    }
  },

  savePlaylists(playlists) {
    try {
      localStorage.setItem(STORAGE_KEYS.PLAYLISTS, JSON.stringify(playlists));
    } catch (e) {
      console.error('Failed to save playlists to localStorage', e);
    }
  },

  addPlaylist(playlist) {
    const playlists = this.getPlaylists();
    const newPlaylist = {
      id: playlist.id || 'pl-' + Date.now(),
      name: playlist.name || 'New Playlist',
      description: playlist.description || '',
      cover: playlist.cover || 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=400',
      source: playlist.source || 'custom',
      tracks: playlist.tracks || [],
      createdAt: Date.now(),
    };
    playlists.push(newPlaylist);
    this.savePlaylists(playlists);
    return newPlaylist;
  },

  deletePlaylist(playlistId) {
    const playlists = this.getPlaylists().filter(p => p.id !== playlistId);
    this.savePlaylists(playlists);
    return playlists;
  },

  updatePlaylist(playlistId, updates) {
    const playlists = this.getPlaylists().map(p => {
      if (p.id === playlistId) {
        return { ...p, ...updates };
      }
      return p;
    });
    this.savePlaylists(playlists);
    return playlists;
  },

  addTrackToPlaylist(playlistId, track) {
    const playlists = this.getPlaylists();
    const pl = playlists.find(p => p.id === playlistId);
    if (pl) {
      if (!pl.tracks.some(t => t.id === track.id)) {
        pl.tracks.push(track);
        this.savePlaylists(playlists);
      }
    }
    return playlists;
  },

  removeTrackFromPlaylist(playlistId, trackId) {
    const playlists = this.getPlaylists();
    const pl = playlists.find(p => p.id === playlistId);
    if (pl) {
      pl.tracks = pl.tracks.filter(t => t.id !== trackId);
      this.savePlaylists(playlists);
    }
    return playlists;
  },

  getLikedTracks() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.LIKED_TRACKS);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  },

  toggleLikeTrack(track) {
    const liked = this.getLikedTracks();
    const exists = liked.some(t => t.id === track.id);
    let updated;
    if (exists) {
      updated = liked.filter(t => t.id !== track.id);
    } else {
      updated = [track, ...liked];
    }
    try {
      localStorage.setItem(STORAGE_KEYS.LIKED_TRACKS, JSON.stringify(updated));
    } catch (e) {
      console.error(e);
    }
    return updated;
  },

  getPlayCounts() {
    try {
      const saved = localStorage.getItem('mcmusic_play_counts_v2');
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  },

  getHistory() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.HISTORY);
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  },

  addToHistory(track) {
    if (!track || !track.id) return;
    const history = this.getHistory().filter(t => t.id !== track.id);
    const updated = [track, ...history].slice(0, 50);
    try {
      localStorage.setItem(STORAGE_KEYS.HISTORY, JSON.stringify(updated));
    } catch (e) {
      console.error(e);
    }

    // Increment play count
    try {
      const counts = this.getPlayCounts();
      const current = counts[track.id] || { count: 0, track, lastPlayed: 0 };
      counts[track.id] = {
        count: (current.count || 0) + 1,
        track,
        lastPlayed: Date.now(),
      };
      localStorage.setItem('mcmusic_play_counts_v2', JSON.stringify(counts));
    } catch (e) {
      console.error(e);
    }
  },

  /**
   * Get dynamic taste profile based on history, play counts, and liked songs
   * Analyzes most played artists, genres, and recent tracks.
   */
  getTasteProfile() {
    const history = this.getHistory();
    const liked = this.getLikedTracks();
    const playCounts = this.getPlayCounts();
    const combined = [...liked, ...history];

    if (combined.length === 0 && Object.keys(playCounts).length === 0) return null;

    const artistCounts = {};
    const genreCounts = {};

    // Calculate artist counts from playCounts with weighted counts
    for (const item of Object.values(playCounts)) {
      if (item.track?.artist) {
        artistCounts[item.track.artist] = (artistCounts[item.track.artist] || 0) + item.count;
      }
      if (item.track?.genre) {
        genreCounts[item.track.genre] = (genreCounts[item.track.genre] || 0) + item.count;
      }
    }

    // Factor in liked tracks (bonus 3 points for favorite artists)
    for (const t of liked) {
      if (t.artist) {
        artistCounts[t.artist] = (artistCounts[t.artist] || 0) + 3;
      }
      if (t.genre) {
        genreCounts[t.genre] = (genreCounts[t.genre] || 0) + 3;
      }
    }

    // Factor in recent history
    for (const t of history) {
      if (t.artist && !artistCounts[t.artist]) {
        artistCounts[t.artist] = 1;
      }
    }

    const topArtists = Object.entries(artistCounts)
      .sort((a, b) => b[1] - a[1])
      .map(entry => entry[0]);

    const topGenres = Object.entries(genreCounts)
      .sort((a, b) => b[1] - a[1])
      .map(entry => entry[0]);

    // Top played tracks sorted by play count
    const topPlayedTracks = Object.values(playCounts)
      .sort((a, b) => b.count - a.count)
      .map(item => item.track)
      .filter(Boolean);

    return {
      topArtists,
      topGenres,
      mostPlayedTracks: topPlayedTracks.slice(0, 10),
      lastPlayedTrack: history[0] || null,
      recentTracks: history.slice(0, 8),
      likedTracks: liked.slice(0, 8),
      hasHistory: history.length > 0 || liked.length > 0 || topPlayedTracks.length > 0,
    };
  },

  getSettings() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.SETTINGS);
      return saved ? JSON.parse(saved) : { fontSize: 'large', syncOffset: 0, autoScroll: true };
    } catch {
      return { fontSize: 'large', syncOffset: 0, autoScroll: true };
    }
  },

  saveSettings(settings) {
    try {
      localStorage.setItem(STORAGE_KEYS.SETTINGS, JSON.stringify(settings));
    } catch (e) {
      console.error(e);
    }
  },
};
