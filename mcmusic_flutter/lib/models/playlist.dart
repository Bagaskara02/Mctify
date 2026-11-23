import 'track.dart';

class Playlist {
  final String id;
  final String name;
  final String description;
  final String cover;
  final List<Track> tracks;

  Playlist({
    required this.id,
    required this.name,
    this.description = '',
    required String cover,
    required this.tracks,
  }) : cover = sanitizeCover(cover, tracks);

  static String sanitizeCover(String rawCover, List<Track> tracks) {
    final cleaned = Track.toHighResArtwork(rawCover);
    final lower = cleaned.toLowerCase();
    final isBad = cleaned.isEmpty ||
        lower.contains('no_thumbnail') ||
        lower.contains('default_playlist') ||
        lower.contains('hqhq720') ||
        lower.contains('sqp=') ||
        lower.endsWith('/default.jpg');
    if (!isBad) return cleaned;

    for (final t in tracks) {
      final candidate = Track.toHighResArtwork(t.artwork, fallbackVideoId: t.videoId);
      if (candidate.isNotEmpty) return candidate;
    }
    return cleaned;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'cover': cover,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final parsedTracks = (json['tracks'] as List? ?? []).map((t) => Track.fromJson(t)).toList();
    return Playlist(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      cover: sanitizeCover((json['cover'] ?? '').toString(), parsedTracks),
      tracks: parsedTracks,
    );
  }
}
