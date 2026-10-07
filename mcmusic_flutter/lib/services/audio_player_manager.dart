import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../models/track.dart';
import 'music_api_service.dart';
import 'storage_service.dart';

class AudioPlayerManager extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final StorageService _storageService = StorageService();
  final MusicApiService _apiService = MusicApiService();

  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _queue = [];
  bool _isShuffle = false;
  bool _isRepeat = false;

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => _queue;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _isRepeat;

  AudioPlayerManager() {
    _initAudioListeners();
  }

  void _initAudioListeners() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      notifyListeners();
    });

    int lastNotifiedSec = -1;
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      if (pos.inSeconds != lastNotifiedSec) {
        lastNotifiedSec = pos.inSeconds;
        notifyListeners();
      }

      // Safety auto-advance if within 1 second of end
      if (_duration.inSeconds > 5 && pos.inSeconds >= _duration.inSeconds - 1) {
        if (!_isRepeat) {
          next();
        } else {
          seek(Duration.zero);
          _player.resume();
        }
      }
    });

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      notifyListeners();
    });

    _player.onPlayerComplete.listen((_) {
      if (_isRepeat) {
        seek(Duration.zero);
        _player.resume();
      } else {
        next();
      }
    });
  }

  Future<void> playTrack(Track track, [List<Track>? newQueue]) async {
    _currentTrack = track;
    if (newQueue != null && newQueue.isNotEmpty) {
      _queue = List.from(newQueue);
    } else if (!_queue.any((t) => t.id == track.id)) {
      _queue.insert(0, track);
    }

    _position = Duration.zero;
    _duration = Duration(seconds: track.duration);
    _isPlaying = true;
    notifyListeners();

    // Record play in storage
    _storageService.recordPlay(track);

    try {
      // 1. If audioUrl is iTunes preview or empty, resolve to full YouTube stream
      final isPreview = track.audioUrl.isEmpty ||
          track.audioUrl.contains('itunes.apple.com') ||
          track.audioUrl.contains('AudioPreview');

      if (isPreview) {
        final fullStream = await _apiService.resolveFullAudioStream(track.title, track.artist);
        if (fullStream != null) {
          final updatedTrack = track.copyWith(audioUrl: fullStream);
          if (_currentTrack?.id == track.id) {
            _currentTrack = updatedTrack;
            await _player.stop();
            await _player.play(UrlSource(fullStream));
            return;
          }
        }
      }

      // 2. Play existing stream
      if (track.audioUrl.isNotEmpty) {
        await _player.stop();
        await _player.play(UrlSource(track.audioUrl));
      }
    } catch (e) {
      debugPrint('Playback error: $e');
    }
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) {
      if (_queue.isNotEmpty) {
        await playTrack(_queue.first);
      }
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
    } else {
      await _player.resume();
      _isPlaying = true;
    }
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    _position = pos;
    notifyListeners();
    await _player.seek(pos);
  }

  Future<void> next() async {
    if (_queue.isEmpty || _currentTrack == null) return;

    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);

    if (_isShuffle && _queue.length > 1) {
      int nextIndex;
      do {
        nextIndex = Random().nextInt(_queue.length);
      } while (nextIndex == currentIndex && _queue.length > 1);
      await playTrack(_queue[nextIndex]);
      return;
    }

    if (currentIndex != -1 && currentIndex < _queue.length - 1) {
      await playTrack(_queue[currentIndex + 1]);
    } else if (_queue.isNotEmpty) {
      await playTrack(_queue.first);
    }
  }

  Future<void> previous() async {
    if (_position.inSeconds > 3) {
      await seek(Duration.zero);
      return;
    }
    if (_queue.isEmpty || _currentTrack == null) return;

    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    if (currentIndex > 0) {
      await playTrack(_queue[currentIndex - 1]);
    } else {
      await playTrack(_queue.last);
    }
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    notifyListeners();
  }

  void toggleRepeat() {
    _isRepeat = !_isRepeat;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
