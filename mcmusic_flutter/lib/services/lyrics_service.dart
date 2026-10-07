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
    final targetDuration = duration > 5 ? duration : null;
    final cacheKey = '${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}:::${targetDuration ?? 0}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // --- TIER 1: Exact lookup with Duration parameter (Matches the exact track recording) ---
    if (targetDuration != null) {
      try {
        final url = Uri.parse(
          'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanArtist)}&track_name=${Uri.encodeComponent(cleanTitle)}&duration=$targetDuration',
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
    }

    // --- TIER 2: Exact lookup without duration (verify returned duration is within tolerance) ---
    try {
      final url = Uri.parse(
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(cleanArtist)}&track_name=${Uri.encodeComponent(cleanTitle)}',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        final returnedDuration = (data['duration'] as num?)?.toDouble();
        final isAcceptable = targetDuration == null ||
            returnedDuration == null ||
            (returnedDuration - targetDuration).abs() <= 12;

        if (synced != null && synced.isNotEmpty && isAcceptable) {
          final parsed = parseLrc(synced);
          if (parsed.isNotEmpty) {
            _cache[cacheKey] = parsed;
            return parsed;
          }
        }
      }
    } catch (_) {}

    // --- TIER 3: Smart Search with Duration-Ranked Scoring ---
    try {
      final q = Uri.encodeComponent('$cleanTitle $cleanArtist');
      final searchUrl = Uri.parse('https://lrclib.net/api/search?q=$q');
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final best = _pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration);
          final synced = best?['syncedLyrics'] as String?;
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

    // --- TIER 4: Fallback search by title alone ---
    try {
      final q = Uri.encodeComponent(cleanTitle);
      final searchUrl = Uri.parse('https://lrclib.net/api/search?q=$q');
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final best = _pickBestSearchResult(list, cleanTitle, cleanArtist, targetDuration);
          final synced = best?['syncedLyrics'] as String?;
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

  Map<String, dynamic>? _pickBestSearchResult(
    List<dynamic> list,
    String cleanTitle,
    String cleanArtist,
    int? targetDuration,
  ) {
    if (list.isEmpty) return null;

    final normTitle = cleanTitle.toLowerCase();
    final normArtist = cleanArtist.toLowerCase();

    final scored = list.map((item) {
      if (item is! Map<String, dynamic>) return {'item': item, 'score': -999};

      int score = 0;
      final synced = item['syncedLyrics'] as String?;
      if (synced != null && synced.isNotEmpty) score += 100;

      // Duration scoring
      final itemDur = (item['duration'] as num?)?.toDouble();
      if (targetDuration != null && itemDur != null) {
        final diff = (itemDur - targetDuration).abs();
        if (diff <= 2) {
          score += 90;
        } else if (diff <= 5) {
          score += 70;
        } else if (diff <= 10) {
          score += 40;
        } else if (diff <= 18) {
          score += 15;
        } else if (diff > 35) {
          score -= 60;
        } else if (diff > 60) {
          score -= 120;
        }
      }

      // Title match
      final itemTitle = ((item['trackName'] ?? '') as String).toLowerCase();
      if (itemTitle == normTitle) {
        score += 50;
      } else if (itemTitle.contains(normTitle) || normTitle.contains(itemTitle)) {
        score += 30;
      }

      // Artist match
      final itemArt = ((item['artistName'] ?? '') as String).toLowerCase();
      if (itemArt == normArtist) {
        score += 50;
      } else if (itemArt.contains(normArtist) || normArtist.contains(itemArt)) {
        score += 30;
      }

      return {'item': item, 'score': score};
    }).toList();

    scored.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));
    return scored.first['item'] as Map<String, dynamic>?;
  }

  List<LyricLine> parseLrc(String lrcContent) {
    final List<Map<String, dynamic>> rawParsed = [];
    final timeRegex = RegExp(r'\[(\d{2}):(\d{2})(?:\.(\d{2,3}))?\]');

    for (final rawLine in lrcContent.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = timeRegex.firstMatch(line);
      if (match == null) continue;

      final min = int.tryParse(match.group(1) ?? '0') ?? 0;
      final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
      final msStr = match.group(3) ?? '0';
      final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
      final time = min * 60 + sec + (ms / 1000.0);

      final cleanText = line.replaceAll(RegExp(r'\[\d{2}:\d{2}(?:\.\d{2,3})?\]'), '').trim();

      // Empty text timestamp marks the explicit vocal end-time of the previous line!
      if (cleanText.isEmpty) {
        if (rawParsed.isNotEmpty) {
          final prev = rawParsed.last;
          if (prev['explicitEndTime'] == null && time > (prev['time'] as double)) {
            prev['explicitEndTime'] = time;
            prev['endTime'] = time;
          }
        }
        continue;
      }

      final isBackgroundVocal = cleanText.startsWith('(') && cleanText.endsWith(')') ||
          cleanText.startsWith('[') && cleanText.endsWith(']');

      rawParsed.add({
        'time': time,
        'text': cleanText.replaceAll(RegExp(r'<\d{2}:\d{2}(?:\.\d{2,3})?>'), '').trim(),
        'rawText': cleanText,
        'isBackgroundVocal': isBackgroundVocal,
      });
    }

    rawParsed.sort((a, b) => (a['time'] as double).compareTo(b['time'] as double));

    final List<LyricLine> lines = [];

    for (int i = 0; i < rawParsed.length; i++) {
      final curr = rawParsed[i];
      final next = i + 1 < rawParsed.length ? rawParsed[i + 1] : null;

      final currTime = curr['time'] as double;
      final nextTime = next != null ? (next['time'] as double) : null;

      // Instrumental intro check
      if (i == 0 && currTime > 6.0) {
        lines.add(LyricLine(
          time: 0.5,
          endTime: currTime - 0.4,
          text: '♪  Intro  ♪',
          isInstrumental: true,
        ));
      }

      double endTime = (curr['explicitEndTime'] as double?) ??
          (nextTime != null
              ? (currTime + ((nextTime - currTime) * 0.94).clamp(1.2, 8.0))
              : currTime + 4.5);

      final lineText = curr['text'] as String;
      final rawText = curr['rawText'] as String;
      final isBg = curr['isBackgroundVocal'] as bool;
      final duration = (endTime - currTime).clamp(0.8, 15.0);

      final words = _computeWordTimings(rawText, currTime, duration);

      final lyricLine = LyricLine(
        time: currTime,
        endTime: endTime,
        text: lineText,
        rawText: rawText,
        words: words,
        isInstrumental: false,
        isBackgroundVocal: isBg,
      );
      lines.add(lyricLine);

      // Instrumental break between lines if gap > 3.8s
      if (nextTime != null && (nextTime - endTime) > 3.8) {
        lines.add(LyricLine(
          time: endTime + 0.3,
          endTime: nextTime - 0.4,
          text: '♪  Musik  ♪',
          isInstrumental: true,
        ));
      }
    }

    return lines;
  }

  List<LyricWord> _computeWordTimings(String rawText, double lineStart, double lineDuration) {
    if (rawText.isEmpty) return [];

    // 1. Enhanced LRC inline tags <mm:ss.xx>word
    final wordTagRegex = RegExp(r'<(\d{2}):(\d{2})(?:\.(\d{2,3}))?>');
    if (wordTagRegex.hasMatch(rawText)) {
      final List<LyricWord> tokens = [];
      final splitRegex = RegExp(r'<(\d{2}):(\d{2})(?:\.(\d{2,3}))?>([^<]+)');
      for (final match in splitRegex.allMatches(rawText)) {
        final min = int.tryParse(match.group(1) ?? '0') ?? 0;
        final sec = int.tryParse(match.group(2) ?? '0') ?? 0;
        final msStr = match.group(3) ?? '0';
        final ms = int.tryParse(msStr.padRight(3, '0').substring(0, 3)) ?? 0;
        final time = min * 60 + sec + (ms / 1000.0);
        final word = (match.group(4) ?? '').trim();
        if (word.isNotEmpty) {
          tokens.add(LyricWord(
            word: word,
            startTime: time,
            endTime: time + 0.3,
            duration: 0.3,
          ));
        }
      }

      if (tokens.isNotEmpty) {
        final List<LyricWord> adjusted = [];
        for (int i = 0; i < tokens.length; i++) {
          final next = i + 1 < tokens.length ? tokens[i + 1] : null;
          final nextStart = next != null ? next.startTime : (lineStart + lineDuration);
          final end = (tokens[i].startTime + 0.15).clamp(tokens[i].startTime + 0.15, nextStart);
          adjusted.add(LyricWord(
            word: tokens[i].word,
            startTime: tokens[i].startTime,
            endTime: end,
            duration: end - tokens[i].startTime,
          ));
        }
        return adjusted;
      }
    }

    // 2. Standard Syllabic Word Weight Estimation
    final clean = rawText.replaceAll(RegExp(r'<\d{2}:\d{2}(?:\.\d{2,3})?>'), '').trim();
    final rawWords = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return [];

    final totalChars = rawWords.fold<int>(0, (sum, w) => sum + (w.isNotEmpty ? w.length : 1));
    final activeDuration = (lineDuration * 0.94).clamp(0.6, 12.0);

    double currentOffset = 0.0;
    final List<LyricWord> result = [];
    for (final word in rawWords) {
      final weight = (word.isNotEmpty ? word.length : 1) / totalChars;
      final wordDur = (activeDuration * weight).clamp(0.18, 5.0);
      final start = lineStart + currentOffset;
      final end = start + wordDur;
      currentOffset += wordDur;

      result.add(LyricWord(
        word: word,
        startTime: start,
        endTime: end,
        duration: wordDur,
      ));
    }

    return result;
  }
}
