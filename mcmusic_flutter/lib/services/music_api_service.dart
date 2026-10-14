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
  Future<String?> resolveVideoId(String title, String artist, [int? expectedDuration]) async {
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
      return _streamCache[cleanKey];
    }

    final yt = YoutubeExplode();
    try {
      // 1. Primary: Search via YoutubeExplode
      final searchResults = await yt.search.search('$sanitizedTitle $firstArtist').timeout(const Duration(seconds: 4));
      if (searchResults.isNotEmpty) {
        final scored = searchResults.map((v) {
          final dur = v.duration?.inSeconds;
          final score = _scoreCandidate(v.title, sanitizedTitle, firstArtist, dur, expectedDuration);
          return MapEntry(v.id.value, score);
        }).toList();

        scored.sort((a, b) => b.value.compareTo(a.value));
        final bestId = scored.first.key;
        _streamCache[cleanKey] = bestId;
        return bestId;
      }
    } catch (e) {
      debugPrint('resolveVideoId primary error: $e');
    } finally {
      yt.close();
    }

    // 2. Fallback: YouTube Music WEB_REMIX API
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
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final match = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"').firstMatch(res.body);
        final vid = match?.group(1);
        if (vid != null) {
          _streamCache[cleanKey] = vid;
          return vid;
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId WEB_REMIX fallback error: $e');
    }

    // 3. Fallback: McMusic Vercel Backend API (powered by youtubei.js)
    try {
      final url = Uri.parse('https://mctify.vercel.app/api/yt/search?q=${Uri.encodeComponent('$title $artist')}&duration=${expectedDuration ?? 0}');
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final vid = data['videoId'] as String?;
        if (vid != null && vid.isNotEmpty) {
          _streamCache[cleanKey] = vid;
          return vid;
        }
      }
    } catch (e) {
      debugPrint('resolveVideoId Vercel backend error: $e');
    }

    return null;
  }

  /// Resolves direct, full-length YouTube audio stream based on chosen bitrate.
  /// Prioritizes MP4 (AAC) audio streams for native 100% Android MediaPlayer compatibility.
  Future<String?> resolveFullAudioStream(
    String title,
    String artist, [
    AudioQuality quality = AudioQuality.high,
    int? expectedDurationSeconds,
  ]) async {
    final cleanKey = '$title $artist ${quality.name}'.toLowerCase().trim();
    if (_streamCache.containsKey(cleanKey)) {
      return _streamCache[cleanKey];
    }

    final yt = YoutubeExplode();
    try {
      String? bestVideoId;

      // 1. First attempt: Search via YoutubeExplode with candidate ranking
      try {
        final searchResults = await yt.search.search('$title $artist').timeout(const Duration(seconds: 6));
        if (searchResults.isNotEmpty) {
          final scored = searchResults.map((v) {
            final dur = v.duration?.inSeconds;
            final score = _scoreCandidate(v.title, title, artist, dur, expectedDurationSeconds);
            return MapEntry(v.id.value, score);
          }).toList();

          scored.sort((a, b) => b.value.compareTo(a.value));
          bestVideoId = scored.first.key;
        }
      } catch (e) {
        debugPrint('YoutubeExplode search note: $e');
      }

      // 2. Second attempt: Fallback to YouTube Music WEB_REMIX API
      if (bestVideoId == null) {
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
            final match = RegExp(r'"videoId"\s*:\s*"([a-zA-Z0-9_-]{11})"').firstMatch(res.body);
            bestVideoId = match?.group(1);
          }
        } catch (_) {}
      }

      if (bestVideoId != null) {
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
      }
    } catch (e) {
      debugPrint('resolveFullAudioStream error: $e');
    } finally {
      yt.close();
    }
    return null;
  }

  static int _scoreCandidate(
    String videoTitle,
    String title,
    String artist, [
    int? videoDurationSeconds,
    int? expectedDurationSeconds,
  ]) {
    final lower = videoTitle.toLowerCase();
    final cleanTitle = title.toLowerCase();
    final cleanArtist = artist.toLowerCase();
    int score = 100;

    if (lower.contains(cleanTitle)) score += 40;
    if (lower.contains(cleanArtist)) score += 30;

    final unwanted = [
      'brooklyn session', 'session', 'live', 'acoustic', 'remix',
      '10 years', 'tribute', 'karaoke', 'terjemahan', 'cover',
      'reaction', 'slowed', 'reverb', 'instrumental', 'guitar cover'
    ];
    for (final term in unwanted) {
      if (lower.contains(term) && !cleanTitle.contains(term)) {
        score -= 90;
      }
    }

    // Explicit bonus if requested version is matched
    for (final term in ['brooklyn session', 'acoustic', 'remix', 'live', 'session']) {
      if (cleanTitle.contains(term) && lower.contains(term)) {
        score += 45;
      }
    }

    if (lower.contains('official audio') || lower.contains('official track') || lower.contains('audio')) {
      score += 25;
    }
    if (lower.contains('official video') || lower.contains('music video')) {
      score += 15;
    }

    if (videoDurationSeconds != null && expectedDurationSeconds != null && expectedDurationSeconds > 0) {
      final diff = (videoDurationSeconds - expectedDurationSeconds).abs();
      if (diff <= 6) {
        score += 35;
      } else if (diff <= 18) {
        score += 20;
      } else if (diff > 45) {
        score -= 40;
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
            ));
          }
        }
      }
    } catch (_) {}
    return list;
  }

  // Search tracks across query (Parallel, fast ~300ms, highly accurate)
  Future<List<Track>> searchTracks(String query) async {
    final cleanQ = query.trim().toLowerCase();
    if (cleanQ.isEmpty) return [];

    final List<Track> results = [];
    final Set<String> seenKeys = <String>{};

    // 1. Run iTunes & Deezer in parallel for instant response (<400ms)
    final responses = await Future.wait([
      _searchItunes(query),
      _searchDeezer(query),
    ]);

    final rawPool = <Track>[...responses[0], ...responses[1]];

    // 2. Score and deduplicate candidates by exact matching and relevance
    int scoreTrack(Track t) {
      final title = t.title.toLowerCase().trim();
      final artist = t.artist.toLowerCase().trim();
      if (title == cleanQ) return 1000;
      if (title.startsWith(cleanQ)) return 800;
      if (artist == cleanQ) return 700;
      if (artist.startsWith(cleanQ)) return 600;
      if (title.contains(cleanQ)) return 400;
      if (artist.contains(cleanQ)) return 300;
      return 100;
    }

    rawPool.sort((a, b) => scoreTrack(b).compareTo(scoreTrack(a)));

    for (final t in rawPool) {
      final key = '${t.title.toLowerCase().trim()}___${t.artist.toLowerCase().trim()}';
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
        for (final v in ytResults.take(10)) {
          final key = '${v.title.toLowerCase().trim()}___${v.author.toLowerCase().trim()}';
          if (!seenKeys.contains(key)) {
            seenKeys.add(key);
            results.add(Track(
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
      } catch (_) {
      } finally {
        yt.close();
      }
    }

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
    final clean = input.trim();
    final reg = RegExp(r'(?:youtu\.be\/|youtube\.com\/(?:embed\/|v\/|watch\?v=|watch\?.+&v=|shorts\/))([a-zA-Z0-9_-]{11})', caseSensitive: false);
    final match = reg.firstMatch(clean);
    if (match != null && match.groupCount >= 1) return match.group(1);
    if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(clean)) return clean;
    return null;
  }

  Future<Track?> resolveYouTubeImport(String input) async {
    final clean = input.trim();
    if (clean.isEmpty) return null;

    final videoId = extractYouTubeId(clean);
    final yt = YoutubeExplode();

    try {
      if (videoId != null) {
        final video = await yt.videos.get(videoId).timeout(const Duration(seconds: 5));
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
          artwork: video.thumbnails.highResUrl.isNotEmpty ? video.thumbnails.highResUrl : defaultArtwork,
          audioUrl: '',
          videoId: video.id.value,
          duration: video.duration?.inSeconds ?? 210,
          streamCount: 'YouTube',
          isExplicit: false,
        );
      }

      final searchResults = await yt.search.search(clean).timeout(const Duration(seconds: 4));
      if (searchResults.isNotEmpty) {
        final v = searchResults.first;
        String title = v.title;
        String artist = v.author;
        if (title.contains(' - ')) {
          final parts = title.split(' - ');
          artist = parts[0].trim();
          title = parts.sublist(1).join(' - ').trim();
        }

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
      debugPrint('resolveYouTubeImport error: $e');
    } finally {
      yt.close();
    }
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
