import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ytp;
import '../models/track.dart';
import '../models/audio_quality.dart';
import 'equalizer_service.dart';
import 'media_audio_handler.dart';
import 'music_api_service.dart';
import 'storage_service.dart';

class AudioPlayerManager extends ChangeNotifier with WidgetsBindingObserver {
  static const MethodChannel _nativeChannel = MethodChannel('com.mcmusic.app/wakelock');
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
  bool _hasPrefetchedNextTrack = false;
  Timer? _backgroundWatchdogTimer;
  Duration _lastWatchdogPosition = Duration.zero;
  int _watchdogStallCount = 0;

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
        await _player.setPlaybackRate(speed);
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
    // Pre-warm and apply stored Equalizer preset & DSP effects on startup
    EqualizerService.instance;
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

  void _startWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _watchdogStallCount = 0;
    _lastWatchdogPosition = _position;
    _backgroundWatchdogTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isPlaying && !_userRequestedPause && _isUsingYoutubeIframe && _ytController != null) {
        _setJsUserRequestedPause(false);
        _injectBackgroundPlaybackScripts();

        // Detect if audio playback is stalled in background while screen is off
        if (_position == _lastWatchdogPosition && _position > Duration.zero) {
          _watchdogStallCount++;
          if (_watchdogStallCount >= 2) {
            // Stalled for 4-6 seconds: enforce playback kick
            _acquireNativeLocks();
            _ytController?.playVideo();
          }
          if (_watchdogStallCount >= 5) {
            // Stalled for 10 seconds: inject direct JS play trigger
            try {
              _ytController?.webViewController.runJavaScript(
                'if (typeof player !== "undefined" && player && player.playVideo) player.playVideo();'
              );
            } catch (_) {}
          }
        } else {
          _watchdogStallCount = 0;
          _lastWatchdogPosition = _position;
        }
      }
    });
  }

  void _stopWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _backgroundWatchdogTimer = null;
    _watchdogStallCount = 0;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (!_userRequestedPause && _currentTrack != null && _isPlaying) {
        _acquireNativeLocks();
        if (_isUsingYoutubeIframe && _ytController != null) {
          _setJsUserRequestedPause(false);
          _injectBackgroundPlaybackScripts();
          _ytController?.playVideo();
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

  Future<void> _injectBackgroundPlaybackScripts() async {
    try {
      final controller = _ytController?.webViewController;
      if (controller == null) return;
      await controller.runJavaScript('''
        (function() {
          window.__userRequestedPause = ${_userRequestedPause ? 'true' : 'false'};

          // 1. Hook HTMLMediaElement.prototype.pause so OS screen-off pause calls are ignored
          if (!window.__pausePatched) {
            window.__pausePatched = true;
            try {
              var origPause = HTMLMediaElement.prototype.pause;
              HTMLMediaElement.prototype.pause = function() {
                if (window.__userRequestedPause) {
                  return origPause.apply(this, arguments);
                }
                return Promise.resolve();
              };

              var origPlay = HTMLMediaElement.prototype.play;
              HTMLMediaElement.prototype.play = function() {
                this.muted = false;
                this.volume = 1.0;
                return origPlay.apply(this, arguments);
              };
            } catch(e) {}
          }

          // 2. Protect existing and newly added video tags
          function protectVideo(v) {
            if (!v || v.__protected) return;
            v.__protected = true;
            v.muted = false;
            v.volume = 1.0;
            try {
              v.removeAttribute('playsinline');
              v.setAttribute('playsinline', '');
            } catch(e) {}

            v.addEventListener('pause', function(e) {
              if (!window.__userRequestedPause) {
                e.stopImmediatePropagation();
                try { v.play(); } catch(_) {}
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

          // 3. Spoof visibility properties so YouTube player engine believes screen is ALWAYS on
          try {
            Object.defineProperty(document, 'hidden', { get: function() { return false; }, configurable: true });
            Object.defineProperty(document, 'visibilityState', { get: function() { return 'visible'; }, configurable: true });
            Object.defineProperty(document, 'webkitVisibilityState', { get: function() { return 'visible'; }, configurable: true });
          } catch(e) {}

          // 4. Block OS screen off / window blur events
          var blockEvents = ['visibilitychange', 'webkitvisibilitychange', 'blur', 'pagehide', 'freeze', 'unload'];
          blockEvents.forEach(function(evt) {
            window.addEventListener(evt, function(e) {
              if (!window.__userRequestedPause) {
                e.stopImmediatePropagation();
              }
            }, true);
            document.addEventListener(evt, function(e) {
              if (!window.__userRequestedPause) {
                e.stopImmediatePropagation();
              }
            }, true);
          });

          // 5. Inaudible Web Audio oscillator keep-alive to keep audio pipeline active
          try {
            if (!window.__keepAliveAudioCtx) {
              var AudioCtx = window.AudioContext || window.webkitAudioContext;
              if (AudioCtx) {
                var actx = new AudioCtx();
                var osc = actx.createOscillator();
                var gain = actx.createGain();
                gain.gain.value = 0.00001;
                osc.connect(gain);
                gain.connect(actx.destination);
                osc.start();
                window.__keepAliveAudioCtx = actx;
              }
            } else if (window.__keepAliveAudioCtx.state === 'suspended') {
              window.__keepAliveAudioCtx.resume();
            }
          } catch(e) {}

          // 6. Ensure player volume is at maximum
          try {
            if (typeof player !== 'undefined' && player) {
              if (typeof player.unMute === 'function') player.unMute();
              if (typeof player.setVolume === 'function') player.setVolume(100);
            }
          } catch(e) {}
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
        ),
      );

      _ytController!.listen((value) {
        if (!_isUsingYoutubeIframe) return;
        if (value.playerState == ytp.PlayerState.playing) {
          _isPlaying = true;
          _userRequestedPause = false;
          _acquireNativeLocks();
          _setJsUserRequestedPause(false);
          _injectBackgroundPlaybackScripts();
          _startWatchdog();
        } else if (value.playerState == ytp.PlayerState.paused) {
          if (_userRequestedPause) {
            _isPlaying = false;
          } else if (!_userRequestedPause && _isPlaying && _currentTrack != null) {
            // Unsolicited pause while playing (e.g. OS screen off or blur event): immediately resume with 0 delay!
            _acquireNativeLocks();
            _setJsUserRequestedPause(false);
            _injectBackgroundPlaybackScripts();
            _ytController?.playVideo();
          }
        } else if (value.playerState == ytp.PlayerState.cued || value.playerState == ytp.PlayerState.unStarted) {
          // Video loaded/cued while screen is off / app in background: immediately force play!
          if (!_userRequestedPause && _isPlaying && _currentTrack != null) {
            _acquireNativeLocks();
            _setJsUserRequestedPause(false);
            _injectBackgroundPlaybackScripts();
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
    if (_audioQuality == quality) return;
    _audioQuality = quality;
    notifyListeners();
    await _storageService.setAudioQuality(quality.name);

    // Invalidate stream cache so future stream resolutions use the new bitrate quality
    MusicApiService.clearStreamCache();

    // Hot-switch playback in real time: if currently playing a direct stream,
    // re-request the audio stream at the new bitrate and resume from current position
    // without resetting playback back to 0:00!
    if (_currentTrack != null && !_isUsingYoutubeIframe) {
      final currentPos = _position;
      final wasPlaying = _isPlaying;
      try {
        final newStream = await _apiService.resolveDirectAudioStream(_currentTrack!, quality);
        if (newStream != null && newStream.isNotEmpty) {
          await _player.stop();
          await _player.play(UrlSource(newStream), position: currentPos);
          if (!wasPlaying) {
            await _player.pause();
          }
          _position = currentPos;
          _isPlaying = wasPlaying;
          _syncMediaHandler();
          notifyListeners();
        }
      } catch (e) {
        debugPrint('[AudioPlayerManager] setAudioQuality hot-switch note: $e');
      }
    }
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

        // Gapless Pre-fetch: pre-cache next track stream 15 seconds before current song ends
        if (_duration.inSeconds > 20 &&
            pos.inSeconds >= _duration.inSeconds - 15 &&
            !_hasPrefetchedNextTrack) {
          _hasPrefetchedNextTrack = true;
          _prefetchNextTrackStream();
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
    _userRequestedPause = true;
    _setJsUserRequestedPause(true);
    _stopWatchdog();
    _releaseNativeLocks();
    if (_isUsingYoutubeIframe && _ytController != null) {
      _ytController!.pauseVideo();
    }
    _player.pause();
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

      // Identify peer hitmakers based on artist genre cluster
      final artLower = track.artist.toLowerCase();
      List<String> peerArtists = ['Bernadya', 'Sal Priadi', 'Juicy Luicy', 'Mahalini', 'Tulus', 'Hindia'];
      if (artLower.contains('hindia') || artLower.contains('feast') || artLower.contains('nadin') ||
          artLower.contains('sal priadi') || artLower.contains('pamungkas') || artLower.contains('fourtwnty')) {
        peerArtists = ['Bernadya', 'Sal Priadi', 'Hindia', 'Nadin Amizah', 'Juicy Luicy', 'Kunto Aji'];
      } else if (artLower.contains('mahalini') || artLower.contains('tulus') || artLower.contains('juicy luicy') ||
                 artLower.contains('tiara') || artLower.contains('lyodra') || artLower.contains('yura')) {
        peerArtists = ['Bernadya', 'Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra'];
      } else if (artLower.contains('sheila') || artLower.contains('dewa') || artLower.contains('noah') ||
                 artLower.contains('peterpan') || artLower.contains('padi') || artLower.contains('ungu')) {
        peerArtists = ['Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Padi', 'Ungu'];
      } else if (artLower.contains('weeknd') || artLower.contains('bruno') || artLower.contains('taylor') ||
                 artLower.contains('billie') || artLower.contains('olivia') || artLower.contains('coldplay')) {
        peerArtists = ['The Weeknd', 'Bruno Mars', 'Taylor Swift', 'Billie Eilish', 'Olivia Rodrigo', 'Coldplay'];
      } else if (artLower.contains('newjeans') || artLower.contains('bts') || artLower.contains('blackpink') ||
                 artLower.contains('aespa') || artLower.contains('twice')) {
        peerArtists = ['NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM', 'TWICE'];
      }

      // Filter out current artist from peers
      final activePeers = peerArtists.where((p) => !artLower.contains(p.toLowerCase())).take(3).toList();

      // Query user's liked and frequently played tracks first
      final userLikedTracks = <Track>[];
      try {
        final liked = await _storageService.getLikedTracks();
        for (final t in liked) {
          final clean = t.title.toLowerCase().trim();
          final tArt = t.artist.toLowerCase();
          final isMatch = tArt.contains(artLower) || artLower.contains(tArt) ||
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

      final artistHits = <Track>[];
      if (searchResults.isNotEmpty) {
        for (final t in searchResults[0]) {
          final clean = t.title.toLowerCase().trim();
          final isJunk = banned.any((b) => clean.contains(b));
          if (!isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
            seen.add(t.id);
            seen.add(clean);
            artistHits.add(t);
          }
        }
      }

      final peerHits = <Track>[];
      for (int i = 1; i < searchResults.length; i++) {
        for (final t in searchResults[i]) {
          final clean = t.title.toLowerCase().trim();
          final isJunk = banned.any((b) => clean.contains(b));
          if (!isJunk && !seen.contains(t.id) && !seen.contains(clean)) {
            seen.add(t.id);
            seen.add(clean);
            peerHits.add(t);
          }
        }
      }

      // Structured Hit Queue Interleaving:
      // High-priority popular songs without random shuffle:
      // 1. User's liked / favorite track (if any)
      // 2. Artist's top #1 hit
      // 3. Peer #1 hit
      // 4. Artist's #2 hit
      // 5. Peer #2 hit
      // 6. Artist's #3 hit ...
      final structuredQueue = <Track>[];
      int userIdx = 0;
      int artIdx = 0;
      int peerIdx = 0;

      while (structuredQueue.length < 18 &&
          (userIdx < userLikedTracks.length || artIdx < artistHits.length || peerIdx < peerHits.length)) {
        if (userIdx < userLikedTracks.length && (structuredQueue.isEmpty || structuredQueue.length % 3 == 0)) {
          structuredQueue.add(userLikedTracks[userIdx++]);
        }
        if (artIdx < artistHits.length && structuredQueue.length < 18) {
          structuredQueue.add(artistHits[artIdx++]);
        }
        if (peerIdx < peerHits.length && structuredQueue.length < 18) {
          structuredQueue.add(peerHits[peerIdx++]);
        }
        if (artIdx >= artistHits.length && peerIdx >= peerHits.length && userIdx < userLikedTracks.length && structuredQueue.length < 18) {
          structuredQueue.add(userLikedTracks[userIdx++]);
        }
      }

      if (structuredQueue.isNotEmpty) {
        _queue = [
          if (_currentTrack != null) _currentTrack! else track,
          ...structuredQueue,
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
    _hasPrefetchedNextTrack = false;
    _mediaHandler?.updateTrack(track, _duration);
    _syncMediaHandler();
    _acquireNativeLocks();
    _startWatchdog();
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
        if (_playbackSpeed != 1.0) {
          try {
            await _player.setPlaybackRate(_playbackSpeed);
          } catch (_) {}
        }
        _isPlaying = true;
        _isUsingYoutubeIframe = false;
        _userRequestedPause = false;
        _acquireNativeLocks();
        _startWatchdog();
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
        _stopWatchdog();
        _releaseNativeLocks();
        _ytController!.pauseVideo();
        _isPlaying = false;
      } else {
        _userRequestedPause = false;
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

      final sampleArtists = playlistArtists.take(3).toList();
      final existingIds = _queue.map((t) => t.id).toSet();
      final existingTitles = _queue.map((t) => t.title.toLowerCase().trim()).toSet();
      final newRecommendations = <Track>[];

      // 2. Prioritize user's liked tracks matching these artists
      try {
        final liked = await _storageService.getLikedTracks();
        for (final t in liked) {
          final cleanTitle = t.title.toLowerCase().trim();
          final tArt = t.artist.toLowerCase();
          final isMatch = sampleArtists.any((a) => tArt.contains(a.toLowerCase()));
          if (isMatch &&
              !existingIds.contains(t.id) &&
              !existingTitles.contains(cleanTitle) &&
              !_isExcludedTrack(cleanTitle)) {
            existingIds.add(t.id);
            existingTitles.add(cleanTitle);
            newRecommendations.add(t);
          }
        }
      } catch (_) {}

      // 3. Search related top hits from these artists (ordered by popularity)
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

      // 4. Supplement with popular hitmaker peers if few
      if (newRecommendations.length < 5) {
        final peers = ['Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy', 'Mahalini', 'Tulus'];
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
    // Remove if already present later in queue (do not remove if currently playing)
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
    _releaseNativeLocks();
    _sleepTimer?.cancel();
    _ytController?.close();
    _player.dispose();
    super.dispose();
  }
}
