/**
 * Music API Service
 * Handles search, metadata, and full-length YouTube Music resolution.
 */

export const DEFAULT_ARTWORK = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600';

/**
 * Universal High-Resolution Artwork Transformer
 * Converts 60x60, 100x100, or low-res thumbnails from Google User Content, YouTube, iTunes, and Spotify into 800x800+ Ultra-HD
 */
export function getHighResArtworkUrl(url) {
  if (!url || typeof url !== 'string') return url || DEFAULT_ARTWORK;
  let clean = url.trim();

  // 1. Google User Content (YouTube Music album art: yt3.googleusercontent.com, lh3.googleusercontent.com)
  if (clean.includes('googleusercontent.com')) {
    if (/=w\d+-h\d+/i.test(clean)) {
      return clean.replace(/=w\d+-h\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (/=s\d+/i.test(clean)) {
      return clean.replace(/=s\d+[^?#]*/i, '=w800-h800-l90-rj');
    }
    if (!clean.includes('=')) {
      return `${clean}=w800-h800-l90-rj`;
    }
  }

  // 2. YouTube Video Thumbnails (i.ytimg.com)
  if (clean.includes('ytimg.com')) {
    if (/default\.jpg/i.test(clean)) {
      return clean.replace(/(default|mqdefault|sddefault)\.jpg/i, 'hq720.jpg').split('?')[0];
    }
  }

  // 3. Apple Music / iTunes (mzstatic.com)
  if (clean.includes('mzstatic.com')) {
    return clean.replace(/\/\d+x\d+bb\./i, '/1000x1000bb.');
  }

  // 4. Spotify CDN
  if (clean.includes('i.scdn.co/image/ab67616d00004851')) {
    return clean.replace('ab67616d00004851', 'ab67616d0000b273');
  }

  return clean;
}

/**
 * Quality & Popularity Filter:
 * Rejects obscure amateur covers, karaoke versions, instrumentals, parodies,
 * tutorials, and junk uploads to ensure ONLY verified, well-known popular hits.
 */
export function isCleanPopularTrack(t) {
  if (!t || !t.title || !t.artist) return false;
  const title = t.title.toLowerCase();
  const artist = t.artist.toLowerCase();

  const bannedKeywords = [
    'karaoke', 'instrumental', 'backing track', 'cover by', 'tribute to',
    'parodi', 'parody', 'ringtone', 'sped up', 'slowed', 'reverb',
    '8d audio', 'tutorial', 'chord', 'guitar lesson', 'bass tab',
    'drum cover', 'reaction', 'teaser', 'trailer', 'podcast',
    'audio visualizer', 'cara ', 'belajar ', 'remake', 'audio only',
    'lirik video', 'lyrics video', 'acapella'
  ];

  if (bannedKeywords.some(w => title.includes(w) || artist.includes(w))) {
    return false;
  }

  // Reasonably standard radio track duration (between 1:15 and 7:30)
  const dur = t.duration || 180;
  if (dur < 75 || dur > 450) return false;

  return true;
}

/**
 * Curated Top Hitmaker Clusters:
 * Groups the biggest, most beloved, and recognizable artists so that
 * recommendations always feature household-name hits.
 */
export const POPULAR_ARTIST_CLUSTERS = [
  {
    name: 'Indie & Alternative Hits',
    keywords: ['hindia', 'feast', 'bernadya', 'nadin amizah', 'sal priadi', 'kunto aji', 'pamungkas', 'danilla', 'fourtwnty', 'barasuara', 'reality club', 'efek rumah kaca', 'sore', 'the adams', 'morad', 'fiersa besari'],
    peers: ['Hindia', '.Feast', 'Bernadya', 'Nadin Amizah', 'Sal Priadi', 'Kunto Aji', 'Pamungkas', 'Fourtwnty', 'Reality Club']
  },
  {
    name: 'Indonesian Pop & Viral Hits',
    keywords: ['mahalini', 'tulus', 'juicy luicy', 'tiara andini', 'lyodra', 'ziva magnolya', 'yura yunita', 'rizky febian', 'jaz', 'raisa', 'afgan', 'fabio asher', 'budi doremi', 'judika', 'virgoun', 'keisya levronka', 'arash buana', 'idgitaf'],
    peers: ['Bernadya', 'Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra', 'Yura Yunita', 'Rizky Febian', 'Raisa']
  },
  {
    name: 'Indonesian Pop Rock & Legend Hits',
    keywords: ['sheila on 7', 'dewa 19', 'peterpan', 'noah', 'padi', 'ungu', 'd\'masiv', 'ada band', 'kotak', 'gigi', 'slank', 'chrisye', 'glenn fredly', 'ari lasso'],
    peers: ['Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Padi', 'Ungu', 'D\'Masiv', 'Glenn Fredly']
  },
  {
    name: 'Global & Western Pop Hits',
    keywords: ['the weeknd', 'bruno mars', 'taylor swift', 'billie eilish', 'olivia rodrigo', 'ed sheeran', 'coldplay', 'dua lipa', 'maroon 5', 'post malone', 'sabrina carpenter', 'ariana grande', 'justin bieber', 'harry styles', 'lady gaga', 'shawn mendes'],
    peers: ['The Weeknd', 'Bruno Mars', 'Taylor Swift', 'Billie Eilish', 'Olivia Rodrigo', 'Coldplay', 'Sabrina Carpenter', 'Ed Sheeran', 'Dua Lipa']
  },
  {
    name: 'K-Pop Hits',
    keywords: ['newjeans', 'bts', 'blackpink', 'aespa', 'le sserafim', 'twice', 'iu', 'seventeen', 'stray kids', 'rosé', 'jennie', 'jungkook', 'ive', 'txt', 'enhypen'],
    peers: ['NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM', 'IU', 'TWICE', 'ROSÉ']
  }
];

export const musicApi = {
  /**
   * Resolve Full Song YouTube Video ID & Duration
   */
  async resolveYouTubeMatch(title, artist, duration) {
    if (!title) return null;
    try {
      const q = `${title} ${artist || ''}`.trim();
      const durParam = duration ? `&duration=${encodeURIComponent(duration)}` : '';
      const res = await fetch(`/api/yt/search?q=${encodeURIComponent(q)}${durParam}`);
      if (res.ok) {
        const data = await res.json();
        if (data && data.videoId) {
          if (data.thumbnail) {
            data.thumbnail = getHighResArtworkUrl(data.thumbnail);
          }
          return data; // { videoId, title, artist, duration, thumbnail }
        }
      }
    } catch (e) {
      console.warn('YouTube backend resolver lookup failed:', e);
    }

    // Retry with title only if artist was included and returned 404
    if (artist) {
      try {
        const res = await fetch(`/api/yt/search?q=${encodeURIComponent(title)}`);
        if (res.ok) {
          const data = await res.json();
          if (data && data.videoId) {
            if (data.thumbnail) {
              data.thumbnail = getHighResArtworkUrl(data.thumbnail);
            }
            return data;
          }
        }
      } catch (_) {}
    }

    return null;
  },

  /**
   * Search both Songs and Artists across YouTube Music and iTunes
   */
  async searchAll(query) {
    if (!query || !query.trim()) return { songs: [], artists: [] };

    try {
      const q = query.trim();
      // 1. YouTube Music backend multi-search
      const ytPromise = fetch(`/api/yt/search-multi?q=${encodeURIComponent(q)}`)
        .then(r => r.ok ? r.json() : { songs: [], artists: [] })
        .catch(() => ({ songs: [], artists: [] }));

      // 2. iTunes API with country=ID (Indonesia)
      const itunesPromise = fetch(`https://itunes.apple.com/search?term=${encodeURIComponent(q)}&country=ID&entity=song&limit=15`)
        .then(r => r.ok ? r.json() : { results: [] })
        .catch(() => ({ results: [] }));

      const [ytData, itunesData] = await Promise.all([ytPromise, itunesPromise]);

      const itunesTracks = (itunesData.results || []).map(item => this.formatTrack(item));
      const ytSongs = (ytData.songs || []).map(s => ({
        id: s.videoId || s.id,
        videoId: s.videoId || s.id,
        title: s.title,
        artist: s.artist,
        album: s.album || 'Single',
        artwork: getHighResArtworkUrl(s.artwork) || DEFAULT_ARTWORK,
        duration: s.duration || 180,
        genre: 'Pop',
        audioUrl: '',
      }));

      // Combine songs prioritizing YouTube full songs
      const seen = new Set();
      const combinedSongs = [];

      for (const s of [...ytSongs, ...itunesTracks]) {
        const cleanTitle = (s.title || '').toLowerCase().trim();
        const cleanArtist = (s.artist || '').toLowerCase().trim();
        const key = `${cleanTitle}-${cleanArtist}`;
        if (!seen.has(key)) {
          seen.add(key);
          combinedSongs.push(s);
        }
      }

      return {
        songs: combinedSongs,
        artists: ytData.artists || [],
      };
    } catch (e) {
      console.error('searchAll error:', e);
      return { songs: [], artists: [] };
    }
  },

  /**
   * Get artist details and their popular singles/songs
   */
  async getArtistDetails(artistId, artistName) {
    try {
      const res = await fetch(`/api/yt/artist?id=${encodeURIComponent(artistId || '')}&name=${encodeURIComponent(artistName || '')}`);
      if (res.ok) {
        const data = await res.json();
        return data; // { artist, topSongs, allSongs }
      }
    } catch (e) {
      console.error('getArtistDetails error:', e);
    }

    // Fallback if needed
    const songs = await this.searchTracks(artistName, 12);
    return {
      artist: {
        id: artistId || 'art-' + encodeURIComponent(artistName),
        name: artistName,
        headerBanner: songs[0]?.artwork || DEFAULT_ARTWORK,
        avatar: songs[0]?.artwork || DEFAULT_ARTWORK,
        monthlyListeners: '4,9 jt pendengar bulanan',
        verified: true,
      },
      topSongs: songs.slice(0, 5),
      allSongs: songs,
    };
  },

  /**
   * Search tracks by keyword (uses combined searchAll)
   */
  async searchTracks(query, limit = 25) {
    if (!query || !query.trim()) return [];

    try {
      const data = await this.searchAll(query);
      if (data.songs && data.songs.length > 0) {
        return data.songs.slice(0, limit);
      }
    } catch (e) {
      console.warn('searchTracks combined failed, trying fallback:', e);
    }

    try {
      const url = `https://itunes.apple.com/search?term=${encodeURIComponent(query.trim())}&country=ID&entity=song&limit=${limit}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error('Search request failed');

      const data = await res.json();
      return (data.results || [])
        .map(item => this.formatTrack(item));
    } catch (e) {
      console.error('Music search error:', e);
      return [];
    }
  },

  /**
   * Search for single track to match an imported title/artist
   */
  async findTrackMatch(title, artist) {
    const q = `${title} ${artist || ''}`.trim();
    const results = await this.searchTracks(q, 5);
    if (results.length > 0) return results[0];

    // Fallback search with title only
    const titleOnlyResults = await this.searchTracks(title, 3);
    return titleOnlyResults[0] || null;
  },

  /**
   * Format raw iTunes API track into clean app format
   */
  formatTrack(item) {
    let artwork = DEFAULT_ARTWORK;
    if (item.artworkUrl100) {
      artwork = getHighResArtworkUrl(item.artworkUrl100);
    }

    return {
      id: item.trackId ? item.trackId.toString() : 't-' + Math.random().toString(36).substr(2, 9),
      title: item.trackName || 'Unknown Title',
      artist: item.artistName || 'Unknown Artist',
      album: item.collectionName || 'Single',
      artwork: artwork,
      originalArtwork: item.artworkUrl100 || DEFAULT_ARTWORK,
      audioUrl: item.previewUrl || '',
      videoId: null, // Will be filled dynamically by YouTube Matcher
      duration: item.trackTimeMillis ? Math.round(item.trackTimeMillis / 1000) : 180,
      genre: item.primaryGenreName || 'Pop',
      releaseYear: item.releaseDate ? item.releaseDate.slice(0, 4) : '2024',
    };
  },

  /**
   * Fetch Live Trending Tracks directly from iTunes API using verified hitmaker artists
   */
  async fetchTrendingTracks() {
    try {
      const topArtists = [
        'Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy',
        'Mahalini', 'Tulus', 'The Weeknd', 'Bruno Mars', 'Billie Eilish'
      ];
      // Shuffle slightly so home is fresh
      const shuffledQueries = [...topArtists].sort(() => Math.random() - 0.5).slice(0, 4);
      const promises = shuffledQueries.map(q => this.searchTracks(q, 4));
      const resultsArrays = await Promise.all(promises);
      const combined = resultsArrays.flat().filter(isCleanPopularTrack);

      if (combined.length > 0) {
        const unique = [];
        const seen = new Set();
        for (const t of combined) {
          if (!seen.has(t.id)) {
            seen.add(t.id);
            unique.push(t);
          }
        }
        return unique.slice(0, 18);
      }
    } catch (e) {
      console.warn('Failed to fetch live trending tracks', e);
    }

    const fallbackResults = (await this.searchTracks('Tulus', 10)).filter(isCleanPopularTrack);
    return fallbackResults.length > 0 ? fallbackResults : [];
  },

  /**
   * Smart Next / Autoplay: Intelligently finds famous, popular tracks related to current track
   */
  async getSmartRecommendations(currentTrack, existingQueue = []) {
    if (!currentTrack) return [];
    const radioTracks = await this.getArtistGenreRadio(currentTrack, 10);
    const existingIds = new Set(existingQueue.map(t => t.id));
    return radioTracks.filter(t => !existingIds.has(t.id));
  },

  /**
   * Search Radio Mode:
   * Generates a randomized queue of TOP POPULAR, FAMOUS songs matching the artist or peer hitmakers.
   * Strictly filters out obscure songs, covers, and amateur tracks.
   */
  async getArtistGenreRadio(track, limit = 18) {
    if (!track) return [];
    const targetId = track.id;
    const targetTitle = (track.title || '').toLowerCase().trim();
    const targetArtist = (track.artist || '').toLowerCase().trim();

    try {
      // 1. Fetch artist's verified top songs
      const artistDetailsPromise = this.getArtistDetails('', track.artist).catch(() => null);
      const artistSearchPromise = this.searchTracks(track.artist, 12).catch(() => []);

      // 2. Identify peer hitmaker cluster
      let peerArtists = ['Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy', 'Mahalini', 'Tulus'];
      for (const cluster of POPULAR_ARTIST_CLUSTERS) {
        if (cluster.keywords.some(k => targetArtist.includes(k) || k.includes(targetArtist))) {
          peerArtists = cluster.peers.filter(p => p.toLowerCase() !== targetArtist);
          break;
        }
      }

      // Pick 2-3 random famous peer hitmakers from the cluster
      const shuffledPeers = [...peerArtists].sort(() => Math.random() - 0.5).slice(0, 3);
      const peerPromises = shuffledPeers.map(peer => this.searchTracks(peer, 6).catch(() => []));

      // 3. Await all verified popular sources in parallel
      const [artistDetails, artistSearch, ...peerResults] = await Promise.all([
        artistDetailsPromise,
        artistSearchPromise,
        ...peerPromises,
      ]);

      const seen = new Set();
      if (targetId) seen.add(targetId);
      seen.add(targetTitle);

      // Collect artist's popular tracks (from topSongs or search)
      const rawArtistPool = [
        ...(artistDetails?.topSongs || []),
        ...(artistDetails?.allSongs || []),
        ...artistSearch,
      ];

      const cleanArtistHits = [];
      for (const t of rawArtistPool) {
        const cleanT = (t.title || '').toLowerCase().trim();
        if (isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
          seen.add(t.id);
          seen.add(cleanT);
          cleanArtistHits.push(t);
        }
      }

      // Collect peer hitmakers' popular tracks
      const rawPeerTracks = peerResults.flat();
      const cleanPeerHits = [];
      for (const t of rawPeerTracks) {
        const cleanT = (t.title || '').toLowerCase().trim();
        if (isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
          seen.add(t.id);
          seen.add(cleanT);
          cleanPeerHits.push(t);
        }
      }

      // Fallback: If not enough hits found, fetch from trending
      if (cleanArtistHits.length + cleanPeerHits.length < 8) {
        const trending = await this.fetchTrendingTracks();
        for (const t of trending) {
          const cleanT = (t.title || '').toLowerCase().trim();
          if (isCleanPopularTrack(t) && !seen.has(t.id) && !seen.has(cleanT)) {
            seen.add(t.id);
            seen.add(cleanT);
            cleanPeerHits.push(t);
          }
        }
      }

      // Shuffle both pools for genuine randomness among POPULAR HITS
      const shuffledArtist = cleanArtistHits.sort(() => Math.random() - 0.5);
      const shuffledPeersHits = cleanPeerHits.sort(() => Math.random() - 0.5);

      // Interleave: artist's popular songs + famous peer songs
      const finalRadioQueue = [];
      const maxLen = Math.max(shuffledArtist.length, shuffledPeersHits.length);
      for (let i = 0; i < maxLen; i++) {
        if (i < shuffledArtist.length) finalRadioQueue.push(shuffledArtist[i]);
        if (i < shuffledPeersHits.length) finalRadioQueue.push(shuffledPeersHits[i]);
      }

      // Return shuffled final queue of famous songs
      return finalRadioQueue.sort(() => Math.random() - 0.5).slice(0, limit);
    } catch (e) {
      console.warn('getArtistGenreRadio error:', e);
      return [];
    }
  },

  /**
   * Fetch Dynamic Personalized Home Sections based on User Taste Profile
   */
  async fetchPersonalizedHome(tasteProfile) {
    try {
      if (tasteProfile && tasteProfile.hasHistory) {
        const topArtist = tasteProfile.topArtists?.[0];
        const secondaryArtist = tasteProfile.topArtists?.[1];
        const lastTrack = tasteProfile.lastPlayedTrack;

        // Fetch tracks for top artist, secondary artist & smart recommendations in parallel
        const [artistTracks, secondaryArtistTracks, similarTracks, trending] = await Promise.all([
          topArtist ? this.searchTracks(topArtist, 10) : Promise.resolve([]),
          secondaryArtist ? this.searchTracks(secondaryArtist, 8) : Promise.resolve([]),
          lastTrack ? this.getSmartRecommendations(lastTrack) : Promise.resolve([]),
          this.fetchTrendingTracks(),
        ]);

        // Construct dynamic quick cards from user's actual most played, recent and liked tracks
        let rawQuick = [
          ...(tasteProfile.mostPlayedTracks || []),
          ...(tasteProfile.recentTracks || []),
          ...(tasteProfile.likedTracks || []),
        ];
        const seen = new Set();
        const quickCards = [];
        for (const t of rawQuick) {
          if (!seen.has(t.id)) {
            seen.add(t.id);
            quickCards.push(t);
            if (quickCards.length >= 6) break;
          }
        }

        // If fewer than 6, fill with artist tracks or trending
        if (quickCards.length < 6) {
          for (const t of [...artistTracks, ...trending]) {
            if (!seen.has(t.id)) {
              seen.add(t.id);
              quickCards.push(t);
              if (quickCards.length >= 6) break;
            }
          }
        }

        const sections = [
          ...(topArtist ? [{
            id: 'top-artist',
            title: `Karena kamu sering memutar ${topArtist}`,
            subtitle: `Rekomendasi terbaik dan lagu serupa dengan artis favoritmu`,
            badge: 'Berdasarkan Selera Musik',
            tracks: artistTracks.length > 0 ? artistTracks : trending.slice(0, 8),
          }] : []),
          ...(lastTrack ? [{
            id: 'similar-vibe',
            title: `Lagu serupa dengan "${lastTrack.title}"`,
            subtitle: `Dipersonalisasi berdasarkan musik yang baru saja kamu dengar`,
            badge: 'Radio Pintar',
            tracks: similarTracks.length > 0 ? similarTracks : trending.slice(6, 14),
          }] : []),
          ...(secondaryArtist && secondaryArtistTracks.length > 0 ? [{
            id: 'secondary-artist',
            title: `Eksplorasi ${secondaryArtist}`,
            subtitle: `Koleksi musik pilihan dari artis favoritmu yang lain`,
            badge: 'Artis Pilihan',
            tracks: secondaryArtistTracks,
          }] : []),
          {
            id: 'trending-section',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Tangga lagu terhangat dan musik paling banyak didengar',
            badge: 'Trending',
            tracks: trending,
          },
        ];

        return {
          isPersonalized: true,
          topArtist,
          quickCards: quickCards.slice(0, 6),
          sections,
          trending,
        };
      }

      // Default state for brand new user with no history yet
      const trending = await this.fetchTrendingTracks();
      return {
        isPersonalized: false,
        quickCards: trending.slice(0, 6),
        sections: [
          {
            id: 'trending-today',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Musik yang sedang viral dan menduduki puncak tangga lagu',
            badge: 'Trending',
            tracks: trending.slice(0, 10),
          },
          {
            id: 'fresh-finds',
            title: 'Pilihan Musik Segar & Terkini',
            subtitle: 'Eksplorasi ragam genre mulai dari pop, r&b, hingga akustik',
            badge: 'Pilihan Untukmu',
            tracks: trending.slice(6, 16),
          },
        ],
        trending,
      };
    } catch (e) {
      console.warn('Personalized home fetch failed, using fallback:', e);
      const trending = await this.fetchTrendingTracks();
      return {
        isPersonalized: false,
        quickCards: trending.slice(0, 6),
        sections: [
          {
            id: 'fallback-trending',
            title: 'Lagu Terpopuler Saat Ini',
            subtitle: 'Musik terhangat',
            badge: 'Trending',
            tracks: trending,
          },
        ],
        trending,
      };
    }
  },
};
