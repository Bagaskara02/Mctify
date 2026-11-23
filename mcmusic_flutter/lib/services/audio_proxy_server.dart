import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class _ProxyStreamEntry {
  final String key;
  String upstreamUrl;
  int totalBytes;
  String contentType;
  final Future<String?> Function()? refreshUrl;
  Future<String?>? refreshInFlight;

  _ProxyStreamEntry({
    required this.key,
    required this.upstreamUrl,
    required this.totalBytes,
    required this.contentType,
    this.refreshUrl,
  });
}

/// High-speed in-memory loopback HTTP Range proxy for YouTube DASH audio streams.
///
/// Security & Resilience guarantees:
/// 1. Bound strictly to 127.0.0.1 loopback and rejects non-loopback remote sockets.
/// 2. Protected by a per-session cryptographically random 256-bit bearer token
///    (verified via constant-time comparison) so no local process can hijack streams.
/// 3. Validates upstream URLs to permit HTTPS (or loopback HTTP for tests only).
/// 4. Translates player HTTP/Range reads into bounded 256 KB chunk requests with
///    LRU RAM cache, automatic socket refresh after OS sleep, and seamless 403/socket recovery.
class AudioProxyServer {
  AudioProxyServer._() : _authToken = _generateSessionToken();

  static final AudioProxyServer instance = AudioProxyServer._();

  static const int chunkSize = 262144; // 256 KB (~16s of 128kbps AAC audio)
  static const int maxCacheBytes = 48 * 1024 * 1024; // 48 MB bounded RAM LRU

  final String _authToken;
  HttpClient _httpClient = _createHttpClient();

