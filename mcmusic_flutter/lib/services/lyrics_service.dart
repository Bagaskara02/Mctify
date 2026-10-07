import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsService {
  static final Map<String, List<LyricLine>> _cache = {};

  static Map<String, String> cleanTitleAndArtist(String rawTitle, String rawArtist) {
    var title = rawTitle.trim();
    var artist = rawArtist.trim();

    // Strip common YouTube tags and suffixes
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](official\s*(music\s*)?video|audio|mv|visualizer|lyric(s)?(\s*video)?|remastered|single|hd|4k|session|brooklyn session|10 years)[\)\]]', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*(feat\.|ft\.)\s+[^-\(\]]+', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'[◐◑]'), '').trim();

    if (title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length == 2) {
        if (artist.isNotEmpty && parts[0].toLowerCase().contains(artist.toLowerCase())) {
          title = parts[1].trim();
        } else if (artist.isNotEmpty && parts[1].toLowerCase().contains(artist.toLowerCase())) {
          title = parts[0].trim();
        }
      }
    }

    title = title.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    artist = artist.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();

    return {'title': title, 'artist': artist};
  }

  Future<List<LyricLine>> fetchLyrics(String artist, String title, int duration) async {
    final cleaned = cleanTitleAndArtist(title, artist);
    final cleanTitle = cleaned['title'] ?? title;
    final cleanArtist = cleaned['artist'] ?? artist;
    final cacheKey = '${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // 1. Try exact match without strict duration first (avoids 503 error)
    try {
      final url = Uri.parse(
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanArtist)}&track_name=${Uri.encodeComponent(cleanTitle)}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          final parsed = parseLrc(synced);
          if (parsed.isNotEmpty) {
            _cache[cacheKey] = parsed;
            return parsed;
          }
        }
      }
    } catch (_) {}

    // 2. Try search query fallback
    try {
      final q = Uri.encodeComponent('$cleanTitle $cleanArtist');
      final searchUrl = Uri.parse('https://lrclib.net/api/search?q=$q');
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final best = list.firstWhere(
            (item) => item['syncedLyrics'] != null && (item['syncedLyrics'] as String).isNotEmpty,
            orElse: () => list.first,
          );
          final synced = best['syncedLyrics'] as String?;
          if (synced != null && synced.isNotEmpty) {
            final parsed = parseLrc(synced);
            if (parsed.isNotEmpty) {
              _cache[cacheKey] = parsed;
              return parsed;
            }
          }
        }
      }
    } catch (_) {}

    return [];
  }

  List<LyricLine> parseLrc(String lrcContent) {
    final List<LyricLine> lines = [];
    final regex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\](.*)');

    for (final line in lrcContent.split('\n')) {
      final match = regex.firstMatch(line.trim());
      if (match != null) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msStr = match.group(3) ?? '0';
        final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final timeInSec = min * 60 + sec + (ms / 1000.0);
        final text = match.group(4)?.trim() ?? '';
        if (text.isNotEmpty) {
          lines.add(LyricLine(time: timeInSec, text: text));
        }
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }
}
