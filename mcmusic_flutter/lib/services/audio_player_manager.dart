import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ytp;
import '../models/track.dart';
import '../models/audio_quality.dart';
import 'equalizer_service.dart';
import 'media_audio_handler.dart';
import 'music_api_service.dart';
import 'storage_service.dart';

class AudioPlayerManager extends ChangeNotifier with WidgetsBindingObserver {
  static const MethodChannel _nativeChannel = MethodChannel('com.mcmusic.app/wakelock');
  final ja.AudioPlayer _player = ja.AudioPlayer(
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    handleInterruptions: true,
  );
  final StorageService _storageService = StorageService();
  final MusicApiService _apiService = MusicApiService();
  final MediaAudioHandler? _mediaHandler;
  ytp.YoutubePlayerController? _ytController;

  Track? _currentTrack;
  bool _isPlaying = false;
  bool _userRequestedPause = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _originalQueue = [];
  List<Track> _queue = [];
  bool _isShuffle = false;
  bool _isRepeat = false;
  bool _isUsingYoutubeIframe = false;
  bool _isAppBackgrounded = false;
  bool _isLoadingRecommendations = false;
  bool _hasPrefetchedNextTrack = false;
  Timer? _backgroundWatchdogTimer;
  Timer? _resumeDebounceTimer;
  Timer? _networkReconnectTimer;
  DateTime? _trackStartTime;
  bool _isRecovering = false;
  int _networkRetryCount = 0;
  bool _isNetworkOnline = true;
  final Set<String> _failedVideoIds = <String>{};

  // Sleep Timer state
  Timer? _sleepTimer;
  int? _sleepTimerRemainingSeconds;
  bool _sleepTimerAtTrackEnd = false;

  // Bitrate / Audio Quality state
  AudioQuality _audioQuality = AudioQuality.high;

  // Playback Speed state
  double _playbackSpeed = 1.0;
  double get playbackSpeed => _playbackSpeed;

  Future<void> setPlaybackSpeed(double speed) async {
    _playbackSpeed = speed;
    try {
      if (_isUsingYoutubeIframe && _ytController != null) {
        _ytController!.setPlaybackRate(speed);
      } else {
        await _player.setSpeed(speed);
      }
    } catch (e) {
      debugPrint('Error setting playback speed: $e');
    }
    notifyListeners();
  }

