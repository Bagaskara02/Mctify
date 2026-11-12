import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/audio_quality.dart';
import 'audio_proxy_server.dart';
import 'storage_service.dart';

class MusicApiService {
  static const String defaultArtwork = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600';
  static final Map<String, String> _streamCache = {};
  static final Map<String, List<Track>> _searchCache = {};
  static final YoutubeExplode _sharedYt = YoutubeExplode();
  final StorageService _storageService = StorageService();

  /// Selects the best audio stream matching requested quality tier.
  static AudioStreamInfo _pickStreamByQuality(
    List<AudioStreamInfo> allStreams,
    AudioQuality quality,
  ) {
    final mp4Streams = allStreams.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
    if (quality == AudioQuality.lossless) {
      // Lossless / Hi-Fi mode: choose highest bitrate across all audio codecs (Opus 251 / Hi-Fi AAC)
      final sortedAll = List<AudioStreamInfo>.from(allStreams)
        ..sort((a, b) => a.bitrate.compareTo(b.bitrate));
      return sortedAll.last;
    }

    final candidateStreams = mp4Streams.isNotEmpty ? mp4Streams : allStreams;
    candidateStreams.sort((a, b) => a.bitrate.compareTo(b.bitrate));

    switch (quality) {
      case AudioQuality.dataSaver:
        return candidateStreams.first;
      case AudioQuality.standard:
        return candidateStreams.firstWhere(
          (s) => s.bitrate.kiloBitsPerSecond <= 140,
          orElse: () => candidateStreams.last,
        );
      case AudioQuality.high:
      case AudioQuality.lossless:
        return candidateStreams.last;
    }
  }

