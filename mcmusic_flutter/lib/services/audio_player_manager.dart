import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
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

  Track? _currentTrack;
  bool _isPlaying = false;
  bool _userRequestedPause = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  List<Track> _queue = [];
  bool _isShuffle = false;
  bool _isRepeat = false;
  bool _isLoadingRecommendations = false;
  bool _hasPrefetchedNextTrack = false;
  Timer? _backgroundWatchdogTimer;
  bool _isRecovering = false;
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
      await _player.setPlaybackRate(speed);
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
    _initMediaHandlerCallbacks();
    _loadStoredAudioQuality();
    // Pre-warm and apply stored Equalizer preset & DSP effects on startup
    EqualizerService.instance;
  }

  Future<void> _acquireNativeLocks() async {
    try {
      await _nativeChannel.invokeMethod('acquireLocks');
      final isIgnoring = await _nativeChannel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (isIgnoring == false) {
        await _nativeChannel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
    } catch (_) {}
  }

  Future<void> _releaseNativeLocks() async {
    try {
      await _nativeChannel.invokeMethod('releaseLocks');
    } catch (_) {}
  }

  void _startWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _backgroundWatchdogTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_userRequestedPause && _isPlaying && _currentTrack != null) {
        // If native player was paused unexpectedly by system without user intent:
        if (_player.state == PlayerState.paused) {
          debugPrint('[AudioPlayerManager] Watchdog: native player paused unexpectedly, auto-resuming...');
          _acquireNativeLocks();
          _player.resume();
        }
      }
    });
  }

  void _stopWatchdog() {
    _backgroundWatchdogTimer?.cancel();
    _backgroundWatchdogTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (!_userRequestedPause && _isPlaying) {
        _acquireNativeLocks();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (!_userRequestedPause && _isPlaying) {
        _acquireNativeLocks();
      }
    }
  }

  Future<void> _handlePlaybackFailure(Track? track, String reason) async {
    if (track == null || _isRecovering) return;
    _isRecovering = true;
    debugPrint('[AudioPlayerManager] Failsafe recovery triggered ($reason) for: "${track.title}"');

    try {
      final currentVid = track.videoId;
      if (currentVid != null && currentVid.isNotEmpty) {
        _failedVideoIds.add(currentVid);
        _apiService.invalidateVideoId(track.title, track.artist, currentVid);
      }

      // 1. Try alternative candidate video and extract direct audio stream
      final altStream = await _apiService.resolveFullAudioStream(
        track.title,
        track.artist,
        _audioQuality,
        track.duration,
        _failedVideoIds,
      );

      if (altStream != null && altStream.isNotEmpty) {
        debugPrint('[AudioPlayerManager] Recovery: alternative audio stream succeeded for "${track.title}"');
        _currentTrack = track.copyWith(audioUrl: altStream);
        _isPlaying = true;
        _userRequestedPause = false;
        await _player.stop();
        await _player.play(UrlSource(altStream));
        _acquireNativeLocks();
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
    if (_currentTrack != null) {
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
      _isPlaying = state == PlayerState.playing;
      _syncMediaHandler();
      notifyListeners();
    });

    int lastNotifiedMs = -1;
    _player.onPositionChanged.listen((pos) {
      _position = pos;
      if ((pos.inMilliseconds - lastNotifiedMs).abs() >= 250) {
        lastNotifiedMs = pos.inMilliseconds;
        _syncMediaHandler();
        notifyListeners();
      }

      // Gapless Pre-fetch: pre-cache next track stream 20 seconds before current song ends
      if (_duration.inSeconds > 25 &&
          pos.inSeconds >= _duration.inSeconds - 20 &&
          !_hasPrefetchedNextTrack) {
        _hasPrefetchedNextTrack = true;
        _prefetchNextTrackStream();
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
      debugPrint('[AudioPlayerManager] onPlayerComplete: Track finished naturally!');
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
    _userRequestedPause = true;
    _stopWatchdog();
    _releaseNativeLocks();
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

      // Balanced Interleaved Queue: Dynamic, fresh, and zero static template!
      final structuredQueue = <Track>[];
      int userIdx = 0;
      int artIdx = 0;
      int peerIdx = 0;

      while (structuredQueue.length < 18 &&
          (userIdx < userLikedTracks.length || artIdx < sampledArtistHits.length || peerIdx < sampledPeerHits.length)) {
        if (userIdx < userLikedTracks.length && (structuredQueue.isEmpty || structuredQueue.length % 3 == 0)) {
          structuredQueue.add(userLikedTracks[userIdx++]);
        }
        if (artIdx < sampledArtistHits.length && structuredQueue.length < 18) {
          structuredQueue.add(sampledArtistHits[artIdx++]);
        }
        if (peerIdx < sampledPeerHits.length && structuredQueue.length < 18) {
          structuredQueue.add(sampledPeerHits[peerIdx++]);
        }
        if (artIdx >= sampledArtistHits.length &&
            peerIdx >= sampledPeerHits.length &&
            userIdx < userLikedTracks.length &&
            structuredQueue.length < 18) {
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

    // Record play in storage
    _storageService.recordPlay(track);

    // 2. Full Song Native Audio Playback (100% Native Audio, ExoPlayer background service, 0 video bugs)
    try {
      // Step A: Check cached stream or direct audioUrl
      String? streamUrl = _apiService.getCachedStream(track, _audioQuality);
      if (streamUrl == null || streamUrl.isEmpty) {
        if (track.audioUrl.isNotEmpty && !MusicApiService.isPreviewUrl(track.audioUrl)) {
          streamUrl = track.audioUrl;
        }
      }

      // Step B: Resolve direct audio stream from YouTube
      if (streamUrl == null || streamUrl.isEmpty) {
        streamUrl = await _apiService.resolveDirectAudioStream(track, _audioQuality);
      }

      if (streamUrl != null && streamUrl.isNotEmpty) {
        debugPrint('[AudioPlayerManager] Playing native audio stream via ExoPlayer: "${track.title}"');
        track = track.copyWith(audioUrl: streamUrl);
        _currentTrack = track;
        await _player.stop();
        await _player.play(UrlSource(streamUrl));
        if (_playbackSpeed != 1.0) {
          try {
            await _player.setPlaybackRate(_playbackSpeed);
          } catch (_) {}
        }
        _isPlaying = true;
        _userRequestedPause = false;
        _acquireNativeLocks();
        _syncMediaHandler();
        notifyListeners();
        _prefetchNextTrackStream();
        return;
      }

      // Step C: Failsafe recovery if first stream attempt failed
      debugPrint('[AudioPlayerManager] Direct stream not resolved for "${track.title}". Trying failsafe recovery...');
      _handlePlaybackFailure(track, 'Could not resolve audio stream');
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
      await _player.seek(pos);
      if (wasPlaying && _player.state != PlayerState.playing) {
        _userRequestedPause = false;
        await _player.resume();
        _isPlaying = true;
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
          if (songRegion != targetRegion) continue;

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
    _player.dispose();
    super.dispose();
  }
}