  static String _generateSessionToken() {
    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static HttpClient _createHttpClient() {
    return HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..idleTimeout = const Duration(seconds: 20)
      ..maxConnectionsPerHost = 6
      ..autoUncompress = false;
  }

  final Map<String, _ProxyStreamEntry> _entries = <String, _ProxyStreamEntry>{};
  final LinkedHashMap<String, Uint8List> _chunkCache = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List>> _inFlightChunks = <String, Future<Uint8List>>{};

  int _cachedBytes = 0;
  HttpServer? _server;
  int? _port;
  Future<int>? _startingFuture;
  Future<int>? _verifyingFuture;

  int? get port => _port;
  bool hasEntry(String key) => _entries.containsKey(key);

  bool _isValidToken(String? provided) {
    if (provided == null || provided.length != _authToken.length) return false;
    int diff = 0;
    for (int i = 0; i < _authToken.length; i++) {
      diff |= provided.codeUnitAt(i) ^ _authToken.codeUnitAt(i);
    }
    return diff == 0;
  }

  static bool isSafeUpstreamUrl(String urlStr) {
    final trimmed = urlStr.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (uri.scheme == 'https') return true;
    if (uri.scheme == 'http' && (uri.host == '127.0.0.1' || uri.host == 'localhost')) {
      return true;
    }
    return false;
  }

  void resetHttpClient() {
    try {
      _httpClient.close(force: true);
    } catch (_) {}
    _httpClient = _createHttpClient();
  }

  Future<int> ensureStarted({bool forceRestartIfBroken = false}) async {
    if (!forceRestartIfBroken && _port != null && _server != null) return _port!;
    if (_startingFuture != null) return _startingFuture!;

    _startingFuture = () async {
      if (forceRestartIfBroken && _server != null) {
        try {
          await _server?.close(force: true);
        } catch (_) {}
        _server = null;
        _port = null;
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen(
        (req) => unawaited(_handleRequest(req)),
        onError: (e) {
          debugPrint('[AudioProxyServer] Server socket error: $e');
          _server = null;
          _port = null;
        },
        onDone: () {
          debugPrint('[AudioProxyServer] Server socket closed');
          _server = null;
          _port = null;
        },
      );
      return server.port;
    }();

    try {
      return await _startingFuture!;
    } finally {
      _startingFuture = null;
    }
  }

  /// Verifies that the loopback socket is actually responding to HTTP requests.
  /// Both Android Doze and iOS background suspension can tear down background sockets.
  /// Uses a concurrency lock so parallel callers do not spawn duplicate servers.
  Future<int> verifyOrRestartServer() {
    if (_verifyingFuture != null) return _verifyingFuture!;
    _verifyingFuture = () async {
      if (_port != null && _server != null) {
        final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 250);
        try {
          final pingUri = Uri.parse('http://127.0.0.1:$_port/ping?token=$_authToken');
          final req = await client.getUrl(pingUri).timeout(const Duration(milliseconds: 300));
          final res = await req.close().timeout(const Duration(milliseconds: 300));
          await res.drain<void>();
          if (res.statusCode == HttpStatus.ok) {
            return _port!;
          }
        } catch (e) {
          debugPrint('[AudioProxyServer] Socket health check failed ($e). Force-restarting loopback server...');
        } finally {
          client.close(force: true);
        }
      }
      resetHttpClient();
      return ensureStarted(forceRestartIfBroken: true);
    }();

    return _verifyingFuture!.whenComplete(() {
      _verifyingFuture = null;
    });
  }

  /// Registers or updates a stream and returns its local proxy URL with bearer token.
  Future<String> registerStream({
    required String key,
    required String upstreamUrl,
    int totalBytes = 0,
    String contentType = 'audio/mp4',
    Future<String?> Function()? refreshUrl,
  }) async {
    if (!isSafeUpstreamUrl(upstreamUrl)) {
      throw ArgumentError('Rejected unsafe upstream URL scheme/host for proxy');
    }
    final port = await verifyOrRestartServer();
    final existing = _entries[key];
    if (existing != null) {
      existing.upstreamUrl = upstreamUrl;
      if (totalBytes > 0) existing.totalBytes = totalBytes;
      if (contentType.isNotEmpty) existing.contentType = contentType;
    } else {
      _entries[key] = _ProxyStreamEntry(
        key: key,
        upstreamUrl: upstreamUrl,
        totalBytes: totalBytes,
        contentType: contentType.isNotEmpty ? contentType : 'audio/mp4',
        refreshUrl: refreshUrl,
      );
    }
    final ext = (contentType.contains('mp4') || contentType.contains('m4a') || contentType.contains('aac'))
        ? '.m4a'
        : (contentType.contains('webm') ? '.webm' : '.mp3');
    return 'http://127.0.0.1:$port/stream$ext?id=${Uri.encodeQueryComponent(key)}&token=$_authToken';
  }

  String? getRegisteredProxyUrl(String key) {
    if (_port == null || !_entries.containsKey(key)) return null;
    final entry = _entries[key];
    final ext = (entry?.contentType.contains('mp4') == true || entry?.contentType.contains('m4a') == true)
        ? '.m4a'
        : (entry?.contentType.contains('webm') == true ? '.webm' : '.mp3');
    return 'http://127.0.0.1:$_port/stream$ext?id=${Uri.encodeQueryComponent(key)}&token=$_authToken';
  }

  bool hasHeadCached(String key) => _chunkCache.containsKey('$key:0');

  /// Pre-fetches Chunk 0 into RAM so Track transitions / Quick Cards start without network delay.
  Future<void> prewarmHead(String key) async {
    final entry = _entries[key];
    if (entry == null) return;
    try {
      await _getChunk(entry, 0);
    } catch (_) {}
  }

  void invalidateEntry(String key) {
    _entries.remove(key);
    final prefix = '$key:';
    final keysToRemove = _chunkCache.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keysToRemove) {
      final removed = _chunkCache.remove(k);
      if (removed != null) {
        _cachedBytes -= removed.length;
      }
    }
    if (_cachedBytes < 0) _cachedBytes = 0;
  }

  void invalidateAllUpstreamEntries() {
    _entries.clear();
    _chunkCache.clear();
    _cachedBytes = 0;
  }

  void clearCache() {
    invalidateAllUpstreamEntries();
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    try {
      _httpClient.close(force: true);
    } catch (_) {}
    clearCache();
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final isLoopback = req.connectionInfo?.remoteAddress.isLoopback ?? true;
      if (!isLoopback) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      if (req.uri.path == '/ping') {
        if (!_isValidToken(req.uri.queryParameters['token'])) {
          req.response.statusCode = HttpStatus.forbidden;
          await req.response.close();
          return;
        }
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'text/plain');
        req.response.write('pong');
        await req.response.close();
        return;
      }

      if (req.uri.path != '/stream' && !req.uri.path.startsWith('/stream.')) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      if (!_isValidToken(req.uri.queryParameters['token'])) {
        req.response.statusCode = HttpStatus.forbidden;
        await req.response.close();
        return;
      }

      final id = req.uri.queryParameters['id'];
      final entry = id != null ? _entries[id] : null;
      if (entry == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }

      if (entry.totalBytes <= 0) {
        try {
          await _getChunk(entry, 0);
        } catch (e) {
          req.response.statusCode = HttpStatus.badGateway;
          await req.response.close();
          return;
        }
      }

      final total = entry.totalBytes;
      if (total <= 0) {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
        return;
      }

