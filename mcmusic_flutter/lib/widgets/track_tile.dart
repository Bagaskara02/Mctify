import 'package:flutter/material.dart';
import '../models/track.dart';
import '../theme/app_theme.dart';
import 'optimized_image.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final int index;
  final bool isCurrent;
  final bool isPlaying;
  final bool isLiked;
  final VoidCallback onPlay;
  final VoidCallback onToggleLike;
  final bool showNumber;

  const TrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.isCurrent,
    required this.isPlaying,
    required this.isLiked,
    required this.onPlay,
    required this.onToggleLike,
    this.showNumber = true,
  });

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isCurrent ? Colors.white.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            // Track index or playing indicator
            if (showNumber)
              SizedBox(
                width: 24,
                child: isCurrent && isPlaying
                    ? const Icon(Icons.equalizer, color: AppTheme.primaryAzure, size: 18)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: isCurrent ? AppTheme.primaryAzure : AppTheme.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),

            // Artwork
            OptimizedImage(
              imageUrl: track.artwork,
              width: 44,
              height: 44,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(width: 12),

            // Title & Artist + Explicit Badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.primaryAzure : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (track.isExplicit) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF404040),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: const Text(
                            'E',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Stream Count (Matching Spotify screenshot)
            Text(
              track.streamCount,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 12),

            // Like heart icon
            IconButton(
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? AppTheme.primaryAzure : AppTheme.textMuted,
                size: 20,
              ),
              onPressed: onToggleLike,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 10),

            // Duration
            Text(
              _formatDuration(track.duration),
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
