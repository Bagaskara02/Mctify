const STORAGE_KEYS = {
  PLAYLISTS: 'mcmusic_playlists_v2',
  LIKED_TRACKS: 'mcmusic_liked_tracks_v2',
  HISTORY: 'mcmusic_history_v2',
  SETTINGS: 'mcmusic_settings_v2',
  SKIPS: 'mcmusic_skips_v2',
  COMPLETES: 'mcmusic_completes_v2',
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

  getSkips() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.SKIPS);
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  },

  getCompletes() {
    try {
      const saved = localStorage.getItem(STORAGE_KEYS.COMPLETES);
      return saved ? JSON.parse(saved) : {};
    } catch {
      return {};
    }
  },

  /**
   * Negative Feedback: Records user skip or queue jump
   * Early skips down-weight the track and artist so they are not recommended again.
   */
  recordTrackSkip(track, listenedSec = 0, duration = 0) {
    if (!track || !track.title) return;
    const cleanT = (track.title || '').toLowerCase().trim();
    const cleanA = (track.artist || '').toLowerCase().trim();
    const trackKey = `${cleanT}:::${cleanA}`;
    const idKey = track.id ? String(track.id) : trackKey;

    try {
      const skips = this.getSkips();
      const current = skips[trackKey] || skips[idKey] || {
        trackKey,
        id: track.id,
        title: track.title,
        artist: track.artist,
        genre: track.genre || '',
        count: 0,
        lastSkippedAt: 0,
      };

      current.count = (current.count || 0) + 1;
      current.lastSkippedAt = Date.now();
      current.title = track.title;
      current.artist = track.artist;
      current.genre = track.genre || current.genre || '';
      current.lastDuration = duration;
      current.lastListenedSec = listenedSec;

      skips[trackKey] = current;
      if (track.id) skips[track.id] = current;
      localStorage.setItem(STORAGE_KEYS.SKIPS, JSON.stringify(skips));
    } catch (e) {
      console.warn('recordTrackSkip error:', e);
    }
  },

  /**
   * Positive Feedback: Records full or engaged listen
   * Rewards track affinity and cancels negative skip penalties on artist.
   */
  recordTrackComplete(track) {
    if (!track || !track.title) return;
    const cleanT = (track.title || '').toLowerCase().trim();
    const cleanA = (track.artist || '').toLowerCase().trim();
    const trackKey = `${cleanT}:::${cleanA}`;
    const idKey = track.id ? String(track.id) : trackKey;

    try {
      const completes = this.getCompletes();
      const current = completes[trackKey] || completes[idKey] || {
        trackKey,
        id: track.id,
        title: track.title,
        artist: track.artist,
        count: 0,
        lastCompletedAt: 0,
      };

      current.count = (current.count || 0) + 1;
      current.lastCompletedAt = Date.now();
      completes[trackKey] = current;
      if (track.id) completes[track.id] = current;
      localStorage.setItem(STORAGE_KEYS.COMPLETES, JSON.stringify(completes));
    } catch (e) {
      console.warn('recordTrackComplete error:', e);
    }
  },

  /**
   * Returns a unified set of excluded track keys (recently played + skipped)
   * to guarantee zero immediate repetition across consecutive randomize cycles.
   */
  getRecentExclusionKeys(historyLimit = 6) {
    const exclusions = new Set();
    try {
      const history = this.getHistory() || [];
      // Only exclude immediate recent history (last 5-6 tracks) so queue doesn't repeat back-to-back
      for (const t of history.slice(0, historyLimit)) {
        if (t?.id) exclusions.add(String(t.id));
        if (t?.title && t?.artist) {
          const tClean = (t.title || '').toLowerCase().trim();
          const aClean = (t.artist || '').toLowerCase().trim();
          exclusions.add(`${tClean}:::${aClean}`);
        }
      }

      const skips = this.getSkips();
      const cutoff = Date.now() - (6 * 60 * 60 * 1000); // 6 hours
      for (const item of Object.values(skips)) {
        if (!item || typeof item !== 'object') continue;
        if (item.lastSkippedAt && item.lastSkippedAt < cutoff) continue;
        if (item.id) exclusions.add(String(item.id));
        if (item.title && item.artist) {
          const tClean = (item.title || '').toLowerCase().trim();
          const aClean = (item.artist || '').toLowerCase().trim();
          exclusions.add(`${tClean}:::${aClean}`);
        }
      }
    } catch {}
    return exclusions;
  },

  /**
   * Get dynamic taste profile based on history, play counts, liked songs, and skip learning
   * Analyzes most played artists, genres, skipped tracks, and penalized artists.
   */
  getTasteProfile() {
    try {
      const history = this.getHistory() || [];
      const liked = this.getLikedTracks() || [];
      const playCounts = this.getPlayCounts() || {};
      const skips = this.getSkips() || {};
      const completes = this.getCompletes() || {};
      const combined = [...liked, ...history];

      // Calculate skipped track keys & artist penalties
      const skippedTrackKeys = new Set();
      const penalizedArtists = {}; // artist -> penalty score
      const skipCutoff = Date.now() - (72 * 60 * 60 * 1000); // 3 days

      for (const item of Object.values(skips)) {
        if (!item || typeof item !== 'object') continue;
        if (item.count >= 1 && (!item.lastSkippedAt || item.lastSkippedAt > skipCutoff)) {
          if (item.id) skippedTrackKeys.add(String(item.id));
          if (item.title) {
            const cleanT = (item.title || '').toLowerCase().trim();
            skippedTrackKeys.add(cleanT);
            if (item.artist) {
              const artKey = (item.artist || '').toLowerCase().trim();
              skippedTrackKeys.add(`${cleanT}:::${artKey}`);
              penalizedArtists[artKey] = (penalizedArtists[artKey] || 0) + (Number(item.count) || 1);
            }
          }
        }
      }

      // Offset penalties for artists where user also completed tracks
      for (const item of Object.values(completes)) {
        if (!item || typeof item !== 'object') continue;
        if (item.artist) {
          const artKey = (item.artist || '').toLowerCase().trim();
          if (penalizedArtists[artKey]) {
            penalizedArtists[artKey] = Math.max(0, penalizedArtists[artKey] - (Number(item.count) || 1));
          }
        }
      }

      if (combined.length === 0 && Object.keys(playCounts).length === 0) {
        return {
          topArtists: [],
          topGenres: [],
          mostPlayedTracks: [],
          lastPlayedTrack: null,
          recentTracks: [],
          likedTracks: [],
          skippedTrackKeys,
          penalizedArtists,
          hasHistory: false,
        };
      }

      const artistCounts = {};
      const genreCounts = {};

      // Calculate artist counts from playCounts with weighted counts
      for (const item of Object.values(playCounts)) {
        if (!item || typeof item !== 'object') continue;
        const count = Number(item.count) || 1;
        if (item.track?.artist) {
          artistCounts[item.track.artist] = (artistCounts[item.track.artist] || 0) + count;
        }
        if (item.track?.genre) {
          genreCounts[item.track.genre] = (genreCounts[item.track.genre] || 0) + count;
        }
      }

      // Factor in liked tracks (bonus 3 points for favorite artists)
      for (const t of liked) {
        if (t?.artist) {
          artistCounts[t.artist] = (artistCounts[t.artist] || 0) + 3;
        }
        if (t?.genre) {
          genreCounts[t.genre] = (genreCounts[t.genre] || 0) + 3;
        }
      }

      // Factor in recent history
      for (const t of history) {
        if (t?.artist && !artistCounts[t.artist]) {
          artistCounts[t.artist] = 1;
        }
      }

      // Subtract negative skip penalties from artist affinity
      for (const [art, count] of Object.entries(artistCounts)) {
        const pen = penalizedArtists[art.toLowerCase()] || 0;
        artistCounts[art] = Math.max(0, count - pen * 2);
      }

      const topArtists = Object.entries(artistCounts)
        .filter(([, score]) => score > 0)
        .sort((a, b) => b[1] - a[1])
        .map(entry => entry[0]);

      const topGenres = Object.entries(genreCounts)
        .sort((a, b) => b[1] - a[1])
        .map(entry => entry[0]);

      // Top played tracks sorted by play count, excluding explicitly skipped tracks
      const topPlayedTracks = Object.values(playCounts)
        .filter(item => item && typeof item === 'object' && item.track)
        .filter(item => {
          const t = item.track;
          const idStr = String(t.id || '');
          const cleanT = (t.title || '').toLowerCase().trim();
          const key = `${cleanT}:::${(t.artist || '').toLowerCase().trim()}`;
          return !skippedTrackKeys.has(idStr) && !skippedTrackKeys.has(cleanT) && !skippedTrackKeys.has(key);
        })
        .sort((a, b) => (Number(b.count) || 0) - (Number(a.count) || 0))
        .map(item => item.track)
        .filter(Boolean);

      return {
        topArtists,
        topGenres,
        mostPlayedTracks: topPlayedTracks.slice(0, 10),
        lastPlayedTrack: history[0] || null,
        recentTracks: history.slice(0, 8),
        likedTracks: liked.slice(0, 8),
        skippedTrackKeys,
        penalizedArtists,
        hasHistory: history.length > 0 || liked.length > 0 || topPlayedTracks.length > 0,
      };
    } catch (e) {
      console.warn('getTasteProfile fallback:', e);
      return null;
    }
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

  getRecentSearches() {
    try {
      const saved = localStorage.getItem('mctify_recent_searches_v1');
      return saved ? JSON.parse(saved) : [];
    } catch {
      return [];
    }
  },

  addRecentSearch(item) {
    if (!item || !item.query || !item.query.trim()) return [];
    const trimmed = item.query.trim();
    const type = item.type || 'query';
    try {
      const current = this.getRecentSearches().filter(
        (x) => !((x.query || '').toLowerCase() === trimmed.toLowerCase() && (x.type || 'query') === type)
      );
      const updated = [
        {
          query: trimmed,
          title: item.title || trimmed,
          subtitle: item.subtitle || 'Pencarian',
          artwork: item.artwork || '',
          type,
        },
        ...current,
      ].slice(0, 14);
      localStorage.setItem('mctify_recent_searches_v1', JSON.stringify(updated));
      return updated;
    } catch {
      return [];
    }
  },

  removeRecentSearch(query, type) {
    try {
      const updated = this.getRecentSearches().filter(
        (x) => !((x.query || '').toLowerCase() === (query || '').toLowerCase() && (!type || x.type === type))
      );
      localStorage.setItem('mctify_recent_searches_v1', JSON.stringify(updated));
      return updated;
    } catch {
      return [];
    }
  },

  clearRecentSearches() {
    try {
      localStorage.removeItem('mctify_recent_searches_v1');
      return [];
    } catch {
      return [];
    }
  },

  getTransitionSettings() {
    try {
      const saved = localStorage.getItem('mcmusic_transition_settings_v1');
      if (saved) return JSON.parse(saved);
      return {
        bars: '2 bars',
        durationSec: 5.5,
        volume: 'overlap',
        eq: 'none',
        effect: 'high_pass',
        enabled: true,
      };
    } catch {
      return {
        bars: '2 bars',
        durationSec: 5.5,
        volume: 'overlap',
        eq: 'none',
        effect: 'high_pass',
        enabled: true,
      };
    }
  },

  saveTransitionSettings(settings) {
    try {
      localStorage.setItem('mcmusic_transition_settings_v1', JSON.stringify(settings));
    } catch (e) {
      console.error('Failed to save transition settings', e);
    }
  },
};
