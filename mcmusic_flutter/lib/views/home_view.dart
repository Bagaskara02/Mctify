import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../utils/artwork_palette.dart';
import '../widgets/optimized_image.dart';
import '../widgets/shimmer_skeleton.dart';
import '../widgets/track_action_sheet.dart';
import 'playlist_detail_view.dart';

class HomeView extends StatefulWidget {
  final AudioPlayerManager player;

  const HomeView({
    super.key,
    required this.player,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final MusicApiService _api = MusicApiService();
  final StorageService _storage = StorageService();

  String _selectedFilter = 'Semua'; // Semua, Musik, Mix, Podcast
  List<Track> _quickCards = [];
  List<Track> _recentRotation = [];
  List<Track> _startListening = [];
  List<Track> _trendingHits = [];
  String _startListeningTitle = 'Diputar Baru-Baru Ini & Rekomendasi';
  String _startListeningSubtitle = 'Berdasarkan selera musikmu';
  List<Track> _likedTracks = [];
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  final Set<String> _likedIds = {};
  List<Map<String, dynamic>> _popularRadios = [];
  List<Map<String, dynamic>> _dailyMixes = [];
  String? _lastRecordedTrackId;
  ArtworkColors _ambientColors = ArtworkColors.fallbackDefault;
  String? _lastAmbientUrl;

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 19) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  void _syncAmbientHeader(String? url, String seed) {
    if (url == null || url.isEmpty || url == _lastAmbientUrl) return;
    _lastAmbientUrl = url;
    ArtworkPalette.extract(url, seed: seed).then((colors) {
      if (mounted && _lastAmbientUrl == url) {
        setState(() => _ambientColors = colors);
      }
    });
  }

  List<Map<String, dynamic>> _buildDailyMixes(List<Track> pool) {
    final mixConfigs = [
      {
        'title': 'Daily Mix 01',
        'badge': 'MIX 1',
        'color': const Color(0xFF3B82F6),
        'query': 'Pop Hits Trending The Weeknd Bruno Mars Coldplay',
        'keywords': ['weeknd', 'coldplay', 'bruno', 'taylor', 'dua lipa', 'billie', 'ariana', 'pop', 'sabrina', 'charlie'],
      },
      {
        'title': 'Daily Mix 02',
        'badge': 'MIX 2',
        'color': const Color(0xFF10B981),
        'query': 'Lagu Indonesia Hits Bernadya Tulus Hindia Mahalini',
        'keywords': ['tulus', 'bernadya', 'mahalini', 'hindia', 'pamungkas', 'feby', 'tiara', 'lyodra', 'sal priadi', 'for revenge', 'sheila', 'dewa'],
      },
      {
        'title': 'Release Radar',
        'badge': 'NEW',
        'color': const Color(0xFFA855F7),
        'query': 'New Music Release Hits 2025',
        'keywords': ['2025', '2026', 'new', 'single', 'lady gaga', 'rosé', 'kendrick', 'sza', 'keshi', 'newjeans'],
      },
      {
        'title': 'Discover Weekly',
        'badge': 'DISCOVER',
        'color': const Color(0xFFF59E0B),
        'query': 'Rex Orange County NIKI Daniel Caesar Joji Chill',
        'keywords': ['niki', 'joji', 'daniel caesar', 'rex orange', 'frank ocean', 'lany', 'lauv', 'clairo', 'boy pablo', 'chill'],
      },
    ];

    final usedGlobalIds = <String>{};
    final mixes = <Map<String, dynamic>>[];

    for (int i = 0; i < mixConfigs.length; i++) {
      final cfg = mixConfigs[i];
      final keywords = (cfg['keywords'] as List<String>);
      final matched = <Track>[];

      // 1. Prioritize tracks matching the mix's vibe/keywords without cross-mix duplicates
      for (final t in pool) {
        if (usedGlobalIds.contains(t.id)) continue;
        final hay = '${t.title} ${t.artist} ${t.album}'.toLowerCase();
        if (keywords.any((kw) => hay.contains(kw))) {
          matched.add(t);
          usedGlobalIds.add(t.id);
          if (matched.length >= 14) break;
        }
      }

      // 2. Fill remaining slots with distinct offset tracks from pool so every card is rich
      if (matched.length < 10 && pool.isNotEmpty) {
        final offset = (i * 4) % pool.length;
        final rotated = [...pool.skip(offset), ...pool.take(offset)];
        for (final t in rotated) {
          if (matched.any((m) => m.id == t.id)) continue;
          if (usedGlobalIds.contains(t.id) && matched.length >= 6) continue;
          matched.add(t);
          usedGlobalIds.add(t.id);
          if (matched.length >= 12) break;
        }
      }

      final cover = matched.isNotEmpty ? matched.first.artwork : MusicApiService.defaultArtwork;
      final artistsLabel = matched.isNotEmpty
          ? matched.map((t) => t.artist.split(',').first.trim()).toSet().take(3).join(', ')
          : 'Campuran playlist kurasi untukmu';

      mixes.add({
        'title': cfg['title'],
        'badge': cfg['badge'],
        'color': cfg['color'],
        'cover': cover,
        'subtitle': '$artistsLabel, dan lainnya',
        'tracks': matched,
        'query': cfg['query'],
      });
    }
    return mixes;
  }

  List<Map<String, dynamic>> _buildDynamicRadios({
    String? topArtist,
    String? lastArtist,
    required List<Track> tracksPool,
  }) {
    final List<Map<String, dynamic>> radios = [];
    final List<Color> colors = [
      const Color(0xFF3B82F6), // Electric Azure
      const Color(0xFF68D391), // Mint
      const Color(0xFFF6AD55), // Coral
      const Color(0xFF9F7AEA), // Violet
      const Color(0xFF4FD1C5), // Teal
    ];

    final artistsToFeature = <String>{};
    if (topArtist != null && topArtist.isNotEmpty) artistsToFeature.add(topArtist);
    if (lastArtist != null && lastArtist.isNotEmpty) artistsToFeature.add(lastArtist);
    artistsToFeature.addAll(['The Weeknd', 'Tulus', 'Coldplay', 'NIKI', 'Bernadya', 'Bruno Mars']);

    int colorIdx = 0;
    for (final artist in artistsToFeature.take(6)) {
      final matching = tracksPool.where((t) => t.artist.toLowerCase().contains(artist.toLowerCase())).toList();
      final images = <String>[];
      if (matching.isNotEmpty) {
        images.addAll(matching.map((t) => t.artwork).take(2));
      }
      if (images.isEmpty) {
        images.add(MusicApiService.defaultArtwork);
      }

      radios.add({
        'title': artist,
        'bgColor': colors[colorIdx % colors.length],
        'artists': 'Dengan hits $artist & artis serupa',
        'images': images,
        'search': artist,
      });
      colorIdx++;
    }

    return radios;
  }

  @override
  void initState() {
    super.initState();
    _loadHomeData();
    widget.player.addListener(_onPlayerStateChanged);
    StorageService.playlistRevision.addListener(_loadHomeData);
  }

  void _onPlayerStateChanged() {
    final current = widget.player.currentTrack;
    if (current != null && current.id != _lastRecordedTrackId) {
      _lastRecordedTrackId = current.id;
      _syncAmbientHeader(current.artwork, current.title);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _loadHomeData();
      });
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerStateChanged);
    StorageService.playlistRevision.removeListener(_loadHomeData);
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    try {
      final history = await _storage.getHistory();
      final liked = await _storage.getLikedTracks();
      final playlists = await _storage.getPlaylists();
      final topArtist = await _storage.getTopArtist();

      final trending = await _api.getTrendingTracks();

      // Gather candidate tracks for 7 Quick Cards (+ 1 Liked Songs fixed slot #1 = 8 tiles!)
      final candidateTracks = <Track>[...history, ...liked];
      for (final pl in playlists) {
        candidateTracks.addAll(pl.tracks);
      }
      candidateTracks.addAll(trending);

      final seenKeys = <String>{};
      final List<Track> quickCards = [];
      for (final t in candidateTracks) {
        final fullKey = '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
        if (!seenKeys.contains(fullKey)) {
          seenKeys.add(fullKey);
          quickCards.add(t);
          if (quickCards.length >= 7) break;
        }
      }

      List<Track> recentRotation = [];
      List<Track> startListening = [];
      String startListeningSubtitle = 'Dipilih sesuai riwayat putarmu';
      String startListeningTitle = 'Putar Lagi & Rekomendasi';

      if (history.isNotEmpty) {
        final seenArtists = <String>{};
        final seenIds = <String>{};
        final List<Track> diverseRecent = [];
        for (final t in history) {
          final a = t.artist.trim().toLowerCase();
          if (!seenIds.contains(t.id) && !seenArtists.contains(a)) {
            seenIds.add(t.id);
            seenArtists.add(a);
            diverseRecent.add(t);
            if (diverseRecent.length >= 6) break;
          }
        }
        recentRotation = diverseRecent.isNotEmpty ? diverseRecent : history.take(6).toList();
        final lastTrack = history.first;

        final recommended = await _api.getSmartRecommendations(lastTrack);
        startListening = recommended.take(6).toList();

        if (topArtist != null && topArtist.isNotEmpty) {
          startListeningSubtitle = 'Karena kamu sering mendengarkan $topArtist';
          startListeningTitle = 'Rekomendasi Untukmu';
        } else {
          startListeningSubtitle = 'Mirip dengan "${lastTrack.title}"';
          startListeningTitle = 'Radio & Lagu Serupa';
        }
      } else {
        recentRotation = trending.take(6).toList();
        startListening = trending.skip(3).take(6).toList();
      }

      final pool = [...history, ...startListening, ...liked, ...trending];
      final radios = _buildDynamicRadios(
        topArtist: topArtist,
        lastArtist: history.isNotEmpty ? history.first.artist : null,
        tracksPool: pool,
      );
      final mixes = _buildDailyMixes(pool);

      final heroTrack = widget.player.currentTrack ?? (quickCards.isNotEmpty ? quickCards.first : null);
      if (heroTrack != null) {
        _syncAmbientHeader(heroTrack.artwork, heroTrack.title);
      }

      if (mounted) {
        setState(() {
          _quickCards = quickCards;
          _recentRotation = recentRotation;
          _startListening = startListening;
          _trendingHits = trending;
          _startListeningTitle = startListeningTitle;
          _startListeningSubtitle = startListeningSubtitle;
          _likedTracks = liked;
          _playlists = playlists;
          _popularRadios = radios;
          _dailyMixes = mixes;
          _likedIds.clear();
          _likedIds.addAll(liked.map((t) => t.id));
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading dynamic home data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleLike(Track track) async {
    HapticFeedback.lightImpact();
    await _storage.toggleLikeTrack(track);
    setState(() {
      if (_likedIds.contains(track.id)) {
        _likedIds.remove(track.id);
      } else {
        _likedIds.add(track.id);
      }
    });
  }

  void _openLikedPlaylist() {
    HapticFeedback.lightImpact();
    final likedPlaylist = Playlist(
      id: 'pl-liked-shortcut',
      name: 'Lagu yang Disukai',
      description: 'Daftar putar lagu favoritmu tersimpan lokal di McTify',
      cover: _likedTracks.isNotEmpty ? _likedTracks.first.artwork : MusicApiService.defaultArtwork,
      tracks: _likedTracks,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          playlist: likedPlaylist,
          player: widget.player,
          onPlaylistChanged: _loadHomeData,
        ),
      ),
    );
  }

  Future<List<Track>> _resolveMixTracks(Map<String, dynamic> mix) async {
    final existing = List<Track>.from((mix['tracks'] as List<Track>?) ?? []);
    if (existing.length >= 12) return existing;
    try {
      final fetched = await _api.searchTracks(mix['query'] as String);
      final seenIds = existing.map((t) => t.id).toSet();
      for (final t in fetched) {
        if (seenIds.add(t.id)) {
          existing.add(t);
          if (existing.length >= 16) break;
        }
      }
    } catch (_) {}
    return existing;
  }

  Future<void> _openDailyMix(Map<String, dynamic> mix) async {
    HapticFeedback.lightImpact();
    final tracks = await _resolveMixTracks(mix);
    if (!mounted) return;
    final pl = Playlist(
      id: 'mix-${mix['title'].hashCode}',
      name: mix['title'] as String,
      description: 'Dibuat khusus untukmu • ${mix['subtitle']}',
      cover: tracks.isNotEmpty ? tracks.first.artwork : (mix['cover'] as String),
      tracks: tracks,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailView(
          playlist: pl,
          player: widget.player,
          onPlaylistChanged: _loadHomeData,
          isVirtualMix: true,
        ),
      ),
    );
  }

  Future<void> _playMixDirectly(Map<String, dynamic> mix) async {
    HapticFeedback.mediumImpact();
    final tracks = await _resolveMixTracks(mix);
    if (tracks.isNotEmpty) {
      await widget.player.playTrack(tracks.first, tracks);
    }
  }

  void _openRadioStation(String query) async {
    final tracks = await _api.searchTracks(query);
    if (tracks.isNotEmpty) {
      widget.player.playTrack(tracks.first, tracks);
    }
  }

  void _showTrackMenu(Track track) {
    showTrackActionSheet(
      context: context,
      track: track,
      player: widget.player,
      onPlaylistModified: _loadHomeData,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(child: HomeSkeletonLoader()),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          // Top Spotify Dynamic Ambient Header Gradient (reacts to active artwork)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 290,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomCenter,
                  colors: [
                    _ambientColors.primary.withValues(alpha: 0.85),
                    _ambientColors.secondary.withValues(alpha: 0.45),
                    const Color(0xFF121212),
                  ],
                  stops: const [0.0, 0.55, 1.0],
                ),
              ),
            ),
          ),

          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: AppTheme.primaryAzure,
              backgroundColor: const Color(0xFF1E1E24),
              onRefresh: _loadHomeData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                slivers: [
                  // Spotify Header Bar: Brand Emblem Avatar + Filter Pills
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: _openLikedPlaylist,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: const BoxDecoration(
                                color: AppTheme.primaryAzure,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text(
                                  'M',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildFilterPill('Semua', 'Semua'),
                                  const SizedBox(width: 8),
                                  _buildFilterPill('Musik', 'Musik'),
                                  const SizedBox(width: 8),
                                  _buildFilterPill('Mix', 'Mix & Radio'),
                                  const SizedBox(width: 8),
                                  _buildFilterPill('Podcast', 'Trending'),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 8-Card 2-Column Spotify Shortcuts Grid (Tile 1 = Lagu yang Disukai)
                  if (_selectedFilter == 'Semua' || _selectedFilter == 'Musik')
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _greeting,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 23,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                InkWell(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _loadHomeData();
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: const Padding(
                                    padding: EdgeInsets.all(6),
                                    child: Icon(Icons.refresh_rounded, color: Colors.white70, size: 21),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 3.05,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                              itemCount: (_quickCards.length + 1).clamp(1, 8),
                              itemBuilder: (context, idx) {
                                if (idx == 0) {
                                  return _buildLikedShortcutTile();
                                }
                                return _buildQuickCard(_quickCards[idx - 1]);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 24)),

                  // Section 2: "Dibuat Untuk Kamu" (Daily Mixes & Release Radar)
                  if (_selectedFilter == 'Semua' || _selectedFilter == 'Mix' || _selectedFilter == 'Musik')
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Dibuat Untuk Kamu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 205,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _dailyMixes.length,
                              itemBuilder: (context, idx) => _buildDailyMixCard(_dailyMixes[idx]),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 20)),

                  // Section 3: "Baru Saja Diputar" (Jump Back In compact square cards)
                  if ((_selectedFilter == 'Semua' || _selectedFilter == 'Musik') && _recentRotation.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Lompat Kembali',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 168,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _recentRotation.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 12),
                              itemBuilder: (context, idx) {
                                final track = _recentRotation[idx];
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    widget.player.playTrack(track, _recentRotation);
                                  },
                                  child: SizedBox(
                                    width: 120,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: OptimizedImage(
                                            imageUrl: track.artwork,
                                            width: 120,
                                            height: 120,
                                            memCacheWidth: 240,
                                            memCacheHeight: 240,
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          track.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          track.artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 22)),

                  // Section 4: "Radio Campuran Artis"
                  if (_selectedFilter == 'Semua' || _selectedFilter == 'Mix')
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Radio Artis Populer',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 205,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _popularRadios.length,
                              itemBuilder: (context, idx) => _buildRadioCard(_popularRadios[idx]),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SliverToBoxAdapter(child: SizedBox(height: 18)),

                  // Section 5: "Pilihan Trending & Rekomendasi"
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _startListeningSubtitle,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedFilter == 'Podcast' ? 'Trending Saat Ini' : _startListeningTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...((_selectedFilter == 'Podcast' && _trendingHits.isNotEmpty
                                  ? _trendingHits.take(8)
                                  : _startListening)
                              .map(_buildRecentTrackTile)),
                        ],
                      ),
                    ),
                  ),

                  // User Playlists shelf if exists
                  if (_playlists.isNotEmpty) ...[
                    const SliverToBoxAdapter(child: SizedBox(height: 24)),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              'Playlist Kamu',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 192,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _playlists.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 12),
                              itemBuilder: (context, idx) {
                                final pl = _playlists[idx];
                                return SizedBox(
                                  width: 136,
                                  child: _buildRecentPlaylistCard(pl),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Extra bottom clearance for translucent MiniPlayer + Bottom Dock
                  const SliverToBoxAdapter(child: SizedBox(height: 160)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Slot #1 Signature Spotify Purple-Blue Liked Songs Shortcut
  Widget _buildLikedShortcutTile() {
    return InkWell(
      onTap: _openLikedPlaylist,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: const Color(0xFF23252C).withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                ),
              ),
              child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Lagu Disukai',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickCard(Track t) {
    final isCurrent = widget.player.currentTrack?.id == t.id;
    final isPlaying = isCurrent && widget.player.isPlaying;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isCurrent) {
          widget.player.togglePlayPause();
        } else {
          widget.player.playTrack(t, _quickCards);
        }
      },
      borderRadius: BorderRadius.circular(5),
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          color: isCurrent
              ? AppTheme.primaryAzure.withValues(alpha: 0.22)
              : const Color(0xFF23252C).withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(5),
          border: isCurrent
              ? Border.all(color: AppTheme.primaryAzure.withValues(alpha: 0.45), width: 1)
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            OptimizedImage(
              imageUrl: t.artwork,
              width: 54,
              height: 54,
              memCacheWidth: 110,
              memCacheHeight: 110,
              borderRadius: BorderRadius.zero,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
            if (isCurrent)
              Padding(
                padding: const EdgeInsets.only(right: 8, left: 4),
                child: Icon(
                  isPlaying ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                  color: AppTheme.primaryAzure,
                  size: 16,
                ),
              )
            else
              const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill(String key, String label) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = key);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAzure : const Color(0xFF27272D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildDailyMixCard(Map<String, dynamic> mix) {
    final accent = mix['color'] as Color;
    final title = mix['title'] as String;
    final badge = mix['badge'] as String;
    final cover = mix['cover'] as String;
    final subtitle = mix['subtitle'] as String;

    return GestureDetector(
      onTap: () => _openDailyMix(mix),
      child: Container(
        width: 146,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 146,
                height: 146,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    OptimizedImage(
                      imageUrl: cover,
                      width: 146,
                      height: 146,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                    ),
                    // Subtle bottom vignette + Spotify Daily Mix corner badge
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.72)],
                            stops: const [0.45, 1.0],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                        ),
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    // Subtle Play trigger: tapping Play starts playback; tapping card opens PlaylistView
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: GestureDetector(
                        onTap: () => _playMixDirectly(mix),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              'Playlist • $subtitle',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentTrackTile(Track t) {
    final isLiked = _likedIds.contains(t.id);
    final isCurrent = widget.player.currentTrack?.id == t.id;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isCurrent) {
          widget.player.togglePlayPause();
        } else {
          widget.player.playTrackFromSearch(t);
        }
      },
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: OptimizedImage(
                imageUrl: t.artwork,
                width: 48,
                height: 48,
                memCacheWidth: 100,
                memCacheHeight: 100,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isCurrent) ...[
                        const Icon(Icons.graphic_eq_rounded, color: AppTheme.primaryAzure, size: 15),
                        const SizedBox(width: 5),
                      ],
                      Expanded(
                        child: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (t.isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text('E', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      Expanded(
                        child: Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isLiked ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                color: isLiked ? AppTheme.primaryAzure : Colors.white38,
                size: 22,
              ),
              onPressed: () => _toggleLike(t),
            ),
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 21),
              onPressed: () => _showTrackMenu(t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRadioCard(Map<String, dynamic> r) {
    final bgColor = r['bgColor'] as Color;
    final title = r['title'] as String;
    final artists = r['artists'] as String;
    final images = r['images'] as List<String>;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _openRadioStation(r['search'] ?? title);
      },
      child: Container(
        width: 142,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 142,
              width: 142,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [bgColor, bgColor.withValues(alpha: 0.72)],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.graphic_eq_rounded, color: Colors.black87, size: 16),
                  ),
                  const Positioned(
                    top: 8,
                    right: 8,
                    child: Text(
                      'RADIO',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: images.take(2).map((img) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipOval(
                            child: OptimizedImage(
                              imageUrl: img,
                              width: 48,
                              height: 48,
                              memCacheWidth: 100,
                              memCacheHeight: 100,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 10,
                    right: 10,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              artists,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPlaylistCard(Playlist pl) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PlaylistDetailView(
              playlist: pl,
              player: widget.player,
              onPlaylistChanged: _loadHomeData,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: OptimizedImage(
              imageUrl: pl.cover,
              height: 136,
              width: 136,
              memCacheWidth: 280,
              memCacheHeight: 280,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            pl.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Playlist • ${pl.tracks.length} lagu',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
