// ignore_for_file: avoid_print
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/services/playlist_importer_service.dart';

void main() {
  test('Verify Spotify playlist 4EK6n0S5FqMXdIsdbSpKaC import', () async {
    final importer = PlaylistImporterService();
    const url = 'https://open.spotify.com/playlist/4EK6n0S5FqMXdIsdbSpKaC?si=64e341b72c9942bd';

    print('Starting import test for $url...');
    final playlist = await importer.importFromSpotify(
      url,
      onProgress: (cur, tot, msg) {
        print('Progress [$cur/$tot]: $msg');
      },
    );

    print('\n================ IMPORT SUCCESS ================');
    print('Playlist Name: "${playlist.name}"');
    print('Total Tracks: ${playlist.tracks.length}');
    print('Cover URL: ${playlist.cover}');

    final titles = <String>[];
    for (int i = 0; i < playlist.tracks.length; i++) {
      final t = playlist.tracks[i];
      titles.add(t.title);
      print('${i + 1}. [${t.duration}s] "${t.title}" by "${t.artist}" (Album: ${t.album})');
    }

    expect(playlist.tracks.length, 12);

    final unique = titles.map((e) => e.toLowerCase()).toSet();
    expect(unique.length, 12, reason: 'Duplicate tracks found!');

    expect(titles.any((t) => t.toLowerCase().contains('television')), isTrue, reason: 'Television / So Far So Good missing!');
    expect(titles.any((t) => t.toLowerCase().contains('brooklyn session')), isTrue, reason: 'Brooklyn Session missing!');
    expect(titles.any((t) => t.toLowerCase().contains('acoustic')), isTrue, reason: 'Acoustic Version missing!');

    print('\n[ALL CHECKS PASSED PERFECTLY!]');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
