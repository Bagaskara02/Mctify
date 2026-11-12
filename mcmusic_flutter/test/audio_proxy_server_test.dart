import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/services/audio_proxy_server.dart';

void main() {
  group('AudioProxyServer Loopback Chunk & Seek Tests', () {
    late HttpServer mockUpstream;
    late Uint8List payload;
    int upstreamGets = 0;
    bool force403First = false;

    setUp(() async {
      AudioProxyServer.instance.clearCache();
      upstreamGets = 0;
      force403First = false;
      payload = Uint8List.fromList(List<int>.generate(600000, (i) => (i * 17 + 3) & 0xFF));

      mockUpstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      mockUpstream.listen((req) async {
        // Simulate YouTube androidSdkless rule: reject unranged or open-ended requests with 403!
        final range = req.headers.value(HttpHeaders.rangeHeader);
        final match = range != null ? RegExp(r'^bytes=(\d+)-(\d+)$').firstMatch(range) : null;
        if (match == null) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }

        if (force403First && req.uri.path == '/expired') {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }

        upstreamGets++;
        final start = int.parse(match.group(1)!);
        final rawEnd = int.parse(match.group(2)!);
        final end = rawEnd >= payload.length ? payload.length - 1 : rawEnd;
        final slice = Uint8List.sublistView(payload, start, end + 1);

        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
        req.response.headers.set(HttpHeaders.contentLengthHeader, slice.length);
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/${payload.length}');
        req.response.add(slice);
        await req.response.close();
      });
    });

    tearDown(() async {
      AudioProxyServer.instance.clearCache();
      await mockUpstream.close(force: true);
    });

    test('translates unranged GET and seek into bounded upstream chunks and caches rewinds in RAM', () async {
      final client = HttpClient();
      final proxyUrl = await AudioProxyServer.instance.registerStream(
        key: 'vid123_high',
        upstreamUrl: 'http://127.0.0.1:${mockUpstream.port}/audio',
        totalBytes: payload.length,
        contentType: 'audio/mp4',
      );

      // 1. Pre-warm Chunk 0
      await AudioProxyServer.instance.prewarmHead('vid123_high');
      expect(AudioProxyServer.instance.hasHeadCached('vid123_high'), true);
      expect(upstreamGets, 1);

      // 2. ExoPlayer-style open GET on byte 0..100000 hits RAM (0 extra upstream GETs for Chunk 0!)
      final req1 = await client.getUrl(Uri.parse(proxyUrl));
      req1.headers.set(HttpHeaders.rangeHeader, 'bytes=0-99999');
      final res1 = await req1.close();
      final bytes1 = await res1.fold<List<int>>([], (acc, b) => acc..addAll(b));

      expect(res1.statusCode, HttpStatus.partialContent);
      expect(res1.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-99999/${payload.length}');
      expect(bytes1, equals(payload.sublist(0, 100000)));
      // Chunk 0 served directly from RAM; Chunk 1 may have been read-ahead asynchronously
      await Future.delayed(const Duration(milliseconds: 50));
      final getsAfterRead = upstreamGets;
      expect(getsAfterRead, lessThanOrEqualTo(2));

      // 3. Rewind back to byte 0 -> 100% RAM cache hit, 0 new upstream requests!
      final reqRewind = await client.getUrl(Uri.parse(proxyUrl));
      reqRewind.headers.set(HttpHeaders.rangeHeader, 'bytes=0-199999');
      final resRewind = await reqRewind.close();
      final bytesRewind = await resRewind.fold<List<int>>([], (acc, b) => acc..addAll(b));

      expect(resRewind.statusCode, HttpStatus.partialContent);
      expect(bytesRewind, equals(payload.sublist(0, 200000)));
      expect(upstreamGets, equals(getsAfterRead));

      // 4. Forward seek near end returns exact 206 byte slice
      final reqSeek = await client.getUrl(Uri.parse(proxyUrl));
      reqSeek.headers.set(HttpHeaders.rangeHeader, 'bytes=550000-599999');
      final resSeek = await reqSeek.close();
      final bytesSeek = await resSeek.fold<List<int>>([], (acc, b) => acc..addAll(b));
      expect(resSeek.statusCode, HttpStatus.partialContent);
      expect(bytesSeek, equals(payload.sublist(550000, 600000)));

      client.close(force: true);
    });

    test('refreshes upstream URL seamlessly when upstream returns 403', () async {
      force403First = true;
      final client = HttpClient();
      bool refreshed = false;

      final proxyUrl = await AudioProxyServer.instance.registerStream(
        key: 'vid403_high',
        upstreamUrl: 'http://127.0.0.1:${mockUpstream.port}/expired',
        totalBytes: payload.length,
        contentType: 'audio/mp4',
        refreshUrl: () async {
          refreshed = true;
          return 'http://127.0.0.1:${mockUpstream.port}/fresh';
        },
      );

      final req = await client.getUrl(Uri.parse(proxyUrl));
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (acc, b) => acc..addAll(b));

      expect(refreshed, true);
      expect(res.statusCode, HttpStatus.ok);
      expect(bytes.length, payload.length);
      expect(bytes, equals(payload));

      client.close(force: true);
    });
  });
}
