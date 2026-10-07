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
    required this.cover,
    required this.tracks,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'cover': cover,
    'tracks': tracks.map((t) => t.toJson()).toList(),
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    description: json['description'] ?? '',
    cover: json['cover'] ?? '',
    tracks: (json['tracks'] as List? ?? []).map((t) => Track.fromJson(t)).toList(),
  );
}
