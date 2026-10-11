import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Local HTTP Audio Proxy Server
/// Serves YouTube MP4 audio streams locally over 127.0.0.1 to native Android ExoPlayer / MediaPlayer (audioplayers).
/// This completely bypasses GoogleVideo 403 Forbidden errors, enables 100% full song playback,
/// and allows genuine Android background playback & lockscreen controls when the screen is turned off or app is minimized.
class LocalAudioStreamServer {
  static HttpServer? _server;
  static int _port = 0;
  static final YoutubeExplode _yt = YoutubeExplode();
  static final Map<String, StreamInfo> _streamCache = {};

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

  static Future<void> _handleRequest(HttpRequest request) async {
    try {
      final videoId = request.uri.queryParameters['v'];
      if (videoId == null || videoId.isEmpty) {
        request.response.statusCode = HttpStatus.badRequest;
        await request.response.close();
        return;
      }

      StreamInfo? chosen = _streamCache[videoId];
      if (chosen == null) {
        final manifest = await _yt.videos.streamsClient.getManifest(videoId).timeout(const Duration(seconds: 10));
        final mp4 = manifest.audioOnly.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
        chosen = mp4.isNotEmpty ? mp4.last : manifest.audioOnly.withHighestBitrate();
        _streamCache[videoId] = chosen;
      }

      final totalBytes = chosen.size.totalBytes;

      // Respond to HEAD requests (required by Android MediaPlayer / ExoPlayer)
      if (request.method == 'HEAD') {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
        request.response.headers.set(HttpHeaders.contentLengthHeader, totalBytes);
        request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        await request.response.close();
        return;
      }

      // Handle GET requests with Range support
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      int start = 0;
      if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
        final parts = rangeHeader.substring(6).split('-');
        start = int.tryParse(parts[0]) ?? 0;
      }

      final stream = _yt.videos.streamsClient.get(chosen);
      if (start > 0) {
        request.response.statusCode = HttpStatus.partialContent;
        final end = totalBytes - 1;
        request.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$totalBytes',
        );
        request.response.headers.set(
          HttpHeaders.contentLengthHeader,
          totalBytes - start,
        );
      } else {
        request.response.statusCode = HttpStatus.ok;
        request.response.headers.set(
          HttpHeaders.contentLengthHeader,
          totalBytes,
        );
      }

      request.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mp4');
      request.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

      await request.response.addStream(stream);
      await request.response.close();
    } catch (e) {
      // Stream cancellation or disconnect is normal when changing tracks
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }
}
