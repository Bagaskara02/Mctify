import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/models/track.dart';
import 'package:mcmusic_flutter/models/playlist.dart';
import 'package:mcmusic_flutter/models/artist.dart';
import 'package:mcmusic_flutter/models/lyric_line.dart';

void main() {
  group('Track Model Tests', () {
    test('Track serializes to JSON and deserializes correctly', () {
      final track = Track(
        id: 'track-001',
        title: 'Untold Story',
        artist: 'Bernadya',
        album: 'Sialnya, Hidup Harus Tetap Berjalan',
        artwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4',
        duration: 215,
        videoId: 'abc123xyz89',
        streamCount: '45.000.000',
        isExplicit: true,
      );

      final json = track.toJson();
      expect(json['id'], 'track-001');
      expect(json['title'], 'Untold Story');
      expect(json['isExplicit'], true);

      final deserialized = Track.fromJson(json);
      expect(deserialized.id, track.id);
      expect(deserialized.title, track.title);
      expect(deserialized.artist, track.artist);
      expect(deserialized.duration, 215);
      expect(deserialized.videoId, 'abc123xyz89');
      expect(deserialized.isExplicit, true);
    });

    test('Track.fromJson handles null or missing optional fields gracefully', () {
      final minimalJson = <String, dynamic>{
        'id': 't-min',
        'title': 'Minimal Track',
        'artist': 'Independent Artist',
      };

      final track = Track.fromJson(minimalJson);
      expect(track.id, 't-min');
      expect(track.title, 'Minimal Track');
      expect(track.artist, 'Independent Artist');
      expect(track.album, 'Single');
      expect(track.duration, 180);
      expect(track.isExplicit, false);
      expect(track.videoId, isNull);
    });

    test('Track.copyWith updates specified fields only', () {
      final original = Track(
        id: 't-orig',
        title: 'Song Title',
        artist: 'Artist Name',
        artwork: 'https://example.com/art.jpg',
        duration: 180,
      );

      final updated = original.copyWith(
        title: 'Updated Title',
        videoId: 'new_vid_123',
      );

      expect(updated.id, 't-orig');
      expect(updated.title, 'Updated Title');
      expect(updated.artist, 'Artist Name');
      expect(updated.videoId, 'new_vid_123');
      expect(updated.duration, 180);
    });
  });

  group('Playlist Model Tests', () {
    test('Playlist serializes and deserializes with child tracks', () {
      final track1 = Track(
        id: 't-1',
        title: 'Track 1',
        artist: 'Artist 1',
        artwork: 'https://example.com/1.jpg',
      );

      final playlist = Playlist(
        id: 'pl-test',
        name: 'My Roadtrip Mix',
        description: 'Best driving tunes',
        cover: 'https://example.com/cover.jpg',
        tracks: [track1],
      );

      final json = playlist.toJson();
      expect(json['name'], 'My Roadtrip Mix');
      expect(json['tracks'], isA<List>());
      expect((json['tracks'] as List).length, 1);

      final deserialized = Playlist.fromJson(json);
      expect(deserialized.id, playlist.id);
      expect(deserialized.name, 'My Roadtrip Mix');
      expect(deserialized.tracks.length, 1);
      expect(deserialized.tracks.first.title, 'Track 1');
    });

    test('Playlist.fromJson handles empty tracks and missing cover', () {
      final json = <String, dynamic>{
        'id': 'pl-empty',
        'name': 'Empty Playlist',
      };

      final playlist = Playlist.fromJson(json);
      expect(playlist.id, 'pl-empty');
      expect(playlist.name, 'Empty Playlist');
      expect(playlist.tracks, isEmpty);
    });
  });

  group('Artist & LyricLine Model Tests', () {
    test('Artist model parses correctly', () {
      final artist = Artist(
        id: 'art-01',
        name: 'Sal Priadi',
        avatar: 'https://example.com/sal.jpg',
        headerBanner: 'https://example.com/sal_banner.jpg',
        monthlyListeners: '3.400.000',
        isVerified: true,
      );

      expect(artist.id, 'art-01');
      expect(artist.name, 'Sal Priadi');
      expect(artist.avatar, 'https://example.com/sal.jpg');
      expect(artist.headerBanner, 'https://example.com/sal_banner.jpg');
      expect(artist.monthlyListeners, '3.400.000');
      expect(artist.isVerified, true);
    });

    test('LyricLine properties and duration calculation', () {
      final line = LyricLine(
        time: 12.5,
        endTime: 16.0,
        text: 'Bila kau butuh telinga tuk mendengar',
        isBackgroundVocal: false,
      );

      expect(line.time, 12.5);
      expect(line.endTime, 16.0);
      expect(line.text, 'Bila kau butuh telinga tuk mendengar');
      expect(line.endTime - line.time, closeTo(3.5, 0.01));
      expect(line.isBackgroundVocal, false);
    });
  });
}
