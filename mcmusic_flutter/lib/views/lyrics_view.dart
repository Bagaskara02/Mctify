import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/lyric_line.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/lyrics_service.dart';
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
  final ScrollController _scrollController = ScrollController();

  late Track _currentTrack;
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeLineIndex = 0;
  bool _userScrolled = false;
  Timer? _userScrollTimer;

  // Line keys for smooth ensureVisible scrolling
  final Map<int, GlobalKey> _lineKeys = {};

  // 60 FPS Sub-second Interpolation Ticker
  late final Ticker _ticker;
  double _lastKnownPlayerSec = 0.0;
  int _lastKnownTimestampMs = 0;
  double _currentEffectiveSec = 0.0;

  @override
  void initState() {
    super.initState();
    _currentTrack = widget.player.currentTrack ?? widget.track;
    widget.player.addListener(_onPlayerStateChanged);
    _loadLyrics();

    _lastKnownPlayerSec = widget.player.position.inMilliseconds / 1000.0;
    _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
    _currentEffectiveSec = _lastKnownPlayerSec;

    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _onPlayerStateChanged() {
    final active = widget.player.currentTrack;
    if (active != null && (active.id != _currentTrack.id || active.title != _currentTrack.title)) {
      if (!mounted) return;
      setState(() {
        _currentTrack = active;
        _isLoading = true;
        _lyrics = [];
        _activeLineIndex = 0;
        _lastKnownPlayerSec = 0.0;
        _currentEffectiveSec = 0.0;
        _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
        _lineKeys.clear();
      });
      _loadLyrics();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final playerSec = widget.player.position.inMilliseconds / 1000.0;

    // Detect if player pushed a new coarse position or user sought
    if ((playerSec - _lastKnownPlayerSec).abs() > 0.08) {
      _lastKnownPlayerSec = playerSec;
      _lastKnownTimestampMs = now;
    }

    if (widget.player.isPlaying) {
      final dt = (now - _lastKnownTimestampMs) / 1000.0;
      final clampedDt = dt.clamp(0.0, 0.25);
      final interpolated = _lastKnownPlayerSec + clampedDt;
      if ((interpolated - _currentEffectiveSec).abs() > 0.01) {
        setState(() {
          _currentEffectiveSec = interpolated;
        });
      }
    } else {
      if ((playerSec - _currentEffectiveSec).abs() > 0.01) {
        setState(() {
          _currentEffectiveSec = playerSec;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerStateChanged);
    _ticker.dispose();
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final target = _currentTrack;
    final result = await _lyricsService.fetchLyricsResult(
      target.artist,
      target.title,
      target.duration,
    );
    if (mounted && _currentTrack.id == target.id) {
      setState(() {
        _lyrics = result.lines;
        _isLoading = false;
        _lineKeys.clear();
      });
    }
  }

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients || index < 0 || _userScrolled) return;
    final key = _lineKeys[index];
    final lineCtx = key?.currentContext;
    if (lineCtx != null) {
      // Anchors active line smoothly at 38% from the top of the viewport
      Scrollable.ensureVisible(
        lineCtx,
        alignment: 0.38,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      final viewport = _scrollController.position.viewportDimension;
      const avgItemHeight = 60.0;
      final target = (48.0 + (index * avgItemHeight)) - (viewport * 0.38);
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Acoustic output calibration: Physical speaker/earphone audio lags behind internal player timestamp by ~450ms.
    // Calibrating by -0.45s keeps the visual sweep and active line in 100% lockstep with the vocals heard by the user.
    const double audioLatencyOffsetSec = 0.45;
    final effectiveSec = math.max(0.0, _currentEffectiveSec - audioLatencyOffsetSec);

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
              Color(0xFF04070D),
              Color(0xFF07101E),
              Color(0xFF0C192E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Clean Minimal Top Navigation: Back Button and Centered Title ONLY
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
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
                            _currentTrack.title,
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
                            _currentTrack.artist,
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
                    const SizedBox(width: 48), // Balances the back button
                  ],
                ),
              ),

              // Lyrics Karaoke Body
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
                      )
                    : _lyrics.isEmpty
                        ? const Center(
                            child: Text(
                              'Lirik belum tersedia untuk lagu ini',
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
                                final itemKey = _lineKeys.putIfAbsent(index, () => GlobalKey());

                                // Instrumental interlude
                                if (line.isInstrumental || line.isInterlude) {
                                  return KeyedSubtree(
                                    key: itemKey,
                                    child: InterludeDots(
                                      line: line,
                                      currentTimeSec: effectiveSec,
                                      isActive: isActive,
                                    ),
                                  );
                                }

                                return Padding(
                                  key: itemKey,
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
                                        fontSize: isActive ? 28 : 22,
                                        fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                                        height: 1.35,
                                        letterSpacing: -0.4,
                                      ),
                                      child: isActive && line.words.isNotEmpty
                                          // Word-by-word with syllable & character fade wipe
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
                                                        ? Colors.white.withAlpha(75)
                                                        : Colors.white.withAlpha(45),
                                                shadows: isActive
                                                    ? const [
                                                        Shadow(
                                                          color: Color(0x993B82F6),
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
                  color: Color(0xFF07101E),
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
                          activeTrackColor: const Color(0xFF3B82F6),
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

/// Instrumental Interlude with 3 pulsing dots
class InterludeDots extends StatelessWidget {
  final LyricLine line;
  final double currentTimeSec;
  final bool isActive;

  const InterludeDots({
    super.key,
    required this.line,
    required this.currentTimeSec,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final dur = math.max(0.5, line.endTime - line.time);
    final progress = ((currentTimeSec - line.time) / dur).clamp(0.0, 1.0);
    final dot1 = progress >= 0.1;
    final dot2 = progress >= 0.45;
    final dot3 = progress >= 0.8;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          _buildDot(dot1),
          const SizedBox(width: 8),
          _buildDot(dot2),
          const SizedBox(width: 8),
          _buildDot(dot3),
        ],
      ),
    );
  }

  Widget _buildDot(bool isFilled) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isFilled && isActive ? 9 : 7,
      height: isFilled && isActive ? 9 : 7,
      decoration: BoxDecoration(
        color: isFilled && isActive ? const Color(0xFF3B82F6) : Colors.white24,
        shape: BoxShape.circle,
        boxShadow: isFilled && isActive
            ? const [BoxShadow(color: Color(0x993B82F6), blurRadius: 10, spreadRadius: 1)]
            : null,
      ),
    );
  }
}

/// Syllable / Word Karaoke Fade-Wipe Widget
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
      child: Transform.translate(
        offset: Offset(0, isActivelySinging ? -1.5 : 0),
        child: isActivelySinging
            ? ShaderMask(
                shaderCallback: (Rect bounds) {
                  final p = progress.clamp(0.0, 1.0);
                  final stopA = (p - 0.06).clamp(0.0, 1.0);
                  final stopB = (p + 0.06).clamp(0.0, 1.0);

                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: const [
                      Color(0xFFFFFFFF),
                      Color(0xFF60A5FA), // Neon electric blue highlight
                      Color(0x40FFFFFF),
                      Color(0x40FFFFFF),
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
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1.35,
                    letterSpacing: -0.4,
                    shadows: [
                      Shadow(
                        color: Color(0xCC3B82F6),
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
                      : Colors.white.withAlpha(70),
                  fontSize: 28,
                  fontWeight: progress >= 1.0 ? FontWeight.w800 : FontWeight.w600,
                  height: 1.35,
                  letterSpacing: -0.4,
                  shadows: progress >= 1.0
                      ? const [
                          Shadow(
                            color: Color(0x4D3B82F6),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
      ),
    );
  }
}
