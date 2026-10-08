import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Local embedded streaming audio proxy.
/// Bridges Android's native MediaPlayer with YouTube's CDN by injecting required
/// User-Agent and Range headers, bypassing HTTP 403 blocks and enabling instant,
/// full-length song streaming (3 - 5+ minutes) without pre-download buffering delays.
class LocalAudioProxy {
  static final LocalAudioProxy _instance = LocalAudioProxy._internal();
  factory LocalAudioProxy() => _instance;
  LocalAudioProxy._internal();

  HttpServer? _server;
  int? _port;
  final YoutubeExplode _yt = YoutubeExplode();
  final Map<String, String> _streamUrlCache = {};

  int? get port => _port;
  bool get isRunning => _server != null;

  Future<int> start() async {
    if (_server != null && _port != null) {
      return _port!;
    }

    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      debugPrint('[LocalAudioProxy] Started on 127.0.0.1:$_port');

      _server!.listen(_handleRequest, onError: (err) {
        debugPrint('[LocalAudioProxy] Server error: $err');
      });

      return _port!;
    } catch (e) {
      debugPrint('[LocalAudioProxy] Failed to bind: $e');
      return 0;
    }
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final videoId = req.uri.queryParameters['v'];
    if (videoId == null || videoId.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }

    try {
      String? streamUrl = _streamUrlCache[videoId];
      if (streamUrl == null) {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 5));
        final mp4Streams = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        final chosen = mp4Streams.isNotEmpty ? mp4Streams.last : manifest.audioOnly.withHighestBitrate();
        streamUrl = chosen.url.toString();
        _streamUrlCache[videoId] = streamUrl;
      }

      final clientReq = http.Request('GET', Uri.parse(streamUrl));
      clientReq.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

      // Forward client Range header or default to start
      final clientRange = req.headers.value('range');
      if (clientRange != null) {
        clientReq.headers['Range'] = clientRange;
      } else {
        clientReq.headers['Range'] = 'bytes=0-';
      }

      final streamedRes = await http.Client().send(clientReq);
      req.response.statusCode = streamedRes.statusCode;
      req.response.headers.set('Content-Type', 'audio/mp4');
      req.response.headers.set('Accept-Ranges', 'bytes');

      if (streamedRes.headers['content-length'] != null) {
        req.response.headers.set('Content-Length', streamedRes.headers['content-length']!);
      }
      if (streamedRes.headers['content-range'] != null) {
        req.response.headers.set('Content-Range', streamedRes.headers['content-range']!);
      }

      await req.response.addStream(streamedRes.stream);
      await req.response.close();
    } catch (e) {
      debugPrint('[LocalAudioProxy] Stream pipe error: $e');
      if (!req.response.headers.contentType.toString().contains('audio')) {
        req.response.statusCode = HttpStatus.internalServerError;
      }
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  void dispose() {
    _server?.close(force: true);
    _server = null;
    _port = null;
    _yt.close();
  }
}