  Track? get currentTrack => _currentTrack;
  bool get isPlaying => _isPlaying;
  Duration get position => _position;
  Duration get duration => _duration;
  List<Track> get queue => _queue;
  bool get isShuffle => _isShuffle;
  bool get isRepeat => _isRepeat;
  bool get isNetworkOnline => _isNetworkOnline;
  bool get isAppBackgrounded => _isAppBackgrounded;
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
    _initNativeChannelListeners();
    _initAudioContext();
    _initAudioListeners();
    _initYoutube();
    _initMediaHandlerCallbacks();
    _loadStoredAudioQuality();
    // Pre-warm and apply stored Equalizer preset & DSP effects on startup
    EqualizerService.instance;
  }

  void _initNativeChannelListeners() {
    _nativeChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNetworkAvailable':
        case 'onNetworkValidated':
          _handleNetworkReconnected();
          break;
        case 'onNetworkLost':
          _handleNetworkLost();
          break;
      }
    });
  }

  void _handleNetworkLost() {
    debugPrint('[AudioPlayerManager] Native network lost (switching WiFi <-> Mobile Data)...');
    _isNetworkOnline = false;
  }

  void _handleNetworkReconnected() {
    debugPrint('[AudioPlayerManager] Native network validated! Restoring active audio stream...');
    _isNetworkOnline = true;
    _networkRetryCount = 0;

    _networkReconnectTimer?.cancel();
    _networkReconnectTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_userRequestedPause && _currentTrack != null) {
        _acquireNativeLocks();
        if (_isUsingYoutubeIframe && _ytController != null) {
          final curVid = _currentTrack?.videoId;
          if (curVid != null && curVid.isNotEmpty) {
            final playerState = _ytController?.value.playerState;
            if (playerState != ytp.PlayerState.playing) {
              debugPrint('[AudioPlayerManager] Network restored: re-triggering playback at ${_position.inSeconds}s');
              final posSec = _position.inSeconds.toDouble();
              _ytController?.seekTo(seconds: posSec, allowSeekAhead: true);
              _ytController?.playVideo();
              _injectBackgroundPlaybackScripts();
            }
          }
        } else {
          if (!_player.playing) {
            _player.play();
          }
        }
      }
    });
  }

  Future<void> _acquireNativeLocks() async {
    try {
      await _nativeChannel.invokeMethod('acquireLocks');
    } catch (_) {}
  }

  Future<void> _releaseNativeLocks() async {
    try {
      await _nativeChannel.invokeMethod('releaseLocks');
    } catch (_) {}
  }

  void _scheduleBackgroundResume() {
    _resumeDebounceTimer?.cancel();
    _resumeDebounceTimer = Timer(const Duration(milliseconds: 40), () {
      if (!_userRequestedPause && _currentTrack != null && _isUsingYoutubeIframe) {
        debugPrint('[AudioPlayerManager] Auto-resume triggering...');
        _acquireNativeLocks();
        _setJsUserRequestedPause(false);
        _injectBackgroundPlaybackScripts();
        _ytController?.playVideo();
      }
    });
  }

  void _startWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _trackStartTime = DateTime.now().subtract(_position);

    _backgroundWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_userRequestedPause && _currentTrack != null && _isNetworkOnline) {
        if (_isUsingYoutubeIframe && _ytController != null) {
          final playerState = _ytController?.value.playerState;

          // 1. Resume if unexpectedly paused by OS while screen is off
          if (playerState == ytp.PlayerState.paused) {
            debugPrint('[AudioPlayerManager] Watchdog: unexpected pause detected, auto-resuming...');
            _acquireNativeLocks();
            _setJsUserRequestedPause(false);
            _injectBackgroundPlaybackScripts();
            _ytController?.playVideo();
            return;
          }

          // 2. Safe Wall-clock track completion detector:
          // CRITICAL: NEVER cut off or advance a song while it is actively playing!
          if (playerState == ytp.PlayerState.playing) {
            // Song is actively playing! User is vibing! NEVER interrupt!
            return;
          }

          if (_duration > Duration.zero && _duration.inSeconds > 10) {
            final now = DateTime.now();
            final elapsed = now.difference(_trackStartTime ?? now);
            // Must have exceeded full duration AND be stalled near the end
            if (elapsed.inSeconds >= _duration.inSeconds + 15 &&
                _position >= _duration - const Duration(seconds: 5)) {
              debugPrint('[AudioPlayerManager] Watchdog: track finished near end (${elapsed.inSeconds}s / ${_duration.inSeconds}s). Advancing...');
              _trackStartTime = DateTime.now();
              if (_sleepTimerAtTrackEnd) {
                _triggerSleepTimerStop();
              } else if (_isRepeat) {
                _ytController?.seekTo(seconds: 0);
                _ytController?.playVideo();
              } else {
                next();
              }
              return;
            }
          }
        } else {
          // Native ExoPlayer check
          if (!_player.playing && !_userRequestedPause && _player.processingState != ja.ProcessingState.completed) {
            debugPrint('[AudioPlayerManager] Watchdog: native player paused unexpectedly, auto-resuming...');
            _acquireNativeLocks();
            _player.play();
          } else if (_duration > Duration.zero && _duration.inSeconds > 10) {
            final now = DateTime.now();
            final elapsed = now.difference(_trackStartTime ?? now);
            if (elapsed.inSeconds >= _duration.inSeconds + 15 &&
                _position >= _duration - const Duration(seconds: 5)) {
              debugPrint('[AudioPlayerManager] Watchdog: native player finished near end. Advancing...');
              _trackStartTime = DateTime.now();
              if (_sleepTimerAtTrackEnd) {
                _triggerSleepTimerStop();
              } else if (_isRepeat) {
                seek(Duration.zero);
                _player.play();
              } else {
                next();
              }
              return;
            }
          }
        }
      }
    });
  }

  void _stopWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _backgroundWatchdogTimer = null;
    _resumeDebounceTimer?.cancel();
    _resumeDebounceTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _isAppBackgrounded = true;
      if (!_userRequestedPause && _isPlaying) {
        _acquireNativeLocks();
        if (_isUsingYoutubeIframe) {
          _injectBackgroundPlaybackScripts();
          _ytController?.playVideo();
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      _isAppBackgrounded = false;
      if (!_userRequestedPause && _isPlaying) {
        _acquireNativeLocks();
        if (_isUsingYoutubeIframe) {
          _injectBackgroundPlaybackScripts();
        }
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

  void _setJsLoadingTrack(bool loading) {
    try {
      _ytController?.webViewController.runJavaScript(
        'window.__isLoadingTrack = $loading;'
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

          // 1. Thermal & Battery optimization: ensure lightweight video decoding
          try {
            if (typeof player !== 'undefined' && player && typeof player.setPlaybackQuality === 'function') {
              player.setPlaybackQuality('small');
            }
          } catch(e) {}

          // 2. Spoof visibility properties & block blur/pagehide/visibilitychange pause triggers
          if (!window.__visibilityPatched) {
            window.__visibilityPatched = true;
            try {
              Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
              Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
              Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
            } catch(e) {}

            try {
              Document.prototype.hasFocus = function() { return true; };
            } catch(e) {}

            window.addEventListener('visibilitychange', function(e) {
              e.stopImmediatePropagation();
            }, true);
            document.addEventListener('visibilitychange', function(e) {
              e.stopImmediatePropagation();
            }, true);
            window.addEventListener('pagehide', function(e) {
              e.stopImmediatePropagation();
            }, true);
            window.addEventListener('blur', function(e) {
              e.stopImmediatePropagation();
            }, true);
          }

          // 3. Intercept HTMLMediaElement.prototype.pause (Zero Jeda on Screen Off / Background!)
          // If the pause was not explicitly requested by user in McMusic, completely drop the pause call.
          if (!window.__pausePatched) {
            window.__pausePatched = true;
            try {
              var origPause = HTMLMediaElement.prototype.pause;
              HTMLMediaElement.prototype.pause = function() {
                if (window.__userRequestedPause) {
                  return origPause.apply(this, arguments);
                }
                // Dropped unsolicited pause from OS screen off or Chromium visibility change
                return;
              };
            } catch(e) {}
          }

          // 4. Instant auto-resume on unexpected media pause
          function protectVideo(v) {
            if (!v || v.__bgProtected) return;
            v.__bgProtected = true;

            try {
              v.removeAttribute('disableRemotePlayback');
            } catch(e) {}

            v.addEventListener('pause', function(e) {
              if (v.ended || (v.duration && v.currentTime >= v.duration - 0.5)) return;
              if (!window.__userRequestedPause && !window.__isLoadingTrack) {
                e.stopImmediatePropagation();
                try {
                  var p = v.play();
                  if (p && typeof p.catch === 'function') p.catch(function(){});
                } catch(_) {}
              }
            }, true);
          }

          try {
            document.querySelectorAll('video').forEach(protectVideo);
          } catch(e) {}

          if (!window.__videoObserver && window.MutationObserver) {
            try {
              window.__videoObserver = new MutationObserver(function() {
                document.querySelectorAll('video').forEach(protectVideo);
              });
              window.__videoObserver.observe(document.documentElement, { childList: true, subtree: true });
            } catch(e) {}
          }

          // 4. Auto-recover immediately on network handover (WiFi <-> Cellular)
          if (!window.__networkHooked) {
            window.__networkHooked = true;
            window.addEventListener('online', function() {
              console.log('[McMusic] WebView online event detected');
              if (!window.__userRequestedPause) {
                setTimeout(function() {
                  try {
                    if (typeof player !== 'undefined' && player) {
                      var cur = player.getCurrentTime() || 0;
                      player.seekTo(cur, true);
                      player.playVideo();
                    }
                  } catch(_) {}
                }, 400);
              }
            });
          }
        })();
      ''');
    } catch (_) {}
  }

  void _initYoutube() {
    try {
      const params = ytp.YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        mute: false,
        enableCaption: false,
        showVideoAnnotations: false,
        playsInline: true,
      );

      _ytController = ytp.YoutubePlayerController(
        params: params,
      );
      _ytController!.initWithParams(params: params);

      _ytController!.listen((value) {
        if (!_isUsingYoutubeIframe) return;

        // Failsafe recovery if video is unplayable or embed restricted
        if (value.hasError) {
          debugPrint('[AudioPlayerManager] YouTube Iframe Error: ${value.error} for "${_currentTrack?.title}"');
          _handlePlaybackNetworkError(_currentTrack, 'Iframe error: ${value.error}');
          return;
        }

        if (value.playerState == ytp.PlayerState.playing) {
          _networkRetryCount = 0;
          _isPlaying = true;
          _userRequestedPause = false;
          _setJsLoadingTrack(false);
          _acquireNativeLocks();
          _setJsUserRequestedPause(false);
          _injectBackgroundPlaybackScripts();
          _startWatchdog();
        } else if (value.playerState == ytp.PlayerState.paused) {
          if (_userRequestedPause) {
            _isPlaying = false;
          } else if (!_userRequestedPause && _currentTrack != null) {
            // Unsolicited pause (e.g. OS screen off): resume IMMEDIATELY with 0ms delay!
            _acquireNativeLocks();
            _setJsUserRequestedPause(false);
            _injectBackgroundPlaybackScripts();
            _ytController?.playVideo();
          }
        } else if (value.playerState == ytp.PlayerState.cued) {
          if (!_userRequestedPause && _currentTrack != null) {
            _scheduleBackgroundResume();
          }
        }

        if (value.metaData.duration > Duration.zero) {
          _duration = value.metaData.duration;
        }
        _syncMediaHandler();
        notifyListeners();

        if (value.playerState == ytp.PlayerState.ended) {
          debugPrint('[AudioPlayerManager] YouTube Player: track ended naturally!');
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

        // Gapless Pre-fetch: pre-cache next track 25 seconds before current song ends
        if (_duration.inSeconds > 25 &&
            state.position.inSeconds >= _duration.inSeconds - 25 &&
            !_hasPrefetchedNextTrack) {
          _hasPrefetchedNextTrack = true;
          _prefetchNextTrackStream();
        }
      });
    } catch (e) {
      debugPrint('YouTube controller init error: $e');
    }
  }

  Future<void> _handlePlaybackNetworkError(Track? track, String reason) async {
    if (track == null || _isRecovering) return;
    if (!_isNetworkOnline) {
      debugPrint('[AudioPlayerManager] Playback error during network switch (offline). Retaining current song and waiting for reconnection...');
      return;
    }

    // 1. If error happens during network handover (WiFi <-> Cellular), RETRY the same video at current position first!
    if (_networkRetryCount < 3) {
      _networkRetryCount++;
      debugPrint('[AudioPlayerManager] Temporary network/playback blip (attempt $_networkRetryCount of 3). Retrying "${track.title}" at ${_position.inSeconds}s...');
      await Future.delayed(const Duration(milliseconds: 1200));

      if (!_userRequestedPause && _currentTrack?.id == track.id) {
        if (!_isUsingYoutubeIframe) {
          try {
            debugPrint('[AudioPlayerManager] Retrying native ExoPlayer at ${_position.inSeconds}s...');
            await _player.seek(_position);
            await _player.play();
            return;
          } catch (_) {}
        } else {
          final currentVid = track.videoId;
          if (currentVid != null && currentVid.isNotEmpty && _ytController != null) {
            try {
              _ytController?.seekTo(seconds: _position.inSeconds.toDouble(), allowSeekAhead: true);
              _ytController?.playVideo();
              _injectBackgroundPlaybackScripts();
              return;
            } catch (_) {}
          }
        }
      }
    }

    // 2. Only if 3 retries completely fail while online, escalate to alternative video resolution
    _networkRetryCount = 0;
    _handlePlaybackFailure(track, reason);
  }

  Future<void> _handlePlaybackFailure(Track? track, String reason) async {
    if (track == null || _isRecovering) return;
    if (!_isNetworkOnline) {
      debugPrint('[AudioPlayerManager] Playback failure while offline. Retaining current track.');
      return;
    }
    _isRecovering = true;
    debugPrint('[AudioPlayerManager] Failsafe recovery triggered ($reason) for: "${track.title}"');

    try {
      final currentVid = track.videoId;
      if (currentVid != null && currentVid.isNotEmpty) {
        _failedVideoIds.add(currentVid);
        _apiService.invalidateVideoId(track.title, track.artist, currentVid);
      }

      // 1. Try alternative candidate direct audio stream for Native ExoPlayer murni
      final altStream = await _apiService.resolveDirectAudioStream(
        track,
        _audioQuality,
        _failedVideoIds,
      );

      if (altStream != null && altStream.isNotEmpty && !MusicApiService.isPreviewUrl(altStream)) {
        debugPrint('[AudioPlayerManager] Recovery: alternative native ExoPlayer stream resolved for "${track.title}"');
        _isUsingYoutubeIframe = false;
        _isPlaying = true;
        _userRequestedPause = false;
        try {
          _ytController?.pauseVideo();
        } catch (_) {}
        await _player.stop();
        final audioSource = ja.AudioSource.uri(
          Uri.parse(altStream),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
            'Range': 'bytes=0-',
          },
        );
        await _player.setAudioSource(audioSource);
        await _player.play();
        if (_position > Duration.zero) {
          try {
            await _player.seek(_position);
          } catch (_) {}
        }
        _acquireNativeLocks();
        _startWatchdog();
        _syncMediaHandler();
        notifyListeners();
        _isRecovering = false;
        return;
      }

      // 2. Fallback to alternative YouTube video ID if native stream resolution fails
      final altVideoId = await _apiService.resolveVideoId(
        track.title,
        track.artist,
        track.duration,
        _failedVideoIds,
      );

      if (altVideoId != null && altVideoId.isNotEmpty && !_failedVideoIds.contains(altVideoId)) {
        debugPrint('[AudioPlayerManager] Recovery: alternative videoId resolved ($altVideoId) for "${track.title}"');
        _currentTrack = track.copyWith(videoId: altVideoId);
        _isUsingYoutubeIframe = true;
        _isPlaying = true;
        _userRequestedPause = false;
        try {
          await _player.stop();
        } catch (_) {}
        _ytController?.loadVideoById(videoId: altVideoId);
        _ytController?.playVideo();
        _injectBackgroundPlaybackScripts();
        _acquireNativeLocks();
        _startWatchdog();
        _syncMediaHandler();
        notifyListeners();
        _isRecovering = false;
        return;
      }

      // 2. If all sources failed for this track, auto-advance to next song gracefully
      debugPrint('[AudioPlayerManager] Recovery: all sources exhausted for "${track.title}". Auto-advancing...');
      _isRecovering = false;
      if (_queue.length > 1) {
        await next();
      } else {
        _isPlaying = false;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[AudioPlayerManager] Error during recovery: $e');
      _isRecovering = false;
    }
  }

  void _initAudioContext() {
    try {
      _player.setVolume(1.0);
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
    if (_audioQuality == quality) return;
    _audioQuality = quality;
    MusicApiService.clearStreamCache();
    notifyListeners();
    await _storageService.setAudioQuality(quality.name);
  }

  /// Pre-warms initial catalog tracks silently in background for instant first-tap playback
  void prewarmTracks(List<Track> tracks) {
    if (tracks.isEmpty) return;
    _apiService.prewarmTracks(tracks, quality: _audioQuality, limit: 3);
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
    _player.playerStateStream.listen((state) {
      if (!_isUsingYoutubeIframe) {
        _isPlaying = state.playing;
        _syncMediaHandler();
        notifyListeners();

        if (state.processingState == ja.ProcessingState.completed) {
          debugPrint('[AudioPlayerManager] onPlayerComplete: Track finished naturally!');
          if (_sleepTimerAtTrackEnd) {
            _triggerSleepTimerStop();
          } else if (_isRepeat) {
            seek(Duration.zero);
            _player.play();
          } else {
            next();
          }
        }
      }
    });

    int lastNotifiedMs = -1;
    _player.positionStream.listen((pos) {
      if (!_isUsingYoutubeIframe) {
        _position = pos;
        if ((pos.inMilliseconds - lastNotifiedMs).abs() >= 250) {
          lastNotifiedMs = pos.inMilliseconds;
          _syncMediaHandler();
          notifyListeners();
        }

        // Gapless Pre-fetch
        if (_duration.inSeconds > 25 &&
            pos.inSeconds >= _duration.inSeconds - 25 &&
            !_hasPrefetchedNextTrack) {
          _hasPrefetchedNextTrack = true;
          _prefetchNextTrackStream();
        }
      }
    });

    _player.durationStream.listen((dur) {
      if (!_isUsingYoutubeIframe && dur != null) {
        _duration = dur;
        if (_currentTrack != null) {
          _mediaHandler?.updateTrack(_currentTrack!, dur);
        }
        _syncMediaHandler();
        notifyListeners();
      }
    });

    _player.bufferedPositionStream.listen((buffered) {
      if (!_isUsingYoutubeIframe) {
        _mediaHandler?.updateBufferedPosition(buffered);
      }
    });

    _player.playbackEventStream.listen((event) {
      // Event stream monitoring
    }, onError: (err) {
      debugPrint('[AudioPlayerManager] Native ExoPlayer stream error: $err');
      if (!_isUsingYoutubeIframe && _currentTrack != null) {
        _handlePlaybackNetworkError(_currentTrack, 'Native stream error: $err');
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
    _userRequestedPause = true;
    _stopWatchdog();
    _releaseNativeLocks();
    if (_isUsingYoutubeIframe) {
      _setJsUserRequestedPause(true);
      _ytController?.pauseVideo();
    } else {
      _player.pause();
    }
    _isPlaying = false;
    _syncMediaHandler();
    notifyListeners();
  }

  // --- PLAYBACK METHODS ---

  Future<void> playTrackFromSearch(Track track) async {
    // 1. Play clicked track immediately with single-track queue (instant playback)
    await playTrack(track, [track]);

    // 2. Fetch verified top popular tracks by the same artist & related genre in background
    try {
      final seen = <String>{track.id, track.title.toLowerCase().trim()};
      const banned = [
        'karaoke', 'instrumental', 'cover by', 'tribute to', 'parodi', 'parody',
        'ringtone', 'sped up', 'slowed', 'reverb', 'remake', 'tutorial', 'acapella'
      ];

      // Identify peer hitmakers dynamically based on artist, genre, title, and queue
      final artLower = track.artist.toLowerCase();
      final targetRegion = MusicApiService.detectTrackRegion(track.artist, track.title, track.genre);
      final peerArtists = _apiService.getSimilarArtists(
        track.artist,
        genre: track.genre,
        playlistArtists: _queue.map((t) => t.artist).toList(),
        title: track.title,
      );
      // Select 5-6 random peers each time from the pool for infinite non-template variety
      final activePeers = (List<String>.from(peerArtists)..shuffle())
          .where((p) => !artLower.contains(p.toLowerCase()))
          .take(6)
          .toList();

      // Query user's liked and frequently played tracks (strictly respecting target region!)
      final userLikedTracks = <Track>[];
      try {
        final liked = await _storageService.getLikedTracks();
        for (final t in liked) {
          final clean = t.title.toLowerCase().trim();
          final itemRegion = MusicApiService.detectTrackRegion(t.artist, t.title, t.genre);
          if (itemRegion != targetRegion) continue;

          final tArt = t.artist.toLowerCase();
          final isMatch = tArt.contains(artLower) ||
              artLower.contains(tArt) ||
              activePeers.any((p) => tArt.contains(p.toLowerCase()));
          final isJunk = banned.any((b) => clean.contains(b));
          if (isMatch && !isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
            seen.add(t.id);
            seen.add(clean);
            userLikedTracks.add(t);
          }
        }
      } catch (_) {}

      // Parallel search for artist top hits and peer top hits
      final searchFutures = <Future<List<Track>>>[
        _apiService.searchTracks(track.artist),
        ...activePeers.map((p) => _apiService.searchTracks(p)),
      ];
      final searchResults = await Future.wait(searchFutures);

      // Collect artist songs and randomly sample 2-3 different hits each time
      final cleanArtistHits = <Track>[];
      if (searchResults.isNotEmpty) {
        for (final t in searchResults[0]) {
          final clean = t.title.toLowerCase().trim();
          final isJunk = banned.any((b) => clean.contains(b));
          if (!isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
            seen.add(t.id);
            seen.add(clean);
            cleanArtistHits.add(t);
          }
        }
      }
      final sampledArtistHits = (List<Track>.from(cleanArtistHits)..shuffle()).take(3).toList();

      // Collect peer songs and randomly sample 1-2 different hits per peer
      final sampledPeerHits = <Track>[];
      for (int i = 1; i < searchResults.length; i++) {
        final peerList = <Track>[];
        for (final t in searchResults[i]) {
          final clean = t.title.toLowerCase().trim();
          final songRegion = MusicApiService.detectTrackRegion(t.artist, t.title, t.genre);
          final isJunk = banned.any((b) => clean.contains(b));
          if (songRegion == targetRegion && !isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
            seen.add(t.id);
            seen.add(clean);
            peerList.add(t);
          }
        }
        final peerSample = (peerList..shuffle()).take(2);
        sampledPeerHits.addAll(peerSample);
      }
      sampledPeerHits.shuffle();

      // Combine artist hits and peer hits
      final combinedCandidates = [...sampledArtistHits, ...sampledPeerHits];

      // Anti-template memory filter: filter out tracks played recently in this session
      final freshCandidates = combinedCandidates.where((t) {
        return !MusicApiService.recentRadioHistory.contains(t.title.toLowerCase().trim());
      }).toList();

      final poolToSpread = freshCandidates.length >= 10 ? freshCandidates : combinedCandidates;
      if (poolToSpread == combinedCandidates) {
        MusicApiService.recentRadioHistory.clear();
      }

      // Apply Yugen-inspired Round-Robin spread across artists
      final spreadTracks = MusicApiService.spreadArtists(poolToSpread, maxPerArtist: 2);

      // Balanced Interleaved Queue: Dynamic, fresh, and zero static template!
      final structuredQueue = <Track>[];
      int userIdx = 0;
      int spreadIdx = 0;

      while (structuredQueue.length < 18 &&
          (userIdx < userLikedTracks.length || spreadIdx < spreadTracks.length)) {
        if (userIdx < userLikedTracks.length && (structuredQueue.isEmpty || structuredQueue.length % 4 == 0)) {
          structuredQueue.add(userLikedTracks[userIdx++]);
        }
        if (spreadIdx < spreadTracks.length && structuredQueue.length < 18) {
          structuredQueue.add(spreadTracks[spreadIdx++]);
        }
        if (spreadIdx >= spreadTracks.length && userIdx < userLikedTracks.length && structuredQueue.length < 18) {
          structuredQueue.add(userLikedTracks[userIdx++]);
        }
      }

      // Record selected tracks in session memory
      for (final t in structuredQueue) {
        MusicApiService.recordRecentRadioTrack(t.title);
      }
      if (structuredQueue.isNotEmpty) {
        final anchor = _currentTrack ?? track;
        _originalQueue = [anchor, ...structuredQueue];
        _queue = _isShuffle
            ? buildSpotifyShuffleDeck(_originalQueue, anchor)
            : List.from(_originalQueue);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('playTrackFromSearch error: $e');
    }
  }

  // TWS & Remote Previous Click Tracker (3x Tap detection)
  DateTime? _lastPreviousActionTime;

  void _prefetchNextTrackStream() async {
    if (_queue.isEmpty || _currentTrack == null) return;
    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    if (currentIndex != -1 && currentIndex + 1 < _queue.length) {
      final nextTrack = _queue[currentIndex + 1];
      try {
        await _apiService.prefetchTrackStream(nextTrack, _audioQuality);
        debugPrint('[AudioPlayerManager] Next track "${nextTrack.title}" stream pre-cached for instant playback');
      } catch (e) {
        debugPrint('[AudioPlayerManager] Prefetch next track stream error: $e');
      }
    }
  }

  Future<void> playTrack(Track track, [List<Track>? newQueue]) async {
    // 1. INSTANT UI UPDATE (0ms Perceived Latency):
    // Instantly reflect track title, album, cover, and playing state on UI & Lockscreen
    _currentTrack = track;
    if (newQueue != null && newQueue.isNotEmpty) {
      _originalQueue = List.from(newQueue);
      _queue = _isShuffle
          ? buildSpotifyShuffleDeck(_originalQueue, track)
          : List.from(_originalQueue);
    } else if (!_queue.any((t) => t.id == track.id)) {
      _originalQueue.insert(0, track);
      _queue.insert(0, track);
    }

    _position = Duration.zero;
    _duration = Duration(seconds: track.duration > 0 ? track.duration : 180);
    _isPlaying = true;
    _userRequestedPause = false;
    _hasPrefetchedNextTrack = false;
    _trackStartTime = DateTime.now();
    _mediaHandler?.updateTrack(track, _duration);
    _syncMediaHandler();
    _acquireNativeLocks();
    _startWatchdog();
    notifyListeners(); // Synchronous notification for 0ms lag!

    // Record play in storage
    _storageService.recordPlay(track);

    // 2. Full Song Playback Resolution
    try {
      // Step A: Direct Audio URL if explicitly provided (e.g. self-hosted / direct link, not preview and not raw googlevideo)
      if (track.audioUrl.isNotEmpty &&
          !MusicApiService.isPreviewUrl(track.audioUrl) &&
          !track.audioUrl.contains('googlevideo.com')) {
        debugPrint('[AudioPlayerManager] Playing direct audio stream via Native ExoPlayer');
        try {
          _ytController?.pauseVideo();
        } catch (_) {}
        _isUsingYoutubeIframe = false;
        await _player.stop();
        final audioSource = ja.AudioSource.uri(
          Uri.parse(track.audioUrl),
          headers: const {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept': '*/*',
          },
        );
        await _player.setAudioSource(audioSource);
        await _player.play();
        if (_playbackSpeed != 1.0) {
          try {
            await _player.setSpeed(_playbackSpeed);
          } catch (_) {}
        }
        _isPlaying = true;
        _userRequestedPause = false;
        _acquireNativeLocks();
        _startWatchdog();
        _syncMediaHandler();
        notifyListeners();
        _prefetchNextTrackStream();
        return;
      }

      // Step B: Native ExoPlayer Murni (Full-length 3-5+ min AAC audio stream, 100% free, zero screen-off lag)
      try {
        final directStreamUrl = await _apiService.resolveDirectAudioStream(
          track,
          _audioQuality,
          _failedVideoIds,
        );

        if (directStreamUrl != null &&
            directStreamUrl.isNotEmpty &&
            !MusicApiService.isPreviewUrl(directStreamUrl)) {
          debugPrint('[AudioPlayerManager] Playing full song via Native ExoPlayer murni: "${track.title}"');
          try {
            _ytController?.pauseVideo();
          } catch (_) {}
          _isUsingYoutubeIframe = false;
          await _player.stop();
          final audioSource = ja.AudioSource.uri(
            Uri.parse(directStreamUrl),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept': '*/*',
              'Range': 'bytes=0-',
            },
          );
          await _player.setAudioSource(audioSource);
          await _player.play();
          if (_playbackSpeed != 1.0) {
            try {
              await _player.setSpeed(_playbackSpeed);
            } catch (_) {}
          }
          _isPlaying = true;
          _userRequestedPause = false;
          _acquireNativeLocks();
          _startWatchdog();
          _syncMediaHandler();
          notifyListeners();
          _prefetchNextTrackStream();
          return;
        }
      } catch (streamErr) {
        debugPrint('[AudioPlayerManager] Native ExoPlayer stream resolution error: $streamErr. Falling back to YouTube Engine...');
      }

      // Step C: Fallback to YouTube Player Engine if native stream resolution fails
      String? videoId = track.videoId;
      if (videoId == null || videoId.isEmpty || _failedVideoIds.contains(videoId)) {
        videoId = await _apiService.resolveVideoId(track.title, track.artist, track.duration, _failedVideoIds);
        if (videoId != null && videoId.isNotEmpty) {
          track = track.copyWith(videoId: videoId);
          _currentTrack = track;
        }
      }

      if (videoId != null && videoId.isNotEmpty && _ytController != null) {
        debugPrint('[AudioPlayerManager] Playing full song via YouTube Engine fallback: videoId=$videoId');
        _isUsingYoutubeIframe = true;
        _isPlaying = true;
        _userRequestedPause = false;
        try {
          await _player.stop();
        } catch (_) {}
        _setJsLoadingTrack(true);
        _ytController!.loadVideoById(videoId: videoId);
        if (_playbackSpeed != 1.0) {
          try {
            _ytController!.setPlaybackRate(_playbackSpeed);
          } catch (_) {}
        }
        _setJsUserRequestedPause(false);
        _injectBackgroundPlaybackScripts();
        _acquireNativeLocks();
        _startWatchdog();
        _syncMediaHandler();
        notifyListeners();
        _prefetchNextTrackStream();
        return;
      }

      // Step D: If resolution could not find videoId, DO NOT skip user's track!
      debugPrint('[AudioPlayerManager] Could not resolve stream or videoId for "${track.title}". Keeping current selection.');
      _isPlaying = false;
      _syncMediaHandler();
      notifyListeners();
      return;
    } catch (e) {
      debugPrint('Playback error: $e');
      _handlePlaybackFailure(track, e.toString());
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
        _resumeDebounceTimer?.cancel();
        _setJsUserRequestedPause(true);
        _stopWatchdog();
        _releaseNativeLocks();
        _ytController!.pauseVideo();
        _isPlaying = false;
      } else {
        _userRequestedPause = false;
        _trackStartTime = DateTime.now().subtract(_position);
        _acquireNativeLocks();
        _setJsUserRequestedPause(false);
        _ytController!.playVideo();
        _isPlaying = true;
        _injectBackgroundPlaybackScripts();
        _startWatchdog();
      }
      _syncMediaHandler();
      notifyListeners();
      return;
    }

    if (_isPlaying) {
      _userRequestedPause = true;
      _stopWatchdog();
      _releaseNativeLocks();
      await _player.pause();
      _isPlaying = false;
    } else {
      _userRequestedPause = false;
      _acquireNativeLocks();
      _startWatchdog();
      if (_player.processingState == ja.ProcessingState.ready ||
          _player.processingState == ja.ProcessingState.buffering) {
        await _player.play();
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
    _trackStartTime = DateTime.now().subtract(pos);
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
        if (wasPlaying && !_player.playing) {
          _userRequestedPause = false;
          await _player.play();
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

    // Spotify Deck Playback: Play next sequential item in _queue
    // (When Shuffle is ON, _queue IS already deterministically shuffled with zero repeats!)
    if (currentIndex != -1 && currentIndex < _queue.length - 1) {
      await playTrack(_queue[currentIndex + 1]);
      return;
    }

    // End of playlist/shuffled deck reached!
    if (_isRepeat) {
      if (_isShuffle && _originalQueue.length > 1) {
        _queue = buildSpotifyShuffleDeck(_originalQueue, null);
      }
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
      // 1. Gather distinct artists and genres from the current playlist / queue
      final playlistArtists = <String>{};
      for (final t in _queue) {
        final artist = t.artist.split(',')[0].trim();
        if (artist.isNotEmpty) playlistArtists.add(artist);
      }
      if (_currentTrack != null) {
        final curArtist = _currentTrack!.artist.split(',')[0].trim();
        if (curArtist.isNotEmpty) playlistArtists.add(curArtist);
      }

      final primaryArtist = _currentTrack?.artist ?? (playlistArtists.isNotEmpty ? playlistArtists.first : '');
      final targetRegion = MusicApiService.detectTrackRegion(
        primaryArtist,
        _currentTrack?.title ?? '',
        _currentTrack?.genre ?? '',
      );
      final peerArtists = _apiService.getSimilarArtists(
        primaryArtist,
        genre: _currentTrack?.genre,
        playlistArtists: playlistArtists.toList(),
        title: _currentTrack?.title,
      );

      final sampleArtists = {
        ...(List<String>.from(playlistArtists)..shuffle()).take(2),
        ...(List<String>.from(peerArtists)..shuffle()).take(3),
      }.toList();

      final existingIds = _queue.map((t) => t.id).toSet();
      final existingTitles = _queue.map((t) => t.title.toLowerCase().trim()).toSet();
      final newRecommendations = <Track>[];

      // 2. Prioritize user's liked tracks matching these artists and targetRegion
      try {
        final liked = await _storageService.getLikedTracks();
        for (final t in liked) {
          final cleanTitle = t.title.toLowerCase().trim();
          final songRegion = MusicApiService.detectTrackRegion(t.artist, t.title, t.genre);
          if (songRegion == targetRegion &&
              !existingIds.contains(t.id) &&
              !existingTitles.contains(cleanTitle) &&
              !_isExcludedTrack(cleanTitle)) {
            existingIds.add(t.id);
            existingTitles.add(cleanTitle);
            newRecommendations.add(t);
            if (newRecommendations.length >= 6) break;
          }
        }
      } catch (_) {}

      // 3. Search hits from sample artists (strictly respecting targetRegion)
      for (final artist in sampleArtists) {
        try {
          final results = await _apiService.searchTracks(artist);
          final artistList = <Track>[];
          for (final t in results) {
            final cleanTitle = t.title.toLowerCase().trim();
            final songRegion = MusicApiService.detectTrackRegion(t.artist, t.title, t.genre);
            if (songRegion == targetRegion &&
                !existingIds.contains(t.id) &&
                !existingTitles.contains(cleanTitle) &&
                !_isExcludedTrack(cleanTitle)) {
              existingIds.add(t.id);
              existingTitles.add(cleanTitle);
              artistList.add(t);
            }
          }
          // Take 2-3 random tracks from this artist to avoid static template
          newRecommendations.addAll((artistList..shuffle()).take(3));
          if (newRecommendations.length >= 18) break;
        } catch (_) {}
      }

      // 4. Supplement with additional peer hitmakers from same genre if few
      if (newRecommendations.length < 5) {
        final remainingPeers = (List<String>.from(peerArtists)..shuffle()).take(3);
        for (final peer in remainingPeers) {
          try {
            final results = await _apiService.searchTracks(peer);
            for (final t in results) {
              final cleanTitle = t.title.toLowerCase().trim();
              final songRegion = MusicApiService.detectTrackRegion(t.artist, t.title, t.genre);
              if (songRegion == targetRegion &&
                  !existingIds.contains(t.id) &&
                  !existingTitles.contains(cleanTitle) &&
                  !_isExcludedTrack(cleanTitle)) {
                existingIds.add(t.id);
                existingTitles.add(cleanTitle);
                newRecommendations.add(t);
                if (newRecommendations.length >= 18) break;
              }
            }
          } catch (_) {}
        }
      }

      if (newRecommendations.isNotEmpty) {
        newRecommendations.shuffle();
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
      'reverb', 'remake', 'tutorial', 'acapella'
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

  static String _primaryArtistKey(Track t) {
    final key = t.artist.split(',').first.trim().toLowerCase();
    return key.isEmpty ? '__unknown__' : key;
  }

  /// Spotify-style balanced bucket-spaced Fisher-Yates shuffle:
  /// - Groups by primary artist and Fisher-Yates shuffles within each artist bucket.
  /// - Distributes each artist's tracks evenly across [0, 1) with random phase & jitter
  ///   so consecutive tracks from the same artist don't cluster at the end.
  /// - Guarantees EVERY track plays once before any track repeats.
  /// - Keeps [anchorTrack] at index 0 when provided so active playback isn't interrupted.
  static List<Track> buildSpotifyShuffleDeck(List<Track> source, Track? anchorTrack, {Random? rng}) {
    if (source.isEmpty) return [];
    final random = rng ?? Random();
    final remaining = <Track>[];
    Track? resolvedAnchor;

    for (final t in source) {
      if (anchorTrack != null && t.id == anchorTrack.id && resolvedAnchor == null) {
        resolvedAnchor = t;
      } else {
        remaining.add(t);
      }
    }

    if (remaining.length <= 1) {
      return resolvedAnchor != null ? [resolvedAnchor, ...remaining] : remaining;
    }

    // Group tracks by primary artist
    final buckets = <String, List<Track>>{};
    for (final t in remaining) {
      buckets.putIfAbsent(_primaryArtistKey(t), () => []).add(t);
    }

    // Fisher-Yates shuffle within each bucket and assign spaced positions in [0, 1)
    final weighted = <({Track track, double pos})>[];
    for (final group in buckets.values) {
      for (int i = group.length - 1; i > 0; i--) {
        final j = random.nextInt(i + 1);
        final tmp = group[i];
        group[i] = group[j];
        group[j] = tmp;
      }
      final step = 1.0 / group.length;
      final phase = random.nextDouble() * step;
      for (int k = 0; k < group.length; k++) {
        final jitter = (random.nextDouble() - 0.5) * step * 0.35;
        weighted.add((track: group[k], pos: phase + k * step + jitter));
      }
    }

    weighted.sort((a, b) => a.pos.compareTo(b.pos));
    final deck = weighted.map((e) => e.track).toList();

    // Adjacent repair pass respecting anchorTrack and neighbors
    final anchorKey = resolvedAnchor != null ? _primaryArtistKey(resolvedAnchor) : null;
    for (int i = 0; i < deck.length; i++) {
      final curKey = _primaryArtistKey(deck[i]);
      final prevKey = i == 0 ? anchorKey : _primaryArtistKey(deck[i - 1]);
      if (prevKey != null && curKey == prevKey) {
        for (int j = i + 1; j < deck.length; j++) {
          final candKey = _primaryArtistKey(deck[j]);
          final jPrev = _primaryArtistKey(deck[j - 1]);
          final jNext = j + 1 < deck.length ? _primaryArtistKey(deck[j + 1]) : null;
          if (candKey != prevKey && curKey != jPrev && curKey != jNext) {
            final tmp = deck[i];
            deck[i] = deck[j];
            deck[j] = tmp;
            break;
          }
        }
      }
    }

    if (resolvedAnchor != null) {
      return [resolvedAnchor, ...deck];
    }
    return deck;
  }

  Future<void> shufflePlayPlaylist(List<Track> tracks) async {
    if (tracks.isEmpty) return;
    _isShuffle = true;
    _originalQueue = List.from(tracks);
    _queue = buildSpotifyShuffleDeck(_originalQueue, null);
    await playTrack(_queue.first);
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    if (_originalQueue.isEmpty && _queue.isNotEmpty) {
      _originalQueue = List.from(_queue);
    }
    if (_isShuffle && _originalQueue.length > 1) {
      _queue = buildSpotifyShuffleDeck(_originalQueue, _currentTrack);
    } else if (!_isShuffle && _originalQueue.isNotEmpty) {
      _queue = List.from(_originalQueue);
    }
    _hasPrefetchedNextTrack = false;
    _prefetchNextTrackStream();
    notifyListeners();
  }

  void toggleRepeat() {
    _isRepeat = !_isRepeat;
    notifyListeners();
  }

  void playNext(Track track) {
    if (_currentTrack == null) {
      playTrack(track);
      return;
    }
    final currentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    for (int i = _queue.length - 1; i >= 0; i--) {
      if (i != currentIndex && _queue[i].id == track.id) {
        _queue.removeAt(i);
      }
    }
    final newCurrentIndex = _queue.indexWhere((t) => t.id == _currentTrack!.id);
    if (newCurrentIndex != -1) {
      _queue.insert(newCurrentIndex + 1, track);
    } else {
      _queue.insert(0, track);
    }
    notifyListeners();
  }

  void addToNext(Track track) => playNext(track);

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
    _stopWatchdog();
    _networkReconnectTimer?.cancel();
    _releaseNativeLocks();
    _sleepTimer?.cancel();
    _ytController?.close();
    _player.dispose();
    super.dispose();
  }
}
