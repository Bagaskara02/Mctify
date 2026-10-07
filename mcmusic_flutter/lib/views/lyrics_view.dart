import 'dart:async';
import 'package:flutter/material.dart';
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

class _LyricsViewState extends State<LyricsView> {
  final LyricsService _lyricsService = LyricsService();
  final ScrollController _scrollController = ScrollController();

  List<LyricLine> _lyrics = [];
  bool _isLoading = true;
  int _activeLineIndex = 0;
  bool _userScrolled = false;
  Timer? _userScrollTimer;
  double _syncOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _loadLyrics();
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
    const itemHeight = 64.0;
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
        final currentSec = (widget.player.position.inMilliseconds / 1000.0) + _syncOffset;

        // Find active line with precision
        int currentActive = -1;
        for (int i = 0; i < _lyrics.length; i++) {
          if (_lyrics[i].time <= currentSec) {
            if (i == _lyrics.length - 1 || _lyrics[i + 1].time > currentSec) {
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
                  Color(0xFF061426),
                  Color(0xFF091726),
                  Color(0xFF10141A),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header Bar with Track Info & Sync Offset
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 28, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Expanded(
                          child: Column(
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
                        // Sync calibration button
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _syncOffset -= 0.5);
                              },
                              tooltip: 'Lirik -0.5s',
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _syncOffset == 0 ? 'Sync' : '${_syncOffset > 0 ? '+' : ''}${_syncOffset.toStringAsFixed(1)}s',
                              style: const TextStyle(color: AppTheme.primaryAzure, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _syncOffset += 0.5);
                              },
                              tooltip: 'Lirik +0.5s',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Lyrics List
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

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: GestureDetector(
                                        onTap: () {
                                          widget.player.seek(Duration(milliseconds: (line.time * 1000).toInt()));
                                        },
                                        child: AnimatedDefaultTextStyle(
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
