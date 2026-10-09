import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';
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

  String _selectedFilter = 'All'; // All, Music, Podcasts
  List<Track> _recentRotation = [];
  List<Track> _startListening = [];
  String _startListeningTitle = 'Start listening';
  String _startListeningSubtitle = 'Jump into a session based on your tastes';
  List<Track> _likedTracks = [];
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  final Set<String> _likedIds = {};
  List<Map<String, dynamic>> _popularRadios = [];
  String? _lastRecordedTrackId;

  List<Map<String, dynamic>> _buildDynamicRadios({
    String? topArtist,
    String? lastArtist,
    required List<Track> tracksPool,
  }) {
    final List<Map<String, dynamic>> radios = [];
    final List<Color> colors = [
      const Color(0xFF00A3FF), // Electric Azure
      const Color(0xFF68D391), // Mint
      const Color(0xFFF6AD55), // Coral
      const Color(0xFF9F7AEA), // Violet
      const Color(0xFF4FD1C5), // Teal
    ];

    final artistsToFeature = <String>{};
    if (topArtist != null && topArtist.isNotEmpty) artistsToFeature.add(topArtist);
    if (lastArtist != null && lastArtist.isNotEmpty) artistsToFeature.add(lastArtist);
    artistsToFeature.addAll(['Bernadya', 'Sal Priadi', 'The Weeknd', 'Bruno Mars', 'Coldplay']);

    int colorIdx = 0;
    for (final artist in artistsToFeature.take(5)) {
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
        'artists': 'Radio $artist • Campuran hits terbaik dan lagu serupa',
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
  }

  void _onPlayerStateChanged() {
    final current = widget.player.currentTrack;
    if (current != null && current.id != _lastRecordedTrackId) {
      _lastRecordedTrackId = current.id;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _loadHomeData();
      });
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  Future<void> _loadHomeData() async {
    try {
      final history = await _storage.getHistory();
      final liked = await _storage.getLikedTracks();
      final playlists = await _storage.getPlaylists();
      final topArtist = await _storage.getTopArtist();

      List<Track> recentRotation = [];
      List<Track> startListening = [];
      String startListeningSubtitle = 'Jump into a session based on your tastes';
      String startListeningTitle = 'Start listening';

      if (history.isNotEmpty) {
        // Collect diverse recent rotation with maximum 1 track per artist
        final seenArtists = <String>{};
        final seenIds = <String>{};
        final List<Track> diverseRecent = [];
        for (final t in history) {
          final a = t.artist.trim().toLowerCase();
          if (!seenIds.contains(t.id) && !seenArtists.contains(a)) {
            seenIds.add(t.id);
            seenArtists.add(a);
            diverseRecent.add(t);
            if (diverseRecent.length >= 4) break;
          }
        }
        if (diverseRecent.length < 4) {
          for (final t in history) {
            if (!seenIds.contains(t.id)) {
              seenIds.add(t.id);
              diverseRecent.add(t);
              if (diverseRecent.length >= 4) break;
            }
          }
        }
        recentRotation = diverseRecent;
        final lastTrack = history.first;
        final lastArtist = lastTrack.artist;

        // Fetch smart recommendations dynamically based on actual played track
        final recommended = await _api.getSmartRecommendations(lastTrack);
        startListening = recommended.take(4).toList();

        if (topArtist != null && topArtist.isNotEmpty) {
          startListeningSubtitle = 'Karena kamu sering memutar $topArtist & ${lastTrack.title}';
          startListeningTitle = 'Rekomendasi Untukmu';
        } else {
          startListeningSubtitle = 'Berdasarkan "${lastTrack.title}"';
          startListeningTitle = 'Radio & Rekomendasi';
        }

        final pool = [...history, ...startListening, ...liked];
        _popularRadios = _buildDynamicRadios(
          topArtist: topArtist,
          lastArtist: lastArtist,
          tracksPool: pool,
        );
      } else {
        // Brand new user: fetch live trending hits
        final trending = await _api.getTrendingTracks();
        recentRotation = trending.take(3).toList();
        startListening = trending.skip(3).take(4).toList();
        _popularRadios = _buildDynamicRadios(
          topArtist: null,
          lastArtist: null,
          tracksPool: trending,
        );
      }

      if (mounted) {
        setState(() {
          _recentRotation = recentRotation;
          _startListening = startListening;
          _startListeningTitle = startListeningTitle;
          _startListeningSubtitle = startListeningSubtitle;
          _likedTracks = liked;
          _playlists = playlists;
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

  void _showTrackMenu(Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              ListTile(
                leading: OptimizedImage(imageUrl: track.artwork, width: 44, height: 44, borderRadius: BorderRadius.circular(6)),
                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                trailing: IconButton(
                  icon: Icon(
                    _likedIds.contains(track.id) ? Icons.check_circle : Icons.favorite_border,
                    color: _likedIds.contains(track.id) ? AppTheme.primaryAzure : Colors.white70,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _toggleLike(track);
                  },
                ),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.playlist_play, color: AppTheme.primaryAzure),
                title: const Text('Putar Selanjutnya', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.player.addToNext(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ditambahkan ke putar selanjutnya!'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music, color: AppTheme.primaryAzure),
                title: const Text('Tambahkan ke Antrean', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.player.addToQueue(track);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lagu masuk ke antrean!'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openRadioStation(String query) async {
    final tracks = await _api.searchTracks(query);
    if (tracks.isNotEmpty) {
      widget.player.playTrack(tracks.first, tracks);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryAzure),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // Top Bar: Filter Chips ("All", "Music", "Podcasts") - NO PROFILE ICON!
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    _buildFilterPill('All', 'Semua'),
                    const SizedBox(width: 8),
                    _buildFilterPill('Music', 'Musik'),
                    const SizedBox(width: 8),
                    _buildFilterPill('Podcasts', 'Podcast'),
                  ],
                ),
              ),
            ),

            // Section 1: "Your recent rotation" (Exact Spotify match from screenshot)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your recent rotation',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._recentRotation.map((t) => _buildRecentTrackTile(t)),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section 2: "Popular radio" (Exact Spotify radio cards from screenshot)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Popular radio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 220,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _popularRadios.length,
                      itemBuilder: (context, idx) {
                        final r = _popularRadios[idx];
                        return _buildRadioCard(r);
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section 3: "Recents" (2-column square cards from screenshot 2)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          'Recents',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Show all',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // Left Recent Card: Top Playlist or First Playlist
                        Expanded(
                          child: _playlists.isNotEmpty
                              ? _buildRecentPlaylistCard(_playlists.first)
                              : _buildRecentFallbackCard(),
                        ),
                        const SizedBox(width: 12),
                        // Right Recent Card: Liked Songs Card with purple gradient
                        Expanded(
                          child: _buildLikedSongsCard(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section 4: "Start listening" ("Jump into a session based on your tastes")
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
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _startListeningTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._startListening.map((t) => _buildRecentTrackTile(t)),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section 5: Featured Banner Card ("It's Midnight Darling" from screenshot 3)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildFeaturedBanner(),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Section 6: "It's New Music Friday!"
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      "It's New Music Friday!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 210,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        _buildNewFridayCard(
                          title: 'New Music Friday Indonesia',
                          subtitle: 'Bernadya, Mahalini, Juicy Luicy, Nadin...',
                          imageUrl: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=400',
                          badge: 'NEW MUSIC FRIDAY',
                        ),
                        const SizedBox(width: 14),
                        _buildNewFridayCard(
                          title: 'Release Radar',
                          subtitle: 'Lagu baru rilisan artis favorit kamu minggu ini',
                          imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
                          badge: 'RELEASE RADAR',
                        ),
                        const SizedBox(width: 14),
                        _buildNewFridayCard(
                          title: 'Indo Best Hits',
                          subtitle: 'Pamungkas, Tulus, Dewa 19, Sheila On 7',
                          imageUrl: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=400',
                          badge: 'BEST HITS',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Extra clearance for MiniPlayer and BottomNavigationBar
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  // Filter Pill ("All", "Music", "Podcasts")
  Widget _buildFilterPill(String key, String label) {
    final isSelected = _selectedFilter == key;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryAzure : const Color(0xFF242426),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // Track Tile matching "Your recent rotation" & "Start listening" in screenshots
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
            // Artwork (Spotify style rounded square ~48x48)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: OptimizedImage(
                imageUrl: t.artwork,
                width: 48,
                height: 48,
                memCacheWidth: 100,
                memCacheHeight: 100,
              ),
            ),
            const SizedBox(width: 12),

            // Track details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (t.isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          margin: const EdgeInsets.only(right: 4),
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
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Saved Checkmark Button (Blue Accent Palette!)
            IconButton(
              icon: Icon(
                isLiked ? Icons.check_circle : Icons.check_circle_outline,
                color: isLiked ? AppTheme.primaryAzure : Colors.white24,
                size: 22,
              ),
              onPressed: () => _toggleLike(t),
            ),

            // 3-dots Menu Button
            IconButton(
              icon: const Icon(Icons.more_horiz, color: Colors.white60, size: 22),
              onPressed: () => _showTrackMenu(t),
            ),
          ],
        ),
      ),
    );
  }

  // Radio Card matching "Popular radio" in screenshots
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
        width: 145,
        margin: const EdgeInsets.only(right: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top styled radio art box
            Container(
              height: 145,
              width: 145,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Logo tag top left
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(Icons.graphic_eq, color: Colors.black87, size: 16),
                  ),
                  // "RADIO" tag top right
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

                  // Center circular artist portraits
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
                              width: 50,
                              height: 50,
                              memCacheWidth: 100,
                              memCacheHeight: 100,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  // Bottom Title inside card
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Subtitle artist roster
            Text(
              artists,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Liked Songs Card matching screenshot 2
  Widget _buildLikedSongsCard() {
    return GestureDetector(
      onTap: () {
        if (_likedTracks.isNotEmpty) {
          widget.player.playTrack(_likedTracks.first, _likedTracks);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(Icons.favorite, color: Colors.white, size: 48),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Liked Songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.primaryAzure, size: 12),
              const SizedBox(width: 4),
              Text(
                '${_likedTracks.length} lagu disukai',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Recent Playlist Card matching screenshot 2
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
              height: 140,
              width: double.infinity,
              memCacheWidth: 280,
              memCacheHeight: 280,
            ),
          ),
          const SizedBox(height: 8),
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

  Widget _buildRecentFallbackCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 140,
          decoration: BoxDecoration(
            color: const Color(0xFF242426),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.music_note, color: Colors.white54, size: 40),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Top Hits Indonesia',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        const SizedBox(height: 2),
        const Text(
          'Playlist • McMusic',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
      ],
    );
  }

  // Featured Banner matching screenshot 3 ("It's Midnight Darling")
  Widget _buildFeaturedBanner() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF26262B),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OptimizedImage(
                  imageUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=300',
                  width: 90,
                  height: 90,
                  memCacheWidth: 180,
                  memCacheHeight: 180,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'RILISAN PILIHAN',
                      style: TextStyle(
                        color: AppTheme.primaryAzure,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      "IT'S MIDNIGHT DARLING",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Album debut oleh The Midnight Darlings',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'The Midnight Darlings',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                ),
                onPressed: () {
                  if (_recentRotation.isNotEmpty) {
                    widget.player.playTrack(_recentRotation.first, _recentRotation);
                  }
                },
                child: const Text('Dengarkan sekarang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // New Music Friday Carousel card matching screenshot 3
  Widget _buildNewFridayCard({
    required String title,
    required String subtitle,
    required String imageUrl,
    required String badge,
  }) {
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: OptimizedImage(
                  imageUrl: imageUrl,
                  width: 140,
                  height: 140,
                  memCacheWidth: 280,
                  memCacheHeight: 280,
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(color: AppTheme.primaryAzure, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
