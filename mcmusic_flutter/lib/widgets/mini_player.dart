import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
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
      // Spotify-style Swipe to Skip / Previous
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -200) {
          // Swiped left -> Skip Next
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
        height: 62,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(140),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Bottom hairline progress indicator
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
                      color: AppTheme.primaryAzure,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Main Content Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  // Artwork
                  OptimizedImage(
                    imageUrl: track.artwork,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  const SizedBox(width: 12),

                  // Title & Artist + TWS Info
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
                        Row(
                          children: [
                            const Icon(Icons.headphones, color: AppTheme.primaryAzure, size: 12),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${track.artist} • Geser skip / TWS 2x tap',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Bubble Play toggle button
                  if (onToggleBubble != null)
                    IconButton(
                      icon: Icon(
                        isBubbleActive ? Icons.bubble_chart : Icons.bubble_chart_outlined,
                        color: isBubbleActive ? AppTheme.primaryAzure : AppTheme.textMuted,
                        size: 22,
                      ),
                      tooltip: 'Bubble Play',
                      onPressed: onToggleBubble,
                    ),

                  // Like button
                  IconButton(
                    icon: Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? AppTheme.primaryAzure : AppTheme.textMuted,
                      size: 22,
                    ),
                    onPressed: onToggleLike,
                  ),

                  // Play / Pause button
                  IconButton(
                    icon: Icon(
                      player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                      color: Colors.white,
                      size: 36,
                    ),
                    onPressed: () => player.togglePlayPause(),
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
