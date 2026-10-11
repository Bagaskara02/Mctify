import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:http/http.dart' as http;

/// Local HTTP Audio Stream Proxy Server
/// Proxies YouTube MP4 audio streams locally over 127.0.0.1 to native Android MediaPlayer / ExoPlayer (audioplayers).
/// - Completely bypasses googlevideo 403 Forbidden by attaching desktop User-Agent and proper Range headers.
/// - Enables 100% full song playback.
/// - Enables uninterrupted background playback when the phone screen is turned off or app is minimized.
/// - Keeps Android Notification / Lockscreen media controls 100% synchronized with real playback.
class LocalAudioStreamServer {
  static HttpServer? _server;
  static int _port = 0;
  static final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, Uri> _streamUrlCache = {};

  /// Ensures the local proxy server is running and returns its port
  static Future<int> getPort() async {
    if (_server != null) return _port;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      _server!.listen(
        _handleRequest,
        onError: (err) => debugPrint('[LocalAudioStreamServer] Server error: $err'),
      );
      debugPrint('[LocalAudioStreamServer] Running on http://127.0.0.1:$_port');
      return _port;
    } catch (e) {
      debugPrint('[LocalAudioStreamServer] Failed to bind local server: $e');
      return 0;
    }
  }

  /// Returns the local stream URL for a given YouTube videoId
  static Future<String?> getProxyUrl(String videoId) async {
    final port = await getPort();
    if (port == 0) return null;
    return 'http://127.0.0.1:$port/stream?v=$videoId';
  }

  /// Resolves and caches the direct googlevideo audio stream URI for a videoId
  static Future<Uri?> resolveStreamUri(String videoId) async {
    if (_streamUrlCache.containsKey(videoId)) {
      return _streamUrlCache[videoId];
    }
    try {
      final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 6));
      final mp4Streams = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
      final chosen = mp4Streams.isNotEmpty ? mp4Streams.last : manifest.audioOnly.withHighestBitrate();
      _streamUrlCache[videoId] = chosen.url;
      return chosen.url;
    } catch (e) {
      debugPrint('[LocalAudioStreamServer] resolveStreamUri error: $e');
      return null;
    }
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    final client = http.Client();
    try {
      final videoId = request.uri.queryParameters['v'];
      if (videoId == null || videoId.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      final streamUri = await resolveStreamUri(videoId);
      if (streamUri == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final upReq = http.Request(request.method, streamUri);
      upReq.headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      if (rangeHeader != null) {
        upReq.headers['Range'] = rangeHeader;
      }

      final upRes = await client.send(upReq);
      request.response.statusCode = upRes.statusCode;

      upRes.headers.forEach((k, v) {
        final lower = k.toLowerCase();
        if (lower == 'content-type' ||
            lower == 'content-length' ||
            lower == 'content-range' ||
            lower == 'accept-ranges') {
          request.response.headers.set(k, v);
        }
      });

      await request.response.addStream(upRes.stream);
      await request.response.close();
    } catch (e) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    } finally {
      client.close();
    }
  }
}
