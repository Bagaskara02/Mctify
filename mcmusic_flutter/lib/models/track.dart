class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String artwork;
  final String audioUrl;
  final int duration; // in seconds
  final String? videoId;
  final String streamCount;
  final bool isExplicit;
  final int popularity;
  final String genre;

  Track({
    required this.id,
    required String title,
    required this.artist,
    this.album = 'Single',
    required String artwork,
    this.audioUrl = '',
    this.duration = 180,
    this.videoId,
    this.streamCount = '120.450.000',
    this.isExplicit = false,
    this.popularity = 0,
    this.genre = 'Pop',
  })  : title = cleanTitle(title),
        artwork = toHighResArtwork(artwork, fallbackVideoId: videoId);

  /// Yugen-inspired clean title sanitizer: strips [videoId], bracket video noise, quotes, and uploader noise
  static String cleanTitle(String rawTitle) {
    if (rawTitle.isEmpty) return '';
    var clean = rawTitle.trim();
    // 1. Remove [11-char videoId] at end: e.g. "Song Name [dQw4w9WgXcQ]"
    clean = clean.replaceAll(RegExp(r'\s*\[[\w-]{11}\]\s*$', caseSensitive: false), '');
    // 2. Remove video bracket noise
    clean = clean.replaceAll(
      RegExp(r'\s*[([][^()[\]]*\b(?:official|music\s*video|lyrics?|audio|video|visuali[sz]er|remaster(?:ed)?|hd|hq|4k|m\/?v|session|live|deluxe|10\s*years)\b[^()[\]]*[)\]]', caseSensitive: false),
      '',
    );
    // 3. Remove outer quotes
    clean = clean.replaceAll(RegExp(r'^["\u2018\u201c](.+)["\u2019\u201d]$'), r'$1');
    // 4. Remove channel noise if in title
    clean = clean.replaceAll(RegExp(r'\s*-\s*Official.*$', caseSensitive: false), '');
    return clean.trim().isEmpty ? rawTitle : clean.trim();
  }

  String get displayTitle => cleanTitle(title);

  static final RegExp _validVideoIdRe = RegExp(r'^[a-zA-Z0-9_-]{11}$');

  static bool isValidVideoId(String? id) =>
      id != null && _validVideoIdRe.hasMatch(id.trim());

  static String toHighResArtwork(String url, {String? fallbackVideoId}) {
    final clean = url.trim();
    final safeVid = isValidVideoId(fallbackVideoId) ? fallbackVideoId!.trim() : null;

    if (clean.isEmpty) {
      return safeVid != null ? 'https://i.ytimg.com/vi/$safeVid/hqdefault.jpg' : '';
    }

    // Reject unsafe schemes (javascript:, file:, data:, etc.)
    if (!clean.startsWith('https://') && !clean.startsWith('http://')) {
      return safeVid != null ? 'https://i.ytimg.com/vi/$safeVid/hqdefault.jpg' : '';
    }

    final lower = clean.toLowerCase();
    final isBadPlaceholder = lower.contains('no_thumbnail') ||
        lower.contains('default_playlist');

    if (isBadPlaceholder) {
      return safeVid != null ? 'https://i.ytimg.com/vi/$safeVid/hqdefault.jpg' : '';
    }

    // 1. Google User Content (YouTube Music square studio album art -> 544x544 HD)
    if (clean.contains('googleusercontent.com')) {
      if (RegExp(r'=w\d+-h\d+').hasMatch(clean)) {
        return clean.replaceAll(RegExp(r'=w\d+-h\d+[^?#]*'), '=w544-h544-l90-rj');
      }
      if (RegExp(r'=s\d+').hasMatch(clean)) {
        return clean.replaceAll(RegExp(r'=s\d+[^?#]*'), '=w544-h544-l90-rj');
      }
      if (!clean.contains('=')) {
        return '$clean=w544-h544-l90-rj';
      }
      return clean;
    }

    // 2. YouTube Video Thumbnails -> always normalize to reliable unsigned hqdefault.jpg
    if (clean.contains('ytimg.com')) {
      final viMatch = RegExp(r'/vi(?:_webp)?/([a-zA-Z0-9_-]{11})/').firstMatch(clean);
      if (viMatch != null) {
        return 'https://i.ytimg.com/vi/${viMatch.group(1)}/hqdefault.jpg';
      }
      if (safeVid != null) {
        return 'https://i.ytimg.com/vi/$safeVid/hqdefault.jpg';
      }
      return clean.split('?')[0].replaceAll(
        RegExp(r'(hqhq720|hq720|maxresdefault|sddefault|mqdefault|hqdefault|default)\.(jpg|webp)', caseSensitive: false),
        'hqdefault.jpg',
      );
    }

    // 3. Apple Music / iTunes
    if (clean.contains('mzstatic.com')) {
      return clean.replaceAll(RegExp(r'/\d+x\d+bb\.'), '/1000x1000bb.');
    }

    return clean;
  }

  Track copyWith({
    String? id,
    String? title,
    String? artist,
    String? album,
    String? artwork,
    String? audioUrl,
    int? duration,
    String? videoId,
    String? streamCount,
    bool? isExplicit,
    int? popularity,
    String? genre,
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artwork: artwork != null
          ? toHighResArtwork(artwork, fallbackVideoId: videoId ?? this.videoId)
          : toHighResArtwork(this.artwork, fallbackVideoId: videoId ?? this.videoId),
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      videoId: videoId ?? this.videoId,
      streamCount: streamCount ?? this.streamCount,
      isExplicit: isExplicit ?? this.isExplicit,
      popularity: popularity ?? this.popularity,
      genre: genre ?? this.genre,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'artwork': artwork,
    'audioUrl': audioUrl,
    'duration': duration,
    'videoId': videoId,
    'streamCount': streamCount,
    'isExplicit': isExplicit,
    'popularity': popularity,
    'genre': genre,
  };

  factory Track.fromJson(Map<String, dynamic> json) {
    final vid = json['videoId']?.toString();
    final rawArt = (json['artwork'] ?? '').toString();
    return Track(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      artist: json['artist'] ?? '',
      album: json['album'] ?? 'Single',
      artwork: toHighResArtwork(rawArt, fallbackVideoId: vid),
      audioUrl: json['audioUrl'] ?? '',
      duration: json['duration'] ?? 180,
      videoId: vid,
      streamCount: json['streamCount'] ?? '120.450.000',
      isExplicit: json['isExplicit'] ?? false,
      popularity: (json['popularity'] as num?)?.toInt() ?? 0,
      genre: json['genre'] as String? ?? 'Pop',
    );
  }
}
