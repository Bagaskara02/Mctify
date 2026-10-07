import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';

class CarModeView extends StatefulWidget {
  final AudioPlayerManager player;
  final bool isLiked;
  final VoidCallback onToggleLike;

  const CarModeView({
    super.key,
    required this.player,
    required this.isLiked,
    required this.onToggleLike,
  });

  @override
  State<CarModeView> createState() => _CarModeViewState();
}

class _CarModeViewState extends State<CarModeView> {
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
        final pos = widget.player.position;
        final dur = widget.player.duration.inSeconds > 0
            ? widget.player.duration
            : Duration(seconds: track?.duration ?? 180);

        return Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                children: [
                  // Driving Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.directions_car, color: AppTheme.primaryAzure, size: 28),
                          SizedBox(width: 10),
                          Text(
                            'MODE MOBIL (CAR MODE)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                        onPressed: () => Navigator.pop(context),
                        tooltip: 'Keluar dari Mode Mobil',
                      ),
                    ],
                  ),
                  const Spacer(flex: 1),

                  // Giant Artwork for Glancing
                  if (track != null)
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: OptimizedImage(
                        imageUrl: track.artwork,
                        borderRadius: BorderRadius.circular(20),
                        memCacheWidth: 440,
                        memCacheHeight: 440,
                      ),
                    )
                  else
                    const SizedBox(
                      width: 220,
                      height: 220,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF1E1E1E),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.music_note, color: Colors.white24, size: 80),
                      ),
                    ),
                  const Spacer(flex: 1),

                  // Giant Song Title & Artist
                  Column(
                    children: [
                      Text(
                        track?.title ?? 'Tidak Ada Lagu',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        track?.artist ?? 'McMusic Player',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: AppTheme.primaryAzure,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Large High-Contrast Driving Scrubber
                  RepaintBoundary(
                    child: Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: AppTheme.primaryAzure,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: Colors.white,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                            trackHeight: 8,
                          ),
                          child: Slider(
                            value: pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble()),
                            max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                            onChanged: (val) {
                              widget.player.seek(Duration(seconds: val.round()));
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(pos),
                                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                _formatDuration(dur),
                                style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(flex: 1),

                  // Giant Safe Touch Target Controls (Built for Driving)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Like button
                      IconButton(
                        icon: Icon(
                          widget.isLiked ? Icons.favorite : Icons.favorite_border,
                          color: widget.isLiked ? AppTheme.primaryAzure : Colors.white,
                          size: 40,
                        ),
                        onPressed: widget.onToggleLike,
                      ),

                      // Previous
                      IconButton(
                        icon: const Icon(Icons.skip_previous, color: Colors.white, size: 56),
                        onPressed: () => widget.player.previous(),
                      ),

                      // Giant Play/Pause (88px)
                      GestureDetector(
                        onTap: () => widget.player.togglePlayPause(),
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: const BoxDecoration(
                            color: AppTheme.primaryAzure,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Color(0x6600A3FF),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 52,
                          ),
                        ),
                      ),

                      // Next
                      IconButton(
                        icon: const Icon(Icons.skip_next, color: Colors.white, size: 56),
                        onPressed: () => widget.player.next(),
                      ),

                      // Repeat
                      IconButton(
                        icon: Icon(
                          Icons.repeat,
                          color: widget.player.isRepeat ? AppTheme.primaryAzure : Colors.white60,
                          size: 38,
                        ),
                        onPressed: () => widget.player.toggleRepeat(),
                      ),
                    ],
                  ),
                  const Spacer(flex: 1),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
