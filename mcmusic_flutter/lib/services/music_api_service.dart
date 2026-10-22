import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import '../models/artist.dart';
import '../models/audio_quality.dart';

class MusicApiService {
  static const String defaultArtwork = 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=600';
  static final Map<String, String> _streamCache = {};

  /// Invalidate stream URL cache (called when user switches audio quality)
  static void clearStreamCache() {
    _streamCache.clear();
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

  /// Resolves direct, full-length YouTube MP4 audio stream from videoId
  Future<String?> resolveStreamUrlFromVideoId(String videoId) async {
    final cleanKey = 'stream_$videoId';
    if (_streamCache.containsKey(cleanKey)) {
      return _streamCache[cleanKey];
    }
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 8));
      final mp4Streams = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      final chosen = mp4Streams.isNotEmpty ? mp4Streams.last : manifest.audioOnly.withHighestBitrate();
      final streamUrl = chosen.url.toString();
      _streamCache[cleanKey] = streamUrl;
      return streamUrl;
    } catch (e) {
      debugPrint('resolveStreamUrlFromVideoId error for $videoId: $e');
    } finally {
      yt.close();
    }
    return null;
  }

  /// Returns cached stream URL if already resolved (guaranteeing it's never a 30s preview)
  String? getCachedStream(Track track, [AudioQuality quality = AudioQuality.high]) {
    if (track.audioUrl.isNotEmpty && !isPreviewUrl(track.audioUrl)) {
      return track.audioUrl;
    }
    if (track.videoId != null && track.videoId!.isNotEmpty) {
      final key = 'stream_${track.videoId}';
      if (_streamCache.containsKey(key)) return _streamCache[key];
    }
    final cleanKey = '${track.title} ${track.artist} ${quality.name}'.toLowerCase().trim();
    if (_streamCache.containsKey(cleanKey)) return _streamCache[cleanKey];
    return null;
  }

  /// Silently pre-fetches and caches next audio stream in background for zero-latency playback
  Future<void> prefetchTrackStream(Track track, [AudioQuality quality = AudioQuality.high]) async {
    try {
      String? vid = track.videoId;
      if (vid == null || vid.isEmpty) {
        vid = await resolveVideoId(track.title, track.artist, track.duration);
      }
      if (vid != null && vid.isNotEmpty) {
        await resolveDirectAudioStream(track.copyWith(videoId: vid), quality);
      }
    } catch (_) {}
  }

  /// Resolves direct audio stream for native ExoPlayer background playback (100% full song only!)
  Future<String?> resolveDirectAudioStream(Track track, [AudioQuality quality = AudioQuality.high]) async {
    final cached = getCachedStream(track, quality);
    if (cached != null) return cached;

    // 1. Try resolving direct stream via videoId if already present on track
    String? vid = track.videoId;
    if (vid == null || vid.isEmpty) {
      vid = await resolveVideoId(track.title, track.artist, track.duration);
    }

    if (vid != null && vid.isNotEmpty) {
      final url = await resolveStreamUrlFromVideoId(vid);
      if (url != null && url.isNotEmpty) {
        final key = '${track.title} ${track.artist} ${quality.name}'.toLowerCase().trim();
        _streamCache[key] = url;
        return url;
      }
    }

    // 2. Resolve direct MP4 audio stream from YouTube Explode (full 3-5+ minute song!)
    final stream = await resolveFullAudioStream(track.title, track.artist, quality, track.duration);
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

    // 1. Primary: McMusic Vercel Backend API (powered by youtubei.js YouTube Music)
    // Instant ~120ms response, strictly returns official studio album audio tracks (Topic tracks), 0 skits.
    try {
      final url = Uri.parse('https://mctify.vercel.app/api/yt/search?title=${Uri.encodeComponent(title)}&artist=${Uri.encodeComponent(artist)}&duration=${expectedDuration ?? 0}&q=${Uri.encodeComponent('$title $artist')}');
      final res = await http.get(url).timeout(const Duration(milliseconds: 3500));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final vid = data['videoId'] as String?;
        final resTitle = (data['title'] as String? ?? '').toLowerCase();
        final resArtist = (data['artist'] as String? ?? '').toLowerCase();
        final resDur = (data['duration'] as num?)?.toInt();
        final isDurAcceptable = expectedDuration == null ||
            expectedDuration == 0 ||
            resDur == null ||
            (resDur - expectedDuration).abs() <= 20;

        // Anti-Karaoke / Anti-Instrumental / Anti-Cover filter on backend results:
        final cleanQ = '$title $artist'.toLowerCase();
        final isUnwanted = (resTitle.contains('karaoke') ||
                resTitle.contains('instrumental') ||
                resTitle.contains('made popular by') ||
                resTitle.contains('backing track') ||
                resTitle.contains('tribute') ||
                resTitle.contains('parodi') ||
                resTitle.contains('parody') ||
                resArtist.contains('karaoke')) &&
            !cleanQ.contains('karaoke') &&
            !cleanQ.contains('instrumental');

        if (vid != null &&
            vid.isNotEmpty &&
            !isUnwanted &&
            isDurAcceptable &&
            (excludeVideoIds == null || !excludeVideoIds.contains(vid))) {
          _streamCache[cleanKey] = vid;
          return vid;
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId Vercel backend error: $e');
    }

    // 2. Fallback: Search via YoutubeExplode with Smart Candidate Scoring
    final yt = YoutubeExplode();
    try {
      // Query with 'audio' first to find clean studio tracks over 40s-skit music videos
      final searchResults = await yt.search.search('$sanitizedTitle $firstArtist audio').timeout(const Duration(seconds: 4));
      var pool = searchResults.take(10).toList();
      if (pool.isEmpty) {
        final broadResults = await yt.search.search('$sanitizedTitle $firstArtist').timeout(const Duration(seconds: 4));
        pool = broadResults.take(10).toList();
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
          final bestId = scored.first.key;
          _streamCache[cleanKey] = bestId;
          return bestId;
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId YoutubeExplode error: $e');
    } finally {
      yt.close();
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
    final yt = YoutubeExplode();
    try {
      for (int attempt = 0; attempt < 3; attempt++) {
        final bestVideoId = await resolveVideoId(title, artist, expectedDurationSeconds, excluded);
        if (bestVideoId == null || bestVideoId.isEmpty) break;

        try {
          final manifest = await yt.videos.streamsClient.getManifest(bestVideoId);
          final allStreams = manifest.audioOnly.toList();
          if (allStreams.isNotEmpty) {
            // CRITICAL: Prefer MP4 (AAC) streams. Android native MediaPlayer plays MP4/AAC reliably
            // across all devices, whereas WebM/Opus frequently fails with MEDIA_ERROR_UNKNOWN.
            final mp4Streams = allStreams.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
            final candidateStreams = mp4Streams.isNotEmpty ? mp4Streams : allStreams;

            candidateStreams.sort((a, b) => a.bitrate.compareTo(b.bitrate));

            AudioStreamInfo chosenStream;
            switch (quality) {
              case AudioQuality.dataSaver:
                chosenStream = candidateStreams.first;
                break;
              case AudioQuality.standard:
                chosenStream = candidateStreams.firstWhere(
                  (s) => s.bitrate.kiloBitsPerSecond <= 140,
                  orElse: () => candidateStreams.last,
                );
                break;
              case AudioQuality.high:
                chosenStream = candidateStreams.last;
                break;
            }

            final streamUrl = chosenStream.url.toString();
            _streamCache[cleanKey] = streamUrl;
            return streamUrl;
          }
        } catch (e) {
          debugPrint('Stream manifest for $bestVideoId failed: $e, trying next candidate');
          excluded.add(bestVideoId);
        }
      }
    } catch (e) {
      debugPrint('resolveFullAudioStream error: $e');
    } finally {
      yt.close();
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
    final firstArtist = normArtist.split(' ').first;
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

    // 2. Artist match bonus
    if (normVideo.contains(normArtist) || lowerAuthor.contains(artist.toLowerCase())) {
      score += 200;
    } else if (normVideo.contains(firstArtist) || lowerAuthor.contains(firstArtist)) {
      score += 100;
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
    } else if (!isAcousticRequested) {
      if (combined.contains('live') || combined.contains('concert') || combined.contains('konser')) {
        score -= 850;
      }
    }

    if (isSessionRequested || isStrippedRequested) {
      if (combined.contains('session') || combined.contains('stripped')) {
        score += 750;
      }
    } else if (!isAcousticRequested && combined.contains('session')) {
      score -= 600;
    }

    final unwanted = [
      '10 years', 'tribute', 'karaoke', 'terjemahan',
      'cover', 'guitar cover', 'drum cover', 'piano cover', 'reaction',
      'slowed', 'reverb', 'sped up', 'speed up', 'instrumental',
      'originally performed', 'made popular by', 'in the style of', 'parodi', 'parody', 'mashup',
      'backing track', 'acapella'
    ];
    if (!isAcousticRequested && !isSessionRequested) {
      unwanted.addAll(['brooklyn session', 'session']);
    }

    for (final term in unwanted) {
      if (combined.contains(term) && !cleanTitle.contains(term)) {
        score -= 4000;
      }
    }

    // HEAVY BOOST FOR CLEAN STUDIO AUDIO (Topic track or Official Audio)
    if (lowerAuthor.contains('- topic') || lowerTitle.contains('- topic') || combined.contains('official audio') || combined.contains('provided to youtube by')) {
      score += 650;
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
          if (title.isNotEmpty) {
            final tid = (item['trackId'] ?? '').toString();
            String art = item['artworkUrl100'] ?? defaultArtwork;
            art = art.replaceAll('100x100bb', '600x600bb');
            list.add(Track(
              id: tid,
              title: title,
              artist: artist,
              album: item['collectionName'] ?? 'Single',
              artwork: art,
              audioUrl: '',
              duration: item['trackTimeMillis'] != null ? (item['trackTimeMillis'] / 1000).round() : 180,
              streamCount: '${(100 + list.length * 15)}.000.000',
              isExplicit: item['trackExplicitness'] == 'explicit',
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
          if (title.isNotEmpty) {
            final tid = 'dz_${item['id']}';
            final rank = (item['rank'] as num?)?.toInt() ?? 0;
            list.add(Track(
              id: tid,
              title: title,
              artist: artist,
              album: (item['album']?['title'] ?? 'Single').toString(),
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
        for (int i = 0; i < songs.length; i++) {
          final s = songs[i];
          final title = (s['title'] ?? '').toString();
          final artist = (s['artist'] ?? '').toString();
          final vid = (s['videoId'] ?? s['id'] ?? '').toString();
          if (title.isNotEmpty) {
            final pop = (850000 - (i * 25000)).clamp(200000, 850000);
            list.add(Track(
              id: 'yt_$vid',
              videoId: '', // NOTE: Leave empty so playTrack uses resolveVideoId with duration & embed verification!
              title: title,
              artist: artist,
              album: (s['album'] ?? 'Single').toString(),
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
    const junkTerms = [
      'cover', 'karaoke', 'instrumental', 'tribute', 'parodi', 'parody',
      'sped up', 'slowed', 'reverb', 'nightcore', 'reaction', 'tutorial',
      'originally performed', 'made popular by', 'in the style of', 'backing track',
      'guitar cover', 'piano cover', 'acoustic cover', 'acapella'
    ];

    for (final term in junkTerms) {
      if (!qNorm.contains(term)) {
        if (tTitle.contains(term)) score -= 3000;
        if (tAlbum.contains(term)) score -= 1500;
        if (tArtist.contains(term)) score -= 3000;
      } else {
        score += 300;
      }
    }

    if (!isRemixRequested && !qNorm.contains('remix') && tTitle.contains('remix')) {
      score -= 850;
    }
    if (!isLiveRequested && !isAcousticRequested && !qNorm.contains('live') &&
        (tTitle.contains('live') || tTitle.contains('concert') || tTitle.contains('konser'))) {
      score -= 850;
    }

    // STUDIO ORIGINAL BONUS
    if (!tTitle.contains('remix') && !tTitle.contains('live') && !tTitle.contains('cover') && !tTitle.contains('karaoke')) {
      score += 250;
    }
    if (tTitle.contains('official') || tTitle.contains('original')) {
      score += 200;
    }

    return score;
  }

  // Search tracks across query (Parallel Deezer + iTunes + YouTube Music with Popularity & Studio Original Priority)
  Future<List<Track>> searchTracks(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return [];

    final List<Track> results = [];
    final Set<String> seenKeys = <String>{};

    // 1. Run Deezer, iTunes & YouTube Music in parallel for instant response (<400ms)
    final responses = await Future.wait([
      _searchDeezer(query),
      _searchItunes(query),
      _searchYoutubeMusic(query),
    ]);

    final rawPool = <Track>[...responses[0], ...responses[1], ...responses[2]];

    // 2. Score and deduplicate candidates by studio original relevance and typo tolerance
    rawPool.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));

    for (final t in rawPool) {
      final key = '${_normalizeQuery(t.title)}___${_normalizeQuery(t.artist)}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        results.add(t);
      }
    }

    // 3. Multi-source fallback: Direct YouTube Search for Indie, Covers & Niche Tracks
    if (results.length < 5) {
      final yt = YoutubeExplode();
      try {
        final ytResults = await yt.search.search(query).timeout(const Duration(seconds: 3));
        final ytTracks = <Track>[];
        for (final v in ytResults.take(10)) {
          final key = '${_normalizeQuery(v.title)}___${_normalizeQuery(v.author)}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            ytTracks.add(Track(
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
        ytTracks.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));
        results.addAll(ytTracks);
      } catch (_) {
      } finally {
        yt.close();
      }
    }

    // Re-sort total results ensuring highest studio relevance is strictly on top
    results.sort((a, b) => _calculateSearchRelevance(b, query).compareTo(_calculateSearchRelevance(a, query)));

    // 4. Offline fallback only if all network sources fail completely
    if (results.isEmpty) {
      for (final t in officialTopTracks) {
        if (t.title.toLowerCase().contains(cleanQ) || t.artist.toLowerCase().contains(cleanQ)) {
          results.add(t);
        }
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

    final yt = YoutubeExplode();
    try {
      final ytResults = await yt.search.search('$clean lyric').timeout(const Duration(seconds: 4));
      for (final v in ytResults.take(12)) {
        String title = v.title;
        String artist = v.author;
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }
        final key = '${title.toLowerCase().trim()}_${artist.toLowerCase().trim()}';
        if (!seen.contains(key)) {
          seen.add(key);
          list.add(Track(
            id: 'yt_${v.id.value}',
            title: title,
            artist: artist,
            album: 'Lirik: "$clean"',
            artwork: v.thumbnails.highResUrl.isNotEmpty ? v.thumbnails.highResUrl : defaultArtwork,
            audioUrl: '',
            videoId: v.id.value,
            duration: v.duration?.inSeconds ?? 210,
            streamCount: 'Cocok Lirik',
            isExplicit: false,
          ));
        }
      }
    } catch (_) {
    } finally {
      yt.close();
    }

    try {
      final url = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent(clean)}');
      final res = await http.get(url).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          for (final item in data.take(6)) {
            final tName = item['trackName'] ?? '';
            final aName = item['artistName'] ?? '';
            final key = '${tName.toString().toLowerCase().trim()}_${aName.toString().toLowerCase().trim()}';
            if (tName.toString().isNotEmpty && !seen.contains(key)) {
              seen.add(key);
              list.add(Track(
                id: 'lrc_${item['id']}',
                title: tName.toString(),
                artist: aName.toString(),
                album: (item['albumName'] ?? 'Lirik').toString(),
                artwork: defaultArtwork,
                audioUrl: '',
                duration: item['duration'] != null ? (item['duration'] as num).round() : 180,
                streamCount: 'Cocok Lirik',
                isExplicit: false,
              ));
            }
          }
        }
      }
    } catch (_) {}

    return list;
  }

  // Search Artists matching query
  Future<List<Artist>> searchArtists(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return catalogArtists;

    final matched = catalogArtists.where((a) => a.name.toLowerCase().contains(cleanQ)).toList();
    if (matched.isNotEmpty) return matched;

    // Fallback generate from query
    return [
      Artist(
        id: 'art-${Uri.encodeComponent(query)}',
        name: query,
        headerBanner: defaultArtwork,
        avatar: defaultArtwork,
        monthlyListeners: '3,2 jt pendengar bulanan',
        isVerified: true,
      ),
      ...catalogArtists.take(4),
    ];
  }

  // Get Artist Profile Details & Popular Songs
  Future<Map<String, dynamic>> getArtistDetails(String artistName) async {
    final clean = artistName.toLowerCase().trim();
    Artist artist = catalogArtists.firstWhere(
      (a) => a.name.toLowerCase() == clean,
      orElse: () => Artist(
        id: 'art-${Uri.encodeComponent(artistName)}',
        name: artistName,
        headerBanner: defaultArtwork,
        avatar: defaultArtwork,
        monthlyListeners: '4,9 jt pendengar bulanan',
        isVerified: true,
      ),
    );

    List<Track> topSongs = [];
    topSongs = await searchTracks(artistName);
    if (topSongs.isEmpty) {
      topSongs = officialTopTracks.where((t) => t.artist.toLowerCase() == clean).toList();
      if (topSongs.isEmpty) {
        topSongs = officialTopTracks;
      }
    }

    return {
      'artist': artist,
      'topSongs': topSongs,
    };
  }

  // Fetch Trending / Starter Tracks dynamically from popular hitmaker charts
  Future<List<Track>> getTrendingTracks() async {
    try {
      final topArtists = [
        'Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy',
        'Mahalini', 'Tulus', 'Coldplay', 'The Weeknd', 'Bruno Mars', 'Billie Eilish'
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

  /// Finds famous, popular tracks related to current track for smart radio / next queue
  Future<List<Track>> getSmartRecommendations(Track currentTrack) async {
    final pool = <Track>[];
    final seen = <String>{'${currentTrack.title.toLowerCase().trim()}_${currentTrack.artist.toLowerCase().trim()}'};

    try {
      // 1. Search artist tracks
      final artistTracks = await searchTracks(currentTrack.artist);
      for (final t in artistTracks) {
        final key = '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
        if (!seen.contains(key)) {
          seen.add(key);
          pool.add(t);
          if (pool.length >= 6) break;
        }
      }

      // 2. Add peer hitmaker tracks
      final peers = ['Bernadya', 'Sal Priadi', 'Hindia', 'Juicy Luicy', 'Mahalini', 'Tulus', 'Coldplay', 'The Weeknd'];
      peers.shuffle();
      for (final peer in peers.take(2)) {
        final peerTracks = await searchTracks(peer);
        for (final t in peerTracks) {
          final key = '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
          if (!seen.contains(key)) {
            seen.add(key);
            pool.add(t);
            if (pool.length >= 12) break;
          }
        }
        if (pool.length >= 12) break;
      }

      pool.shuffle();
    } catch (_) {}

    return pool.isNotEmpty ? pool : officialTopTracks;
  }
}
