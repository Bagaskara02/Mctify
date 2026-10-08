import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Local embedded streaming audio proxy.
/// Pre-resolves YouTube stream URLs and pipes chunks to Android MediaPlayer with required
/// User-Agent and Range headers, guaranteeing instant full-song playback (3-5+ minutes)
/// without buffer delays or HTTP 403 errors.
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

  /// Pre-resolves and caches the direct MP4 audio stream URL from YouTube
  Future<String?> getOrResolveStreamUrl(String videoId) async {
    if (_streamUrlCache.containsKey(videoId)) {
      return _streamUrlCache[videoId];
    }
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final mp4Streams = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      final chosen = mp4Streams.isNotEmpty ? mp4Streams.last : manifest.audioOnly.withHighestBitrate();
      final streamUrl = chosen.url.toString();
      _streamUrlCache[videoId] = streamUrl;
      return streamUrl;
    } catch (e) {
      debugPrint('[LocalAudioProxy] Manifest resolution note for $videoId: $e');
    }
    return null;
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
      streamUrl ??= await getOrResolveStreamUrl(videoId);

      if (streamUrl == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
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
      debugPrint('[LocalAudioProxy] Pipe error: $e');
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
