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

  Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album = 'Single',
    required String artwork,
    this.audioUrl = '',
    this.duration = 180,
    this.videoId,
    this.streamCount = '120.450.000',
    this.isExplicit = false,
  }) : artwork = toHighResArtwork(artwork);

  static String toHighResArtwork(String url) {
    if (url.isEmpty) return url;
    var clean = url.trim();

    // 1. Google User Content (YouTube Music 60x60 / 120x120 -> 800x800 HD)
    if (clean.contains('googleusercontent.com')) {
      if (RegExp(r'=w\d+-h\d+').hasMatch(clean)) {
        return clean.replaceAll(RegExp(r'=w\d+-h\d+[^?#]*'), '=w800-h800-l90-rj');
      }
      if (RegExp(r'=s\d+').hasMatch(clean)) {
        return clean.replaceAll(RegExp(r'=s\d+[^?#]*'), '=w800-h800-l90-rj');
      }
      if (!clean.contains('=')) {
        return '$clean=w800-h800-l90-rj';
      }
    }

    // 2. YouTube Video Thumbnails
    if (clean.contains('ytimg.com')) {
      if (clean.contains('default.jpg')) {
        return clean.replaceAll(RegExp(r'(default|mqdefault|sddefault)\.jpg'), 'hq720.jpg').split('?')[0];
      }
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
  }) {
    return Track(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artwork: artwork != null ? toHighResArtwork(artwork) : this.artwork,
      audioUrl: audioUrl ?? this.audioUrl,
      duration: duration ?? this.duration,
      videoId: videoId ?? this.videoId,
      streamCount: streamCount ?? this.streamCount,
      isExplicit: isExplicit ?? this.isExplicit,
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
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] ?? '',
    title: json['title'] ?? '',
    artist: json['artist'] ?? '',
    album: json['album'] ?? 'Single',
    artwork: json['artwork'] ?? '',
    audioUrl: json['audioUrl'] ?? '',
    duration: json['duration'] ?? 180,
    videoId: json['videoId'],
    streamCount: json['streamCount'] ?? '120.450.000',
    isExplicit: json['isExplicit'] ?? false,
  );
}