  /// Fast stream manifest resolver prioritizing progressive `muxed` (itag 18 MP4+AAC)
  /// which streams 100% from 0:00 to end without YouTube's 1 MB (~50s) adaptive `audioOnly` 403 cutoff.
  Future<List<AudioStreamInfo>> _getFastAudioStreams(String videoId) async {
    try {
      final manifest = await _sharedYt.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [YoutubeApiClient.androidSdkless],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 3));
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.toList();
      }
    } catch (_) {}

    try {
      final tvManifest = await _sharedYt.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [YoutubeApiClient.tv],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 3));
      if (tvManifest.muxed.isNotEmpty) return tvManifest.muxed.toList();
      if (tvManifest.audioOnly.isNotEmpty) return tvManifest.audioOnly.toList();
    } catch (_) {}

    try {
      final vrManifest = await _sharedYt.videos.streamsClient
          .getManifest(
            videoId,
            ytClients: [YoutubeApiClient.androidVr],
            requireWatchPage: false,
          )
          .timeout(const Duration(seconds: 4));
      if (vrManifest.muxed.isNotEmpty) return vrManifest.muxed.toList();
      if (vrManifest.audioOnly.isNotEmpty) return vrManifest.audioOnly.toList();
    } catch (_) {}

    return const [];
  }

  /// Registers resolved YouTube audio stream with AudioProxyServer so ExoPlayer receives
  /// HTTP 206 Partial Content without 403 errors, 0ms rewind from RAM, and Chunk 0 pre-warming.
  Future<String> _registerProxyStream(
    String videoId,
    AudioStreamInfo chosen,
    AudioQuality quality,
  ) {
    final container = chosen.container.name.toLowerCase();
    final contentType = container == 'webm' ? 'audio/webm' : 'audio/mp4';
    return AudioProxyServer.instance.registerStream(
      key: '${videoId}_${quality.name}',
      upstreamUrl: chosen.url.toString(),
      totalBytes: chosen.size.totalBytes,
      contentType: contentType,
      refreshUrl: () async {
        final fresh = await _getFastAudioStreams(videoId);
        if (fresh.isEmpty) return null;
        return _pickStreamByQuality(fresh, quality).url.toString();
      },
    );
  }

  /// Invalidate stream URL cache (called when user switches audio quality)
  static void clearStreamCache() {
    _streamCache.clear();
    AudioProxyServer.instance.clearCache();
  }

  static void clearSearchCache() {
    _searchCache.clear();
  }

  static bool isPreviewUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains('preview') ||
        lower.contains('p.scdn.co') ||
        lower.contains('mzstatic.com') ||
        lower.contains('deezer');
  }

  /// Deprecated: 30-second preview resolution completely disabled for 100% full song playback
  Future<String?> resolveAudioUrl(String title, String artist) async {
    // Disabled: FULL SONGS ONLY! Never return 30-second preview clips.
    return null;
  }

  /// Resolves direct, full-length YouTube audio stream from videoId
  Future<String?> resolveStreamUrlFromVideoId(
    String videoId, [
    AudioQuality quality = AudioQuality.high,
  ]) async {
    final cleanKey = 'stream_${videoId}_${quality.name}';
    if (_streamCache.containsKey(cleanKey)) {
      return _streamCache[cleanKey];
    }
    try {
      final allAudio = await _getFastAudioStreams(videoId);
      if (allAudio.isNotEmpty) {
        final chosen = _pickStreamByQuality(allAudio, quality);
        final proxyUrl = await _registerProxyStream(videoId, chosen, quality);
        _streamCache[cleanKey] = proxyUrl;
        return proxyUrl;
      }
    } catch (e) {
      debugPrint('resolveStreamUrlFromVideoId error for $videoId: $e');
    }
    return null;
  }

  /// Returns cached stream URL if already resolved (guaranteeing it's never a 30s preview)
  String? getCachedStream(Track track, [AudioQuality quality = AudioQuality.high]) {
    if (track.audioUrl.isNotEmpty && !isPreviewUrl(track.audioUrl)) {
      return track.audioUrl;
    }
    if (track.videoId != null && track.videoId!.isNotEmpty) {
      final key = 'stream_${track.videoId}_${quality.name}';
      if (_streamCache.containsKey(key)) return _streamCache[key];
    }
    final cleanKey = '${track.title} ${track.artist} ${quality.name}'.toLowerCase().trim();
    if (_streamCache.containsKey(cleanKey)) return _streamCache[cleanKey];
    return null;
  }

  /// Pre-warms top Quick Card / top tracks silently on startup so first Play is instant
  Future<void> prewarmTracks(
    List<Track> tracks, {
    AudioQuality quality = AudioQuality.high,
    int limit = 3,
  }) async {
    final subset = tracks.take(limit).toList();
    await Future.wait(
      subset.map((t) => prefetchTrackStream(t, quality)),
      eagerError: false,
    );
  }

  /// Silently pre-fetches stream URL + Chunk 0 (~256 KB) into RAM so next song / skip starts at ~0ms
  Future<void> prefetchTrackStream(Track track, [AudioQuality quality = AudioQuality.high]) async {
    try {
      String? streamUrl = getCachedStream(track, quality);
      if (streamUrl == null || streamUrl.isEmpty) {
        String? vid = track.videoId;
        if (vid == null || vid.isEmpty) {
          vid = await resolveVideoId(track.title, track.artist, track.duration);
        }
        if (vid != null && vid.isNotEmpty) {
          streamUrl = await resolveDirectAudioStream(track.copyWith(videoId: vid), quality);
        }
      }
      if (streamUrl != null && streamUrl.isNotEmpty) {
        final proxyId = Uri.tryParse(streamUrl)?.queryParameters['id'];
        if (proxyId != null && proxyId.isNotEmpty && !AudioProxyServer.instance.hasHeadCached(proxyId)) {
          await AudioProxyServer.instance.prewarmHead(proxyId);
        }
      }
    } catch (_) {}
  }

  /// Resolves direct audio stream for native ExoPlayer background playback (100% full song only!)
  Future<String?> resolveDirectAudioStream(
    Track track, [
    AudioQuality quality = AudioQuality.high,
    Set<String>? excludeVideoIds,
  ]) async {
    final cached = getCachedStream(track, quality);
    if (cached != null) return cached;

    // 1. Try resolving direct stream via videoId if already present on track and not excluded
    String? vid = track.videoId;
    if (vid == null || vid.isEmpty || (excludeVideoIds != null && excludeVideoIds.contains(vid))) {
      vid = await resolveVideoId(track.title, track.artist, track.duration, excludeVideoIds);
    }

    if (vid != null && vid.isNotEmpty && (excludeVideoIds == null || !excludeVideoIds.contains(vid))) {
      final url = await resolveStreamUrlFromVideoId(vid, quality);
      if (url != null && url.isNotEmpty) {
        final key = '${track.title} ${track.artist} ${quality.name}'.toLowerCase().trim();
        _streamCache[key] = url;
        return url;
      }
    }

    // 2. Resolve direct audio stream from YouTube Explode (full 3-5+ minute song!)
    final stream = await resolveFullAudioStream(
      track.title,
      track.artist,
      quality,
      track.duration,
      excludeVideoIds,
    );
    if (stream != null && stream.isNotEmpty) {
      return stream;
    }

    // CRITICAL: NEVER fall back to 30-second previews!
    // Return null so AudioPlayerManager falls back to Tier 2 (YouTube Player Engine) for full-length playback.
    return null;
  }

  /// Resolves YouTube video ID for full-length song streaming (3 - 5+ minutes)
  Future<String?> resolveVideoId(
    String title,
    String artist, [
    int? expectedDuration,
    Set<String>? excludeVideoIds,
  ]) async {
    final sanitizedTitle = title
        .replaceAll(RegExp(r'[\u00a0\u2000-\u200b\u202f\u205f\u3000]'), ' ')
        .replaceAll('◐', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final firstArtist = artist
        .split(',')[0]
        .replaceAll(RegExp(r'[\u00a0\u2000-\u200b\u202f\u205f\u3000]'), ' ')
        .trim();
    final cleanKey = 'vid_${sanitizedTitle.toLowerCase()}_${firstArtist.toLowerCase()}';
    if (_streamCache.containsKey(cleanKey)) {
      final cached = _streamCache[cleanKey];
      if (cached != null && (excludeVideoIds == null || !excludeVideoIds.contains(cached))) {
        return cached;
      }
    }

    // 1 & 2 RACED IN PARALLEL: Race Vercel Backend (~114ms warm / slow cold start)
    // directly against in-process YoutubeExplode search (~500ms consistent) so
    // cold serverless starts NEVER stall song playback!
    Future<String?> searchViaVercel() async {
      try {
        final url = Uri.parse(
            'https://mctify.vercel.app/api/yt/search?title=${Uri.encodeComponent(title)}&artist=${Uri.encodeComponent(artist)}&duration=${expectedDuration ?? 0}&q=${Uri.encodeComponent('$title $artist')}');
        final res = await http.get(url).timeout(const Duration(milliseconds: 2400));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final vid = data['videoId'] as String?;
          final retTitle = (data['title'] ?? '').toString();
          final retArtist = (data['artist'] ?? '').toString();
          final retDur = (data['duration'] as num?)?.toInt();
          if (vid != null && vid.isNotEmpty && (excludeVideoIds == null || !excludeVideoIds.contains(vid))) {
            final score = _scoreCandidate(retTitle, retArtist, sanitizedTitle, firstArtist, retDur, expectedDuration);
            if (score >= 400) return vid;
          }
        }
      } catch (e) {
        debugPrint('resolveVideoId Vercel backend error: $e');
      }
      return null;
    }

    Future<String?> searchViaExplode() async {
      try {
        final searchResults = await _sharedYt.search
            .search('$sanitizedTitle $firstArtist audio')
            .timeout(const Duration(milliseconds: 3200));
        var pool = searchResults.take(8).toList();
        if (pool.isEmpty) {
          final broadResults = await _sharedYt.search
              .search('$sanitizedTitle $firstArtist')
              .timeout(const Duration(milliseconds: 3000));
          pool = broadResults.take(8).toList();
        }
        if (pool.isNotEmpty) {
          final filtered = pool.where((v) => excludeVideoIds == null || !excludeVideoIds.contains(v.id.value)).toList();
          if (filtered.isNotEmpty) {
            final scored = filtered.map((v) {
              final dur = v.duration?.inSeconds;
              final score = _scoreCandidate(v.title, v.author, sanitizedTitle, firstArtist, dur, expectedDuration);
              return MapEntry(v.id.value, score);
            }).toList();
            scored.sort((a, b) => b.value.compareTo(a.value));
            if (scored.first.value >= 400) return scored.first.key;
          }
        }
      } catch (e) {
        debugPrint('resolveVideoId YoutubeExplode error: $e');
      }
      return null;
    }

    final raceCompleter = Completer<String?>();
    int remaining = 2;
    void handleBranch(Future<String?> fut) {
      fut.then((vid) {
        if (!raceCompleter.isCompleted && vid != null && vid.isNotEmpty) {
          raceCompleter.complete(vid);
        }
      }).catchError((_) {}).whenComplete(() {
        remaining--;
        if (remaining <= 0 && !raceCompleter.isCompleted) {
          raceCompleter.complete(null);
        }
      });
    }

    handleBranch(searchViaVercel());
    handleBranch(searchViaExplode());

    final racedVid = await raceCompleter.future;
    if (racedVid != null && racedVid.isNotEmpty) {
      _streamCache[cleanKey] = racedVid;
      return racedVid;
    }

    // 2. Fallback: YouTube Music Multi-catalog API
    try {
      final multiUrl = Uri.parse('https://mctify.vercel.app/api/yt/search-multi?q=${Uri.encodeComponent('$sanitizedTitle $firstArtist')}');
      final multiRes = await http.get(multiUrl).timeout(const Duration(milliseconds: 2800));
      if (multiRes.statusCode == 200) {
        final multiData = jsonDecode(multiRes.body);
        final songs = multiData['songs'] as List? ?? [];
        final scored = <MapEntry<String, int>>[];
        for (final s in songs) {
          final vid = (s['videoId'] ?? s['id'] ?? '').toString();
          final sTitle = (s['title'] ?? '').toString();
          final sArtist = (s['artist'] ?? '').toString();
          final sDur = (s['duration'] as num?)?.toInt();
          if (vid.isNotEmpty && (excludeVideoIds == null || !excludeVideoIds.contains(vid))) {
            final score = _scoreCandidate(sTitle, sArtist, sanitizedTitle, firstArtist, sDur, expectedDuration);
            scored.add(MapEntry(vid, score));
          }
        }
        if (scored.isNotEmpty) {
          scored.sort((a, b) => b.value.compareTo(a.value));
          if (scored.first.value >= 400) {
            final bestId = scored.first.key;
            _streamCache[cleanKey] = bestId;
            return bestId;
          }
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId search-multi error: $e');
    }

    // 3. Fallback: YouTube Music WEB_REMIX API
    try {
      final url = Uri.parse('https://music.youtube.com/youtubei/v1/search');
      final body = jsonEncode({
        'context': {
          'client': {
            'clientName': 'WEB_REMIX',
            'clientVersion': '1.20240101.01.00',
            'hl': 'id',
            'gl': 'ID',
          }
        },
        'query': '$title $artist',
      });

      final res = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        },
        body: body,
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final matches = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"').allMatches(res.body);
        for (final m in matches) {
          final vid = m.group(1);
          if (vid != null && (excludeVideoIds == null || !excludeVideoIds.contains(vid))) {
            _streamCache[cleanKey] = vid;
            return vid;
          }
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId WEB_REMIX fallback error: $e');
    }

    return null;
  }

  void invalidateVideoId(String title, String artist, String failedVideoId) {
    final sanitizedTitle = title
        .replaceAll(RegExp(r'[\u00a0\u2000-\u200b\u202f\u205f\u3000]'), ' ')
        .replaceAll('◐', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final firstArtist = artist
        .split(',')[0]
        .replaceAll(RegExp(r'[\u00a0\u2000-\u200b\u202f\u205f\u3000]'), ' ')
        .trim();
    final cleanKey = 'vid_${sanitizedTitle.toLowerCase()}_${firstArtist.toLowerCase()}';
    if (_streamCache[cleanKey] == failedVideoId) {
      _streamCache.remove(cleanKey);
    }
  }

  /// Resolves direct, full-length YouTube audio stream based on chosen bitrate.
  /// Prioritizes MP4 (AAC) audio streams for native 100% Android MediaPlayer compatibility.
  Future<String?> resolveFullAudioStream(
    String title,
    String artist, [
    AudioQuality quality = AudioQuality.high,
    int? expectedDurationSeconds,
    Set<String>? excludeVideoIds,
  ]) async {
    final cleanKey = '$title $artist ${quality.name}'.toLowerCase().trim();
    if (_streamCache.containsKey(cleanKey)) {
      return _streamCache[cleanKey];
    }

    final excluded = Set<String>.from(excludeVideoIds ?? const {});
    try {
      for (int attempt = 0; attempt < 3; attempt++) {
        final bestVideoId = await resolveVideoId(title, artist, expectedDurationSeconds, excluded);
        if (bestVideoId == null || bestVideoId.isEmpty) break;

        try {
          final allStreams = await _getFastAudioStreams(bestVideoId);
          if (allStreams.isNotEmpty) {
            final chosenStream = _pickStreamByQuality(allStreams, quality);
            final proxyUrl = await _registerProxyStream(bestVideoId, chosenStream, quality);
            _streamCache[cleanKey] = proxyUrl;
            _streamCache['stream_${bestVideoId}_${quality.name}'] = proxyUrl;
            return proxyUrl;
          }
        } catch (e) {
          debugPrint('Stream manifest for $bestVideoId failed: $e, trying next candidate');
          excluded.add(bestVideoId);
        }
      }
    } catch (e) {
      debugPrint('resolveFullAudioStream error: $e');
    }
    return null;
  }

  static String extractCoreTitle(String title) {
    return title
        .replaceAll(RegExp(r'\s*[\(\[](feat|ft|with|prod\.)[^\)\]]*[\)\]]', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*(acoustic|live|remix|version|official).*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static int _scoreCandidate(
    String videoTitle,
    String videoAuthor,
    String title,
    String artist, [
    int? videoDurationSeconds,
    int? expectedDurationSeconds,
  ]) {
    final lowerTitle = videoTitle.toLowerCase();
    final lowerAuthor = videoAuthor.toLowerCase();
    final combined = '$lowerTitle $lowerAuthor';

    final normVideo = _normalizeQuery(videoTitle);
    final coreTitle = extractCoreTitle(title);
    final normCoreTitle = _normalizeQuery(coreTitle);
    final cleanTitle = title.toLowerCase();
    final normArtist = _normalizeQuery(artist);
    int score = 1000;

    // 1. STRICT CORE TITLE REQUIREMENT: Disqualify completely if candidate doesn't even contain the core song title!
    if (normVideo.contains(normCoreTitle)) {
      score += 650;
    } else {
      final coreTokens = normCoreTitle.split(' ').where((w) => w.length > 1).toList();
      final matchedCount = coreTokens.where((tok) => normVideo.contains(tok)).length;
      if (coreTokens.isNotEmpty && matchedCount == coreTokens.length) {
        score += 450;
      } else {
        score -= 2000; // WRONG SONG (e.g. No Brainer instead of I'm the One)!
      }
    }

    // 2. Strict Artist match requirement:
    final artistTokens = normArtist.split(' ').where((w) => w.length > 1).toList();
    final hasArtistMatch = artistTokens.any((tok) => normVideo.contains(tok) || lowerAuthor.contains(tok));
    if (hasArtistMatch) {
      if (normVideo.contains(normArtist) || lowerAuthor.contains(artist.toLowerCase())) {
        score += 500;
      } else {
        score += 250;
      }
    } else if (artistTokens.isNotEmpty) {
      // Disqualify completely if artist is different (e.g. French Montana when searching PnB Rock)
      score -= 5000;
    }

    final isAcousticRequested = cleanTitle.contains('acoustic');
    final isRemixRequested = cleanTitle.contains('remix');
    final isLiveRequested = cleanTitle.contains('live') || cleanTitle.contains('concert') || cleanTitle.contains('konser');
    final isSessionRequested = cleanTitle.contains('session');
    final isStrippedRequested = cleanTitle.contains('stripped') || cleanTitle.contains('piano');

    // Symmetrical version scoring:
    if (isAcousticRequested) {
      if (combined.contains('acoustic')) {
        score += 750;
        // Prefer clean studio acoustic release (zero intro dialogue/monologue) over live session videos
        if (lowerAuthor.contains('- topic') || lowerTitle.contains('official audio') || !combined.contains('live')) {
          score += 350;
        }
      } else {
        score -= 900;
      }
    } else {
      if (combined.contains('acoustic')) score -= 850;
    }

    if (isRemixRequested) {
      if (combined.contains('remix')) {
        score += 750;
      } else {
        score -= 900;
      }
    } else {
      if (combined.contains('remix')) score -= 850;
    }

    if (isLiveRequested) {
      if (combined.contains('live') || combined.contains('concert') || combined.contains('konser')) {
        score += 750;
      } else {
        score -= 900;
      }
    } else {
      if (combined.contains('live') ||
          combined.contains('concert') ||
          combined.contains('konser') ||
          combined.contains('fancam') ||
          combined.contains('live at') ||
          combined.contains('world tour') ||
          combined.contains('live session')) {
        score -= 3500; // STRICT ANTI-LIVE PENALTY: Never allow concert/live video to defeat studio master!
      }
    }

    if (isSessionRequested || isStrippedRequested) {
      if (combined.contains('session') || combined.contains('stripped')) {
        score += 750;
      }
    } else if (!isAcousticRequested && combined.contains('session')) {
      score -= 1500;
    }

    final unwanted = [
      '10 years', 'tribute', 'karaoke', 'terjemahan',
      'cover', 'guitar cover', 'drum cover', 'piano cover', 'reaction',
      'slowed', 'reverb', 'sped up', 'speed up', 'instrumental', 'instr.',
      'originally performed', 'made popular by', 'in the style of', 'parodi', 'parody', 'mashup',
      'backing track', 'acapella', 'minus one', 'no vocals', 'vocal guide',
      'sing-along', 'sing along', 'type beat', 'free beat', 'rap beat', 'trap beat',
      'ombre2choc'
    ];
    if (!isAcousticRequested && !isSessionRequested) {
      unwanted.addAll(['brooklyn session', 'session']);
    }

    for (final term in unwanted) {
      if (combined.contains(term) && !cleanTitle.contains(term)) {
        score -= 4500;
      }
    }

    // Heavy penalty for scraper & fake remix uploaders (e.g. Ombre2Choc Remix)
    if (lowerAuthor.contains('ombre2choc') || lowerAuthor.contains('karaoke') || lowerAuthor.contains('tribute band')) {
      score -= 5000;
    }

    // Strict Anti-Slowed / Anti-Reverb check if not explicitly requested
    final isSlowedRequested = cleanTitle.contains('slowed') || cleanTitle.contains('reverb') || cleanTitle.contains('sped up');
    if (!isSlowedRequested) {
      final slowedRegex = RegExp(r'\b(slowed|reverb|slowed \+ reverb|slowed and reverb|sped up|speed up|nightcore|8d audio)\b', caseSensitive: false);
      if (slowedRegex.hasMatch(combined)) {
        score -= 4500;
      }
    }

    // HEAVY BOOST FOR CLEAN STUDIO AUDIO (Topic track, Official Studio Release, or Official Audio)
    if (lowerAuthor.contains('- topic') || lowerTitle.contains('- topic') || combined.contains('official audio') || combined.contains('provided to youtube by')) {
      score += 1500;
    }

    // HEAVY PENALTY FOR MUSIC VIDEOS (Cinematic skits, pool dialogue, film intros desync lyrics & ruin listening!)
    final isMv = combined.contains('music video') ||
        combined.contains('official video') ||
        combined.contains('official music video') ||
        combined.contains('video klip') ||
        combined.contains('clip officiel') ||
        combined.contains('visualizer') ||
        RegExp(r'[\(\[]\s*(mv|official mv)\s*[\)\]]', caseSensitive: false).hasMatch(videoTitle);

    if (isMv) {
      score -= 750;
    }

    // Duration matching
    if (videoDurationSeconds != null && expectedDurationSeconds != null && expectedDurationSeconds > 0) {
      final diff = (videoDurationSeconds - expectedDurationSeconds).abs();
      if (diff <= 2) {
        score += 300;
      } else if (diff <= 5) {
        score += 150;
      } else if (diff <= 10) {
        score += 50;
      } else if (diff > 12) {
        score -= 400;
      }
      if (diff > 25) {
        score -= 900;
      }
    }
    return score;
  }

  // Official Top Tracks (Real Global & Indonesian Superhits with valid videoIds)
  static final List<Track> officialTopTracks = [
    Track(
      id: 'honne-location-unknown',
      videoId: 'SRNw0z7y2pI',
      title: 'Location Unknown (feat. Georgia)',
      artist: 'HONNE',
      album: 'Love Me / Love Me Not',
      artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=600',
      duration: 291,
      streamCount: '584.210.300',
      isExplicit: false,
    ),
    Track(
      id: 'jb-beauty-and-a-beat',
      videoId: 'Ys7-6_t7OEQ',
      title: 'Beauty and a Beat (feat. Nicki Minaj)',
      artist: 'Justin Bieber',
      album: 'Believe (Deluxe Edition)',
      artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600',
      duration: 228,
      streamCount: '1.240.560.800',
      isExplicit: false,
    ),
    Track(
      id: 'coldplay-yellow',
      videoId: 'yKNxeF4PqvU',
      title: 'Yellow',
      artist: 'Coldplay',
      album: 'Parachutes',
      artwork: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=600',
      duration: 269,
      streamCount: '2.140.890.120',
      isExplicit: false,
    ),
    Track(
      id: 'the-weeknd-blinding-lights',
      videoId: '4NRXx6U8ABQ',
      title: 'Blinding Lights',
      artist: 'The Weeknd',
      album: 'After Hours',
      artwork: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=600',
      duration: 200,
      streamCount: '3.890.100.540',
      isExplicit: false,
    ),
    Track(
      id: 'taylor-swift-cruel-summer',
      videoId: 'ic8j13U_FS8',
      title: 'Cruel Summer',
      artist: 'Taylor Swift',
      album: 'Lover',
      artwork: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=600',
      duration: 178,
      streamCount: '1.980.200.410',
      isExplicit: false,
    ),
    Track(
      id: 'bruno-die-with-a-smile',
      videoId: 'kPa7bsKwL-c',
      title: 'Die With A Smile',
      artist: 'Lady Gaga & Bruno Mars',
      album: 'Die With A Smile',
      artwork: 'https://images.unsplash.com/photo-1459749411175-04bf5292ceea?auto=format&fit=crop&q=80&w=600',
      duration: 251,
      streamCount: '980.450.000',
      isExplicit: false,
    ),
    Track(
      id: 'mahalini-sial',
      videoId: 'Wl29W8VfRkY',
      title: 'Sial',
      artist: 'Mahalini',
      album: 'F\u00E1bula',
      artwork: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=600',
      duration: 243,
      streamCount: '412.300.900',
      isExplicit: false,
    ),
    Track(
      id: 'sal-priadi-gala-bunga-matahari',
      videoId: '0qJ36kQz_rM',
      title: 'Gala Bunga Matahari',
      artist: 'Sal Priadi',
      album: 'MARKERS AND SUCH PENS FLASHDISKS',
      artwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=600',
      duration: 227,
      streamCount: '280.900.100',
      isExplicit: false,
    ),
    Track(
      id: 'bernadya-satu-bulan',
      videoId: 'gY4m_UoE_oI',
      title: 'Satu Bulan',
      artist: 'Bernadya',
      album: 'Sialnya, Hidup Harus Tetap Berjalan',
      artwork: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=600',
      duration: 205,
      streamCount: '340.100.200',
      isExplicit: false,
    ),
  ];

  // Popular Artists across Global & Indonesia
  static final List<Artist> catalogArtists = [
    Artist(
      id: 'art-honne',
      name: 'HONNE',
      headerBanner: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '6,2 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-justin-bieber',
      name: 'Justin Bieber',
      headerBanner: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '78,4 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-coldplay',
      name: 'Coldplay',
      headerBanner: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '89,1 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-taylor-swift',
      name: 'Taylor Swift',
      headerBanner: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1493225457124-a3eb161ffa5f?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '102,5 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-the-weeknd',
      name: 'The Weeknd',
      headerBanner: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '115,8 jt pendengar bulanan',
      isVerified: true,
    ),
    Artist(
      id: 'art-mahalini',
      name: 'Mahalini',
      headerBanner: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=1200',
      avatar: 'https://images.unsplash.com/photo-1516450360452-9312f5e86fc7?auto=format&fit=crop&q=80&w=400',
      monthlyListeners: '8,4 jt pendengar bulanan',
      isVerified: true,
    ),
  ];

  /// Universal Anti-Junk / Anti-Instrumental / Anti-Karaoke / Anti-Reverb Filter
  /// Strictly filters out non-original versions unless the user explicitly searched for them.
  static bool isUnwantedJunkTrack(String title, String artist, String album, [String? query]) {
    final qNorm = (query ?? '').toLowerCase().trim();
    final tLower = title.toLowerCase();
    final aLower = artist.toLowerCase();
    final albLower = album.toLowerCase();
    final combined = '$tLower $aLower $albLower';

    // If query explicitly requests instrumental, karaoke, slowed, cover, or remix, do not filter:
    final isInstrumentalWanted = qNorm.contains('instrumental') || qNorm.contains('instrumen');
    final isKaraokeWanted = qNorm.contains('karaoke') || qNorm.contains('backing track');
    final isSlowedWanted = qNorm.contains('slowed') || qNorm.contains('reverb') || qNorm.contains('sped up');
    final isCoverWanted = qNorm.contains('cover');

    if (!isInstrumentalWanted) {
      final instPattern = RegExp(r'\b(instrumental|instrument|instr\.?|minus one|no vocals|vocal guide|karaoke version|sing-along|sing along)\b', caseSensitive: false);
      if (instPattern.hasMatch(combined)) return true;
    }

    if (!isKaraokeWanted) {
      final karaokePattern = RegExp(r'\b(karaoke|backing track|tribute to|originally performed by|in the style of|made popular by)\b', caseSensitive: false);
      if (karaokePattern.hasMatch(combined)) return true;
    }

    if (!isCoverWanted) {
      final coverPattern = RegExp(r'\b(guitar cover|piano cover|drum cover|acoustic cover|violin cover|cello cover|cover by|bass tab|guitar tutorial)\b', caseSensitive: false);
      if (coverPattern.hasMatch(combined)) return true;
    }

    if (!isSlowedWanted) {
      final slowedPattern = RegExp(r'\b(slowed|reverb|slowed \+ reverb|slowed and reverb|sped up|speed up|nightcore|8d audio)\b', caseSensitive: false);
      if (slowedPattern.hasMatch(combined)) return true;
    }

    if (combined.contains('parodi') || combined.contains('parody')) return true;

    // Beat scraper detection (e.g. "type beat", "rap beat", "free beat")
    if (RegExp(r'\b(type beat|free beat|instrumental beat|rap beat|trap beat)\b', caseSensitive: false).hasMatch(combined)) {
      return true;
    }

    // Known scraper / fake remix artists (e.g. "Ombre2Choc Remix", "Karaoke All Stars")
    if (aLower.contains('ombre2choc') || aLower.contains('karaoke') || aLower.contains('tribute band')) {
      return true;
    }

    const bannedKeywords = [
      'reaction', 'teaser', 'trailer', 'podcast',
      'audio visualizer', 'cara ', 'belajar ', 'remake', 'audio only',
      'lirik video', 'lyrics video', 'acapella'
    ];
    if (bannedKeywords.any((b) => combined.contains(b))) return true;

    return false;
  }

  // Parallelized fast search helper: iTunes Global & ID catalog
  Future<List<Track>> _searchItunes(String query) async {
    final List<Track> list = [];
    try {
      final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&entity=song&limit=30');
      final res = await http.get(url).timeout(const Duration(milliseconds: 3200));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = (data['results'] as List? ?? []);
        for (final item in results) {
          final title = item['trackName'] ?? '';
          final artist = item['artistName'] ?? '';
          final album = item['collectionName'] ?? 'Single';
          if (title.isNotEmpty) {
            if (isUnwantedJunkTrack(title, artist, album, query)) continue;
            final tid = (item['trackId'] ?? '').toString();
            final genre = (item['primaryGenreName'] as String?) ?? 'Pop';
            String art = item['artworkUrl100'] ?? defaultArtwork;
            art = art.replaceAll('100x100bb', '600x600bb');
            list.add(Track(
              id: tid,
              title: title,
              artist: artist,
              album: album,
              artwork: art,
              audioUrl: '',
              duration: item['trackTimeMillis'] != null ? (item['trackTimeMillis'] / 1000).round() : 180,
              streamCount: '${(100 + list.length * 15)}.000.000',
              isExplicit: item['trackExplicitness'] == 'explicit',
              genre: genre,
            ));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // Parallelized fast search helper: Deezer Global Music Catalog
  Future<List<Track>> _searchDeezer(String query) async {
    final List<Track> list = [];
    try {
      final url = Uri.parse('https://api.deezer.com/search?q=${Uri.encodeComponent(query)}&limit=25');
      final res = await http.get(url).timeout(const Duration(milliseconds: 3000));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final items = (data['data'] as List? ?? []);
        for (final item in items) {
          final title = (item['title'] ?? '').toString();
          final artist = (item['artist']?['name'] ?? '').toString();
          final album = (item['album']?['title'] ?? 'Single').toString();
          if (title.isNotEmpty) {
            if (isUnwantedJunkTrack(title, artist, album, query)) continue;
            final tid = 'dz_${item['id']}';
            final rank = (item['rank'] as num?)?.toInt() ?? 0;
            list.add(Track(
              id: tid,
              title: title,
              artist: artist,
              album: album,
              artwork: (item['album']?['cover_big'] ?? item['album']?['cover_medium'] ?? defaultArtwork).toString(),
              audioUrl: '',
              duration: (item['duration'] as num?)?.toInt() ?? 180,
              streamCount: '${(80 + list.length * 12)}.000.000',
              isExplicit: item['explicit_lyrics'] == true,
              popularity: rank,
            ));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // Parallelized fast search helper: YouTube Music Multi-Catalog (Popularity-ordered Hits)
  Future<List<Track>> _searchYoutubeMusic(String query) async {
    final List<Track> list = [];
    try {
      final url = Uri.parse('https://mctify.vercel.app/api/yt/search-multi?q=${Uri.encodeComponent(query)}');
      final res = await http.get(url).timeout(const Duration(milliseconds: 3200));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final songs = (data['songs'] as List? ?? []);
        final qNorm = query.toLowerCase();
        final isLiveWanted = qNorm.contains('live') || qNorm.contains('concert') || qNorm.contains('konser');

        for (int i = 0; i < songs.length; i++) {
          final s = songs[i];
          final title = (s['title'] ?? '').toString();
          final artist = (s['artist'] ?? '').toString();
          final album = (s['album'] ?? 'Single').toString();
          final vid = (s['videoId'] ?? s['id'] ?? '').toString();
          if (title.isNotEmpty) {
            if (isUnwantedJunkTrack(title, artist, album, query)) continue;

            // Whole-word Anti-Live / Anti-Concert Filter (Prevents false positives on Alive, Long Live, Stay Alive, Deliver)
            if (!isLiveWanted) {
              final liveRegex = RegExp(r'\b(live at|live in|live from|\(live\)|\[live\]|- live|concert|konser|fancam|world tour)\b', caseSensitive: false);
              if (liveRegex.hasMatch(title.toLowerCase())) {
                continue;
              }
            }

            final pop = (850000 - (i * 25000)).clamp(200000, 850000);
            list.add(Track(
              id: 'yt_$vid',
              videoId: vid, // CRITICAL: preserve verified YouTube Music studio audio videoId!
              title: title,
              artist: artist,
              album: album,
              artwork: (s['artwork'] ?? defaultArtwork).toString(),
              audioUrl: '',
              duration: (s['duration'] as num?)?.toInt() ?? 180,
              streamCount: '${(300 - i * 10).clamp(50, 950)}.000.000',
              isExplicit: false,
              popularity: pop,
            ));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final row = List<int>.generate(b.length + 1, (i) => i);
    for (int i = 1; i <= a.length; i++) {
      int prev = row[0];
      row[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final current = row[j];
        if (a[i - 1] == b[j - 1]) {
          row[j] = prev;
        } else {
          int m = prev;
          if (row[j - 1] < m) m = row[j - 1];
          if (current < m) m = current;
          row[j] = 1 + m;
        }
        prev = current;
      }
    }
    return row[b.length];
  }

  static String _normalizeQuery(String s) {
    final base = s
        .toLowerCase()
        .replaceAll('ü', 'u')
        .replaceAll(RegExp(r"['’´`]"), '')
        .replaceAll(RegExp(r'[\(\)\[\]\-–—.,\/#!$%\^&\*;:{}=\_`~?]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Expand common abbreviations so informal queries find global studio titles
    final expanded = base.split(' ').map((t) {
      if (t == 'u') return 'you';
      if (t == 'ur') return 'your';
      if (t == 'r') return 'are';
      if (t == 'im') return 'i am';
      if (t == 'ft' || t == 'feat') return 'featuring';
      return t;
    }).toList();

    return expanded.join(' ');
  }

  static const List<String> _superstarArtists = [
    'justin bieber', 'dj khaled', 'the weeknd', 'taylor swift', 'bruno mars',
    'billie eilish', 'coldplay', 'ed sheeran', 'ariana grande', 'drake',
    'post malone', 'dua lipa', 'eminem', 'rihanna', 'maroon 5', 'shawn mendes',
    'charlie puth', 'sam smith', 'adele', 'katy perry', 'harry styles',
    'olivia rodrigo', 'kendrick lamar', 'travis scott', 'sza', 'bts', 'blackpink',
    'niki', 'rich brian', 'bernadya', 'sal priadi', 'hindia', 'mahalini',
    'tulus', 'juicy luicy', 'sheila on 7', 'dewa 19', 'noah', 'tiara andini',
    'lyodra', 'yura yunita', 'pamungkas', 'feby putri', 'fiersa besari', 'glenn fredly'
  ];

  static int _calculateSearchRelevance(Track track, String rawQuery) {
    final qNorm = _normalizeQuery(rawQuery);
    final qTokens = qNorm.split(' ').where((t) => t.isNotEmpty).toList();
    if (qTokens.isEmpty) return 0;

    final tTitle = _normalizeQuery(track.title);
    final tArtist = _normalizeQuery(track.artist);
    final tAlbum = _normalizeQuery(track.album);
    final combined = '$tTitle $tArtist';
    final trackWords = combined.split(' ').where((w) => w.isNotEmpty).toList();

    int score = 1000;

    double matchedTokens = 0;
    for (final qTok in qTokens) {
      int bestDist = 999;
      bool exactFound = false;

      for (final w in trackWords) {
        if (w == qTok) {
          exactFound = true;
          break;
        }
        if (w.contains(qTok) || qTok.contains(w)) {
          if (qTok.length >= 3 && w.length >= 3) {
            exactFound = true;
            break;
          }
        }
        // Typo tolerance (e.g. biebier -> bieber, know -> now)
        if (qTok.length >= 4 && w.length >= 4) {
          final d = _levenshtein(qTok, w);
          if (d < bestDist) bestDist = d;
        }
      }

      if (exactFound) {
        matchedTokens += 1.0;
        score += 260;
      } else if (bestDist <= 1) {
        matchedTokens += 0.9;
        score += 190;
      } else if (bestDist <= 2 && qTok.length >= 6) {
        matchedTokens += 0.6;
        score += 110;
      }
    }

    final matchRatio = matchedTokens / qTokens.length;
    score += (matchRatio * 700).round();

    // 1. Prefix match bonus (Spotify-like instant hit suggestion on short prefixes like "im the ")
    if (tTitle.startsWith(qNorm)) {
      score += 550;
    } else if (combined.startsWith(qNorm)) {
      score += 400;
    }

    // Exact phrase match bonus
    if (tTitle.contains(qNorm) || combined.contains(qNorm)) {
      score += 450;
    }
    if (tTitle == qNorm) {
      score += 650;
    }

    // 2. Global Popularity Boost (Deezer rank & YouTube Music stream weighting)
    if (track.popularity > 0) {
      score += ((track.popularity / 1000) * 0.85).round();
    }

    // 3. Superstar / Global Hitmaker artist bonus
    if (_superstarArtists.any((art) => tArtist.contains(art))) {
      score += 450;
    }

    // 4. Two-way version scoring for search (acoustic, remix, live)
    final isAcousticRequested = qNorm.contains('acoustic');
    final isRemixRequested = qNorm.contains('remix');
    final isLiveRequested = qNorm.contains('live') || qNorm.contains('concert') || qNorm.contains('konser');

    if (isAcousticRequested) {
      if (tTitle.contains('acoustic')) {
        score += 750;
      } else {
        score -= 900;
      }
    }
    if (isRemixRequested) {
      if (tTitle.contains('remix')) {
        score += 750;
      } else {
        score -= 900;
      }
    }
    if (isLiveRequested) {
      if (tTitle.contains('live') || tTitle.contains('concert')) {
        score += 750;
      } else {
        score -= 900;
      }
    }

    // HEAVY PENALTIES FOR NON-ORIGINAL TRACKS (Remix, Live, Concert, Cover, Karaoke, Tribute, Slowed)
    final junkWordRegex = RegExp(r'\b(karaoke|instrumental|tribute|parodi|parody|sped up|slowed|reverb|nightcore|reaction|tutorial|originally performed|made popular by|in the style of|backing track|guitar cover|piano cover|acoustic cover|acapella)\b', caseSensitive: false);
    if (!junkWordRegex.hasMatch(qNorm)) {
      if (junkWordRegex.hasMatch(tTitle)) score -= 3000;
      if (junkWordRegex.hasMatch(tAlbum)) score -= 1500;
      if (junkWordRegex.hasMatch(tArtist)) score -= 3000;
    } else {
      score += 300;
    }

    if (!isRemixRequested && !qNorm.contains('remix') && tTitle.contains('remix')) {
      score -= 850;
    }
    final liveRegex = RegExp(r'\b(live at|live in|live from|\(live\)|\[live\]|- live|concert|konser|fancam)\b', caseSensitive: false);
    if (!isLiveRequested && !isAcousticRequested && !qNorm.contains('live') &&
        (liveRegex.hasMatch(tTitle) || liveRegex.hasMatch(tAlbum))) {
      score -= 3500; // STRICT ANTI-LIVE FILTER: Original studio track is always prioritized
    }

    // STUDIO ORIGINAL BONUS (Official Studio Master)
    if (!tTitle.contains('remix') && !tTitle.contains('live') && !tTitle.contains('cover') && !tTitle.contains('karaoke') && !tTitle.contains('instrumental')) {
      score += 600;
    }
    if (tTitle.contains('official') || tTitle.contains('original')) {
      score += 300;
    }

    return score;
  }

  // Search tracks across query (Parallel Deezer + iTunes + YouTube Music + Unified Lyric Search)
  Future<List<Track>> searchTracks(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return [];

    if (_searchCache.containsKey(cleanQ)) {
      final cached = _searchCache[cleanQ]!;
      if (cached.isNotEmpty) return cached;
    }

    final List<Track> results = [];
    final Set<String> seenKeys = <String>{};
    final isLongQuery = cleanQ.split(RegExp(r'\s+')).length >= 3;

    // 0. Include matching tracks from User's Local Library (Liked & History - never lose searched songs!)
    try {
      final localLiked = await _storageService.getLikedTracks();
      final localHistory = await _storageService.getHistory();
      final localPool = [...localLiked, ...localHistory];
      for (final t in localPool) {
        final tTitle = t.title.toLowerCase();
        final tArtist = t.artist.toLowerCase();
        if (tTitle.contains(cleanQ) || tArtist.contains(cleanQ) || cleanQ.contains(tTitle)) {
          final key = '${_normalizeQuery(t.title)}___${_normalizeQuery(t.artist)}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            results.add(t);
          }
        }
      }
    } catch (_) {}

    // 1. Run YouTube Music, Deezer, iTunes (and Unified Lyric Search if 3+ words) in parallel (<350ms)
    final searchFutures = <Future<List<Track>>>[
      _searchYoutubeMusic(query),
      _searchDeezer(query),
      _searchItunes(query),
    ];
    if (isLongQuery) {
      searchFutures.add(searchTracksByLyrics(query));
    }

    final responses = await Future.wait(searchFutures);
    final ytTracks = responses.isNotEmpty ? responses[0] : <Track>[];
    final rawPool = <Track>[];
    for (final r in responses) {
      rawPool.addAll(r);
    }

    // CRITICAL SPEED FIX: Map YouTube Music videoIds and pre-attach onto Deezer & iTunes tracks!
    // This allows 100% of search tracks to play INSTANTLY in 50ms without resolveVideoId bottleneck!
    // Map YouTube Music videoIds and pre-attach onto Deezer & iTunes tracks
    // CRITICAL: NEVER map by title alone! Video ID is strictly matched ONLY when title matches AND artist shares significant tokens.
    final ytTrackMap = <String, String>{};
    for (final t in ytTracks) {
      if (t.videoId != null && t.videoId!.isNotEmpty) {
        final k = '${_normalizeQuery(t.title)}___${_normalizeQuery(t.artist)}';
        ytTrackMap[k] = t.videoId!;
      }
    }

    for (int i = 0; i < rawPool.length; i++) {
      final t = rawPool[i];
      if (t.videoId == null || t.videoId!.isEmpty) {
        final normT = _normalizeQuery(t.title);
        final normA = _normalizeQuery(t.artist);
        final k = '${normT}___$normA';
        String? vid = ytTrackMap[k];
        if (vid == null) {
          // Check if candidate artist matches target artist tokens (NEVER match by title alone!)
          final aTokens = normA.split(' ').where((w) => w.length > 2).toList();
          for (final entry in ytTrackMap.entries) {
            final parts = entry.key.split('___');
            if (parts.length == 2 && parts[0] == normT) {
              final candidateArtist = parts[1];
              if (aTokens.isNotEmpty && aTokens.any((tok) => candidateArtist.contains(tok))) {
                vid = entry.value;
                break;
              }
            }
          }
        }
        if (vid != null && vid.isNotEmpty) {
          rawPool[i] = t.copyWith(videoId: vid);
        }
      }
    }

    // 2. Score and deduplicate candidates by studio original relevance and typo tolerance
    rawPool.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));

    for (final t in rawPool) {
      if (isUnwantedJunkTrack(t.title, t.artist, t.album, query)) continue;
      final key = '${_normalizeQuery(t.title)}___${_normalizeQuery(t.artist)}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        results.add(t);
      }
    }

    // 3. Fallback: If no tracks found yet, try lyric search explicitly
    if (results.isEmpty && !isLongQuery) {
      final lyricTracks = await searchTracksByLyrics(query);
      for (final t in lyricTracks) {
        final key = '${_normalizeQuery(t.title)}___${_normalizeQuery(t.artist)}';
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          results.add(t);
        }
      }
    }

    // 4. Secondary fallback: Direct YouTube Search for ultra-niche or Indie tracks
    if (results.length < 3) {
      final yt = YoutubeExplode();
      try {
        final ytResults = await yt.search.search(query).timeout(const Duration(milliseconds: 2500));
        final ytCandidateTracks = <Track>[];
        for (final v in ytResults.take(8)) {
          final titleLower = v.title.toLowerCase();
          if (titleLower.contains('karaoke')) continue;
          final key = '${_normalizeQuery(v.title)}___${_normalizeQuery(v.author)}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            ytCandidateTracks.add(Track(
              id: 'yt_${v.id.value}',
              videoId: v.id.value,
              title: v.title,
              artist: v.author,
              album: 'YouTube Music',
              artwork: v.thumbnails.highResUrl,
              audioUrl: '',
              duration: v.duration?.inSeconds ?? 210,
              streamCount: '${(50 + results.length * 8)}.000.000',
              isExplicit: false,
            ));
          }
        }
        ytCandidateTracks.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));
        results.addAll(ytCandidateTracks);
      } catch (_) {
      } finally {
        yt.close();
      }
    }

    // Re-sort total results ensuring highest studio relevance is strictly on top
    results.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));

    // 5. Offline fallback only if all network sources fail completely
    if (results.isEmpty) {
      for (final t in officialTopTracks) {
        if (t.title.toLowerCase().contains(cleanQ) || t.artist.toLowerCase().contains(cleanQ)) {
          results.add(t);
        }
      }
    }

    // Only cache non-empty search results so temporary network dropouts don't permanently poison cache!
    if (results.isNotEmpty) {
      _searchCache[cleanQ] = results;
      if (_searchCache.length > 80) {
        _searchCache.remove(_searchCache.keys.first);
      }
    }

    return results;
  }

  static String? extractYouTubeId(String input) {
    if (input.trim().isEmpty) return null;
    final clean = input.trim();

    // 1. Support share message text with embedded URL (e.g. "Dengarkan di YouTube: https://youtu.be/...")
    final urlRegex = RegExp(r'https?://[^\s]+', caseSensitive: false);
    final urlMatch = urlRegex.firstMatch(clean);
    String target = urlMatch != null ? urlMatch.group(0)! : clean;

    // Strip trailing punctuation from messaging apps (e.g. . , ! ? ) > ] " ')
    target = target.replaceAll(RegExp(r'''[\.,!?;:)>\]"']+$'''), '');

    try {
      final uri = Uri.parse(target.startsWith('http') ? target : 'https://$target');
      String? videoId = uri.queryParameters['v'];
      if (videoId == null || videoId.isEmpty) {
        if (uri.host.contains('youtu.be')) {
          final segments = uri.pathSegments;
          if (segments.isNotEmpty) videoId = segments.first;
        } else if (uri.path.contains('/shorts/') || uri.path.contains('/embed/') || uri.path.contains('/live/') || uri.path.contains('/v/')) {
          final segments = uri.pathSegments;
          if (segments.isNotEmpty) videoId = segments.last;
        }
      }
      if (videoId != null) {
        if (videoId.contains('?')) videoId = videoId.split('?').first;
        if (videoId.contains('&')) videoId = videoId.split('&').first;
        if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(videoId)) return videoId;
      }
    } catch (_) {}

    // 2. Regex fallback
    final reg = RegExp(
      r'(?:youtu\.be\/|youtube(?:-nocookie)?\.com\/(?:embed\/|v\/|watch\?.*v=|shorts\/|live\/))([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = reg.firstMatch(target);
    if (match != null && match.groupCount >= 1) return match.group(1);
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) return clean;
    return null;
  }

  Future<Track?> resolveYouTubeImport(String input) async {
    final clean = input.trim();
    if (clean.isEmpty) return null;

    final videoId = extractYouTubeId(clean);

    // ==========================================
    // CASE A: DIRECT YOUTUBE LINK OR VIDEO ID
    // ==========================================
    if (videoId != null) {
      // 1. Official YouTube oEmbed API (<150ms latency, zero bot-detection / throttling risk)
      try {
        final oembedUrl = Uri.parse('https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=$videoId&format=json');
        final oembedRes = await http.get(oembedUrl).timeout(const Duration(seconds: 4));
        if (oembedRes.statusCode == 200) {
          final data = jsonDecode(oembedRes.body);
          String rawTitle = (data['title'] ?? 'YouTube Music').toString();
          String artist = (data['author_name'] ?? 'YouTube').toString();
          String title = rawTitle;

          if (rawTitle.contains(' - ')) {
            final parts = rawTitle.split(' - ');
            artist = parts[0].trim();
            title = parts.sublist(1).join(' - ').trim();
          }

          title = title
              .replaceAll(RegExp(r'\((Official (Music )?Video|Official Audio|Lyric(s)? Video)\)', caseSensitive: false), '')
              .replaceAll(RegExp(r'\[(Official (Music )?Video|Official Audio|Lyric(s)? Video)\]', caseSensitive: false), '')
              .trim();

          return Track(
            id: 'yt_$videoId',
            title: title.isNotEmpty ? title : 'YouTube Track',
            artist: artist.isNotEmpty ? artist : 'YouTube',
            album: 'YouTube Import',
            artwork: 'https://i.ytimg.com/vi/$videoId/hq720.jpg',
            audioUrl: '',
            videoId: videoId,
            duration: 210,
            streamCount: 'YouTube',
            isExplicit: false,
          );
        }
      } catch (e) {
        debugPrint('YouTube oEmbed resolve note: $e');
      }

      // 2. YoutubeExplode metadata lookup with 8-second timeout
      final yt = YoutubeExplode();
      try {
        final video = await yt.videos.get(videoId).timeout(const Duration(seconds: 8));
        String title = video.title;
        String artist = video.author;

        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        title = title
            .replaceAll(RegExp(r'\((Official (Music )?Video|Official Audio|Lyric(s)? Video)\)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[(Official (Music )?Video|Official Audio|Lyric(s)? Video)\]', caseSensitive: false), '')
            .trim();

        return Track(
          id: 'yt_${video.id.value}',
          title: title,
          artist: artist,
          album: 'YouTube Import',
          artwork: video.thumbnails.highResUrl.isNotEmpty ? video.thumbnails.highResUrl : 'https://i.ytimg.com/vi/$videoId/hq720.jpg',
          audioUrl: '',
          videoId: video.id.value,
          duration: video.duration?.inSeconds ?? 210,
          streamCount: 'YouTube',
          isExplicit: false,
        );
      } catch (e) {
        debugPrint('YoutubeExplode video get note: $e');
      } finally {
        yt.close();
      }

      // 3. Fail-safe fallback: We have a valid videoId, so NEVER fail or show error!
      return Track(
        id: 'yt_$videoId',
        title: 'YouTube Track ($videoId)',
        artist: 'YouTube',
        album: 'YouTube Import',
        artwork: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        audioUrl: '',
        videoId: videoId,
        duration: 210,
        streamCount: 'YouTube',
        isExplicit: false,
      );
    }

    // ==========================================
    // CASE B: SEARCH QUERY (SONG TITLE / ARTIST)
    // ==========================================
    // 1. First, search verified music catalog (iTunes/Deezer) for clean title & artist
    try {
      final catalogTracks = await searchTracks(clean);
      if (catalogTracks.isNotEmpty) {
        final top = catalogTracks.first;
        final vid = await resolveVideoId(top.title, top.artist, top.duration);
        if (vid != null && vid.isNotEmpty) {
          return Track(
            id: 'yt_$vid',
            title: top.title,
            artist: top.artist,
            album: top.album,
            artwork: top.artwork,
            audioUrl: '',
            videoId: vid,
            duration: top.duration,
            streamCount: 'YouTube Import',
            isExplicit: top.isExplicit,
          );
        }
      }
    } catch (e) {
      debugPrint('Search catalog fallback note: $e');
    }

    // 2. YoutubeExplode search fallback with 8-second timeout
    final yt = YoutubeExplode();
    try {
      final searchResults = await yt.search.search(clean).timeout(const Duration(seconds: 8));
      if (searchResults.isNotEmpty) {
        final v = searchResults.first;
        String title = v.title;
        String artist = v.author;
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

        title = title
            .replaceAll(RegExp(r'\((Official (Music )?Video|Official Audio|Lyric(s)? Video)\)', caseSensitive: false), '')
            .replaceAll(RegExp(r'\[(Official (Music )?Video|Official Audio|Lyric(s)? Video)\]', caseSensitive: false), '')
            .trim();

        return Track(
          id: 'yt_${v.id.value}',
          title: title,
          artist: artist,
          album: 'YouTube Search',
          artwork: v.thumbnails.highResUrl.isNotEmpty ? v.thumbnails.highResUrl : defaultArtwork,
          audioUrl: '',
          videoId: v.id.value,
          duration: v.duration?.inSeconds ?? 210,
          streamCount: 'YouTube',
          isExplicit: false,
        );
      }
    } catch (e) {
      debugPrint('resolveYouTubeImport search note: $e');
    } finally {
      yt.close();
    }

    // 3. Vercel backend search fallback
    try {
      final url = Uri.parse('https://mctify.vercel.app/api/yt/search?q=${Uri.encodeComponent(clean)}');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data != null && data['videoId'] != null) {
          final vid = data['videoId'].toString();
          return Track(
            id: 'yt_$vid',
            title: (data['title'] ?? clean).toString(),
            artist: (data['artist'] ?? 'YouTube').toString(),
            album: 'YouTube Search',
            artwork: (data['thumbnail'] ?? 'https://i.ytimg.com/vi/$vid/hqdefault.jpg').toString(),
            audioUrl: '',
            videoId: vid,
            duration: (data['duration'] as num?)?.toInt() ?? 210,
            streamCount: 'YouTube',
            isExplicit: false,
          );
        }
      }
    } catch (_) {}

    return null;
  }

  Future<List<Track>> searchTracksByLyrics(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return [];

    final List<Track> list = [];
    final Set<String> seen = {};

    // 1. YouTube Music Full Lyric Indexing Search via Vercel Backend
    final ytMusicFuture = () async {
      try {
        final url = Uri.parse('https://mctify.vercel.app/api/yt/search-multi?q=${Uri.encodeComponent(clean)}');
        final res = await http.get(url).timeout(const Duration(milliseconds: 3200));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final songs = (data['songs'] as List? ?? []);
          return songs;
        }
      } catch (_) {}
      return [];
    }();

    // 2. LRCLIB Worldwide Lyric Database Search
    final lrclibFuture = () async {
      try {
        final url = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(clean)}');
        final res = await http.get(url).timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is List) return data;
        }
      } catch (_) {}
      return [];
    }();

    final results = await Future.wait([ytMusicFuture, lrclibFuture]);
    final ytSongs = results[0];
    final lrcList = results[1];

    // Priority A: YouTube Music Studio Album Songs (Authentic master track from lyrics)
    for (int i = 0; i < ytSongs.length; i++) {
      final s = ytSongs[i];
      final title = (s['title'] ?? '').toString();
      final artist = (s['artist'] ?? '').toString();
      final vid = (s['videoId'] ?? s['id'] ?? '').toString();

      final lowerTitle = title.toLowerCase();
      // Anti-Live / Anti-Concert / Anti-Karaoke filter
      if (lowerTitle.contains('live') ||
          lowerTitle.contains('concert') ||
          lowerTitle.contains('konser') ||
          lowerTitle.contains('fancam') ||
          lowerTitle.contains('karaoke') ||
          lowerTitle.contains('instrumental')) {
        continue;
      }

      final key = '${title.toLowerCase().trim()}___${artist.toLowerCase().trim()}';
      if (title.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        list.add(Track(
          id: 'yt_$vid',
          videoId: vid,
          title: title,
          artist: artist,
          album: (s['album'] ?? 'Lirik: "$clean"').toString(),
          artwork: (s['artwork'] ?? defaultArtwork).toString(),
          audioUrl: '',
          duration: (s['duration'] as num?)?.toInt() ?? 180,
          streamCount: 'Cocok Lirik',
          isExplicit: false,
          popularity: 900000 - (i * 20000),
        ));
      }
    }

    // Priority B: LRCLIB Verified Lyric Database Hits
    for (final item in lrcList.take(6)) {
      final tName = (item['trackName'] ?? '').toString().trim();
      final aName = (item['artistName'] ?? '').toString().trim();
      final lowerTitle = tName.toLowerCase();
      if (lowerTitle.contains('live') || lowerTitle.contains('concert') || lowerTitle.contains('karaoke')) continue;

      final key = '${tName.toLowerCase()}___${aName.toLowerCase()}';
      if (tName.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        list.add(Track(
          id: 'lrc_${item['id']}',
          title: tName,
          artist: aName,
          album: (item['albumName'] ?? 'Lirik: "$clean"').toString(),
          artwork: defaultArtwork,
          audioUrl: '',
          duration: item['duration'] != null ? (item['duration'] as num).round() : 180,
          streamCount: 'Cocok Lirik',
          isExplicit: false,
          popularity: 850000,
        ));
      }
    }

    return list;
  }

  static String _formatFanCount(dynamic rawCount) {
    final n = rawCount is num ? rawCount.toInt() : int.tryParse(rawCount?.toString() ?? '') ?? 0;
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(1).replaceAll('.', ',')} jt pendengar';
    } else if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(0)} rb pendengar';
    }
    return n > 0 ? '$n penggemar' : 'Artis Terverifikasi';
  }

  // Real Spotify-grade Artist Search (Deezer Artist Catalog + YouTube Music + Local Verified Catalog)
  Future<List<Artist>> searchArtists(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return catalogArtists;

    final map = <String, Artist>{};

    // 1. Catalog preset artists matching query
    for (final a in catalogArtists) {
      if (a.name.toLowerCase().contains(cleanQ)) {
        map[a.name.toLowerCase().trim()] = a;
      }
    }

    // 2. Parallel real artist search from Deezer Artist API & YT Music multi-search
    Future<List<Artist>> fetchDeezerArtists() async {
      try {
        final url = Uri.parse('https://api.deezer.com/search/artist?q=${Uri.encodeComponent(query.trim())}&limit=8');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = (data['data'] as List?) ?? [];
          return list
              .where((item) => item['name'] != null && item['picture_big'] != null)
              .map<Artist>((item) {
                final picXl = (item['picture_xl'] ?? item['picture_big'] ?? item['picture_medium'] ?? defaultArtwork).toString();
                final picMed = (item['picture_big'] ?? item['picture_medium'] ?? defaultArtwork).toString();
                return Artist(
                  id: 'dz_art_${item['id']}',
                  name: item['name'].toString(),
                  headerBanner: picXl,
                  avatar: picMed,
                  monthlyListeners: _formatFanCount(item['nb_fan']),
                  isVerified: true,
                );
              })
              .toList();
        }
      } catch (_) {}
      return [];
    }

    Future<List<Artist>> fetchYtArtists() async {
      try {
        final url = Uri.parse('https://mctify.vercel.app/api/yt/search-multi?q=${Uri.encodeComponent(query.trim())}');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = (data['artists'] as List?) ?? [];
          return list
              .where((item) => item['name'] != null)
              .map<Artist>((item) {
                final art = Track.toHighResArtwork(item['artwork']?.toString() ?? defaultArtwork);
                return Artist(
                  id: (item['id'] ?? 'yt_art_${item['name']}').toString(),
                  name: item['name'].toString(),
                  headerBanner: art,
                  avatar: art,
                  monthlyListeners: (item['subscribers'] ?? 'Artis Populer').toString(),
                  isVerified: true,
                );
              })
              .toList();
        }
      } catch (_) {}
      return [];
    }

    final parallel = await Future.wait([fetchDeezerArtists(), fetchYtArtists()]);
    for (final artistList in parallel) {
      for (final a in artistList) {
        final key = a.name.toLowerCase().trim();
        if (key.isEmpty) continue;
        if (!map.containsKey(key)) {
          map[key] = a;
        }
      }
    }

    final list = map.values.toList();
    // Prioritize exact / prefix name matches
    list.sort((a, b) {
      final an = a.name.toLowerCase();
      final bn = b.name.toLowerCase();
      int scoreA = an == cleanQ ? 3 : (an.startsWith(cleanQ) ? 2 : (an.contains(cleanQ) ? 1 : 0));
      int scoreB = bn == cleanQ ? 3 : (bn.startsWith(cleanQ) ? 2 : (bn.contains(cleanQ) ? 1 : 0));
      return scoreB.compareTo(scoreA);
    });

    return list;
  }

  // Get Artist Profile Details & Popular Songs with Real Artwork Lookup
  Future<Map<String, dynamic>> getArtistDetails(String artistName) async {
    final clean = artistName.toLowerCase().trim();
    Artist? artist;

    final presetIdx = catalogArtists.indexWhere((a) => a.name.toLowerCase() == clean);
    if (presetIdx != -1) {
      artist = catalogArtists[presetIdx];
    } else {
      final fetchedArtists = await searchArtists(artistName);
      if (fetchedArtists.isNotEmpty) {
        artist = fetchedArtists.first;
      }
    }

    List<Track> topSongs = await searchTracks(artistName);
    if (topSongs.isEmpty) {
      topSongs = officialTopTracks.where((t) => t.artist.toLowerCase() == clean).toList();
      if (topSongs.isEmpty) {
        topSongs = officialTopTracks;
      }
    }

    artist ??= Artist(
      id: 'art-${Uri.encodeComponent(artistName)}',
      name: artistName,
      headerBanner: topSongs.isNotEmpty ? topSongs.first.artwork : defaultArtwork,
      avatar: topSongs.isNotEmpty ? topSongs.first.artwork : defaultArtwork,
      monthlyListeners: 'Artis Terverifikasi',
      isVerified: true,
    );

    return {
      'artist': artist,
      'topSongs': topSongs,
    };
  }

  /// Spotify-style live autocomplete suggestions as user types
  Future<List<String>> getSearchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    try {
      final url = Uri.parse(
          'https://mctify.vercel.app/api/yt/search-multi?mode=suggest&q=${Uri.encodeComponent(trimmed)}');
      final res = await http.get(url).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = (data['suggestions'] as List?) ?? [];
        return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).take(8).toList();
      }
    } catch (_) {}
    return [];
  }

  static String detectTrackRegion(String artistName, String title, String genre) {
    final normArtist = artistName.toLowerCase().trim();
    final normTitle = title.toLowerCase().trim();
    final normGenre = genre.toLowerCase().trim();

    // 1. Explicit genre matches
    if (normGenre.contains('k-pop') || normGenre.contains('kpop') || normGenre.contains('korean')) return 'kpop';
    if (normGenre.contains('j-pop') || normGenre.contains('jpop') || normGenre.contains('japanese') || normGenre.contains('anime')) return 'jpop';
    if (normGenre.contains('dangdut') || normGenre.contains('koplo') || normGenre.contains('campursari') || normGenre.contains('indo pop')) return 'indonesia';

    // 2. Known K-Pop artists
    const kpopArtists = [
      'bts', 'blackpink', 'newjeans', 'twice', 'aespa', 'stray kids', 'exo',
      'seventeen', 'red velvet', 'itzy', 'ive', 'le sserafim', 'txt', 'nct',
      'iu', 'taeyeon', 'enhypen', 'monsta x', 'ateez', 'got7', 'mamamoo', 'bigbang'
    ];
    if (kpopArtists.any((a) => normArtist.contains(a) || a.contains(normArtist))) return 'kpop';

    // 3. Known J-Pop artists
    const jpopArtists = [
      'yoasobi', 'kenshi yonezu', 'ado', 'aimer', 'official hige dandism',
      'fujii kaze', 'radwimps', 'one ok rock', 'eve', 'lisa', 'vaundy', 'king gnu'
    ];
    if (jpopArtists.any((a) => normArtist.contains(a) || a.contains(normArtist))) return 'jpop';

    // 4. Known Indonesian artists
    const indonesianArtists = [
      'sheila on 7', 'dewa 19', 'peterpan', 'noah', 'padi', 'ungu', "d'masiv",
      'ada band', 'kotak', 'gigi', 'slank', 'chrisye', 'ari lasso', 'kerispatih',
      'samsons', 'letto', 'naif', 'j-rocks', 'radja', 'wali', 'armada', 'repvblik',
      'seventeen', 'kangen band', 'jamrud', 'boomerang', 'mahalini', 'tulus',
      'juicy luicy', 'tiara andini', 'lyodra', 'ziva magnolya', 'yura yunita',
      'rizky febian', 'raisa', 'afgan', 'judika', 'fabio asher', 'budi doremi',
      'keisya levronka', 'jaz', 'andmesh', 'cakra khan', 'arash buana', 'idgitaf',
      'glenn fredly', 'marcell', 'rio febrian', 'sammy simorangkir', 'feby putri',
      'hindia', 'feast', '.feast', 'nadin amizah', 'sal priadi', 'kunto aji',
      'pamungkas', 'danilla', 'fourtwnty', 'barasuara', 'reality club',
      'efek rumah kaca', 'sore', 'the adams', 'morad', 'fiersa besari',
      'bilal indrajaya', 'bernadya', 'perunggu', 'jason ranti', 'soegi bornean',
      'denny caknan', 'guyon waton', 'ndarboy genk', 'happy asmara', 'gilga sahid',
      'didi kempot', 'nella kharisma', 'via vallen', 'gildcoustic', 'aftershine',
      'hendra kumbara', 'woro widowati', 'difarina indra', 'tasya rosmala',
      'shinta arsinta', 'masdddho', 'niken salindry'
    ];
    if (indonesianArtists.any((a) => normArtist.contains(a) || a.contains(normArtist))) {
      return 'indonesia';
    }

    // 5. Known Western / International / 88rising artists
    const westernArtists = [
      '88rising', 'joji', 'rich brian', 'niki', 'warren hue', 'stephanie poetri',
      'daniel caesar', 'frank ocean', 'sza', 'steve lacy', 'giveon', 'brent faiyaz',
      'keshi', 'umi', 'mac ayres', 'jeremy zucker', 'lauv', 'lany', 'honne',
      'alec benjamin', 'rex orange county', 'boy pablo', 'clairo', 'cuco',
      'faye webster', 'bruno major', 'dominic fike', 'childish gambino', 'khalid',
      'post malone', 'bazzi', 'pink sweat', 'the weeknd', 'bruno mars',
      'taylor swift', 'billie eilish', 'olivia rodrigo', 'ed sheeran', 'coldplay',
      'dua lipa', 'maroon 5', 'sabrina carpenter', 'ariana grande', 'justin bieber',
      'harry styles', 'lady gaga', 'shawn mendes', 'adele', 'sam smith', 'charlie puth',
      'linkin park', 'avenged sevenfold', 'green day', 'queen', 'arctic monkeys',
      'oasis', 'guns n roses', 'bon jovi', 'red hot chili peppers', 'foo fighters',
      'nirvana', 'metallica', 'paramore', 'my chemical romance', 'radiohead',
      'the beatles', 'ac/dc', 'u2', 'muse', 'eminem', 'drake', 'kendrick lamar',
      'travis scott', 'kanye west', 'snoop dogg', 'jay-z', 'juice wrld', 'xxxtentacion',
      'lil nas x', 'cardi b', 'nicky jam', 'alan walker', 'marshmello', 'avicii',
      'the chainsmokers', 'calvin harris', 'martin garrix', 'dj snake', 'david guetta',
      'zedd', 'kygo'
    ];
    if (westernArtists.any((a) => normArtist.contains(a) || a.contains(normArtist))) {
      return 'western';
    }

    // 6. Indonesian language keywords in title
    const indoTitleWords = [
      'yang', 'dan', 'di', 'ke', 'dari', 'ini', 'itu', 'untuk', 'pada', 'adalah',
      'dengan', 'bisa', 'ada', 'tak', 'tidak', 'kau', 'aku', 'kamu', 'dia',
      'mereka', 'kita', 'kami', 'hati', 'cinta', 'sayang', 'kasih', 'rindu',
      'sendiri', 'bersama', 'menunggu', 'pergi', 'hilang', 'kembali', 'pulang',
      'lagu', 'jiwa', 'malam', 'pagi', 'siang', 'sore', 'hujan', 'angin',
      'bintang', 'bulan', 'matahari', 'dunia', 'rasa', 'terlalu', 'sudah',
      'belum', 'jangan', 'hanya', 'saja', 'seperti', 'bukan', 'tentang',
      'saat', 'ketika', 'selalu', 'pernah', 'tanpa', 'masih', 'tetap',
      'hidup', 'mati', 'mimpi', 'bayang', 'senja', 'kenangan', 'luka', 'janji'
    ];
    final titleWords = normTitle.split(RegExp(r'[^a-zA-Z0-9]+')).where((s) => s.isNotEmpty);
    if (titleWords.any((word) => indoTitleWords.contains(word))) {
      return 'indonesia';
    }

    // 7. Common English words
    const englishWords = [
      'the', 'and', 'to', 'of', 'a', 'in', 'that', 'have', 'i', 'it', 'for',
      'not', 'on', 'with', 'he', 'as', 'you', 'do', 'at', 'this', 'but', 'his',
      'by', 'from', 'they', 'we', 'say', 'her', 'she', 'or', 'an', 'will', 'my',
      'one', 'all', 'would', 'there', 'their', 'what', 'so', 'up', 'out', 'if',
      'about', 'who', 'get', 'which', 'go', 'me', 'love', 'summer', 'madness',
      'night', 'day', 'sun', 'moon', 'star', 'rain', 'fire', 'light', 'dark',
      'sweet', 'young', 'forever', 'together', 'without', 'never', 'again',
      'always', 'some', 'where', 'how', 'why', 'little', 'big', 'high', 'low',
      'cold', 'hot', 'wild', 'free', 'crazy', 'lost', 'found', 'broken', 'home'
    ];
    if (titleWords.any((token) => englishWords.contains(token))) {
      return 'western';
    }

    return 'western';
  }

  static final List<Map<String, dynamic>> artistGenreClusters = [
    {
      'name': 'Western R&B, Chill Hop & Urban',
      'region': 'western',
      'genreKeywords': ['r&b', 'r&b/soul', 'soul', 'neo-soul', 'contemporary r&b', 'chill', 'lo-fi'],
      'keywords': [
        '88rising', 'joji', 'rich brian', 'niki', 'warren hue', 'stephanie poetri',
        'daniel caesar', 'frank ocean', 'sza', 'steve lacy', 'giveon',
        'brent faiyaz', 'keshi', 'umi', 'mac ayres', 'jeremy zucker',
        'lauv', 'lany', 'honne', 'alec benjamin', 'rex orange county',
        'boy pablo', 'clairo', 'cuco', 'faye webster', 'bruno major',
        'dominic fike', 'childish gambino', 'khalid', 'post malone', 'bazzi', 'pink sweat'
      ],
      'peers': [
        'Joji', 'Keshi', 'NIKI', 'Rich Brian', 'Daniel Caesar', 'Frank Ocean',
        'SZA', 'Steve Lacy', 'Giveon', 'Brent Faiyaz', 'Dominic Fike',
        'Jeremy Zucker', 'Lauv', 'LANY', 'HONNE', 'Rex Orange County', 'Boy Pablo'
      ]
    },
    {
      'name': 'Global & Western Pop Hits',
      'region': 'western',
      'genreKeywords': ['pop', 'dance pop', 'electropop', 'teen pop'],
      'keywords': [
        'the weeknd', 'bruno mars', 'taylor swift', 'billie eilish', 'olivia rodrigo',
        'ed sheeran', 'coldplay', 'dua lipa', 'maroon 5', 'post malone',
        'sabrina carpenter', 'ariana grande', 'justin bieber', 'harry styles',
        'lady gaga', 'shawn mendes', 'adele', 'sam smith', 'charlie puth',
        'sia', 'katy perry', 'miley cyrus', 'selena gomez', 'camila cabello'
      ],
      'peers': [
        'The Weeknd', 'Bruno Mars', 'Taylor Swift', 'Billie Eilish',
        'Olivia Rodrigo', 'Ed Sheeran', 'Coldplay', 'Dua Lipa', 'Maroon 5',
        'Sabrina Carpenter', 'Ariana Grande', 'Justin Bieber', 'Harry Styles'
      ]
    },
    {
      'name': 'Western Rock & Alternative Legends',
      'region': 'western',
      'genreKeywords': ['rock', 'alternative rock', 'classic rock', 'hard rock', 'grunge', 'metal'],
      'keywords': [
        'linkin park', 'avenged sevenfold', 'green day', 'queen', 'arctic monkeys',
        'oasis', 'guns n roses', 'bon jovi', 'red hot chili peppers', 'foo fighters',
        'nirvana', 'metallica', 'paramore', 'my chemical romance', 'radiohead',
        'the beatles', 'ac/dc', 'u2', 'muse', 'system of a down', 'bring me the horizon'
      ],
      'peers': [
        'Linkin Park', 'Avenged Sevenfold', 'Green Day', 'Queen',
        'Arctic Monkeys', 'Oasis', 'Guns N Roses', 'Red Hot Chili Peppers',
        'Nirvana', 'Paramore', 'My Chemical Romance', 'Radiohead'
      ]
    },
    {
      'name': 'Hip-Hop, Rap & Trap Hits',
      'region': 'western',
      'genreKeywords': ['hip-hop', 'rap', 'trap', 'hip hop'],
      'keywords': [
        'eminem', 'drake', 'kendrick lamar', 'travis scott', 'kanye west',
        'snoop dogg', 'jay-z', 'juice wrld', 'xxxtentacion', 'lil nas x',
        'cardi b', 'nicki minaj', '21 savage', 'metro boomin', 'future',
        'j. cole', 'post malone', 'mac miller', 'jack harlow', 'central cee'
      ],
      'peers': [
        'Eminem', 'Drake', 'Kendrick Lamar', 'Travis Scott', 'Kanye West',
        'Juice WRLD', 'Post Malone', 'J. Cole', 'Metro Boomin', 'Future'
      ]
    },
    {
      'name': 'EDM, Dance & Electronic Hits',
      'region': 'western',
      'genreKeywords': ['electronic', 'dance', 'edm', 'house', 'techno', 'dubstep'],
      'keywords': [
        'alan walker', 'marshmello', 'avicii', 'the chainsmokers', 'calvin harris',
        'martin garrix', 'dj snake', 'david guetta', 'zedd', 'kygo', 'skrillex',
        'tiesto', 'alesso', 'major lazer', 'illenium', 'clean bandit', 'galantis'
      ],
      'peers': [
        'Alan Walker', 'Marshmello', 'Avicii', 'The Chainsmokers',
        'Calvin Harris', 'Martin Garrix', 'Zedd', 'Kygo'
      ]
    },
    {
      'name': 'Indonesian Pop & Ballad Hits',
      'region': 'indonesia',
      'genreKeywords': ['pop', 'indo pop', 'indonesian pop', 'ballad'],
      'keywords': [
        'mahalini', 'tulus', 'juicy luicy', 'tiara andini', 'lyodra', 'ziva magnolya',
        'yura yunita', 'rizky febian', 'raisa', 'afgan', 'judika', 'fabio asher',
        'budi doremi', 'keisya levronka', 'jaz', 'andmesh', 'cakra khan', 'arash buana',
        'idgitaf', 'glenn fredly', 'marcell', 'rio febrian', 'sammy simorangkir', 'feby putri'
      ],
      'peers': [
        'Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra',
        'Yura Yunita', 'Rizky Febian', 'Raisa', 'Afgan', 'Judika'
      ]
    },
    {
      'name': 'Indonesian Indie, Folk & Alternative Hits',
      'region': 'indonesia',
      'genreKeywords': ['indie', 'alternative', 'folk', 'indie pop', 'acoustic'],
      'keywords': [
        'hindia', 'feast', '.feast', 'nadin amizah', 'sal priadi', 'kunto aji',
        'pamungkas', 'danilla', 'fourtwnty', 'barasuara', 'reality club',
        'efek rumah kaca', 'sore', 'the adams', 'morad', 'fiersa besari',
        'bilal indrajaya', 'bernadya', 'perunggu', 'jason ranti', 'soegi bornean'
      ],
      'peers': [
        'Hindia', '.Feast', 'Nadin Amizah', 'Sal Priadi', 'Kunto Aji',
        'Pamungkas', 'Fourtwnty', 'Reality Club', 'Barasuara', 'The Adams'
      ]
    },
    {
      'name': 'Indonesian Pop Rock & Legend Band Hits',
      'region': 'indonesia',
      'genreKeywords': ['rock', 'pop rock', 'legend', 'band indonesia', 'classic rock'],
      'keywords': [
        'sheila on 7', 'dewa 19', 'peterpan', 'noah', 'padi', 'ungu', "d'masiv",
        'ada band', 'kotak', 'gigi', 'slank', 'chrisye', 'ari lasso', 'kerispatih',
        'samsons', 'letto', 'naif', 'j-rocks', 'radja', 'wali', 'armada', 'repvblik',
        'seventeen', 'kangen band', 'jamrud', 'boomerang'
      ],
      'peers': [
        'Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Padi', 'Ungu',
        "D'Masiv", 'Ada Band', 'Ari Lasso', 'Glenn Fredly'
      ]
    },
    {
      'name': 'Indonesian Dangdut, Koplo & Jawa Pop Hits',
      'region': 'indonesia',
      'genreKeywords': ['dangdut', 'koplo', 'jawa', 'campursari'],
      'keywords': [
        'denny caknan', 'guyon waton', 'ndarboy genk', 'happy asmara', 'gilga sahid',
        'didi kempot', 'nella kharisma', 'via vallen', 'gildcoustic', 'aftershine',
        'hendra kumbara', 'woro widowati', 'difarina indra', 'tasya rosmala',
        'shinta arsinta', 'masdddho', 'niken salindry'
      ],
      'peers': [
        'Denny Caknan', 'Guyon Waton', 'Happy Asmara', 'Gilga Sahid',
        'Ndarboy Genk', 'Didi Kempot', 'Aftershine'
      ]
    },
    {
      'name': 'K-Pop & Korean Hits',
      'region': 'kpop',
      'genreKeywords': ['k-pop', 'kpop', 'korean pop', 'korean'],
      'keywords': [
        'bts', 'blackpink', 'newjeans', 'twice', 'aespa', 'stray kids', 'exo',
        'seventeen', 'red velvet', 'itzy', 'ive', 'le sserafim', 'txt', 'nct',
        'iu', 'taeyeon', 'enhypen', 'monsta x', 'ateez', 'got7', 'mamamoo', 'bigbang'
      ],
      'peers': [
        'NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM',
        'IVE', 'TWICE', 'IU', 'Seventeen', 'Stray Kids'
      ]
    },
    {
      'name': 'J-Pop & Japanese Hits',
      'region': 'jpop',
      'genreKeywords': ['j-pop', 'jpop', 'japanese', 'anime'],
      'keywords': [
        'yoasobi', 'kenshi yonezu', 'ado', 'aimer', 'official hige dandism',
        'fujii kaze', 'radwimps', 'one ok rock', 'eve', 'lisa', 'vaundy', 'king gnu'
      ],
      'peers': [
        'YOASOBI', 'Kenshi Yonezu', 'Ado', 'Aimer', 'Official HIGE DANdism',
        'Fujii Kaze', 'RADWIMPS', 'ONE OK ROCK', 'Eve'
      ]
    }
  ];

  List<String> getSimilarArtists(String artistName, {String? genre, List<String>? playlistArtists, String? title}) {
    final normArtist = artistName.toLowerCase().trim();
    final normGenre = (genre ?? '').toLowerCase().trim();
    final targetRegion = detectTrackRegion(artistName, title ?? '', genre ?? '');

    // 1. Direct artist match in cluster
    if (normArtist.isNotEmpty) {
      for (final cluster in artistGenreClusters) {
        final keywords = (cluster['keywords'] as List<String>);
        if (keywords.any((k) => normArtist.contains(k) || k.contains(normArtist))) {
          final peers = (cluster['peers'] as List<String>)
              .where((p) => !p.toLowerCase().contains(normArtist) && !normArtist.contains(p.toLowerCase()))
              .toList()..shuffle();
          return peers;
        }
      }
    }

    // 2. Dominant playlist artist cluster matching target region
    if (playlistArtists != null && playlistArtists.isNotEmpty) {
      final clusterScores = <Map<String, dynamic>, int>{};
      for (final pArtist in playlistArtists) {
        final pNorm = pArtist.toLowerCase().trim();
        for (final cluster in artistGenreClusters) {
          if (cluster['region'] == targetRegion) {
            final keywords = (cluster['keywords'] as List<String>);
            if (keywords.any((k) => pNorm.contains(k) || k.contains(pNorm))) {
              clusterScores[cluster] = (clusterScores[cluster] ?? 0) + 1;
            }
          }
        }
      }
      if (clusterScores.isNotEmpty) {
        final topCluster = clusterScores.entries.reduce((a, b) => a.value > b.value ? a : b).key;
        final peers = (topCluster['peers'] as List<String>)
            .where((p) => !p.toLowerCase().contains(normArtist) && !normArtist.contains(p.toLowerCase()))
            .toList()..shuffle();
        return peers;
      }
    }

    // 3. Match genre keyword restricted to target region
    if (normGenre.isNotEmpty) {
      for (final cluster in artistGenreClusters) {
        if (cluster['region'] == targetRegion) {
          final genreKeywords = (cluster['genreKeywords'] as List<String>);
          if (genreKeywords.any((gk) => normGenre.contains(gk))) {
            final peers = (cluster['peers'] as List<String>)
                .where((p) => !p.toLowerCase().contains(normArtist) && !normArtist.contains(p.toLowerCase()))
                .toList()..shuffle();
            return peers;
          }
        }
      }
    }

    // 4. Region-locked fallbacks (strictly respect target region!)
    if (targetRegion == 'western') {
      final westernPools = [
        ['The Weeknd', 'Bruno Mars', 'Coldplay', 'Taylor Swift', 'Billie Eilish', 'Olivia Rodrigo'],
        ['Joji', 'Keshi', 'NIKI', 'Daniel Caesar', 'Frank Ocean', 'SZA', 'Dominic Fike'],
        ['Linkin Park', 'Avenged Sevenfold', 'Green Day', 'Queen', 'Arctic Monkeys'],
        ['Eminem', 'Drake', 'Kendrick Lamar', 'Travis Scott', 'Post Malone', 'Juice WRLD']
      ];
      final selected = (List.from(westernPools)..shuffle()).first;
      return List<String>.from(selected)..shuffle();
    }

    if (targetRegion == 'kpop') {
      return (['NewJeans', 'BTS', 'BLACKPINK', 'aespa', 'LE SSERAFIM', 'TWICE', 'IU']..shuffle());
    }

    if (targetRegion == 'jpop') {
      return (['YOASOBI', 'Kenshi Yonezu', 'Ado', 'Aimer', 'RADWIMPS', 'Official HIGE DANdism']..shuffle());
    }

    final fallbackPools = [
      ['Sheila On 7', 'Dewa 19', 'NOAH', 'Peterpan', 'Ungu', "D'Masiv"],
      ['Mahalini', 'Tulus', 'Juicy Luicy', 'Tiara Andini', 'Lyodra', 'Yura Yunita', 'Rizky Febian'],
      ['Denny Caknan', 'Guyon Waton', 'Happy Asmara', 'Gilga Sahid', 'Ndarboy Genk']
    ];
    final selected = (List.from(fallbackPools)..shuffle()).first;
    return List<String>.from(selected)..shuffle();
  }


  // Fetch Trending / Starter Tracks dynamically from diverse hitmaker charts
  Future<List<Track>> getTrendingTracks() async {
    try {
      final topArtists = [
        'The Weeknd', 'Bruno Mars', 'Coldplay', 'Taylor Swift', 'Billie Eilish',
        'Sheila On 7', 'Dewa 19', 'NOAH', 'Mahalini', 'Tulus',
        'Linkin Park', 'Avenged Sevenfold', 'NewJeans', 'Denny Caknan'
      ];
      final shuffled = List<String>.from(topArtists)..shuffle();
      final results = <Track>[];
      final seen = <String>{};

      for (final artist in shuffled.take(4)) {
        final artistTracks = await searchTracks(artist);
        for (final t in artistTracks) {
          final key = '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(t);
            if (results.length >= 20) break;
          }
        }
        if (results.length >= 20) break;
      }

      if (results.isNotEmpty) {
        return results;
      }
    } catch (e) {
      debugPrint('getTrendingTracks dynamic fetch note: $e');
    }
    return officialTopTracks;
  }

  /// Filter out parodies, karaoke, tutorials, and non-studio junk
  static bool isCleanPopularTrack(Track t) {
    if (t.title.isEmpty || t.artist.isEmpty) return false;
    if (isUnwantedJunkTrack(t.title, t.artist, t.album)) return false;
    if (t.duration < 75 || t.duration > 450) return false;
    return true;
  }

  /// Yugen-inspired Round-Robin artist spreading:
  /// Disperses tracks across unique artists so that no single artist
  /// monopolizes the queue, creating a balanced and rich listening experience.
  static List<Track> spreadArtists(List<Track> tracks, {int maxPerArtist = 2}) {
    if (tracks.isEmpty) return [];
    final byArtist = <String, List<Track>>{};
    for (final t in tracks) {
      final key = t.artist.toLowerCase().trim();
      byArtist.putIfAbsent(key, () => []).add(t);
    }

    // Shuffle tracks within each artist for variety
    for (final list in byArtist.values) {
      list.shuffle();
    }

    final result = <Track>[];
    final artistKeys = byArtist.keys.toList()..shuffle();

    for (var round = 0; round < maxPerArtist; round++) {
      for (final aKey in artistKeys) {
        final list = byArtist[aKey]!;
        if (round < list.length) {
          result.add(list[round]);
        }
      }
    }

    return result;
  }

  static final Set<String> recentRadioHistory = <String>{};
  static const int maxRecentHistory = 40;

  static void recordRecentRadioTrack(String key) {
    if (key.isEmpty) return;
    recentRadioHistory.add(key.toLowerCase().trim());
    if (recentRadioHistory.length > maxRecentHistory) {
      recentRadioHistory.remove(recentRadioHistory.first);
    }
  }

  static void clearRecentRadioHistory() {
    recentRadioHistory.clear();
  }

  /// Finds famous, popular tracks related to current track and playlist for smart radio / next queue
  Future<List<Track>> getSmartRecommendations(Track currentTrack, {List<Track>? queue}) async {
    final pool = <Track>[];
    final seen = <String>{
      '${currentTrack.title.toLowerCase().trim()}_${currentTrack.artist.toLowerCase().trim()}'
    };

    try {
      final targetRegion = detectTrackRegion(currentTrack.artist, currentTrack.title, currentTrack.genre);
      final playlistArtists = queue?.map((t) => t.artist).toList();

      // 1. Resolve matching peers in same region
      final allPeers = getSimilarArtists(
        currentTrack.artist,
        genre: currentTrack.genre,
        playlistArtists: playlistArtists,
        title: currentTrack.title,
      );

      // Randomly pick 4 peers for non-template variety
      final selectedPeers = (List<String>.from(allPeers)..shuffle()).take(4).toList();

      // 2. Query artist hits and peer hits in parallel
      final artistSearchFuture = searchTracks(currentTrack.artist);
      final peerFutures = selectedPeers.map((peer) => searchTracks(peer));

      final results = await Future.wait([artistSearchFuture, ...peerFutures]);
      final artistTracks = results[0];
      final peerResults = results.sublist(1);

      final candidates = <Track>[];

      for (final t in artistTracks) {
        if (!isCleanPopularTrack(t)) continue;
        final key = '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
        if (seen.contains(key)) continue;
        seen.add(key);
        candidates.add(t);
      }

      for (final peerTracks in peerResults) {
        for (final t in peerTracks) {
          if (!isCleanPopularTrack(t)) continue;
          final region = detectTrackRegion(t.artist, t.title, t.genre);
          if (region != targetRegion) continue; // STRICT REGIONAL ISOLATION!

          final key = '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
          if (seen.contains(key)) continue;
          seen.add(key);
          candidates.add(t);
        }
      }

      // Anti-template memory filter
      final freshCandidates = candidates
          .where((t) => !recentRadioHistory.contains(t.title.toLowerCase().trim()))
          .toList();

      final poolToSpread = freshCandidates.length >= 8 ? freshCandidates : candidates;
      if (poolToSpread == candidates) {
        recentRadioHistory.clear();
      }

      // YUGEN SPREAD_ARTISTS: Round-Robin interleaving across artists!
      final spreadQueue = spreadArtists(poolToSpread, maxPerArtist: 2);

      for (final t in spreadQueue) {
        recordRecentRadioTrack(t.title);
      }

      if (spreadQueue.isNotEmpty) {
        return spreadQueue.take(15).toList();
      }
    } catch (e) {
      debugPrint('getSmartRecommendations error: $e');
    }

    return pool.isNotEmpty ? pool : officialTopTracks;
  }
}
