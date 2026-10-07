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

  @override
  void initState() {
    super.initState();
    _loadLyrics();
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
    if (!_scrollController.hasClients || index < 0) return;
    const itemHeight = 60.0;
    final target = (index * itemHeight) - 150.0;
    _scrollController.animateTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final currentSec = widget.player.position.inMilliseconds / 1000.0;

        // Find active line
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToActive(_activeLineIndex);
          });
        }

        return Scaffold(
          body: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0A2540),
                  Color(0xFF0F1E2E),
                  Color(0xFF121212),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.keyboard_arrow_down, size: 28, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        Column(
                          children: [
                            Text(
                              widget.track.title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              widget.track.artist,
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),

                  // Lyrics List
                  Expanded(
                    child: _isLoading
                        ? const Center(
                            child: CircularProgressIndicator(color: AppTheme.primaryAzure),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            cacheExtent: 400,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                            itemCount: _lyrics.length,
                            itemBuilder: (context, index) {
                              final line = _lyrics[index];
                              final isActive = index == _activeLineIndex;
                              final isPassed = index < _activeLineIndex;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                child: GestureDetector(
                                  onTap: () {
                                    widget.player.seek(Duration(milliseconds: (line.time * 1000).toInt()));
                                  },
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 250),
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : isPassed
                                              ? Colors.white38
                                              : Colors.white24,
                                      fontSize: isActive ? 26 : 22,
                                      fontWeight: isActive ? FontWeight.w900 : FontWeight.bold,
                                      height: 1.3,
                                      letterSpacing: -0.5,
                                    ),
                                    child: Text(line.text),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Mini Bottom Scrubber (RepaintBoundary to avoid full-screen redraw)
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