      if (req.method.toUpperCase() == 'HEAD') {
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        req.response.headers.set(HttpHeaders.contentTypeHeader, entry.contentType);
        req.response.headers.set(HttpHeaders.contentLengthHeader, total);
        await req.response.close();
        return;
      }

      final rangeHeader = req.headers.value(HttpHeaders.rangeHeader);
      int start = 0;
      int end = total - 1;
      bool hasRange = false;

      if (rangeHeader != null && rangeHeader.trim().toLowerCase().startsWith('bytes=')) {
        hasRange = true;
        final spec = rangeHeader.trim().substring(6).split(',').first.trim();
        final dashIdx = spec.indexOf('-');
        if (dashIdx == -1) {
          hasRange = false;
        } else {
          final startStr = spec.substring(0, dashIdx).trim();
          final endStr = spec.substring(dashIdx + 1).trim();
          if (startStr.isEmpty && endStr.isNotEmpty) {
            final suffix = int.tryParse(endStr) ?? 0;
            start = max(0, total - suffix);
            end = total - 1;
          } else if (startStr.isNotEmpty) {
            start = int.tryParse(startStr) ?? 0;
            if (endStr.isNotEmpty) {
              end = min(total - 1, int.tryParse(endStr) ?? (total - 1));
            }
          }
        }
      }

      if (start < 0 || start >= total || end < start) {
        req.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$total');
        await req.response.close();
        return;
      }

      final contentLength = end - start + 1;
      req.response.bufferOutput = false;
      req.response.statusCode = hasRange ? HttpStatus.partialContent : HttpStatus.ok;
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(HttpHeaders.contentTypeHeader, entry.contentType);
      req.response.headers.set(HttpHeaders.contentLengthHeader, contentLength);
      req.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (hasRange) {
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
      }

      bool aborted = false;
      req.response.done.then((_) {
        aborted = true;
      }, onError: (_) {
        aborted = true;
      });

      int cursor = start;
      while (cursor <= end && !aborted) {
        final chunkIndex = cursor ~/ chunkSize;
        final chunkData = await _getChunk(entry, chunkIndex);
        if (aborted || chunkData.isEmpty) break;

        final chunkStart = chunkIndex * chunkSize;
        final sliceStart = cursor - chunkStart;
        if (sliceStart >= chunkData.length) break;

        final remainingInChunk = chunkData.length - sliceStart;
        final remainingInRequest = end - cursor + 1;
        final writeLen = min(remainingInChunk, remainingInRequest);
        if (writeLen <= 0) break;

        final slice = (sliceStart == 0 && writeLen == chunkData.length)
            ? chunkData
            : Uint8List.sublistView(chunkData, sliceStart, sliceStart + writeLen);

        try {
          req.response.add(slice);
        } catch (_) {
          aborted = true;
          break;
        }

        cursor += writeLen;

        // Trigger seamless 1-chunk read-ahead so next 16s are ready before playback reaches them
        if (!aborted) {
          _triggerReadAhead(entry, chunkIndex + 1);
        }
      }

