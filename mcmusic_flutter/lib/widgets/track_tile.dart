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
                    ? const AnimatedEqualizerBars(color: AppTheme.primaryAzure)
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

/// Spotify-style 3-bar animated equalizer indicator for playing songs
class AnimatedEqualizerBars extends StatefulWidget {
  final Color color;

  const AnimatedEqualizerBars({
    super.key,
    this.color = AppTheme.primaryAzure,
  });

  @override
  State<AnimatedEqualizerBars> createState() => _AnimatedEqualizerBarsState();
}

class _AnimatedEqualizerBarsState extends State<AnimatedEqualizerBars>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final val = _controller.value;
        final h1 = 4.0 + 10.0 * val;
        final h2 = 14.0 - 10.0 * val;
        final h3 = 6.0 + 8.0 * ((val + 0.5) % 1.0);

        return SizedBox(
          width: 14,
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildBar(h1),
              const SizedBox(width: 2),
              _buildBar(h2),
              const SizedBox(width: 2),
              _buildBar(h3),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.5,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(1.5),
      ),
    );
  }
}
