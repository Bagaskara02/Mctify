import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/lyric_line.dart';
import '../services/audio_player_manager.dart';
import '../services/equalizer_service.dart';
import '../services/lyrics_service.dart';
import '../services/music_api_service.dart';
import '../theme/app_theme.dart';
import '../utils/artwork_palette.dart';
import '../views/artist_view.dart';
import '../views/car_mode_view.dart';
import '../views/equalizer_view.dart';
import '../views/lyrics_view.dart';
import '../views/queue_view.dart';
import 'audio_quality_modal.dart';
import 'optimized_image.dart';
import 'sleep_timer_modal.dart';
import 'track_action_sheet.dart';

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
  final MusicApiService _api = MusicApiService();
  List<LyricLine> _lyrics = [];
  String? _lastLoadedTrackId;
  String? _lastPaletteUrl;
  ArtworkColors _palette = ArtworkColors.fallbackDefault;
  double? _dragSeconds;

  @override
  void initState() {
    super.initState();
    _fetchLyricsIfNeeded();
    _syncPalette();
  }

  void _syncPalette() {
    final track = widget.player.currentTrack;
    if (track == null || track.artwork == _lastPaletteUrl) return;
    _lastPaletteUrl = track.artwork;
    _palette = ArtworkPalette.getCachedOrFallback(track.artwork, seed: track.title);
    ArtworkPalette.extract(track.artwork, seed: track.title).then((colors) {
      if (mounted && _lastPaletteUrl == track.artwork) {
        setState(() => _palette = colors);
      }
    });
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

  Future<void> _openArtistProfile(Track track) async {
    HapticFeedback.lightImpact();
    final primaryArtist = track.artist.split(',').first.split('&').first.trim();
    final artists = await _api.searchArtists(primaryArtist);
    if (!mounted) return;
    if (artists.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ArtistView(
            artist: artists.first,
            player: widget.player,
          ),
        ),
      );
    }
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

                // 0. Tambahkan ke Playlist
                ListTile(
                  leading: const Icon(Icons.add_circle_outline, color: Colors.white),
                  title: const Text('Tambahkan ke Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  onTap: () {
                    Navigator.pop(context);
                    showTrackActionSheet(
                      context: context,
                      track: track,
                      player: widget.player,
                    );
                  },
                ),

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

                // 5. Kecepatan Pemutaran (Playback Speed)
                ListTile(
                  leading: const Icon(Icons.speed, color: AppTheme.primaryAzure),
                  title: const Text('Kecepatan Pemutaran', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${widget.player.playbackSpeed}x ${widget.player.playbackSpeed == 1.0 ? '(Normal)' : ''}',
                    style: TextStyle(
                      color: widget.player.playbackSpeed != 1.0 ? AppTheme.primaryAzure : AppTheme.textMuted,
                      fontSize: 11,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showPlaybackSpeedModal(context);
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

  void _showPlaybackSpeedModal(BuildContext context) {
    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Kecepatan Pemutaran',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                ...speeds.map((s) {
                  final isSelected = widget.player.playbackSpeed == s;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${s}x ${s == 1.0 ? '(Normal)' : ''}',
                      style: TextStyle(
                        color: isSelected ? AppTheme.primaryAzure : Colors.white,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppTheme.primaryAzure)
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.player.setPlaybackSpeed(s);
                      Navigator.pop(context);
                    },
                  );
                }),
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
        _syncPalette();

        final pos = widget.player.position;
        final dur = widget.player.duration.inSeconds > 0
            ? widget.player.duration
            : Duration(seconds: track.duration > 0 ? track.duration : 180);

        final displaySec = _dragSeconds ?? pos.inSeconds.toDouble().clamp(0.0, dur.inSeconds.toDouble());
        final displayPos = Duration(seconds: displaySec.round());
        final remaining = (dur - displayPos).isNegative ? Duration.zero : (dur - displayPos);

        // Find active + upcoming synced lyric lines
        int activeLyricIndex = -1;
        if (_lyrics.isNotEmpty) {
          for (int i = 0; i < _lyrics.length; i++) {
            if (_lyrics[i].time <= displaySec) {
              activeLyricIndex = i;
            } else {
              break;
            }
          }
        }
        final currentLine = (activeLyricIndex >= 0 && activeLyricIndex < _lyrics.length)
            ? _lyrics[activeLyricIndex]
            : null;
        final nextLine = (activeLyricIndex >= 0 && activeLyricIndex + 1 < _lyrics.length)
            ? _lyrics[activeLyricIndex + 1]
            : null;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic,
          height: MediaQuery.of(context).size.height * 0.96,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                _palette.primary,
                _palette.secondary,
                const Color(0xFF0A0A0C),
              ],
              stops: const [0.0, 0.56, 1.0],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            bottom: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  children: [
                    // Pull down handle
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 2),
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // Top Bar (Chevron Down, "MEMUTAR DARI ..." + Album title, More Options)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'MEMUTAR DARI',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.65),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 1),
                                Text(
                                  track.album.isNotEmpty ? track.album : 'Koleksi McTify',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert_rounded, size: 26, color: Colors.white),
                            onPressed: () => _showMoreOptionsModal(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Main Square Album Artwork with Play/Pause Scale Bounce & Tap to Lyrics (MySpoti + Apple Music aesthetic)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 26),
                      child: AspectRatio(
                        aspectRatio: 1,
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
                          child: AnimatedScale(
                            scale: widget.player.isPlaying ? 1.0 : 0.92,
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutBack,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    blurRadius: 32,
                                    spreadRadius: 2,
                                    offset: const Offset(0, 14),
                                  ),
                                ],
                              ),
                              child: Hero(
                                tag: 'current_artwork_${track.id}',
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: OptimizedImage(
                                    imageUrl: track.artwork,
                                    borderRadius: BorderRadius.circular(12),
                                    memCacheWidth: 700,
                                    memCacheHeight: 700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // Track Title, Clickable Artist, Audio Quality Badge & Like Circle
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
                                  track.title,
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
                                GestureDetector(
                                  onTap: () => _openArtistProfile(track),
                                  child: Text(
                                    track.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.78),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // Spotube / MySpoti Codec & Bitrate Badge
                                GestureDetector(
                                  onTap: () => AudioQualityModal.show(context, widget.player),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.high_quality_rounded, size: 13, color: AppTheme.primaryAzure),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${widget.player.audioQuality.label} • ${widget.player.audioQuality.bitrate}',
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Saved Checkmark Button (Spotify 2025 style with Electric Azure)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.onToggleLike();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 220),
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: widget.isLiked ? AppTheme.primaryAzure : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: widget.isLiked ? AppTheme.primaryAzure : Colors.white60,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                widget.isLiked ? Icons.check : Icons.add,
                                color: widget.isLiked ? Colors.black : Colors.white,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Scrubber Slider
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.white,
                          overlayColor: Colors.white.withAlpha(32),
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                        ),
                        child: Slider(
                          value: displaySec.clamp(0.0, dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0),
                          max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1.0,
                          onChanged: (val) => setState(() => _dragSeconds = val),
                          onChangeEnd: (val) {
                            widget.player.seek(Duration(seconds: val.round()));
                            setState(() => _dragSeconds = null);
                          },
                        ),
                      ),
                    ),

                    // Timestamps (Elapsed vs Remaining)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(displayPos),
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '-${_formatDuration(remaining)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Main Transport Controls Row (Spotify Classic: Shuffle, Prev, Play, Next, Repeat + indicator dots)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.shuffle_rounded,
                                  color: widget.player.isShuffle ? AppTheme.primaryAzure : Colors.white70,
                                  size: 25,
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
                          IconButton(
                            icon: const Icon(Icons.skip_previous_rounded, size: 40, color: Colors.white),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.player.previous();
                            },
                          ),
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              widget.player.togglePlayPause();
                            },
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 16,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                widget.player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: Colors.black,
                                size: 40,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next_rounded, size: 40, color: Colors.white),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.player.next();
                            },
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  Icons.repeat_rounded,
                                  color: widget.player.isRepeat ? AppTheme.primaryAzure : Colors.white70,
                                  size: 25,
                                ),
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  widget.player.toggleRepeat();
                                },
                              ),
                              Container(
                                width: 4,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: widget.player.isRepeat ? AppTheme.primaryAzure : Colors.transparent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Utility Controls Row (EQ, Timer, Speed, Share, Queue)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.graphic_eq_rounded, size: 21, color: Colors.white70),
                                tooltip: 'Equalizer',
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
                              IconButton(
                                icon: Icon(
                                  Icons.timer_outlined,
                                  size: 21,
                                  color: widget.player.isSleepTimerActive ? AppTheme.primaryAzure : Colors.white70,
                                ),
                                tooltip: 'Sleep Timer',
                                onPressed: () => SleepTimerModal.show(context, widget.player),
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _showPlaybackSpeedModal(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: widget.player.playbackSpeed != 1.0
                                        ? AppTheme.primaryAzure.withValues(alpha: 0.25)
                                        : Colors.white.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${widget.player.playbackSpeed}x',
                                    style: TextStyle(
                                      color: widget.player.playbackSpeed != 1.0 ? AppTheme.primaryAzure : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.share_outlined, size: 21, color: Colors.white70),
                                tooltip: 'Bagikan',
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  Clipboard.setData(ClipboardData(text: 'Mendengarkan "${track.title}" oleh ${track.artist} di McTify!'));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Tautan lagu disalin ke clipboard!'),
                                      duration: Duration(milliseconds: 900),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.queue_music_rounded, size: 24, color: Colors.white70),
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

                    const SizedBox(height: 12),

                    // MySpoti & Spotify Authentic Artwork-Tinted Live Lyrics Card
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 450),
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
                        decoration: BoxDecoration(
                          color: _palette.surfaceTint,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.lyrics_outlined, color: Colors.white, size: 17),
                                    SizedBox(width: 7),
                                    Text(
                                      'Lirik',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.28),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Text(
                                        'Layar Penuh',
                                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                                      ),
                                      SizedBox(width: 4),
                                      Icon(Icons.open_in_full_rounded, size: 13, color: Colors.white),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            if (_lyrics.isEmpty)
                              Text(
                                'Ketuk untuk membuka lirik sinkron & mode karaoke penuh...',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              )
                            else ...[
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                child: Text(
                                  currentLine?.text.isNotEmpty == true
                                      ? currentLine!.text
                                      : _lyrics.first.text,
                                  key: ValueKey<String>(currentLine?.text ?? _lyrics.first.text),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    fontWeight: FontWeight.w900,
                                    height: 1.3,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                              ),
                              if (nextLine?.text.isNotEmpty == true) ...[
                                const SizedBox(height: 6),
                                Text(
                                  nextLine!.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.58),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
