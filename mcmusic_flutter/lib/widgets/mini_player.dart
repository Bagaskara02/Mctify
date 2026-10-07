import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import 'fullscreen_player.dart';
import 'optimized_image.dart';

class MiniPlayer extends StatelessWidget {
  final AudioPlayerManager player;
  final bool isLiked;
  final VoidCallback onToggleLike;

  const MiniPlayer({
    super.key,
    required this.player,
    required this.isLiked,
    required this.onToggleLike,
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF242424),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Bottom hairline progress indicator (isolated in RepaintBoundary to avoid re-rendering entire card on every tick)
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
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Main Content Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Artwork
                  OptimizedImage(
                    imageUrl: track.artwork,
                    width: 44,
                    height: 44,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(width: 12),

                  // Title & Artist
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
                            color: AppTheme.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
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
