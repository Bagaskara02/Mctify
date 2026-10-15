import 'dart:async';
import 'dart:math' as math;
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

  late Track _currentTrack;
  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeLineIndex = 0;
  bool _userScrolled = false;
  Timer? _userScrollTimer;
  double? _manualOffset;
  double _autoOffset = 0.0;
  String _detectedStyle = 'pop';
  String _selectedStyle = 'auto'; // 'auto' | 'pop' | 'ballad' | 'kinetic' | 'chill'

  String get activeStyle => _selectedStyle == 'auto' ? _detectedStyle : _selectedStyle;
  bool get isAutoSync => _manualOffset == null;
  double get effectiveSyncOffset => isAutoSync ? _autoOffset : _manualOffset!;

  // Line keys for exact ensureVisible scrolling
  final Map<int, GlobalKey> _lineKeys = {};

  // 60 FPS Sub-second Interpolation Ticker
  late final Ticker _ticker;
  double _lastKnownPlayerSec = 0.0;
  int _lastKnownTimestampMs = 0;
  double _currentEffectiveSec = 0.0;

  String get _trackKey =>
      '${_currentTrack.artist.trim().toLowerCase()}:::${_currentTrack.title.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _currentTrack = widget.player.currentTrack ?? widget.track;
    widget.player.addListener(_onPlayerStateChanged);
    _loadStoredSyncOffset();
    _loadLyrics();

    _lastKnownPlayerSec = widget.player.position.inMilliseconds / 1000.0;
    _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
    _currentEffectiveSec = _lastKnownPlayerSec + effectiveSyncOffset;

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
        _manualOffset = null;
        _autoOffset = 0.0;
        _detectedStyle = 'pop';
        _lastKnownPlayerSec = 0.0;
        _currentEffectiveSec = 0.0;
        _lastKnownTimestampMs = DateTime.now().millisecondsSinceEpoch;
        _lineKeys.clear();
      });
      _loadStoredSyncOffset();
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

  void _cycleStyle() {
    setState(() {
      if (_selectedStyle == 'auto') {
        _selectedStyle = 'pop';
      } else if (_selectedStyle == 'pop') {
        _selectedStyle = 'ballad';
      } else if (_selectedStyle == 'ballad') {
        _selectedStyle = 'kinetic';
      } else if (_selectedStyle == 'kinetic') {
        _selectedStyle = 'chill';
      } else {
        _selectedStyle = 'auto';
      }
    });
    HapticFeedback.selectionClick();
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
        _autoOffset = result.autoOffset;
        _detectedStyle = result.detectedStyle;
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
      // Anchors active line smoothly at 35% from the top of the viewport
      Scrollable.ensureVisible(
        lineCtx,
        alignment: 0.35,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    } else {
      final viewport = _scrollController.position.viewportDimension;
      const avgItemHeight = 56.0;
      final target = (48.0 + (index * avgItemHeight)) - (viewport * 0.35);
      _scrollController.animateTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String _getStyleLabel(String st) {
    switch (st) {
      case 'ballad':
        return '🌊 Balada';
      case 'kinetic':
        return '🔥 Rap';
      case 'chill':
        return '🌙 Santai';
      case 'pop':
      default:
        return '⚡ Pop';
    }
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
              Color(0xFF04070D),
              Color(0xFF07101E),
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
                            _currentTrack.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  _currentTrack.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              // Song Style Mode Selector Pill
                              GestureDetector(
                                onTap: _cycleStyle,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6).withAlpha(35),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFF3B82F6).withAlpha(80),
                                    ),
                                  ),
                                  child: Text(
                                    _selectedStyle == 'auto'
                                        ? 'AUTO (${_getStyleLabel(_detectedStyle)})'
                                        : _getStyleLabel(_selectedStyle),
                                    style: const TextStyle(
                                      color: Color(0xFF60A5FA),
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Auto Sync & Tuning Pill with -0.5, -0.1, +0.1, +0.5 buttons
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: isAutoSync ? const Color(0xFF0F2231) : const Color(0xFF1F1D14),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isAutoSync
                              ? const Color(0xFF3B82F6).withAlpha(120)
                              : Colors.amberAccent.withAlpha(120),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // -0.5s button
                          InkWell(
                            onTap: () => _updateSyncOffset(-0.5),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Text(
                                '-.5',
                                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          // -0.1s button
                          InkWell(
                            onTap: () => _updateSyncOffset(-0.1),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Icon(Icons.remove, size: 12, color: Colors.white70),
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
                                    const Icon(Icons.bolt, size: 12, color: Color(0xFF60A5FA)),
                                    const SizedBox(width: 2),
                                  ],
                                  Text(
                                    isAutoSync
                                        ? 'AUTO'
                                        : '${effectiveSyncOffset >= 0 ? '+' : ''}${effectiveSyncOffset.toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      color: isAutoSync ? const Color(0xFF60A5FA) : Colors.amberAccent,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: isAutoSync ? 0.4 : 0.0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // +0.1s button
                          InkWell(
                            onTap: () => _updateSyncOffset(0.1),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Icon(Icons.add, size: 12, color: Colors.white70),
                            ),
                          ),
                          // +0.5s button
                          InkWell(
                            onTap: () => _updateSyncOffset(0.5),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                              child: Text(
                                '+.5',
                                style: TextStyle(color: Colors.white60, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          if (!isAutoSync) ...[
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: _resetToAutoSync,
                              child: const Icon(Icons.refresh, size: 12, color: Color(0xFF60A5FA)),
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
                        child: CircularProgressIndicator(color: Color(0xFF3B82F6)),
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
                                final itemKey = _lineKeys.putIfAbsent(index, () => GlobalKey());

                                // Instrumental break / interlude
                                if (line.isInstrumental || line.isInterlude) {
                                  return KeyedSubtree(
                                    key: itemKey,
                                    child: InterludeIndicator(
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
                                        fontSize: isActive ? 27 : 21,
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
                                                  styleMode: activeStyle,
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

/// Instrumental Interlude Indicator with 3 pulsing/filling dots
class InterludeIndicator extends StatelessWidget {
  final LyricLine line;
  final double currentTimeSec;
  final bool isActive;

  const InterludeIndicator({
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
          const Icon(Icons.music_note, color: Color(0xFF3B82F6), size: 18),
          const SizedBox(width: 8),
          Text(
            'MUSIK',
            style: TextStyle(
              color: isActive ? const Color(0xFF60A5FA) : Colors.white24,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              _buildDot(dot1),
              const SizedBox(width: 6),
              _buildDot(dot2),
              const SizedBox(width: 6),
              _buildDot(dot3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDot(bool isFilled) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isFilled && isActive ? 8 : 6,
      height: isFilled && isActive ? 8 : 6,
      decoration: BoxDecoration(
        color: isFilled && isActive ? const Color(0xFF3B82F6) : Colors.white24,
        shape: BoxShape.circle,
        boxShadow: isFilled && isActive
            ? const [BoxShadow(color: Color(0x993B82F6), blurRadius: 8, spreadRadius: 1)]
            : null,
      ),
    );
  }
}

/// Syllable / Word Karaoke Fade-Wipe Widget with adaptive styles
class KaraokeWordWipe extends StatelessWidget {
  final LyricWord word;
  final double currentTimeSec;
  final VoidCallback onTap;
  final String styleMode;

  const KaraokeWordWipe({
    super.key,
    required this.word,
    required this.currentTimeSec,
    required this.onTap,
    this.styleMode = 'pop',
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

    double scale = 1.0;
    double dy = 0.0;
    if (isActivelySinging) {
      if (styleMode == 'pop') {
        scale = 1.06;
        dy = -2.0;
      } else if (styleMode == 'ballad') {
        scale = 1.03;
        dy = -1.0;
      } else if (styleMode == 'kinetic') {
        scale = 1.04;
      } else {
        scale = 1.02;
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Transform.translate(
        offset: Offset(0, dy),
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.centerLeft,
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
                        Color(0x60FFFFFF),
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
                        : Colors.white.withAlpha(85),
                    fontSize: progress >= 1.0 ? 26 : 25,
                    fontWeight: progress >= 1.0 ? FontWeight.w800 : FontWeight.w600,
                    height: 1.35,
                    letterSpacing: -0.4,
                    shadows: progress >= 1.0
                        ? const [
                            Shadow(
                              color: Color(0x663B82F6),
                              blurRadius: 10,
                            ),
                          ]
                        : null,
                  ),
                ),
        ),
      ),
    );
  }
}
