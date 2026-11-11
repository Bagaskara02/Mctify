import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ArtworkColors {
  final Color primary;
  final Color secondary;
  final Color surfaceTint;

  const ArtworkColors({
    required this.primary,
    required this.secondary,
    required this.surfaceTint,
  });

  static const ArtworkColors fallbackDefault = ArtworkColors(
    primary: Color(0xFF1A365D),
    secondary: Color(0xFF0F172A),
    surfaceTint: Color(0xFF1B2838),
  );
}

class ArtworkPalette {
  static final Map<String, ArtworkColors> _cache = {};
  static final Map<String, Future<ArtworkColors>> _inFlight = {};

  static ArtworkColors getCachedOrFallback(String url, {String seed = ''}) {
    if (_cache.containsKey(url)) return _cache[url]!;
    return _seededFallback(seed.isNotEmpty ? seed : url);
  }

  static Future<ArtworkColors> extract(String url, {String seed = ''}) {
    if (url.isEmpty) {
      return Future.value(_seededFallback(seed));
    }
    if (_cache.containsKey(url)) {
      return Future.value(_cache[url]!);
    }
    if (_inFlight.containsKey(url)) {
      return _inFlight[url]!;
    }

    final future = _computePalette(url, seed);
    _inFlight[url] = future;
    future.whenComplete(() => _inFlight.remove(url));
    return future;
  }

  static Future<ArtworkColors> _computePalette(String url, String seed) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
        return _seededFallback(seed.isNotEmpty ? seed : url);
      }

      final resp = await http.get(uri).timeout(const Duration(seconds: 4));
      if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) {
        return _seededFallback(seed.isNotEmpty ? seed : url);
      }

      final codec = await ui.instantiateImageCodec(
        resp.bodyBytes,
        targetWidth: 24,
        targetHeight: 24,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      frame.image.dispose();
      codec.dispose();

      if (byteData == null) {
        return _seededFallback(seed.isNotEmpty ? seed : url);
      }

      final bytes = byteData.buffer.asUint8List();
      int rSum = 0, gSum = 0, bSum = 0, count = 0;
      int r2Sum = 0, g2Sum = 0, b2Sum = 0, count2 = 0;

      for (int i = 0; i + 3 < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];
        if (a < 180) continue;

        final brightness = (r + g + b) / 3.0;
        if (brightness > 22 && brightness < 235) {
          final maxC = [r, g, b].reduce((x, y) => x > y ? x : y);
          final minC = [r, g, b].reduce((x, y) => x < y ? x : y);
          final sat = maxC - minC;

          if (sat > 28) {
            rSum += r;
            gSum += g;
            bSum += b;
            count++;
          } else {
            r2Sum += r;
            g2Sum += g;
            b2Sum += b;
            count2++;
          }
        }
      }

      Color baseColor;
      if (count >= 4) {
        baseColor = Color.fromARGB(
          255,
          (rSum ~/ count).clamp(0, 255),
          (gSum ~/ count).clamp(0, 255),
          (bSum ~/ count).clamp(0, 255),
        );
      } else if (count2 >= 4) {
        baseColor = Color.fromARGB(
          255,
          (r2Sum ~/ count2).clamp(0, 255),
          (g2Sum ~/ count2).clamp(0, 255),
          (b2Sum ~/ count2).clamp(0, 255),
        );
      } else {
        return _seededFallback(seed.isNotEmpty ? seed : url);
      }

      final hsl = HSLColor.fromColor(baseColor);
      final primary = hsl
          .withLightness(hsl.lightness.clamp(0.18, 0.30))
          .withSaturation(hsl.saturation.clamp(0.28, 0.65))
          .toColor();
      final secondary = hsl
          .withLightness((hsl.lightness * 0.55).clamp(0.08, 0.16))
          .withSaturation((hsl.saturation * 0.8).clamp(0.18, 0.50))
          .toColor();
      final surfaceTint = hsl
          .withLightness(hsl.lightness.clamp(0.22, 0.34))
          .withSaturation(hsl.saturation.clamp(0.30, 0.60))
          .toColor();

      final result = ArtworkColors(
        primary: primary,
        secondary: secondary,
        surfaceTint: surfaceTint,
      );
      if (_cache.length > 60) {
        _cache.clear();
      }
      _cache[url] = result;
      return result;
    } catch (_) {
      return _seededFallback(seed.isNotEmpty ? seed : url);
    }
  }

  static ArtworkColors _seededFallback(String seed) {
    const palettes = [
      ArtworkColors(
        primary: Color(0xFF16384E),
        secondary: Color(0xFF0A1620),
        surfaceTint: Color(0xFF1C4661),
      ),
      ArtworkColors(
        primary: Color(0xFF2D1B4E),
        secondary: Color(0xFF120B1F),
        surfaceTint: Color(0xFF392363),
      ),
      ArtworkColors(
        primary: Color(0xFF143D30),
        secondary: Color(0xFF091B15),
        surfaceTint: Color(0xFF1A4E3E),
      ),
      ArtworkColors(
        primary: Color(0xFF471B2A),
        secondary: Color(0xFF1D0A11),
        surfaceTint: Color(0xFF592235),
      ),
      ArtworkColors(
        primary: Color(0xFF3F2B16),
        secondary: Color(0xFF1A1108),
        surfaceTint: Color(0xFF51381C),
      ),
    ];
    final idx = seed.hashCode.abs() % palettes.length;
    return palettes[idx];
  }
}
