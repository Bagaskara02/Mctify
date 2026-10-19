import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcmusic_flutter/models/track.dart';
import 'package:mcmusic_flutter/models/playlist.dart';
import 'package:mcmusic_flutter/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  group('StorageService Tests', () {
    test('Returns default playlists when storage is empty', () async {
      final playlists = await storage.getPlaylists();
      expect(playlists, isNotEmpty);
      expect(playlists.any((p) => p.name.contains('Late Night Chill')), isTrue);
    });

    test('addTrackToPlaylist adds track and prevents duplicate', () async {
      final initialPlaylists = await storage.getPlaylists();
      final targetPlaylistId = initialPlaylists.first.id;

      final track = Track(
        id: 'track-test-1',
        title: 'Bila Kau Butuh Telinga',
        artist: 'Bernadya',
        artwork: 'https://example.com/art.jpg',
      );

      await storage.addTrackToPlaylist(targetPlaylistId, track);

      var updated = await storage.getPlaylists();
      var foundPl = updated.firstWhere((p) => p.id == targetPlaylistId);
      expect(foundPl.tracks.length, 1);
      expect(foundPl.tracks.first.id, 'track-test-1');

      // Adding the same track again should be deduplicated
      await storage.addTrackToPlaylist(targetPlaylistId, track);
      updated = await storage.getPlaylists();
      foundPl = updated.firstWhere((p) => p.id == targetPlaylistId);
      expect(foundPl.tracks.length, 1);
    });

    test('toggleLikeTrack adds then removes a track from favorites', () async {
      final track = Track(
        id: 't-fav-01',
        title: 'Favorit Pertama',
        artist: 'Artis Keren',
        artwork: 'https://example.com/fav.jpg',
      );

      // 1. First toggle: add to favorites
      await storage.toggleLikeTrack(track);
      var isLiked = await storage.isTrackLiked('t-fav-01');
      expect(isLiked, isTrue);

      var liked = await storage.getLikedTracks();
      expect(liked.length, 1);
      expect(liked.first.title, 'Favorit Pertama');

      // 2. Second toggle: remove from favorites
      await storage.toggleLikeTrack(track);
      isLiked = await storage.isTrackLiked('t-fav-01');
      expect(isLiked, isFalse);

      liked = await storage.getLikedTracks();
      expect(liked, isEmpty);
    });

    test('Recovers gracefully from corrupted JSON in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({
        'mcmusic_playlists': 'INVALID_CORRUPTED_JSON{{[',
        'mcmusic_liked_tracks': 'NOT_JSON',
      });

      // Should not throw an exception, but return clean empty/default lists
      final playlists = await storage.getPlaylists();
      expect(playlists, isA<List<Playlist>>());

      final liked = await storage.getLikedTracks();
      expect(liked, isEmpty);
    });
  });
}
