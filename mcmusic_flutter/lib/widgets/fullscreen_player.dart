import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import '../views/lyrics_view.dart';
import 'optimized_image.dart';

class FullscreenPlayer extends StatefulWidget {
  final AudioPlayerManager player;
  final bool isLiked;
  final VoidCallback onToggleLike;

  const FullscreenPlayer({
    super.key,
    required this.player,
    required this.isLiked,
    required this.onToggleLike,
  });

  @override
  State<FullscreenPlayer> createState() => _FullscreenPlayerState();
}

class _FullscreenPlayerState extends State<FullscreenPlayer> {
  String _formatDuration(Duration d) {
    final mins = d.inMinutes;
    final secs = d.inSeconds % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final track = widget.player.currentTrack;
        if (track == null) return const SizedBox.shrink();

        final pos = widget.player.position;
        final dur = widget.player.duration.inSeconds > 0
            ? widget.player.duration
            : Duration(seconds: track.duration);

        return Container(
          height: MediaQuery.of(context).size.height * 0.94,
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            children: [
              // Pull down handle
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),

              // Header bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      const Text(
                        'SEDANG MEMUTAR DARI',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        track.album,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.more_vert, size: 22),
                    onPressed: () {},
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Large Artwork (downsampled for low memory devices)
              AspectRatio(
                aspectRatio: 1,
                child: OptimizedImage(
                  imageUrl: track.artwork,
                  borderRadius: BorderRadius.circular(12),
                  memCacheWidth: 600,
                  memCacheHeight: 600,
                ),
              ),
              const Spacer(flex: 1),

              // Track Info + Like Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      widget.isLiked ? Icons.favorite : Icons.favorite_border,
                      color: widget.isLiked ? AppTheme.primaryAzure : AppTheme.textMuted,
                      size: 28,
                    ),
                    onPressed: widget.onToggleLike,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Scrubber Slider & Timestamps (Isolated in RepaintBoundary for smooth 60fps on potato devices)
              RepaintBoundary(
                child: Column(
                  children: [
                    Slider(
                      value: pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                      max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                      onChanged: (val) {
                        widget.player.seek(Duration(seconds: val.round()));
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(pos),
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                          Text(
                            _formatDuration(dur),
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Control Buttons Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.shuffle,
                      color: widget.player.isShuffle ? AppTheme.primaryAzure : AppTheme.textMuted,
                      size: 24,
                    ),
                    onPressed: () => widget.player.toggleShuffle(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 36, color: Colors.white),
                    onPressed: () => widget.player.previous(),
                  ),
                  GestureDetector(
                    onTap: () => widget.player.togglePlayPause(),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        widget.player.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.black,
                        size: 36,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 36, color: Colors.white),
                    onPressed: () => widget.player.next(),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.repeat,
                      color: widget.player.isRepeat ? AppTheme.primaryAzure : AppTheme.textMuted,
                      size: 24,
                    ),
                    onPressed: () => widget.player.toggleRepeat(),
                  ),
                ],
              ),
              const Spacer(flex: 1),

              // Bottom Karaoke Lyrics Button
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LyricsView(
                        track: track,
                        player: widget.player,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.mic, color: Colors.black, size: 18),
                label: const Text('Buka Lirik Karaoke', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAzure,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