      try {
        await req.response.close();
      } catch (_) {}
    } catch (e) {
      debugPrint('[AudioProxyServer] Request handling note: $e');
      try {
        req.response.statusCode = HttpStatus.badGateway;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _triggerReadAhead(_ProxyStreamEntry entry, int nextChunkIndex) {
    if (entry.totalBytes > 0 && nextChunkIndex * chunkSize >= entry.totalBytes) {
      return;
    }
    final cacheKey = '${entry.key}:$nextChunkIndex';
    if (_chunkCache.containsKey(cacheKey) || _inFlightChunks.containsKey(cacheKey)) {
      return;
    }
    unawaited(_getChunk(entry, nextChunkIndex).catchError((_) => Uint8List(0)));
  }

  Future<Uint8List> _getChunk(_ProxyStreamEntry entry, int chunkIndex) {
    final cacheKey = '${entry.key}:$chunkIndex';
    final cached = _chunkCache.remove(cacheKey);
    if (cached != null) {
      _chunkCache[cacheKey] = cached; // Promote to MRU
      return Future.value(cached);
    }

    final existingFuture = _inFlightChunks[cacheKey];
    if (existingFuture != null) {
      return existingFuture;
    }

    final fut = _fetchAndCacheChunk(entry, chunkIndex, cacheKey);
    _inFlightChunks[cacheKey] = fut;
    fut.whenComplete(() => _inFlightChunks.remove(cacheKey));
    return fut;
  }

  Future<Uint8List> _fetchAndCacheChunk(
    _ProxyStreamEntry entry,
    int chunkIndex,
    String cacheKey,
  ) async {
    final chunkStart = chunkIndex * chunkSize;
    int chunkEnd = chunkStart + chunkSize - 1;
    if (entry.totalBytes > 0) {
      if (chunkStart >= entry.totalBytes) return Uint8List(0);
      chunkEnd = min(chunkEnd, entry.totalBytes - 1);
    }

    Uint8List data;
    try {
      data = await _fetchChunkUpstream(entry, chunkStart, chunkEnd, allowRefresh: true);
    } catch (e) {
      final isSocketStale = e is SocketException || e is HandshakeException || e is TimeoutException || e is HttpException;
      if (isSocketStale) {
        resetHttpClient();
        if (entry.refreshUrl != null) {
          await _refreshEntryUrl(entry).catchError((_) => null);
        }
      }
      await Future.delayed(const Duration(milliseconds: 100));
      data = await _fetchChunkUpstream(entry, chunkStart, chunkEnd, allowRefresh: true);
    }
    if (data.isNotEmpty) {
      _putChunkInCache(cacheKey, data);
    }
    return data;
  }

  Future<Uint8List> _fetchChunkUpstream(
    _ProxyStreamEntry entry,
    int chunkStart,
    int chunkEnd, {
    required bool allowRefresh,
  }) async {
    final request = await _httpClient.getUrl(Uri.parse(entry.upstreamUrl)).timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$chunkStart-$chunkEnd');
    request.headers.set(HttpHeaders.acceptHeader, '*/*');

    final response = await request.close().timeout(const Duration(seconds: 10));
    if ((response.statusCode == 403 || response.statusCode == 410) &&
        allowRefresh &&
        entry.refreshUrl != null) {
      await response.drain<void>();
      final refreshed = await _refreshEntryUrl(entry);
      if (refreshed != null && refreshed.isNotEmpty) {
        return _fetchChunkUpstream(entry, chunkStart, chunkEnd, allowRefresh: false);
      }
      throw HttpException('Upstream returned ${response.statusCode}');
    }

    if (response.statusCode != 206 && response.statusCode != 200) {
      await response.drain<void>();
      throw HttpException('Upstream returned HTTP ${response.statusCode}');
    }

    // Discover totalBytes from Content-Range header if caller passed totalBytes == 0
    if (entry.totalBytes <= 0) {
      final cr = response.headers.value(HttpHeaders.contentRangeHeader);
      if (cr != null) {
        final slashIdx = cr.lastIndexOf('/');
        if (slashIdx != -1) {
          final parsedTotal = int.tryParse(cr.substring(slashIdx + 1).trim());
          if (parsedTotal != null && parsedTotal > 0) {
            entry.totalBytes = parsedTotal;
          }
        }
      } else if (response.statusCode == 200 && response.contentLength > 0) {
        entry.totalBytes = response.contentLength;
      }
    }

    final builder = BytesBuilder(copy: false);
    await for (final part in response) {
      builder.add(part);
    }
    var bytes = builder.takeBytes();

    // Defensive slice if upstream ignored Range and returned 200 full body
    if (response.statusCode == 200 && bytes.length > chunkStart && chunkStart > 0) {
      final sliceEnd = min(bytes.length, chunkEnd + 1);
      bytes = Uint8List.sublistView(bytes, chunkStart, sliceEnd);
    }
    return bytes;
  }

  Future<String?> _refreshEntryUrl(_ProxyStreamEntry entry) async {
    if (entry.refreshInFlight != null) {
      return entry.refreshInFlight;
    }
    final completer = entry.refreshUrl!().then((newUrl) {
      if (newUrl != null && newUrl.isNotEmpty && isSafeUpstreamUrl(newUrl)) {
        entry.upstreamUrl = newUrl;
        return newUrl;
      }
      return null;
    }).whenComplete(() {
      entry.refreshInFlight = null;
    });
    entry.refreshInFlight = completer;
    return completer;
  }

  void _putChunkInCache(String cacheKey, Uint8List data) {
    final old = _chunkCache.remove(cacheKey);
    if (old != null) {
      _cachedBytes -= old.length;
    }
    _chunkCache[cacheKey] = data;
    _cachedBytes += data.length;

    while (_cachedBytes > maxCacheBytes && _chunkCache.isNotEmpty) {
      final oldestKey = _chunkCache.keys.first;
      final removed = _chunkCache.remove(oldestKey);
      if (removed != null) {
        _cachedBytes -= removed.length;
      }
    }
  }
}
