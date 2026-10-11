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

class AudioPlayerManager extends ChangeNotifier with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  final StorageService _storageService = StorageService();
  final MusicApiService _apiService = MusicApiService();
  final MediaAudioHandler? _mediaHandler;
  ytp.YoutubePlayerController? _ytController;

  Track? _currentTrack;
  bool _isPlaying = false;
  bool _userRequestedPause = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _queue = [];
  bool _isShuffle = false;
  bool _isRepeat = false;
  bool _isUsingYoutubeIframe = false;
  bool _isLoadingRecommendations = false;

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
    WidgetsBinding.instance.addObserver(this);
    _initAudioContext();
    _initAudioListeners();
    _initYoutube();
    _initMediaHandlerCallbacks();
    _loadStoredAudioQuality();
  }

  static const String _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_isPlaying && _isUsingYoutubeIframe && !_userRequestedPause && _ytController != null) {
        _setJsUserRequestedPause(false);
        _injectBackgroundPlaybackScripts();
        _ytController?.playVideo();
      }
    }
  }

  void _setJsUserRequestedPause(bool requested) {
    try {
      _ytController?.webViewController.runJavaScript(
        'window.__userRequestedPause = $requested;'
      );
    } catch (_) {}
  }

  Future<void> _injectBackgroundPlaybackScripts() async {
    try {
      final controller = _ytController?.webViewController;
      if (controller == null) return;
      await controller.runJavaScript('''
        (function() {
          window.__userRequestedPause = ${_userRequestedPause ? 'true' : 'false'};

          try {
            Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
            Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
            Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
          } catch(e) {}

          window.addEventListener('blur', function(e) { e.stopImmediatePropagation(); }, true);
          window.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);
          document.addEventListener('visibilitychange', function(e) { e.stopImmediatePropagation(); }, true);

          function attachPlayerListener() {
            if (typeof player !== 'undefined' && player && typeof player.addEventListener === 'function') {
              try {
                player.addEventListener('onStateChange', function(event) {
                  var state = typeof event === 'object' && event !== null ? event.data : event;
                  if (state === 2 && !window.__userRequestedPause) {
                    setTimeout(function() {
                      if (!window.__userRequestedPause && typeof player !== 'undefined' && player) {
                        player.playVideo();
                      }
                    }, 60);
                  }
                });
              } catch(e) {}
            }
          }

          attachPlayerListener();

          if (!window.__mcmusicWatchdog) {
            window.__mcmusicWatchdog = setInterval(function() {
              try {
                attachPlayerListener();
                if (typeof player !== 'undefined' && player && typeof player.getPlayerState === 'function') {
                  var state = player.getPlayerState();
                  if (state === 2 && !window.__userRequestedPause) {
                    player.playVideo();
                  }
                }
              } catch(e) {}
            }, 600);
          }
        })();
      ''');
    } catch (_) {}
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
          playsInline: true,
          userAgent: _desktopUserAgent,
        ),
      );

      _ytController!.listen((value) {
        if (!_isUsingYoutubeIframe) return;
        if (value.playerState == ytp.PlayerState.playing) {
          _isPlaying = true;
          _userRequestedPause = false;
          _setJsUserRequestedPause(false);
          _injectBackgroundPlaybackScripts();
        } else if (value.playerState == ytp.PlayerState.paused) {
          _isPlaying = false;
          if (!_userRequestedPause) {
            // Auto-resume continuous background & screen-off playback
            _setJsUserRequestedPause(false);
            _ytController?.playVideo();
          }
        }
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
        if (!_isUsingYoutubeIframe) return;
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
      if (!_isUsingYoutubeIframe) {
        _isPlaying = state == PlayerState.playing;
        _syncMediaHandler();
        notifyListeners();
      }
    });

    int lastNotifiedMs = -1;
    _player.onPositionChanged.listen((pos) {
      if (!_isUsingYoutubeIframe) {
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
      }
    });

    _player.onDurationChanged.listen((dur) {
      if (!_isUsingYoutubeIframe) {
        _duration = dur;
        if (_currentTrack != null) {
          _mediaHandler?.updateTrack(_currentTrack!, dur);
        }
        _syncMediaHandler();
        notifyListeners();
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (!_isUsingYoutubeIframe) {
        if (_sleepTimerAtTrackEnd) {
          _triggerSleepTimerStop();
        } else if (_isRepeat) {
          seek(Duration.zero);
          _player.resume();
        } else {
          next();
        }
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

  Future<void> playTrackFromSearch(Track track) async {
    // 1. Play clicked track immediately with single-track queue (instant playback)
    await playTrack(track, [track]);

    // 2. Fetch verified tracks by the same artist & related genre in background
    try {
      final artistTracks = await _apiService.searchTracks(track.artist);
      final seen = <String>{track.id, track.title.toLowerCase().trim()};
      final pool = <Track>[];
      final banned = ['karaoke', 'instrumental', 'cover by', 'tribute to', 'parodi', 'parody', 'ringtone', 'sped up', 'slowed', 'reverb', 'remake', 'tutorial'];

      for (final t in artistTracks) {
        final clean = t.title.toLowerCase().trim();
        final isJunk = banned.any((b) => clean.contains(b));
        if (!isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
          seen.add(t.id);
          seen.add(clean);
          pool.add(t);
        }
      }

      // If artist has fewer than 5 tracks, supplement with popular hitmaker peers
      if (pool.length < 5) {
        final peers = ['Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy', 'Mahalini', 'Tulus'];
        peers.shuffle(Random());
        for (final peer in peers.take(2)) {
          final peerTracks = await _apiService.searchTracks(peer);
          for (final t in peerTracks) {
            final clean = t.title.toLowerCase().trim();
            final isJunk = banned.any((b) => clean.contains(b));
            if (!isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
              seen.add(t.id);
              seen.add(clean);
              pool.add(t);
            }
          }
        }
      }

      // Shuffle for randomized hit radio
      pool.shuffle(Random());
      if (pool.isNotEmpty) {
        _queue = [
          if (_currentTrack != null) _currentTrack! else track,
          ...pool,
        ];
        notifyListeners();
      }
    } catch (e) {
      debugPrint('playTrackFromSearch error: $e');
    }
  }

  // TWS & Remote Previous Click Tracker (3x Tap detection)
  DateTime? _lastPreviousActionTime;

  void _prefetchNextTrackStream() {
    if (_queue.isEmpty || _currentTrack == null) return;
    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    if (currentIndex != -1 && currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[currentIndex + 1];
      _apiService.prefetchTrackStream(nextTrack, _audioQuality);
    }
  }

  Future<void> playTrack(Track track, [List<Track>? newQueue]) async {
    // 1. INSTANT UI UPDATE (0ms Perceived Latency):
    // Instantly reflect track title, album, cover, and playing state on UI & Lockscreen
    _currentTrack = track;
    if (newQueue != null && newQueue.isNotEmpty) {
      _queue = List.from(newQueue);
    } else if (!_queue.any((t) => t.id == track.id)) {
      _queue.insert(0, track);
    }

    _position = Duration.zero;
    _duration = Duration(seconds: track.duration > 0 ? track.duration : 180);
    _isPlaying = true;
    _userRequestedPause = false;
    _mediaHandler?.updateTrack(track, _duration);
    _syncMediaHandler();
    notifyListeners(); // Synchronous notification for 0ms lag!

    // Stop previous audio engines immediately
    try {
      await _player.stop();
    } catch (_) {}
    try {
      _ytController?.pauseVideo();
    } catch (_) {}
    _isUsingYoutubeIframe = false;

    // Record play in storage
    _storageService.recordPlay(track);

    // 2. Full Song Playback Resolution (Instant 0ms start, 100% Full Song, continuous background audio)
    try {
      // Step A: Direct Audio URL if explicitly provided (e.g. self-hosted / direct link, not preview and not raw googlevideo)
      if (track.audioUrl.isNotEmpty &&
          !MusicApiService.isPreviewUrl(track.audioUrl) &&
          !track.audioUrl.contains('googlevideo.com')) {
        debugPrint('[AudioPlayerManager] Playing direct audio stream via ExoPlayer');
        await _player.play(UrlSource(track.audioUrl));
        _isPlaying = true;
        _isUsingYoutubeIframe = false;
        _userRequestedPause = false;
        _syncMediaHandler();
        notifyListeners();
        _prefetchNextTrackStream();
        return;
      }

      // Step B: Fast Full Song Playback via YouTube Player Engine (Instant, 0ms delay, Full song)
      String? videoId = track.videoId;
      if (videoId == null || videoId.isEmpty) {
        videoId = await _apiService.resolveVideoId(track.title, track.artist, track.duration);
        if (videoId != null && videoId.isNotEmpty) {
          track = track.copyWith(videoId: videoId);
          _currentTrack = track;
        }
      }

      if (videoId != null && videoId.isNotEmpty && _ytController != null) {
        debugPrint('[AudioPlayerManager] Playing full song via YouTube Engine: videoId=$videoId');
        _isUsingYoutubeIframe = true;
        _isPlaying = true;
        _userRequestedPause = false;
        await _player.stop();
        _ytController!.loadVideoById(videoId: videoId);
        _ytController!.playVideo();
        _setJsUserRequestedPause(false);
        _injectBackgroundPlaybackScripts();
        _syncMediaHandler();
        notifyListeners();
        _prefetchNextTrackStream();
        return;
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

    if (_isUsingYoutubeIframe && _ytController != null) {
      if (_isPlaying) {
        _userRequestedPause = true;
        _setJsUserRequestedPause(true);
        _ytController!.pauseVideo();
        _isPlaying = false;
      } else {
        _userRequestedPause = false;
        _setJsUserRequestedPause(false);
        _ytController!.playVideo();
        _isPlaying = true;
        _injectBackgroundPlaybackScripts();
      }
      _syncMediaHandler();
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      _userRequestedPause = true;
      await _player.pause();
      _isPlaying = false;
    } else {
      _userRequestedPause = false;
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
    final wasPlaying = _isPlaying;
    try {
      if (_isUsingYoutubeIframe && _ytController != null) {
        _ytController!.seekTo(seconds: pos.inSeconds.toDouble(), allowSeekAhead: true);
        if (wasPlaying) {
          _userRequestedPause = false;
          _setJsUserRequestedPause(false);
          _ytController!.playVideo();
          _isPlaying = true;
          _injectBackgroundPlaybackScripts();
        }
      } else {
        await _player.seek(pos);
        if (wasPlaying && _player.state != PlayerState.playing) {
          _userRequestedPause = false;
          await _player.resume();
          _isPlaying = true;
        }
      }
    } catch (e) {
      debugPrint('Seek error: $e');
    }
    _syncMediaHandler();
    notifyListeners();
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
      return;
    }

    // End of playlist reached!
    if (_isRepeat) {
      // Repeat is active, repeat playlist from beginning
      await playTrack(_queue.first);
      return;
    }

    // Dynamic Autoplay / Radio matching playlist vibe!
    await _continueWithPlaylistRecommendations();
  }

  Future<void> _continueWithPlaylistRecommendations() async {
    if (_isLoadingRecommendations) return;
    _isLoadingRecommendations = true;

    try {
      // 1. Gather distinct artists from the current playlist / queue
      final playlistArtists = <String>{};
      for (final t in _queue) {
        final artist = t.artist.split(',')[0].trim();
        if (artist.isNotEmpty) playlistArtists.add(artist);
      }
      if (_currentTrack != null) {
        final curArtist = _currentTrack!.artist.split(',')[0].trim();
        if (curArtist.isNotEmpty) playlistArtists.add(curArtist);
      }

      final artistList = playlistArtists.toList()..shuffle(Random());
      final sampleArtists = artistList.take(3).toList();

      final existingIds = _queue.map((t) => t.id).toSet();
      final existingTitles = _queue.map((t) => t.title.toLowerCase().trim()).toSet();
      final newRecommendations = <Track>[];

      // 2. Search related hit tracks from these artists
      for (final artist in sampleArtists) {
        try {
          final results = await _apiService.searchTracks(artist);
          for (final t in results) {
            final cleanTitle = t.title.toLowerCase().trim();
            if (!existingIds.contains(t.id) &&
                !existingTitles.contains(cleanTitle) &&
                !_isExcludedTrack(cleanTitle)) {
              existingIds.add(t.id);
              existingTitles.add(cleanTitle);
              newRecommendations.add(t);
            }
          }
        } catch (_) {}
      }

      // 3. Supplement with popular hitmaker peers if few
      if (newRecommendations.length < 5) {
        final peers = ['Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy', 'Mahalini', 'Tulus', 'Nadin Amizah', 'Fabio Asher'];
        peers.shuffle(Random());
        for (final peer in peers.take(2)) {
          final results = await _apiService.searchTracks(peer);
          for (final t in results) {
            final cleanTitle = t.title.toLowerCase().trim();
            if (!existingIds.contains(t.id) &&
                !existingTitles.contains(cleanTitle) &&
                !_isExcludedTrack(cleanTitle)) {
              existingIds.add(t.id);
              existingTitles.add(cleanTitle);
              newRecommendations.add(t);
            }
          }
        }
      }

      // 4. Randomize the new recommendations to fit the playlist vibe
      newRecommendations.shuffle(Random());

      if (newRecommendations.isNotEmpty) {
        _queue.addAll(newRecommendations);
        notifyListeners();
        await playTrack(newRecommendations.first);
      } else if (_queue.isNotEmpty) {
        await playTrack(_queue.first);
      }
    } catch (e) {
      debugPrint('Error continuing playlist recommendations: $e');
      if (_queue.isNotEmpty) {
        await playTrack(_queue.first);
      }
    } finally {
      _isLoadingRecommendations = false;
    }
  }

  bool _isExcludedTrack(String title) {
    const banned = [
      'karaoke', 'instrumental', 'cover by', 'tribute to',
      'parodi', 'parody', 'ringtone', 'sped up', 'slowed',
      'reverb', 'remake', 'tutorial'
    ];
    return banned.any((b) => title.contains(b));
  }


  Future<void> previous() async {
    final now = DateTime.now();
    final wasRecentlyRewound = _lastPreviousActionTime != null &&
        now.difference(_lastPreviousActionTime!).inMilliseconds < 2800;

    // Standard Spotify / TWS behavior:
    // If audio is > 3 seconds in and not recently rewound: rewind to 00:00!
    // If audio is <= 3 seconds in, OR if user taps previous AGAIN within 2.8s: skip to previous track!
    if (!wasRecentlyRewound && _position.inSeconds > 3) {
      _lastPreviousActionTime = now;
      await seek(Duration.zero);
      if (!_isPlaying) {
        await togglePlayPause();
      }
      return;
    }

    _lastPreviousActionTime = null;
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
    WidgetsBinding.instance.removeObserver(this);
    _sleepTimer?.cancel();
    _ytController?.close();
    _player.dispose();
    super.dispose();
  }
}
