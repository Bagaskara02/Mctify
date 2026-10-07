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
    required this.artwork,
    this.audioUrl = '',
    this.duration = 180,
    this.videoId,
    this.streamCount = '120.450.000',
    this.isExplicit = false,
  });

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
      artwork: artwork ?? this.artwork,
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
