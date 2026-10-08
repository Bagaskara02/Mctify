import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';
import '../widgets/track_tile.dart';

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

  List<Track> _quickCards = [];
  List<Track> _popularTracks = [];
  List<Track> _artistTracks = [];
  String? _topArtist;
  bool _isLoading = true;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _loadHomeData();
  }

  Future<void> _loadHomeData() async {
    final trending = await _api.getTrendingTracks();
    final liked = await _storage.getLikedTracks();
    final topArt = await _storage.getTopArtist();

    List<Track> artTracks = [];
    if (topArt != null) {
      artTracks = await _api.searchTracks(topArt);
    } else {
      artTracks = MusicApiService.officialTopTracks;
    }

    if (mounted) {
      setState(() {
        _quickCards = trending.take(6).toList();
        _popularTracks = trending;
        _artistTracks = artTracks;
        _topArtist = topArt ?? 'HONNE';
        _likedIds.addAll(liked.map((t) => t.id));
        _isLoading = false;
      });
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Selamat Pagi';
    if (hour < 18) return 'Selamat Siang';
    return 'Selamat Malam';
  }

  void _toggleLike(Track track) async {
    await _storage.toggleLikeTrack(track);
    setState(() {
      if (_likedIds.contains(track.id)) {
        _likedIds.remove(track.id);
      } else {
        _likedIds.add(track.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.darkBackground,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryAzure),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: CustomScrollView(
        slivers: [
          // Greeting & Top Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getGreeting(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      Icon(Icons.auto_awesome, color: AppTheme.primaryAzure, size: 14),
                      SizedBox(width: 6),
                      Text(
                        'Dipersonalisasi berdasarkan lagu yang sering kamu putar',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 6 Quick Cards Grid
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 3.2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _quickCards[index];
                  final isCurrent = widget.player.currentTrack?.id == track.id;

                  return InkWell(
                    onTap: () {
                      if (isCurrent) {
                        widget.player.togglePlayPause();
                      } else {
                        widget.player.playTrack(track, _quickCards);
                      }
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(20),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Row(
                        children: [
                          OptimizedImage(
                            imageUrl: track.artwork,
                            width: 54,
                            height: 54,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (isCurrent && widget.player.isPlaying)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.equalizer, color: AppTheme.primaryAzure, size: 18),
                            ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: _quickCards.length,
              ),
            ),
          ),

          // Section 1: "Karena kamu sering memutar [Top Artist / HONNE]"
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Karena kamu sering memutar $_topArtist',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Koleksi rilisan terbaik dan lagu serupa',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAzure.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.primaryAzure.withAlpha(80)),
                    ),
                    child: const Text(
                      'FAVORIT',
                      style: TextStyle(
                        color: AppTheme.primaryAzure,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Horizontal cards for artist section
          SliverToBoxAdapter(
            child: SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _artistTracks.length,
                itemBuilder: (context, index) {
                  final track = _artistTracks[index];
                  final isCurrent = widget.player.currentTrack?.id == track.id;

                  return Container(
                    width: 140,
                    margin: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () {
                        if (isCurrent) {
                          widget.player.togglePlayPause();
                        } else {
                          widget.player.playTrack(track, _artistTracks);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Stack(
                                children: [
                                  OptimizedImage(
                                    imageUrl: track.artwork,
                                    width: 140,
                                    height: 140,
                                  ),
                                  if (isCurrent)
                                    Container(
                                      color: Colors.black45,
                                      child: Center(
                                        child: Icon(
                                          widget.player.isPlaying ? Icons.pause : Icons.play_arrow,
                                          color: AppTheme.primaryAzure,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Section 2: Popular Hits / Trending
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Text(
                'Lagu Terpopuler Saat Ini',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final track = _popularTracks[index];
                final isCurrent = widget.player.currentTrack?.id == track.id;

                return TrackTile(
                  track: track,
                  index: index,
                  isCurrent: isCurrent,
                  isPlaying: widget.player.isPlaying,
                  isLiked: _likedIds.contains(track.id),
                  onPlay: () {
                    if (isCurrent) {
                      widget.player.togglePlayPause();
                    } else {
                      widget.player.playTrack(track, _popularTracks);
                    }
                  },
                  onToggleLike: () => _toggleLike(track),
                );
              },
              childCount: _popularTracks.length,
            ),
          ),

          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }
}
