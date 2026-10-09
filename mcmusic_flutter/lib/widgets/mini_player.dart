import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import 'audio_quality_modal.dart';
import 'fullscreen_player.dart';
import 'optimized_image.dart';

class MiniPlayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final progress = player.duration.inSeconds > 0
        ? (player.position.inSeconds / player.duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => FullscreenPlayer(
            player: player,
            isLiked: isLiked,
            onToggleLike: onToggleLike,
          ),
        );
      },
      // Spotify-style Horizontal Swipe to Skip / Previous
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          // Swiped left -> Skip Next
          HapticFeedback.lightImpact();
          player.next();
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
          // Swiped right -> Undo / Previous
          HapticFeedback.lightImpact();
          player.previous();
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFF222429),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(160),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // Hairline progress indicator at the very bottom edge (Spotify exact match)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: RepaintBoundary(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    height: 2.5,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            // Content row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Album Artwork (Spotify style rounded square)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: OptimizedImage(
                      imageUrl: track.artwork,
                      width: 40,
                      height: 40,
                      memCacheWidth: 80,
                      memCacheHeight: 80,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Track Title & Artist
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Devices Connect Button (Spotify icon)
                  IconButton(
                    icon: const Icon(Icons.devices_rounded, color: Colors.white70, size: 20),
                    tooltip: 'Perangkat',
                    onPressed: () => AudioQualityModal.show(context, player),
                  ),

                  // Saved Checkmark Button (Blue Accent Palette!)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onToggleLike();
                    },
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: isLiked ? AppTheme.primaryAzure : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isLiked ? AppTheme.primaryAzure : Colors.white54,
                          width: 1.8,
                        ),
                      ),
                      child: Icon(
                        isLiked ? Icons.check : Icons.add,
                        color: isLiked ? Colors.black : Colors.white70,
                        size: 15,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Play / Pause Icon Button (Solid white Spotify style)
                  IconButton(
                    icon: Icon(
                      player.isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: 28,
                    ),
                    onPressed: () {
                      HapticFeedback.mediumImpact();
                      player.togglePlayPause();
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
