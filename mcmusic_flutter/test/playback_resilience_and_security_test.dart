// ignore_for_file: experimental_member_use
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcmusic_flutter/models/playlist.dart';
import 'package:mcmusic_flutter/models/track.dart';
import 'package:mcmusic_flutter/services/audio_player_manager.dart';
import 'package:mcmusic_flutter/services/audio_proxy_server.dart';
import 'package:mcmusic_flutter/services/storage_service.dart';

class _DirectHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Artwork Normalization & XSS/Scheme Filtering', () {
    test('normalizes YouTube Music square art and ytimg URLs without hqhq720 bug', () {
      expect(
        Track.toHighResArtwork(
          'https://i.ytimg.com/vi_webp/dQw4w9WgXcQ/mqdefault.webp?sqp=abc',
          fallbackVideoId: 'dQw4w9WgXcQ',
        ),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      expect(
        Track.toHighResArtwork(
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
          fallbackVideoId: 'dQw4w9WgXcQ',
        ),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      expect(
        Track.toHighResArtwork(
          'https://lh3.googleusercontent.com/xyz=w120-h120-l90-rj',
          fallbackVideoId: 'dQw4w9WgXcQ',
        ),
        'https://lh3.googleusercontent.com/xyz=w544-h544-l90-rj',
      );
      // Legacy broken hqhq720 heals back to hqdefault when valid fallbackVideoId exists
      expect(
        Track.toHighResArtwork(
          'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqhq720.jpg',
          fallbackVideoId: 'dQw4w9WgXcQ',
        ),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('rejects unsafe schemes on Track and falls back to safe thumbnail', () {
      expect(Track.toHighResArtwork('javascript:alert(1)'), '');
      expect(Track.toHighResArtwork('data:text/html,<script>1</script>'), '');
      expect(
        Track.toHighResArtwork('javascript:alert(1)', fallbackVideoId: 'dQw4w9WgXcQ'),
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });

    test('Playlist.sanitizeCover falls back to first healthy track artwork', () {
      final track = Track(
        id: 'yt-1',
        title: 'Test Track',
        artist: 'Test Artist',
        artwork: 'https://lh3.googleusercontent.com/cover=w60-h60-l90-rj',
        videoId: 'dQw4w9WgXcQ',
      );
      final pl = Playlist(
        id: 'pl-1',
        name: 'Test Playlist',
        cover: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/no_thumbnail.jpg',
        tracks: [track],
      );
      expect(pl.cover, 'https://lh3.googleusercontent.com/cover=w544-h544-l90-rj');
    });
  });

  group('AudioProxyServer Security (Bearer Token & SSRF Guard)', () {
    test('rejects unsafe upstream schemes via ArgumentError', () async {
      await expectLater(
        () => AudioProxyServer.instance.registerStream(
          key: 'unsafe-file',
          upstreamUrl: 'file:///etc/passwd',
        ),
        throwsArgumentError,
      );
      await expectLater(
        () => AudioProxyServer.instance.registerStream(
          key: 'unsafe-http',
          upstreamUrl: 'http://example.com/audio.m4a',
        ),
        throwsArgumentError,
      );
    });

    test('requires valid 256-bit bearer token on loopback proxy and streams payload with valid token', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final payload = Uint8List.fromList(List<int>.generate(1024, (i) => i % 251));
        final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        upstream.listen((HttpRequest req) async {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('audio', 'mp4');
          req.response.headers.set('Accept-Ranges', 'bytes');
          req.response.contentLength = payload.length;
          req.response.add(payload);
          await req.response.close();
        });

        final client = HttpClient();
        const streamKey = 'sec_test_key_v1';
        try {
          final tokenizedUrl = await AudioProxyServer.instance.registerStream(
            key: streamKey,
            upstreamUrl: 'http://127.0.0.1:${upstream.port}/audio.m4a',
            totalBytes: payload.length,
            contentType: 'audio/mp4',
          );
          final uri = Uri.parse(tokenizedUrl);
          expect(uri.host, '127.0.0.1');
          expect(uri.queryParameters['id'], streamKey);
          expect((uri.queryParameters['token'] ?? '').length, 64);

          // 1. Missing token -> 403 Forbidden
          final noTokenUri = uri.replace(queryParameters: {'id': streamKey});
          final noTokenReq = await client.getUrl(noTokenUri);
          final noTokenRes = await noTokenReq.close();
          await noTokenRes.drain<void>();
          expect(noTokenRes.statusCode, HttpStatus.forbidden);

          // 2. Wrong token -> 403 Forbidden
          final badTokenUri = uri.replace(
            queryParameters: {'id': streamKey, 'token': '0' * 64},
          );
          final badTokenReq = await client.getUrl(badTokenUri);
          final badTokenRes = await badTokenReq.close();
          await badTokenRes.drain<void>();
          expect(badTokenRes.statusCode, HttpStatus.forbidden);

          // 3. Valid token -> 200 OK with exact bytes
          final goodReq = await client.getUrl(uri);
          final goodRes = await goodReq.close();
          final received = await goodRes.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
          expect(goodRes.statusCode, HttpStatus.ok);
          expect(Uint8List.fromList(received), payload);
        } finally {
          AudioProxyServer.instance.invalidateEntry(streamKey);
          client.close(force: true);
          await upstream.close(force: true);
        }
      }, _DirectHttpOverrides());
    });
  });

  group('StorageService Session Persistence & Playlist Healing', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves and loads playback session across cold/evicted restarts', () async {
      final storage = StorageService();
      final t1 = Track(
        id: 'yt-a',
        title: 'Lagu Pertama',
        artist: 'Artis Satu',
        artwork: 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
        videoId: 'dQw4w9WgXcQ',
        duration: 215,
      );
      final t2 = Track(
        id: 'yt-b',
        title: 'Lagu Kedua',
        artist: 'Artis Dua',
        artwork: 'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj',
        videoId: '9bZkp7q19f0',
        duration: 240,
      );

      await storage.savePlaybackSession(
        currentTrack: t1,
        position: const Duration(minutes: 1, seconds: 42),
        queue: [t1, t2],
        queueIndex: 0,
        isShuffle: true,
        isRepeat: false,
      );

      final loaded = await storage.loadPlaybackSession();
      expect(loaded, isNotNull);
      final restoredTrack = loaded!['track'] as Track;
      final restoredQueue = loaded['queue'] as List<Track>;
      expect(restoredTrack.title, 'Lagu Pertama');
      expect(restoredTrack.videoId, 'dQw4w9WgXcQ');
      expect(loaded['positionMs'], 102000);
      expect(restoredQueue.length, 2);
      expect(loaded['queueIndex'], 0);
      expect(loaded['isShuffle'], true);
      expect(loaded['isRepeat'], false);
    });

    test('heals legacy hqhq720 artwork and deduplicates tracks by videoId', () async {
      SharedPreferences.setMockInitialValues({
        'mcmusic_playlists': jsonEncode([
          {
            'id': 'pl-yt-1',
            'name': 'EDM Mix',
            'description': 'Imported',
            'cover': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqhq720.jpg',
            'tracks': [
              {
                'id': 't1',
                'title': 'Track One',
                'artist': 'Artist',
                'artwork': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqhq720.jpg',
                'videoId': 'dQw4w9WgXcQ',
                'audioUrl': '',
                'duration': 200,
              },
              {
                'id': 't1-dup',
                'title': 'Track One Duplicate Title',
                'artist': 'Artist Official',
                'artwork': 'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
                'videoId': 'dQw4w9WgXcQ',
                'audioUrl': '',
                'duration': 200,
              },
            ],
          },
        ]),
      });

      final storage = StorageService();
      final playlists = await storage.getPlaylists();
      expect(playlists.length, 1);
      expect(playlists.first.tracks.length, 1);
      expect(
        playlists.first.tracks.first.artwork,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
      expect(
        playlists.first.cover,
        'https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg',
      );
    });
  });

  group('TWS / External Audio Device Classification', () {
    AudioDevice makeDevice(AudioDeviceType type, {bool isOutput = true, bool isInput = false}) {
      return AudioDevice(
        id: 'dev-${type.name}-${isOutput ? 'out' : 'in'}',
        name: type.name,
        isInput: isInput,
        isOutput: isOutput,
        type: type,
      );
    }

    test('detects Bluetooth TWS, wired headsets, USB audio, CarPlay/Android Auto, and AirPlay outputs', () {
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.bluetoothA2dp)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.bluetoothSco)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.bluetoothLe)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.wiredHeadset)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.wiredHeadphones)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.usbAudio)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.carAudio)), isTrue);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.airPlay)), isTrue);
    });

    test('ignores built-in speaker/earpiece and input-only microphones', () {
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.builtInSpeaker)), isFalse);
      expect(AudioPlayerManager.isExternalHeadsetOrTws(makeDevice(AudioDeviceType.builtInEarpiece)), isFalse);
      expect(
        AudioPlayerManager.isExternalHeadsetOrTws(
          makeDevice(AudioDeviceType.bluetoothSco, isOutput: false, isInput: true),
        ),
        isFalse,
      );
    });
  });
}
