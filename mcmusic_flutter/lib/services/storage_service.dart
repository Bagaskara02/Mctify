import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/playlist.dart';

class StorageService {
  static const String _keyLiked = 'mcmusic_liked_tracks';
  static const String _keyPlaylists = 'mcmusic_playlists';
  static const String _keyHistory = 'mcmusic_history';
  static const String _keyPlayCounts = 'mcmusic_play_counts';

  Future<List<Track>> getLikedTracks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyLiked);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Track.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> toggleLikeTrack(Track track) async {
    final prefs = await SharedPreferences.getInstance();
    final liked = await getLikedTracks();
    final index = liked.indexWhere((t) => t.id == track.id);
    if (index != -1) {
      liked.removeAt(index);
    } else {
      liked.insert(0, track);
    }
    await prefs.setString(_keyLiked, jsonEncode(liked.map((t) => t.toJson()).toList()));
  }

  Future<bool> isTrackLiked(String trackId) async {
    final liked = await getLikedTracks();
    return liked.any((t) => t.id == trackId);
  }

  Future<List<Playlist>> getPlaylists() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyPlaylists);
    if (raw == null) {
      return [
        Playlist(
          id: 'pl-chill',
          name: 'Late Night Chill',
          description: 'Mellow melodies, ambient beats, and soothing vocals',
          cover: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
          tracks: [],
        )
      ];
    }
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Playlist.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePlaylists(List<Playlist> playlists) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPlaylists, jsonEncode(playlists.map((p) => p.toJson()).toList()));
  }

  Future<List<Track>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyHistory);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => Track.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> recordPlay(Track track) async {
    final prefs = await SharedPreferences.getInstance();
    final history = await getHistory();
    history.removeWhere((t) => t.id == track.id);
    history.insert(0, track);
    if (history.length > 50) history.removeLast();
    await prefs.setString(_keyHistory, jsonEncode(history.map((t) => t.toJson()).toList()));

    // Increment play counts
    try {
      final rawCounts = prefs.getString(_keyPlayCounts);
      final Map<String, int> counts = rawCounts != null ? Map<String, int>.from(jsonDecode(rawCounts)) : {};
      counts[track.artist] = (counts[track.artist] ?? 0) + 1;
      await prefs.setString(_keyPlayCounts, jsonEncode(counts));
    } catch (_) {}
  }

  Future<String?> getTopArtist() async {
    final prefs = await SharedPreferences.getInstance();
    final rawCounts = prefs.getString(_keyPlayCounts);
    if (rawCounts == null) return null;
    try {
      final Map<String, dynamic> counts = jsonDecode(rawCounts);
      if (counts.isEmpty) return null;
      var sorted = counts.entries.toList()..sort((a, b) => (b.value as int).compareTo(a.value as int));
      return sorted.first.key;
    } catch (_) {
      return null;
    }
  }
}
