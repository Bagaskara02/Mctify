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
/// Why this exists:
/// 1. YouTube `androidSdkless` googlevideo URLs return HTTP 403 to ExoPlayer when opened
///    with an unranged GET (byte 0) or open-ended `Range: bytes=0-`, forcing slow WebView fallback.
/// 2. This proxy translates ExoPlayer's standard HTTP/Range reads into bounded 256 KB chunk
///    requests (`Range: bytes=start-end`) that googlevideo serves in ~120-160ms with HTTP 206.
/// 3. Keeps an LRU RAM cache + automatic 1-chunk read-ahead so:
///    - Pre-warmed next tracks & Quick Cards start playing in < 20ms (0ms network wait).
///    - Rewinding or seeking backward hits RAM cache instantaneously (< 1ms).
class AudioProxyServer {
  AudioProxyServer._();

  static final AudioProxyServer instance = AudioProxyServer._();

  static const int chunkSize = 262144; // 256 KB (~16s of 128kbps AAC audio)
  static const int maxCacheBytes = 48 * 1024 * 1024; // 48 MB bounded RAM LRU

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 25)
    ..maxConnectionsPerHost = 6
    ..autoUncompress = false;

  final Map<String, _ProxyStreamEntry> _entries = <String, _ProxyStreamEntry>{};
  final LinkedHashMap<String, Uint8List> _chunkCache = LinkedHashMap<String, Uint8List>();
  final Map<String, Future<Uint8List>> _inFlightChunks = <String, Future<Uint8List>>{};

  int _cachedBytes = 0;
  HttpServer? _server;
  int? _port;
  Future<int>? _startingFuture;

  Future<int> ensureStarted() async {
    if (_port != null) return _port!;
    if (_startingFuture != null) return _startingFuture!;

    _startingFuture = () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen(
        (req) => unawaited(_handleRequest(req)),
        onError: (e) => debugPrint('[AudioProxyServer] Server error: $e'),
      );
      return server.port;
    }();

    try {
      return await _startingFuture!;
    } finally {
      _startingFuture = null;
    }
  }

  /// Registers or updates a stream and returns its local proxy URL (`http://127.0.0.1:<port>/stream?id=...`).
  Future<String> registerStream({
    required String key,
    required String upstreamUrl,
    int totalBytes = 0,
    String contentType = 'audio/mp4',
    Future<String?> Function()? refreshUrl,
  }) async {
    final port = await ensureStarted();
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
    return 'http://127.0.0.1:$port/stream?id=${Uri.encodeQueryComponent(key)}';
  }

  String? getRegisteredProxyUrl(String key) {
    if (_port == null || !_entries.containsKey(key)) return null;
    return 'http://127.0.0.1:$_port/stream?id=${Uri.encodeQueryComponent(key)}';
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

  void clearCache() {
    _entries.clear();
    _chunkCache.clear();
    _cachedBytes = 0;
  }

  Future<void> dispose() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
    clearCache();
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      if (req.uri.path != '/stream') {
        req.response.statusCode = HttpStatus.notFound;
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

    Uint8List data = await _fetchChunkUpstream(entry, chunkStart, chunkEnd, allowRefresh: true);
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
    final request = await _httpClient.getUrl(Uri.parse(entry.upstreamUrl));
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=$chunkStart-$chunkEnd');
    request.headers.set(HttpHeaders.acceptHeader, '*/*');

    final response = await request.close();
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
      if (newUrl != null && newUrl.isNotEmpty) {
        entry.upstreamUrl = newUrl;
      }
      return newUrl;
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
