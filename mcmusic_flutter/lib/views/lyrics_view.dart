import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/lyric_line.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/lyrics_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

class LyricsView extends StatefulWidget {
  final Track track;
  final AudioPlayerManager player;

  const LyricsView({
    super.key,
    required this.track,
    required this.player,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> with SingleTickerProviderStateMixin {
  final LyricsService _lyricsService = LyricsService();
  final StorageService _storageService = StorageService();
  final ScrollController _scrollController = ScrollController();

  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeLineIndex = 0;
  bool _userScrolled = false;
  Timer? _userScrollTimer;
  double? _manualOffset;
  double _autoOffset = 0.0;

  bool get isAutoSync => _manualOffset == null;
  double get effectiveSyncOffset => isAutoSync ? _autoOffset : _manualOffset!;

  // 60 FPS Sub-second Interpolation Ticker
  late final Ticker _ticker;
  double _lastKnownPlayerSec = 0.0;
  int _lastKnownTimestampMs = 0;
  double _currentEffectiveSec = 0.0;

  String get _trackKey =>
      '${widget.track.artist.trim().toLowerCase()}:::${widget.track.title.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _loadStoredSyncOffset();
    _loadLyrics();

    _lastKnownPlayerSec = widget.player.position.inMilliseconds / 1000.0;
    _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
    _currentEffectiveSec = _lastKnownPlayerSec + effectiveSyncOffset;

    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final playerSec = widget.player.position.inMilliseconds / 1000.0;

    // Detect if player pushed a new coarse position or if user sought
    if ((playerSec - _lastKnownPlayerSec).abs() > 0.08) {
      _lastKnownPlayerSec = playerSec;
      _lastKnownTimestampMs = now;
    }

    final curOffset = effectiveSyncOffset;
    if (widget.player.isPlaying) {
      final dt = (now - _lastKnownTimestampMs) / 1000.0;
      // Clamp interpolation to not drift too far ahead before next player update
      final clampedDt = dt.clamp(0.0, 0.45);
      final interpolated = _lastKnownPlayerSec + clampedDt + curOffset;
      if ((interpolated - _currentEffectiveSec).abs() > 0.01) {
        setState(() {
          _currentEffectiveSec = interpolated;
        });
      }
    } else {
      final staticPos = playerSec + curOffset;
      if ((staticPos - _currentEffectiveSec).abs() > 0.01) {
        setState(() {
          _currentEffectiveSec = staticPos;
        });
      }
    }
  }

  Future<void> _loadStoredSyncOffset() async {
    final saved = await _storageService.getLyricsSyncOffset(_trackKey);
    if (mounted && saved != 0.0) {
      setState(() => _manualOffset = saved);
    }
  }

  void _updateSyncOffset(double delta) {
    setState(() {
      final base = _manualOffset ?? _autoOffset;
      _manualOffset = ((base + delta) * 10).roundToDouble() / 10.0;
    });
    if (_manualOffset != null) {
      _storageService.setLyricsSyncOffset(_trackKey, _manualOffset!);
    }
    HapticFeedback.selectionClick();
  }

  void _resetToAutoSync() {
    setState(() => _manualOffset = null);
    _storageService.setLyricsSyncOffset(_trackKey, 0.0);
    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final result = await _lyricsService.fetchLyricsResult(
      widget.track.artist,
      widget.track.title,
      widget.track.duration,
    );
    if (mounted) {
      setState(() {
        _lyrics = result.lines;
        _autoOffset = result.autoOffset;
        _isLoading = false;
      });
    }
  }

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients || index < 0 || _userScrolled) return;
    const itemHeight = 78.0;
    final target = (index * itemHeight) - 170.0;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Effective time with small vocal anticipation lead (100ms)
    final effectiveSec = _currentEffectiveSec + 0.10;

    // Determine current active lyric line
    int currentActive = -1;
    for (int i = 0; i < _lyrics.length; i++) {
      if (_lyrics[i].time <= effectiveSec) {
        if (i == _lyrics.length - 1 || _lyrics[i + 1].time > effectiveSec) {
          currentActive = i;
          break;
        }
      }
    }

    if (currentActive != -1 && currentActive != _activeLineIndex) {
      _activeLineIndex = currentActive;
      if (!_userScrolled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActive(_activeLineIndex);
        });
      }
    }

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF060B14),
              Color(0xFF091424),
              Color(0xFF0C192E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top Navigation & Calibration Controls
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down, size: 30, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            widget.track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            widget.track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Auto Sync & Tuning Pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAutoSync ? const Color(0xFF0F2231) : const Color(0xFF1F1D14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAutoSync
                              ? const Color(0xFF00E5FF).withAlpha(120)
                              : Colors.amberAccent.withAlpha(120),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          InkWell(
                            onTap: () => _updateSyncOffset(-0.1),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Icon(Icons.remove, size: 13, color: Colors.white70),
                            ),
                          ),
                          GestureDetector(
                            onTap: _resetToAutoSync,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isAutoSync) ...[
                                    const Icon(Icons.bolt, size: 13, color: Color(0xFF00E5FF)),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isAutoSync
                                        ? 'AUTO SYNC'
                                        : '${effectiveSyncOffset >= 0 ? '+' : ''}${effectiveSyncOffset.toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      color: isAutoSync ? const Color(0xFF00E5FF) : Colors.amberAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: isAutoSync ? 0.4 : 0.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => _updateSyncOffset(0.1),
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Icon(Icons.add, size: 13, color: Colors.white70),
                            ),
                          ),
                          if (!isAutoSync) ...[
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: _resetToAutoSync,
                              child: const Icon(Icons.refresh, size: 12, color: Color(0xFF00E5FF)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Lyrics Karaoke Body
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppTheme.primaryAzure),
                      )
                    : _lyrics.isEmpty
                        ? const Center(
                            child: Text(
                              'Lirik tidak ditemukan untuk lagu ini',
                              style: TextStyle(color: Colors.white54, fontSize: 14),
                            ),
                          )
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is UserScrollNotification) {
                                _userScrolled = true;
                                _userScrollTimer?.cancel();
                                _userScrollTimer = Timer(const Duration(milliseconds: 2800), () {
                                  if (mounted) {
                                    setState(() {
                                      _userScrolled = false;
                                    });
                                  }
                                });
                              }
                              return false;
                            },
                            child: ListView.builder(
                              controller: _scrollController,
                              cacheExtent: 600,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                              itemCount: _lyrics.length,
                              itemBuilder: (context, index) {
                                final line = _lyrics[index];
                                final isActive = index == _activeLineIndex;
                                final isPassed = index < _activeLineIndex;

                                // Instrumental break
                                if (line.isInstrumental) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 20),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.music_note, color: AppTheme.primaryAzure, size: 18),
                                        const SizedBox(width: 8),
                                        Text(
                                          line.text,
                                          style: TextStyle(
                                            color: isActive ? const Color(0xFF00E5FF) : Colors.white24,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 2.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: GestureDetector(
                                    onTap: () {
                                      widget.player.seek(Duration(milliseconds: (line.time * 1000).toInt()));
                                      HapticFeedback.selectionClick();
                                    },
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 250),
                                      curve: Curves.easeOutCubic,
                                      style: TextStyle(
                                        fontSize: isActive ? 27 : 21,
                                        fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                                        height: 1.35,
                                        letterSpacing: -0.4,
                                      ),
                                      child: isActive && line.words.isNotEmpty
                                          // Word-by-word with fluid character fade-geser
                                          ? Wrap(
                                              spacing: 7.0,
                                              runSpacing: 6.0,
                                              children: line.words.map((w) {
                                                return KaraokeWordWipe(
                                                  word: w,
                                                  currentTimeSec: effectiveSec,
                                                  onTap: () {
                                                    widget.player.seek(
                                                      Duration(milliseconds: (w.startTime * 1000).toInt()),
                                                    );
                                                    HapticFeedback.selectionClick();
                                                  },
                                                );
                                              }).toList(),
                                            )
                                          : Text(
                                              line.text,
                                              style: TextStyle(
                                                color: isActive
                                                    ? Colors.white
                                                    : isPassed
                                                        ? Colors.white.withAlpha(90)
                                                        : Colors.white.withAlpha(60),
                                                shadows: isActive
                                                    ? const [
                                                        Shadow(
                                                          color: Color(0x9900A3FF),
                                                          blurRadius: 18,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
              ),

              // Bottom Mini Controls
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFF091424),
                  border: Border(top: BorderSide(color: Colors.white10)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        widget.player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        color: Colors.white,
                        size: 40,
                      ),
                      onPressed: () {
                        widget.player.togglePlayPause();
                        HapticFeedback.lightImpact();
                      },
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          activeTrackColor: AppTheme.primaryAzure,
                          inactiveTrackColor: Colors.white12,
                          thumbColor: Colors.white,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          value: widget.player.position.inSeconds.toDouble().clamp(
                                0.0,
                                widget.player.duration.inSeconds.toDouble() > 0
                                    ? widget.player.duration.inSeconds.toDouble()
                                    : 1.0,
                              ),
                          max: widget.player.duration.inSeconds.toDouble() > 0
                              ? widget.player.duration.inSeconds.toDouble()
                              : 1.0,
                          onChanged: (val) {
                            widget.player.seek(Duration(seconds: val.round()));
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Syllable / Word Karaoke Fade-Wipe Widget (Apple Music & Lyra style)
/// Sweeps smoothly across letters from left to right as the singer sings ("BA GUS", etc.)
class KaraokeWordWipe extends StatelessWidget {
  final LyricWord word;
  final double currentTimeSec;
  final VoidCallback onTap;

  const KaraokeWordWipe({
    super.key,
    required this.word,
    required this.currentTimeSec,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final start = word.startTime;
    final end = word.endTime;

    double progress;
    if (currentTimeSec < start) {
      progress = 0.0;
    } else if (currentTimeSec >= end) {
      progress = 1.0;
    } else {
      progress = (currentTimeSec - start) / (word.duration > 0.01 ? word.duration : 0.01);
      progress = progress.clamp(0.0, 1.0);
    }

    final isActivelySinging = progress > 0.0 && progress < 1.0;

    return GestureDetector(
      onTap: onTap,
      child: isActivelySinging
          ? ShaderMask(
              shaderCallback: (Rect bounds) {
                // Smooth gradient wipe band across the letters of the word
                final p = progress.clamp(0.0, 1.0);
                final stopA = (p - 0.06).clamp(0.0, 1.0);
                final stopB = (p + 0.06).clamp(0.0, 1.0);

                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: const [
                    Color(0xFFFFFFFF),
                    Color(0xFF00E5FF), // Neon cyan highlight on current syllable
                    Color(0x60FFFFFF), // Dimmed upcoming letters
                    Color(0x60FFFFFF),
                  ],
                  stops: [
                    0.0,
                    stopA,
                    stopB,
                    1.0,
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcIn,
              child: Text(
                word.word,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.w900,
                  height: 1.35,
                  letterSpacing: -0.4,
                  shadows: [
                    Shadow(
                      color: Color(0xCC00E5FF),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
            )
          : Text(
              word.word,
              style: TextStyle(
                color: progress >= 1.0
                    ? Colors.white
                    : Colors.white.withAlpha(85),
                fontSize: progress >= 1.0 ? 26 : 25,
                fontWeight: progress >= 1.0 ? FontWeight.w800 : FontWeight.w600,
                height: 1.35,
                letterSpacing: -0.4,
                shadows: progress >= 1.0
                    ? const [
                        Shadow(
                          color: Color(0x6600A3FF),
                          blurRadius: 10,
                        ),
                      ]
                    : null,
              ),
            ),
    );
  }
}
