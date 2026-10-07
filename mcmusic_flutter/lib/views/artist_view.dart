import 'package:flutter/material.dart';
import '../models/artist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';
import '../widgets/track_tile.dart';

class ArtistView extends StatefulWidget {
  final Artist artist;
  final AudioPlayerManager player;

  const ArtistView({
    super.key,
    required this.artist,
    required this.player,
  });

  @override
  State<ArtistView> createState() => _ArtistViewState();
}

class _ArtistViewState extends State<ArtistView> {
  final MusicApiService _api = MusicApiService();
  final StorageService _storage = StorageService();

  List<Track> _topSongs = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  final Set<String> _likedIds = {};

  @override
  void initState() {
    super.initState();
    _loadArtist();
  }

  Future<void> _loadArtist() async {
    final data = await _api.getArtistDetails(widget.artist.name);
    final liked = await _storage.getLikedTracks();
    if (mounted) {
      setState(() {
        _topSongs = data['topSongs'] as List<Track>;
        _likedIds.addAll(liked.map((t) => t.id));
        _isLoading = false;
      });
    }
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
    final artist = widget.artist;
    final isPlayingThis = widget.player.isPlaying &&
        (widget.player.currentTrack?.artist.toLowerCase().contains(artist.name.toLowerCase()) ?? false);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      body: CustomScrollView(
        slivers: [
          // Hero Banner SliverAppBar matching media_1791353080300.png
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            backgroundColor: AppTheme.darkBackground,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.black45,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Header Banner Image
                  OptimizedImage(
                    imageUrl: artist.headerBanner,
                    fit: BoxFit.cover,
                    memCacheWidth: 800,
                  ),

                  // Dark Gradients
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black26,
                          Colors.transparent,
                          AppTheme.darkBackground,
                        ],
                      ),
                    ),
                  ),

                  // Artist Name & Badge on bottom
                  Positioned(
                    left: 20,
                    bottom: 20,
                    right: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Verified Badge
                        Row(
                          children: const [
                            Icon(Icons.check_circle, color: AppTheme.primaryAzure, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Diverifikasi oleh Spotify',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Giant Name
                        Text(
                          artist.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Monthly Listeners
                        Text(
                          artist.monthlyListeners,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Action Row (Play Button, Follow, Menu)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  // Big Electric Azure Play Button
                  GestureDetector(
                    onTap: () {
                      if (_topSongs.isNotEmpty) {
                        if (isPlayingThis) {
                          widget.player.togglePlayPause();
                        } else {
                          widget.player.playTrack(_topSongs.first, _topSongs);
                        }
                      }
                    },
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryAzure,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x6600A3FF),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        isPlayingThis ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Follow Button
                  OutlinedButton(
                    onPressed: () {
                      setState(() => _isFollowing = !_isFollowing);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _isFollowing ? AppTheme.primaryAzure : Colors.white38,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    ),
                    child: Text(
                      _isFollowing ? 'Mengikuti' : 'Ikuti',
                      style: TextStyle(
                        color: _isFollowing ? AppTheme.primaryAzure : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Spacer(),

                  IconButton(
                    icon: const Icon(Icons.more_horiz, color: AppTheme.textMuted, size: 26),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),

          // Popular Section Header
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                'Populer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Popular Track List
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppTheme.primaryAzure),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _topSongs[index];
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
                        widget.player.playTrack(track, _topSongs);
                      }
                    },
                    onToggleLike: () => _toggleLike(track),
                  );
                },
                childCount: _topSongs.length,
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
