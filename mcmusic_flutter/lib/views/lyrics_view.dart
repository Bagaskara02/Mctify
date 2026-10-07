import 'dart:async';
import 'package:flutter/material.dart';
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

class _LyricsViewState extends State<LyricsView> {
  final LyricsService _lyricsService = LyricsService();
  final StorageService _storageService = StorageService();
  final ScrollController _scrollController = ScrollController();

  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeLineIndex = 0;
  bool _userScrolled = false;
  Timer? _userScrollTimer;
  double _syncOffset = 0.0;

  String get _trackKey =>
      '${widget.track.artist.trim().toLowerCase()}:::${widget.track.title.trim().toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _loadStoredSyncOffset();
    _loadLyrics();
  }

  Future<void> _loadStoredSyncOffset() async {
    final saved = await _storageService.getLyricsSyncOffset(_trackKey);
    if (mounted) {
      setState(() => _syncOffset = saved);
    }
  }

  void _updateSyncOffset(double delta) {
    setState(() {
      _syncOffset = ((_syncOffset + delta) * 10).roundToDouble() / 10.0;
    });
    _storageService.setLyricsSyncOffset(_trackKey, _syncOffset);
  }

  void _resetSyncOffset() {
    setState(() => _syncOffset = 0.0);
    _storageService.setLyricsSyncOffset(_trackKey, 0.0);
  }

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadLyrics() async {
    final lines = await _lyricsService.fetchLyrics(
      widget.track.artist,
      widget.track.title,
      widget.track.duration,
    );
    if (mounted) {
      setState(() {
        _lyrics = lines;
        _isLoading = false;
      });
    }
  }

  void _scrollToActive(int index) {
    if (!_scrollController.hasClients || index < 0 || _userScrolled) return;
    const itemHeight = 72.0;
    final target = (index * itemHeight) - 160.0;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        // Effective time with 120ms vocal-onset anticipation lead
        final effectiveSec =
            (widget.player.position.inMilliseconds / 1000.0) + _syncOffset + 0.12;

        // Find active line with precision
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
                  Color(0xFF040A14),
                  Color(0xFF071220),
                  Color(0xFF0D141E),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header Bar with Track Info & Sync Calibration Controls
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 28, color: Colors.white),
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
                        // Sync calibration tuner badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.timer_outlined, size: 14, color: AppTheme.primaryAzure),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => _updateSyncOffset(-0.1),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Icon(Icons.remove, size: 14, color: Colors.white70),
                                ),
                              ),
                              GestureDetector(
                                onTap: _resetSyncOffset,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: Text(
                                    _syncOffset == 0.0
                                        ? 'Sync'
                                        : '${_syncOffset > 0 ? '+' : ''}${_syncOffset.toStringAsFixed(1)}s',
                                    style: TextStyle(
                                      color: _syncOffset == 0.0
                                          ? AppTheme.primaryAzure
                                          : _syncOffset > 0
                                              ? Colors.amberAccent
                                              : Colors.lightGreenAccent,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _updateSyncOffset(0.1),
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                  child: Icon(Icons.add, size: 14, color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Lyrics List with Word-by-Word Syllable Karaoke
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
                                    _userScrollTimer = Timer(const Duration(milliseconds: 2500), () {
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
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                                  itemCount: _lyrics.length,
                                  itemBuilder: (context, index) {
                                    final line = _lyrics[index];
                                    final isActive = index == _activeLineIndex;
                                    final isPassed = index < _activeLineIndex;

                                    // Instrumental break indicator
                                    if (line.isInstrumental) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.music_note, color: AppTheme.primaryAzure, size: 20),
                                            const SizedBox(width: 8),
                                            Text(
                                              line.text,
                                              style: TextStyle(
                                                color: isActive ? AppTheme.primaryAzure : Colors.white30,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 2.0,
                                              ),
                                            ),
                                            if (isActive) ...[
                                              const SizedBox(width: 8),
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: const BoxDecoration(
                                                  color: AppTheme.primaryAzure,
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryAzure.withValues(alpha: 0.6),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryAzure.withValues(alpha: 0.3),
                                                  shape: BoxShape.circle,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: GestureDetector(
                                        onTap: () {
                                          widget.player.seek(Duration(milliseconds: (line.time * 1000).toInt()));
                                        },
                                        child: isActive && line.words.isNotEmpty
                                            // Word-by-word active karaoke display
                                            ? Wrap(
                                                spacing: 6.0,
                                                runSpacing: 4.0,
                                                children: line.words.map((w) {
                                                  final isWordCurrent =
                                                      effectiveSec >= w.startTime && effectiveSec < w.endTime;
                                                  final isWordFinished = effectiveSec >= w.endTime;

                                                  return GestureDetector(
                                                    onTap: () {
                                                      widget.player.seek(
                                                          Duration(milliseconds: (w.startTime * 1000).toInt()));
                                                    },
                                                    child: Text(
                                                      w.word,
                                                      style: TextStyle(
                                                        color: isWordCurrent
                                                            ? const Color(0xFF00E5FF)
                                                            : isWordFinished
                                                                ? Colors.white
                                                                : Colors.white38,
                                                        fontSize: isWordCurrent ? 27 : 25,
                                                        fontWeight: isWordCurrent
                                                            ? FontWeight.w900
                                                            : isWordFinished
                                                                ? FontWeight.w800
                                                                : FontWeight.w600,
                                                        height: 1.3,
                                                        letterSpacing: -0.4,
                                                        shadows: isWordCurrent
                                                            ? [
                                                                const Shadow(
                                                                  color: Color(0xCC00A3FF),
                                                                  blurRadius: 18,
                                                                )
                                                              ]
                                                            : null,
                                                      ),
                                                    ),
                                                  );
                                                }).toList(),
                                              )
                                            : AnimatedDefaultTextStyle(
                                                duration: const Duration(milliseconds: 200),
                                                style: TextStyle(
                                                  color: isActive
                                                      ? Colors.white
                                                      : isPassed
                                                          ? Colors.white38
                                                          : Colors.white24,
                                                  fontSize: isActive ? 26 : 21,
                                                  fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                                                  height: 1.3,
                                                  letterSpacing: -0.4,
                                                  fontStyle: line.isBackgroundVocal ? FontStyle.italic : FontStyle.normal,
                                                  shadows: isActive
                                                      ? [
                                                          const Shadow(
                                                            color: Color(0x8000A3FF),
                                                            blurRadius: 18,
                                                          )
                                                        ]
                                                      : null,
                                                ),
                                                child: Text(line.text),
                                              ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),

                  // Bottom Mini Player Controls
                  RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              widget.player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: Colors.white,
                              size: 40,
                            ),
                            onPressed: () => widget.player.togglePlayPause(),
                          ),
                          Expanded(
                            child: Slider(
                              value: widget.player.position.inSeconds.toDouble().clamp(
                                    0.0,
                                    widget.player.duration.inSeconds.toDouble(),
                                  ),
                              max: widget.player.duration.inSeconds.toDouble() > 0
                                  ? widget.player.duration.inSeconds.toDouble()
                                  : 1.0,
                              onChanged: (val) {
                                widget.player.seek(Duration(seconds: val.round()));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
