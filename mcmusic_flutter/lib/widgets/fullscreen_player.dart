import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../services/equalizer_service.dart';
import '../theme/app_theme.dart';
import '../views/car_mode_view.dart';
import '../views/equalizer_view.dart';
import '../views/lyrics_view.dart';
import 'audio_quality_modal.dart';
import 'optimized_image.dart';
import 'sleep_timer_modal.dart';

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

  void _showMoreOptionsModal(BuildContext context) {
    final track = widget.player.currentTrack;
    if (track == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Track title & artist header
                Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: OptimizedImage(
                        imageUrl: track.artwork,
                        borderRadius: BorderRadius.circular(8),
                        memCacheWidth: 100,
                        memCacheHeight: 100,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),

                // 1. Mode Mobil (Car Mode)
                ListTile(
                  leading: const Icon(Icons.directions_car, color: AppTheme.primaryAzure),
                  title: const Text('Mode Mobil (Car Mode)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tampilan aman tombol besar untuk berkendara', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CarModeView(
                          player: widget.player,
                          isLiked: widget.isLiked,
                          onToggleLike: widget.onToggleLike,
                        ),
                      ),
                    );
                  },
                ),

                // 2. Equalizer & Efek Suara
                ListTile(
                  leading: const Icon(Icons.graphic_eq, color: AppTheme.primaryAzure),
                  title: const Text('Equalizer & Bass Boost', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('Preset: ${EqualizerService.instance.selectedPresetName}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EqualizerView(
                          equalizerService: EqualizerService.instance,
                        ),
                      ),
                    );
                  },
                ),

                // 3. Pengatur Waktu Tidur (Sleep Timer)
                ListTile(
                  leading: const Icon(Icons.bedtime, color: AppTheme.primaryAzure),
                  title: const Text('Pengatur Waktu Tidur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    widget.player.isSleepTimerActive
                        ? 'Aktif (${widget.player.sleepTimerFormatted})'
                        : 'Mati otomatis setelah waktu tertentu',
                    style: TextStyle(
                      color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    SleepTimerModal.show(context, widget.player);
                  },
                ),

                // 4. Kualitas Audio Streaming (Bitrate)
                ListTile(
                  leading: const Icon(Icons.high_quality, color: AppTheme.primaryAzure),
                  title: const Text('Kualitas Streaming', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text('${widget.player.audioQuality.label} (${widget.player.audioQuality.bitrate})', style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                  onTap: () {
                    Navigator.pop(context);
                    AudioQualityModal.show(context, widget.player);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
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
                    onPressed: () => _showMoreOptionsModal(context),
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

              // Scrubber Slider & Timestamps
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

              // Quick Action Chips Row (Car Mode, Sleep Timer, EQ, Bitrate)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Sleep Timer Chip
                  ActionChip(
                    avatar: Icon(
                      Icons.bedtime,
                      size: 15,
                      color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : Colors.white60,
                    ),
                    label: Text(
                      widget.player.isSleepTimerActive
                          ? widget.player.sleepTimerFormatted ?? 'Timer'
                          : 'Tidur',
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : Colors.white70,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    backgroundColor: const Color(0xFF222222),
                    onPressed: () => SleepTimerModal.show(context, widget.player),
                  ),
                  const SizedBox(width: 8),

                  // Car Mode Chip
                  ActionChip(
                    avatar: const Icon(Icons.directions_car, size: 15, color: Colors.white60),
                    label: const Text('Mobil', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                    backgroundColor: const Color(0xFF222222),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CarModeView(
                            player: widget.player,
                            isLiked: widget.isLiked,
                            onToggleLike: widget.onToggleLike,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),

                  // Equalizer Chip
                  ActionChip(
                    avatar: const Icon(Icons.graphic_eq, size: 15, color: Colors.white60),
                    label: const Text('EQ', style: TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.bold)),
                    backgroundColor: const Color(0xFF222222),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EqualizerView(
                            equalizerService: EqualizerService.instance,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

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
