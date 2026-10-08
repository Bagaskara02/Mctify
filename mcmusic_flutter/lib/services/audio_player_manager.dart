import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ytp;
import '../models/track.dart';
import '../models/audio_quality.dart';
import 'media_audio_handler.dart';
import 'music_api_service.dart';
import 'storage_service.dart';

class AudioPlayerManager extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  final StorageService _storageService = StorageService();
  final MusicApiService _apiService = MusicApiService();
  final MediaAudioHandler? _mediaHandler;
  ytp.YoutubePlayerController? _ytController;

  Track? _currentTrack;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _queue = [];
  bool _isShuffle = false;
  bool _isRepeat = false;

  // Sleep Timer state
  Timer? _sleepTimer;
  int? _sleepTimerRemainingSeconds;
  bool _sleepTimerAtTrackEnd = false;

  // Bitrate / Audio Quality state
  AudioQuality _audioQuality = AudioQuality.high;

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => _queue;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _isRepeat;
  ytp.YoutubePlayerController? get ytController => _ytController;

  // Sleep Timer getters
  int? get sleepTimerRemainingSeconds => _sleepTimerRemainingSeconds;
  bool get isSleepTimerActive => _sleepTimerRemainingSeconds != null || _sleepTimerAtTrackEnd;
  String? get sleepTimerFormatted {
    if (_sleepTimerAtTrackEnd) return 'Akhir Lagu';
    if (_sleepTimerRemainingSeconds != null) {
      final mins = _sleepTimerRemainingSeconds! ~/ 60;
      final secs = _sleepTimerRemainingSeconds! % 60;
      return '$mins:${secs < 10 ? '0' : ''}$secs';
    }
    return null;
  }

  // Audio Quality getter
  AudioQuality get audioQuality => _audioQuality;

  AudioPlayerManager({MediaAudioHandler? mediaHandler}) : _mediaHandler = mediaHandler {
    _initAudioContext();
    _initAudioListeners();
    _initYoutube();
    _initMediaHandlerCallbacks();
    _loadStoredAudioQuality();
  }

  void _initYoutube() {
    try {
      _ytController = ytp.YoutubePlayerController(
        params: const ytp.YoutubePlayerParams(
          showControls: false,
          showFullscreenButton: false,
          mute: false,
          enableCaption: false,
          showVideoAnnotations: false,
        ),
      );

      _ytController!.listen((value) {
        _isPlaying = value.playerState == ytp.PlayerState.playing;
        if (value.metaData.duration > Duration.zero) {
          _duration = value.metaData.duration;
        }
        _syncMediaHandler();
        notifyListeners();

        if (value.playerState == ytp.PlayerState.ended) {
          if (_sleepTimerAtTrackEnd) {
            _triggerSleepTimerStop();
          } else if (_isRepeat) {
            _ytController!.seekTo(seconds: 0);
            _ytController!.playVideo();
          } else {
            next();
          }
        }
      });

      _ytController!.videoStateStream.listen((state) {
        _position = state.position;
        _syncMediaHandler();
        notifyListeners();
      });
    } catch (e) {
      debugPrint('YouTube controller init error: $e');
    }
  }

  void _initAudioContext() {
    try {
      AudioPlayer.global.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: true,
            contentType: AndroidContentType.music,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gain,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {
              AVAudioSessionOptions.defaultToSpeaker,
              AVAudioSessionOptions.mixWithOthers,
            },
          ),
        ),
      );
      _player.setPlayerMode(PlayerMode.mediaPlayer);
      _player.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      debugPrint('AudioContext init note: $e');
    }
  }

  Future<void> _loadStoredAudioQuality() async {
    try {
      final saved = await _storageService.getAudioQuality();
      _audioQuality = AudioQuality.fromString(saved);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setAudioQuality(AudioQuality quality) async {
    _audioQuality = quality;
    notifyListeners();
    await _storageService.setAudioQuality(quality.name);
  }

  void _initMediaHandlerCallbacks() {
    final handler = _mediaHandler;
    if (handler == null) return;
    handler.onPlay = () => togglePlayPause();
    handler.onPause = () => togglePlayPause();
    handler.onSkipToNext = () => next();
    handler.onSkipToPrevious = () => previous();
    handler.onSeekTo = (pos) => seek(pos);
  }

  void _syncMediaHandler() {
    final handler = _mediaHandler;
    if (handler == null) return;
    handler.updatePlaybackState(
      isPlaying: _isPlaying,
      position: _position,
      duration: _duration,
    );
  }

  void _initAudioListeners() {
    _player.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      _syncMediaHandler();
      notifyListeners();
    });

    int lastNotifiedMs = -1;
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      if ((pos.inMilliseconds - lastNotifiedMs).abs() >= 100) {
        lastNotifiedMs = pos.inMilliseconds;
        _syncMediaHandler();
        notifyListeners();
      }

      // Safety auto-advance if within 0.8s of end
      if (_duration.inSeconds > 5 && pos.inSeconds >= _duration.inSeconds - 1) {
        if (_sleepTimerAtTrackEnd) {
          _triggerSleepTimerStop();
        } else if (!_isRepeat) {
          next();
        } else {
          seek(Duration.zero);
          _player.resume();
        }
      }
    });

    _player.onDurationChanged.listen((dur) {
      _duration = dur;
      if (_currentTrack != null) {
        _mediaHandler?.updateTrack(_currentTrack!, dur);
      }
      _syncMediaHandler();
      notifyListeners();
    });

    _player.onPlayerComplete.listen((_) {
      if (_sleepTimerAtTrackEnd) {
        _triggerSleepTimerStop();
      } else if (_isRepeat) {
        seek(Duration.zero);
        _player.resume();
      } else {
        next();
      }
    });
  }

  // --- SLEEP TIMER METHODS ---

  void setSleepTimerMinutes(int minutes) {
    cancelSleepTimer();
    _sleepTimerRemainingSeconds = minutes * 60;
    _sleepTimerAtTrackEnd = false;
    notifyListeners();

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sleepTimerRemainingSeconds != null && _sleepTimerRemainingSeconds! > 0) {
        _sleepTimerRemainingSeconds = _sleepTimerRemainingSeconds! - 1;
        notifyListeners();
      } else {
        _triggerSleepTimerStop();
      }
    });
  }

  void setSleepTimerAtTrackEnd() {
    cancelSleepTimer();
    _sleepTimerAtTrackEnd = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerRemainingSeconds = null;
    _sleepTimerAtTrackEnd = false;
    notifyListeners();
  }

  void _triggerSleepTimerStop() {
    cancelSleepTimer();
    _player.pause();
    _isPlaying = false;
    _syncMediaHandler();
    notifyListeners();
  }

  // --- PLAYBACK METHODS ---

  Future<void> playTrack(Track track, [List<Track>? newQueue]) async {
    _currentTrack = track;
    if (newQueue != null && newQueue.isNotEmpty) {
      _queue = List.from(newQueue);
    } else if (!_queue.any((t) => t.id == track.id)) {
      _queue.insert(0, track);
    }

    _position = Duration.zero;
    _duration = Duration(seconds: track.duration);
    _mediaHandler?.updateTrack(track, _duration);
    _syncMediaHandler();

    // Stop previous audio immediately
    try {
      await _player.stop();
    } catch (_) {}

    // Record play in storage
    _storageService.recordPlay(track);

    try {
      String? videoId = track.videoId;
      if (videoId == null || videoId.isEmpty) {
        videoId = await _apiService.resolveVideoId(track.title, track.artist, track.duration);
      }

      // Play via official YouTube Player Engine (100% full song, 0% 403 errors, official Google embed)
      if (videoId != null && videoId.isNotEmpty) {
        debugPrint('[AudioPlayerManager] Loading videoId=$videoId into official YouTube Player');
        if (_ytController != null) {
          _ytController!.loadVideoById(videoId: videoId);
          _ytController!.playVideo();
          _isPlaying = true;
          _syncMediaHandler();
          notifyListeners();
          return;
        }
      }

      if (track.audioUrl.isNotEmpty) {
        await _player.play(UrlSource(track.audioUrl));
        _isPlaying = true;
      }
    } catch (e) {
      debugPrint('Playback error: $e');
    }

    _syncMediaHandler();
    notifyListeners();
  }

  Future<void> togglePlayPause() async {
    if (_currentTrack == null) {
      if (_queue.isNotEmpty) {
        await playTrack(_queue.first);
      }
      return;
    }

    if (_ytController != null) {
      if (_isPlaying) {
        _ytController!.pauseVideo();
        _isPlaying = false;
      } else {
        _ytController!.playVideo();
        _isPlaying = true;
      }
      _syncMediaHandler();
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      await _player.pause();
      _isPlaying = false;
    } else {
      if (_player.state == PlayerState.paused) {
        await _player.resume();
      } else if (_currentTrack != null) {
        await playTrack(_currentTrack!);
        return;
      }
      _isPlaying = true;
    }
    _syncMediaHandler();
    notifyListeners();
  }

  Future<void> seek(Duration pos) async {
    _position = pos;
    _syncMediaHandler();
    notifyListeners();
    if (_ytController != null) {
      _ytController!.seekTo(seconds: pos.inSeconds.toDouble());
    } else {
      await _player.seek(pos);
    }
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

  // --- QUEUE MANAGEMENT METHODS ---

  void addToNext(Track track) {
    if (_currentTrack == null) {
      playTrack(track);
      return;
    }
    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    if (currentIndex != -1) {
      _queue.insert(currentIndex + 1, track);
    } else {
      _queue.insert(0, track);
    }
    notifyListeners();
  }

  void addToQueue(Track track) {
    if (_currentTrack == null) {
      playTrack(track);
      return;
    }
    _queue.add(track);
    notifyListeners();
  }

  void removeFromQueue(int index) {
    if (index >= 0 && index < _queue.length) {
      _queue.removeAt(index);
      notifyListeners();
    }
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    if (oldIndex >= 0 && oldIndex < _queue.length && newIndex >= 0 && newIndex < _queue.length) {
      final item = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, item);
      notifyListeners();
    }
  }

  void clearQueue() {
    if (_currentTrack != null) {
      _queue = [_currentTrack!];
    } else {
      _queue.clear();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _ytController?.close();
    _player.dispose();
    super.dispose();
  }
}
