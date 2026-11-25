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
import 'package:mcmusic_flutter/services/transition_engine.dart';

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

  group('TransitionEngine DSP, Camelot Wheel, and Pair Persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('computes deterministic BPM, Camelot key, and harmonic compatibility', () {
      final t1 = Track(
        id: 'trans-1',
        title: 'Keep You Safe',
        artist: 'New West',
        artwork: '',
        duration: 192,
      );
      final t2 = Track(
        id: 'trans-2',
        title: 'Fall In Love Alone',
        artist: 'Stacey Ryan',
        artwork: '',
        duration: 205,
      );

      final m1 = TransitionEngine.computeTrackBpmAndKey(t1);
      final m2 = TransitionEngine.computeTrackBpmAndKey(t2);
      expect(m1.bpm, 118);
      expect(m1.camelot, '4B');
      expect(m2.bpm, 115);
      expect(m2.camelot, '4B');

      final compat = TransitionEngine.computeCamelotCompatibility(m1.camelot, m2.camelot);
      expect(compat.tier, 'perfect');
      expect(compat.score, 99);
    });

    test('calculates musical 4/4 bar durations and evaluates DSP volume/EQ/filter envelopes', () {
      final stats = TransitionEngine.computeBarDurationSec(120, 120, '2 bars');
      expect(stats.barCount, 2);
      expect(stats.beats, 8);
      expect(stats.durationSec, 4.0);

      const cfg = TransitionConfig(
        volumeMode: 'crossfade',
        eqMode: 'bass_swap',
        effectsMode: 'high_pass',
        syncTempo: true,
        bpmA: 120,
        bpmB: 126,
      );

      final startEnv = TransitionEngine.evaluateTransitionEnvelope(0.0, cfg);
      final midEnv = TransitionEngine.evaluateTransitionEnvelope(0.5, cfg);
      final endEnv = TransitionEngine.evaluateTransitionEnvelope(1.0, cfg);

      expect(startEnv.outGain, closeTo(1.0, 0.01));
      expect(startEnv.inGain, closeTo(0.0, 0.01));
      expect(midEnv.outGain, closeTo(0.707, 0.02));
      expect(midEnv.inGain, closeTo(0.707, 0.02));
      expect(endEnv.outGain, closeTo(0.0, 0.01));
      expect(endEnv.inGain, closeTo(1.0, 0.01));
      expect(endEnv.outHighpassHz, greaterThan(1000.0));
      expect(startEnv.inLowDb, lessThan(-10.0));
      expect(endEnv.outLowDb, lessThan(-10.0));
    });

    test('strictly isolates 0:34 cue to Ain\'t In LA -> Close To Me and prevents bleed to generic pairs', () async {
      final storage = StorageService();
      final aintInLa = Track(id: 'yt_0ijm2Xui5N8', title: "Ain't In LA", artist: 'ADÉLA', artwork: '');
      final closeToMe = Track(id: 'yt_ajN57m_OSpY', title: 'Close To Me', artist: 'Ellie Goulding', artwork: '');
      final outgoing = Track(id: 'song-a', title: 'Keep You Safe', artist: 'New West', artwork: '');
      final incoming = Track(id: 'song-b', title: 'Fall In Love Alone', artist: 'Stacey Ryan', artwork: '');

      // 1. Curated directional pair gets 16 bars mashup and 34.0s intro cue
      final curated = await storage.getTransitionForPair(aintInLa, closeToMe);
      expect(curated.bars, '16 bars');
      expect(curated.volumeMode, 'mashup');
      expect(curated.introOffsetSec, 34.0);
      await storage.saveTransitionForPair(aintInLa, closeToMe, curated);

      // 2. Reverse direction must NOT inherit curated blueprint
      final reverse = await storage.getTransitionForPair(closeToMe, aintInLa);
      expect(reverse.introOffsetSec, 0.0);
      expect(reverse.volumeMode, isNot('mashup'));

      // 3. Generic pair saves mode without leaking outro/intro cue offsets
      const custom = TransitionConfig(
        bars: '4 bars',
        durationSec: 8.2,
        volumeMode: 'rise_drop',
        eqMode: 'bass_swap',
        effectsMode: 'echo_fade',
        syncTempo: true,
        outroOffsetSec: -2.0,
        introOffsetSec: 34.0,
      );

      await storage.saveTransitionForPair(outgoing, incoming, custom);
      final loaded = await storage.getTransitionForPair(outgoing, incoming);

      expect(loaded.bars, '4 bars');
      expect(loaded.volumeMode, 'rise_drop');
      expect(loaded.eqMode, 'none');
      expect(loaded.effectsMode, 'echo_fade');
      expect(loaded.outroOffsetSec, 0.0);
      expect(loaded.introOffsetSec, 0.0);
      expect(loaded.pairKey, isNotNull);
    });

    test('StorageService.reorderPlaylistTracks updates track order persistently', () async {
      final storage = StorageService();
      final t1 = Track(id: 't1', title: 'Song 1', artist: 'Artist 1', artwork: '');
      final t2 = Track(id: 't2', title: 'Song 2', artist: 'Artist 2', artwork: '');
      final t3 = Track(id: 't3', title: 'Song 3', artist: 'Artist 3', artwork: '');
      await storage.savePlaylists([
        Playlist(id: 'pl-reorder', name: 'Test Mix', cover: '', tracks: [t1, t2, t3]),
      ]);

      await storage.reorderPlaylistTracks('pl-reorder', [t3, t1, t2]);
      final pls = await storage.getPlaylists();
      final updated = pls.firstWhere((p) => p.id == 'pl-reorder');
      expect(updated.tracks.map((t) => t.id).toList(), ['t3', 't1', 't2']);
    });
  });
}
