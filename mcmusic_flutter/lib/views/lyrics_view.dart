import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/audio_quality.dart';
import '../models/lyric_line.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/lyrics_service.dart';
import '../utils/artwork_palette.dart';
import '../widgets/audio_quality_modal.dart';
import '../widgets/optimized_image.dart';

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
  double _syncOffsetSec = 0.0;
  ArtworkColors _palette = ArtworkColors.fallbackDefault;
  String? _lastPaletteUrl;

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
    _syncPalette(_currentTrack.artwork, _currentTrack.title);
    _loadLyrics();

    _lastKnownPlayerSec = widget.player.position.inMilliseconds / 1000.0;
    _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
    _currentEffectiveSec = _lastKnownPlayerSec;

    _ticker = createTicker(_onTick);
    _ticker.start();
  }

  void _syncPalette(String url, String title) {
    if (url == _lastPaletteUrl) return;
    _lastPaletteUrl = url;
    _palette = ArtworkPalette.getCachedOrFallback(url, seed: title);
    ArtworkPalette.extract(url, seed: title).then((pal) {
      if (mounted && _lastPaletteUrl == url) {
        setState(() => _palette = pal);
      }
    });
  }

  void _onPlayerStateChanged() {
    final active = widget.player.currentTrack;
    if (active != null && (active.id != _currentTrack.id || active.title != _currentTrack.title)) {
      if (!mounted) return;
      _syncPalette(active.artwork, active.title);
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

  String _formatDuration(int totalSeconds) {
    final safe = totalSeconds.clamp(0, 35999);
    final mins = safe ~/ 60;
    final secs = safe % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  @override
  Widget build(BuildContext context) {
    // Acoustic output calibration: Physical speaker/earphone audio lags behind internal player timestamp by ~450ms.
    // Calibrating by -0.45s keeps the visual sweep and active line in 100% lockstep with the vocals heard by the user.
    const double audioLatencyOffsetSec = 0.45;
    final effectiveSec = math.max(0.0, _currentEffectiveSec - (audioLatencyOffsetSec + _syncOffsetSec));

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

    final durSec = widget.player.duration.inSeconds > 0
        ? widget.player.duration.inSeconds
        : (_currentTrack.duration > 0 ? _currentTrack.duration : 1);
    final posSec = widget.player.position.inSeconds.clamp(0, durSec);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _palette.primary,
              _palette.secondary.withValues(alpha: 0.72),
              const Color(0xFF0A0C12),
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Modern Spotify / Apple Music Top Header with Cover Art + Lossless Pill + Sync Calibrator
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: OptimizedImage(
                        imageUrl: _currentTrack.artwork,
                        width: 36,
                        height: 36,
                        memCacheWidth: 80,
                        memCacheHeight: 80,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _currentTrack.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (widget.player.audioQuality == AudioQuality.lossless) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)]),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'LOSSLESS',
                                    style: TextStyle(color: Colors.black, fontSize: 8, fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            _currentTrack.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.high_quality_rounded,
                        color: widget.player.audioQuality == AudioQuality.lossless
                            ? const Color(0xFFFBBF24)
                            : Colors.white70,
                        size: 22,
                      ),
                      tooltip: 'Kualitas Audio',
                      onPressed: () => AudioQualityModal.show(context, widget.player),
                    ),
                    IconButton(
                      icon: const Icon(Icons.share_outlined, color: Colors.white70, size: 20),
                      tooltip: 'Salin Lirik',
                      onPressed: () {
                        if (_lyrics.isEmpty) return;
                        final clip = _lyrics.take(8).map((l) => l.text).join('\n');
                        Clipboard.setData(ClipboardData(text: '${_currentTrack.title} - ${_currentTrack.artist}\n\n$clip\n\n— McTify'));
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Cuplikan lirik disalin ke clipboard!'),
                            duration: Duration(milliseconds: 1200),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Compact Timing Calibrator Strip
              if (_lyrics.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _syncOffsetSec = ((_syncOffsetSec - 0.2) * 10).round() / 10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text('-0.2s', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _syncOffsetSec = 0.0),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Text(
                            'Sync ${_syncOffsetSec >= 0 ? '+' : ''}${_syncOffsetSec.toStringAsFixed(1)}s',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _syncOffsetSec = ((_syncOffsetSec + 0.2) * 10).round() / 10),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          child: Text('+0.2s', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
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

              // Frosted Glass Spotify Bottom Player Bar
              Container(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.42),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.10))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3.5,
                        activeTrackColor: Colors.white,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: posSec.toDouble(),
                        max: durSec.toDouble(),
                        onChanged: (val) {
                          widget.player.seek(Duration(seconds: val.round()));
                        },
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatDuration(posSec),
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '-${_formatDuration(durSec - posSec)}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 34),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.player.previous();
                          },
                        ),
                        const SizedBox(width: 18),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            widget.player.togglePlayPause();
                          },
                          child: Container(
                            width: 54,
                            height: 54,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.black,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(width: 18),
                        IconButton(
                          icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 34),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.player.next();
                          },
                        ),
                      ],
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
