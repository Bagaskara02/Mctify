import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/lyric_line.dart';
import '../services/audio_player_manager.dart';
import '../services/equalizer_service.dart';
import '../services/lyrics_service.dart';
import '../theme/app_theme.dart';
import '../views/car_mode_view.dart';
import '../views/equalizer_view.dart';
import '../views/lyrics_view.dart';
import '../views/queue_view.dart';
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
  final LyricsService _lyricsService = LyricsService();
  List<LyricLine> _lyrics = [];
  String? _lastLoadedTrackId;
  double? _dragSeconds;

  @override
  void initState() {
    super.initState();
    _fetchLyricsIfNeeded();
  }

  void _fetchLyricsIfNeeded() async {
    final track = widget.player.currentTrack;
    if (track == null || track.id == _lastLoadedTrackId) return;
    _lastLoadedTrackId = track.id;

    try {
      final res = await _lyricsService.fetchLyrics(
        track.artist,
        track.title,
        track.duration,
      );
      if (mounted) {
        setState(() => _lyrics = res);
      }
    } catch (_) {}
  }

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
      backgroundColor: const Color(0xFF1A1A1E),
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

                // 1. Equalizer & Bass Boost
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

                // 2. Mode Mobil (Car Mode)
                ListTile(
                  leading: const Icon(Icons.directions_car, color: AppTheme.primaryAzure),
                  title: const Text('Mode Mobil (Car Mode)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Tampilan tombol besar aman berkendara', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
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

                // 3. Pengatur Waktu Tidur (Sleep Timer)
                ListTile(
                  leading: const Icon(Icons.timer_outlined, color: AppTheme.primaryAzure),
                  title: const Text('Pengatur Waktu Tidur', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    widget.player.isSleepTimerActive
                        ? 'Aktif (${widget.player.sleepTimerFormatted})'
                        : 'Mati otomatis setelah waktu ditentukan',
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

                // 4. Kualitas Audio Streaming
                ListTile(
                  leading: const Icon(Icons.high_quality, color: AppTheme.primaryAzure),
                  title: const Text('Kualitas Audio (Bitrate)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${widget.player.audioQuality.label} • ${widget.player.audioQuality.bitrate}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  ),
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

        _fetchLyricsIfNeeded();

        final pos = widget.player.position;
        final dur = widget.player.duration.inSeconds > 0
            ? widget.player.duration
            : Duration(seconds: track.duration > 0 ? track.duration : 180);

        final displaySec = _dragSeconds ?? pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble());
        final displayPos = Duration(seconds: displaySec.round());
        final remaining = (dur - displayPos).isNegative ? Duration.zero : (dur - displayPos);

        // Find active synced lyric line
        LyricLine? currentLine;
        LyricLine? nextLine;
        if (_lyrics.isNotEmpty) {
          for (int i = 0; i < _lyrics.length; i++) {
            if (_lyrics[i].time <= displaySec) {
              currentLine = _lyrics[i];
              if (i + 1 < _lyrics.length) {
                nextLine = _lyrics[i + 1];
              }
            } else {
              break;
            }
          }
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.95,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF1A1A1E),
                Color(0xFF131316),
                Color(0xFF0F0F12),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Pull down handle
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Top Bar (Chevrondown, Album / Playlist Title, More icon) - NO PROFILE ICON!
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down, size: 30, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          track.album.isNotEmpty ? track.album : 'SEDANG MEMUTAR',
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz, size: 28, color: Colors.white),
                        onPressed: () => _showMoreOptionsModal(context),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Main Square Album Artwork (Exact match to Spotify / reference screenshot)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 28,
                            spreadRadius: 2,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: OptimizedImage(
                          imageUrl: track.artwork,
                          borderRadius: BorderRadius.circular(10),
                          memCacheWidth: 700,
                          memCacheHeight: 700,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Active Synced Lyric Quote Display (Directly below artwork, exact match to screenshot)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
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
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          (currentLine != null && currentLine.text.trim().isNotEmpty)
                              ? currentLine.text
                              : (track.album.isNotEmpty ? track.album : 'Hi-Fi Audio • 24-bit Flac'),
                          key: ValueKey<String>(currentLine?.text ?? track.album),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Track Info & Saved Checkmark (Electric Blue circle instead of green)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Saved Checkmark Button (Blue Accent Palette!)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onToggleLike();
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: widget.isLiked ? AppTheme.primaryAzure : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.isLiked ? AppTheme.primaryAzure : Colors.white54,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            widget.isLiked ? Icons.check : Icons.add,
                            color: widget.isLiked ? Colors.black : Colors.white70,
                            size: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // Scrubber Slider (Electric Blue, Seek Freeze Fix with local drag state)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppTheme.primaryAzure,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: AppTheme.primaryAzure.withAlpha(40),
                      trackHeight: 3.5,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    ),
                    child: Slider(
                      value: displaySec.clamp(0.0, dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0),
                      max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                      onChanged: (val) {
                        setState(() => _dragSeconds = val);
                      },
                      onChangeEnd: (val) {
                        widget.player.seek(Duration(seconds: val.round()));
                        setState(() => _dragSeconds = null);
                      },
                    ),
                  ),
                ),

                // Timestamps (Elapsed vs Countdown Remaining like Spotify)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(displayPos),
                        style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '-${_formatDuration(remaining)}',
                        style: const TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Main Playback Controls Row (Shuffle with blue dot, Prev, Big White Play/Pause, Next, Timer)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // 1. Shuffle (Blue active color + blue indicator dot)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.shuffle,
                              color: widget.player.isShuffle ? AppTheme.primaryAzure : Colors.white60,
                              size: 26,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.player.toggleShuffle();
                            },
                          ),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: widget.player.isShuffle ? AppTheme.primaryAzure : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),

                      // 2. Skip Previous (With 3x tap rewind / previous track logic)
                      IconButton(
                        icon: const Icon(Icons.skip_previous, size: 38, color: Colors.white),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.player.previous();
                        },
                      ),

                      // 3. Play / Pause Button (Massive solid white circle with dark icon)
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.player.togglePlayPause();
                        },
                        child: Container(
                          width: 66,
                          height: 66,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white24,
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.player.isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.black,
                            size: 38,
                          ),
                        ),
                      ),

                      // 4. Skip Next
                      IconButton(
                        icon: const Icon(Icons.skip_next, size: 38, color: Colors.white),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          widget.player.next();
                        },
                      ),

                      // 5. Timer / Sleep Timer (Blue active color + blue indicator dot)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.timer_outlined,
                              color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : Colors.white60,
                              size: 26,
                            ),
                            onPressed: () => SleepTimerModal.show(context, widget.player),
                          ),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Secondary Utility Row (Devices, Share, Queue)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Connected Device icon (AirPods / Device switcher)
                      IconButton(
                        icon: const Icon(Icons.devices_rounded, size: 22, color: Colors.white70),
                        tooltip: 'Pilih Output Perangkat',
                        onPressed: () => AudioQualityModal.show(context, widget.player),
                      ),
                      Row(
                        children: [
                          // Share Icon
                          IconButton(
                            icon: const Icon(Icons.ios_share_rounded, size: 22, color: Colors.white70),
                            tooltip: 'Bagikan',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Clipboard.setData(ClipboardData(text: 'Mendengarkan "${track.title}" oleh ${track.artist} di McMusic!'));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Tautan lagu disalin ke clipboard!'),
                                  duration: Duration(milliseconds: 900),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                          ),
                          // Queue Icon
                          IconButton(
                            icon: const Icon(Icons.queue_music_rounded, size: 26, color: Colors.white70),
                            tooltip: 'Antrean Lagu',
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              QueueView.show(context, widget.player);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Bottom Lyrics Preview Drawer Card (Exact match to screenshot bottom card)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
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
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF28282D),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: const [
                            Text(
                              'Lyrics preview',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Icon(Icons.open_in_full, size: 16, color: Colors.white70),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          nextLine?.text.isNotEmpty == true
                              ? nextLine!.text
                              : (currentLine?.text.isNotEmpty == true
                                  ? currentLine!.text
                                  : 'Ketuk untuk membuka lirik karaoke lengkap per-huruf...'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
