import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/audio_quality.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import '../utils/artwork_palette.dart';
import 'audio_quality_modal.dart';
import 'fullscreen_player.dart';
import 'optimized_image.dart';

class MiniPlayer extends StatefulWidget {
  final AudioPlayerManager player;
  final bool isLiked;
  final VoidCallback onToggleLike;
  final VoidCallback? onToggleBubble;
  final bool isBubbleActive;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.isLiked,
    required this.onToggleLike,
    this.onToggleBubble,
    this.isBubbleActive = false,
  });

  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  ArtworkColors _palette = ArtworkColors.fallbackDefault;
  String? _lastArtworkUrl;

  void _syncPalette(String url, String title) {
    if (url == _lastArtworkUrl) return;
    _lastArtworkUrl = url;
    _palette = ArtworkPalette.getCachedOrFallback(url, seed: title);
    ArtworkPalette.extract(url, seed: title).then((extracted) {
      if (mounted && _lastArtworkUrl == url) {
        setState(() => _palette = extracted);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    _syncPalette(track.artwork, track.title);

    final progress = widget.player.duration.inSeconds > 0
        ? (widget.player.position.inSeconds / widget.player.duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => FullscreenPlayer(
            player: widget.player,
            isLiked: widget.isLiked,
            onToggleLike: widget.onToggleLike,
          ),
        );
      },
      // Spotify / RiMusic Horizontal Swipe to Skip / Previous
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          HapticFeedback.lightImpact();
          widget.player.next();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.skip_next, color: AppTheme.primaryAzure, size: 20),
                  SizedBox(width: 8),
                  Text('Lagu berikutnya'),
                ],
              ),
              duration: Duration(milliseconds: 900),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else if (velocity > 200) {
          HapticFeedback.lightImpact();
          widget.player.previous();
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.skip_previous, color: AppTheme.primaryAzure, size: 20),
                  SizedBox(width: 8),
                  Text('Lagu sebelumnya'),
                ],
              ),
              duration: Duration(milliseconds: 900),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
        height: 58,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _palette.surfaceTint,
              _palette.primary,
            ],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.7),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Hairline progress track + fill at the bottom edge (Spotify exact match)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              child: Container(
                height: 2.2,
                color: Colors.white.withValues(alpha: 0.16),
                alignment: Alignment.centerLeft,
                child: RepaintBoundary(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(
                      height: 2.2,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Content Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  // Album Artwork with Hero flight animation
                  Hero(
                    tag: 'current_artwork_${track.id}',
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: OptimizedImage(
                          imageUrl: track.artwork,
                          width: 40,
                          height: 40,
                          memCacheWidth: 80,
                          memCacheHeight: 80,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Track Title & Artist
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                track.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ),
                            if (widget.player.audioQuality == AudioQuality.lossless) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
                                  borderRadius: BorderRadius.circular(3.5),
                                ),
                                child: const Text(
                                  'LOSSLESS',
                                  style: TextStyle(color: Colors.black, fontSize: 7.5, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        Row(
                          children: [
                            if (widget.player.isPlaying) ...[
                              const Icon(Icons.graphic_eq, color: AppTheme.primaryAzure, size: 12),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                track.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Devices / Audio Quality pill icon
                  IconButton(
                    icon: const Icon(Icons.speaker_group_outlined, color: Colors.white70, size: 19),
                    tooltip: 'Kualitas & Perangkat',
                    padding: const EdgeInsets.all(6),
                    constraints: const BoxConstraints(),
                    onPressed: () => AudioQualityModal.show(context, widget.player),
                  ),

                  const SizedBox(width: 6),

                  // Saved Checkmark Button (Spotify 2025 style with Electric Azure accent)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      widget.onToggleLike();
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: widget.isLiked ? AppTheme.primaryAzure : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.isLiked ? AppTheme.primaryAzure : Colors.white60,
                          width: 1.8,
                        ),
                      ),
                      child: Icon(
                        widget.isLiked ? Icons.check : Icons.add,
                        color: widget.isLiked ? Colors.black : Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Play / Pause Icon Button
                  IconButton(
                    icon: Icon(
                      widget.player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      widget.player.togglePlayPause();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
