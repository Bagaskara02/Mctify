import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsResult {
  final List<LyricLine> lines;
  final double autoOffset;
  final bool isSynced;
  final String source;
  final String detectedStyle;

  const LyricsResult({
    required this.lines,
    this.autoOffset = 0.0,
    this.isSynced = false,
    this.source = 'LRCLIB',
    this.detectedStyle = 'pop',
  });
}

class LyricsService {
  static final Map<String, LyricsResult> _cache = {};

  /// Calculate intelligent auto-sync offset based on LRC [offset: xxx] tags
  /// and audio stream vs studio metadata duration differential.
  static double calculateAutoSyncOffset(String? syncedLyrics, int? targetDuration, double? trackDuration) {
    double offset = 0.0;
    if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
      final match = RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false).firstMatch(syncedLyrics);
      if (match != null) {
        final parsed = int.tryParse(match.group(1) ?? '0') ?? 0;
        offset += parsed / 1000.0;
      }
    }
    if (targetDuration != null && trackDuration != null && targetDuration > 5 && trackDuration > 5) {
      final diff = targetDuration - trackDuration;
      if (diff >= 0.3 && diff <= 3.5) {
        offset -= (diff * 0.2).clamp(0.0, 0.4);
      } else if (diff <= -0.3 && diff >= -3.5) {
        offset += (diff.abs() * 0.2).clamp(0.0, 0.4);
      }
    }
    return (offset * 10).roundToDouble() / 10.0;
  }

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

  /// Detect song style to provide adaptive lyric animations
  /// Returns: 'ballad' | 'pop' | 'kinetic' | 'chill'
  static String detectSongStyle(String title, String artist, List<LyricLine> lines, [int? duration]) {
    final text = '$title $artist'.toLowerCase();

    // 1. Keyword analysis
    if (RegExp(r'\b(acoustic|akustik|piano|orchestra|slowed|sad|gundah|galau|heartbreak|sleep|lullaby)\b').hasMatch(text)) {
      return 'ballad';
    }
    if (RegExp(r'\b(rap|hip[\s-]?hop|drill|trap|freestyle|diss|sped up|rock|metal|punk)\b').hasMatch(text)) {
      return 'kinetic';
    }
    if (RegExp(r'\b(chill|lofi|lo-fi|r&b|soul|jazz|indie|night|vibes|ambient|relaxed)\b').hasMatch(text)) {
      return 'chill';
    }
    if (RegExp(r'\b(remix|dance|edm|party|club|upbeat|disco|electronic|house|pop)\b').hasMatch(text)) {
      return 'pop';
    }

    // 2. Cadence analysis (Words per second across active singing lines)
    if (lines.length > 2) {
      int totalWords = 0;
      double activeSingingSeconds = 0.0;
      for (final line in lines) {
        if (!line.isInstrumental && !line.isInterlude && line.words.isNotEmpty) {
          totalWords += line.words.length;
          activeSingingSeconds += math.max(0.5, line.endTime - line.time);
        }
      }

      final wordsPerSec = activeSingingSeconds > 0 ? (totalWords / activeSingingSeconds) : 1.2;
      if (wordsPerSec >= 2.8) return 'kinetic';
      if (wordsPerSec >= 1.6) return 'pop';
      if (wordsPerSec <= 0.95) return 'ballad';
      return 'chill';
    }

    return 'pop';
  }

  Future<LyricsResult> fetchLyricsResult(String artist, String title, int duration) async {
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
          final trackDur = (data['duration'] as num?)?.toDouble();
          if (synced != null && synced.isNotEmpty) {
            final parsed = parseLrc(synced);
            if (parsed.isNotEmpty) {
              final autoOffset = calculateAutoSyncOffset(synced, targetDuration, trackDur);
              final style = detectSongStyle(cleanTitle, cleanArtist, parsed, targetDuration);
              final result = LyricsResult(
                lines: parsed,
                autoOffset: autoOffset,
                isSynced: true,
                source: 'LRCLIB (Exact Match)',
                detectedStyle: style,
              );
              _cache[cacheKey] = result;
              return result;
            }
          }
        }
      } catch (_) {}
    }

    // --- TIER 2: Exact lookup without duration ---
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
            final autoOffset = calculateAutoSyncOffset(synced, targetDuration, returnedDuration);
            final style = detectSongStyle(cleanTitle, cleanArtist, parsed, targetDuration);
            final result = LyricsResult(
              lines: parsed,
              autoOffset: autoOffset,
              isSynced: true,
              source: 'LRCLIB (Name Match)',
              detectedStyle: style,
            );
            _cache[cacheKey] = result;
            return result;
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
          final trackDur = (best?['duration'] as num?)?.toDouble();
          if (synced != null && synced.isNotEmpty) {
            final parsed = parseLrc(synced);
            if (parsed.isNotEmpty) {
              final autoOffset = calculateAutoSyncOffset(synced, targetDuration, trackDur);
              final style = detectSongStyle(cleanTitle, cleanArtist, parsed, targetDuration);
              final result = LyricsResult(
                lines: parsed,
                autoOffset: autoOffset,
                isSynced: true,
                source: 'LRCLIB (Ranked Match)',
                detectedStyle: style,
              );
              _cache[cacheKey] = result;
              return result;
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
          final trackDur = (best?['duration'] as num?)?.toDouble();
          if (synced != null && synced.isNotEmpty) {
            final parsed = parseLrc(synced);
            if (parsed.isNotEmpty) {
              final autoOffset = calculateAutoSyncOffset(synced, targetDuration, trackDur);
              final style = detectSongStyle(cleanTitle, cleanArtist, parsed, targetDuration);
              final result = LyricsResult(
                lines: parsed,
                autoOffset: autoOffset,
                isSynced: true,
                source: 'LRCLIB (Title Search)',
                detectedStyle: style,
              );
              _cache[cacheKey] = result;
              return result;
            }
          }
        }
      }
    } catch (_) {}

    final empty = const LyricsResult(lines: [], autoOffset: 0.0, isSynced: false);
    _cache[cacheKey] = empty;
    return empty;
  }

  Future<List<LyricLine>> fetchLyrics(String artist, String title, int duration) async {
    final res = await fetchLyricsResult(artist, title, duration);
    return res.lines;
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
    final timeRegex = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');

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

      final cleanText = line.replaceAll(RegExp(r'\[\d{1,3}:\d{2}(?:[.:]\d{1,3})?\]'), '').trim();

      // Empty text timestamp marks the explicit vocal end-time of the previous line
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

      // Instrumental intro check (> 4.2s)
      if (i == 0 && currTime > 4.2) {
        lines.add(LyricLine(
          time: 0.5,
          endTime: currTime - 0.2,
          text: '♪ Intro ♪',
          isInstrumental: true,
          isInterlude: true,
        ));
      }

      final lineText = curr['text'] as String;
      final rawText = curr['rawText'] as String;
      final isBg = curr['isBackgroundVocal'] as bool;

      // Vocal Duration Cap calculation
      double duration;
      if (curr['explicitEndTime'] != null) {
        duration = ((curr['explicitEndTime'] as double) - currTime).clamp(0.8, 12.0);
      } else if (nextTime != null) {
        final rawGap = nextTime - currTime;
        final capped = math.min(rawGap - 0.15, math.max(1.8, lineText.length * 0.11));
        duration = capped.clamp(0.8, 9.5);
      } else {
        duration = math.min(lineText.length * 0.11, 4.5).clamp(1.8, 4.5);
      }

      final endTime = currTime + duration;
      final words = _computeWordTimings(rawText, currTime, duration);

      final lyricLine = LyricLine(
        time: currTime,
        endTime: endTime,
        text: lineText,
        rawText: rawText,
        words: words,
        isInstrumental: false,
        isInterlude: false,
        isBackgroundVocal: isBg,
      );
      lines.add(lyricLine);

      // Instrumental interlude between lines if gap > 4.5s
      if (nextTime != null && (nextTime - endTime) > 4.5) {
        lines.add(LyricLine(
          time: endTime + 0.15,
          endTime: nextTime - 0.2,
          text: '♪ Musik ♪',
          isInstrumental: true,
          isInterlude: true,
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
          final wordDur = end - tokens[i].startTime;
          adjusted.add(LyricWord(
            word: tokens[i].word,
            startTime: tokens[i].startTime,
            endTime: end,
            duration: wordDur,
            chars: _generateCharTimings(tokens[i].word, tokens[i].startTime, wordDur),
          ));
        }
        return adjusted;
      }
    }

    // 2. Standard Syllabic Word & Character Weight Generator
    final clean = rawText.replaceAll(RegExp(r'<\d{2}:\d{2}(?:\.\d{2,3})?>'), '').trim();
    final rawWords = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return [];

    // Vowel & punctuation weights for natural vocal flow
    double calculateWordWeight(String word) {
      final vowels = RegExp(r'[aiueoAIUEO]').allMatches(word).length;
      double weight = math.max(1.0, vowels * 1.6 + word.length * 0.4);
      if (RegExp(r'[,;]$').hasMatch(word)) weight += 0.8;
      if (RegExp(r'[.!?]$').hasMatch(word)) weight += 1.4;
      return weight;
    }

    final weights = rawWords.map(calculateWordWeight).toList();
    final totalWeight = weights.fold<double>(0.0, (sum, w) => sum + w);
    final activeDuration = (lineDuration * 0.94).clamp(0.6, 12.0);

    double currentOffset = 0.0;
    final List<LyricWord> result = [];
    for (int idx = 0; idx < rawWords.length; idx++) {
      final word = rawWords[idx];
      final wordWeight = weights[idx] / totalWeight;
      final wordDur = (activeDuration * wordWeight).clamp(0.18, 5.0);
      final start = lineStart + currentOffset;
      final end = start + wordDur;
      currentOffset += wordDur;

      result.add(LyricWord(
        word: word,
        startTime: start,
        endTime: end,
        duration: wordDur,
        chars: _generateCharTimings(word, start, wordDur),
      ));
    }

    return result;
  }

  /// Break word down into individual characters with micro-timestamps
  static List<LyricChar> _generateCharTimings(String word, double wordStart, double wordDuration) {
    if (word.isEmpty) return [];
    final chars = word.split('');
    if (chars.isEmpty) return [];

    final weights = chars.map((ch) {
      if (RegExp(r'[aiueoAIUEO]').hasMatch(ch)) return 1.8;
      if (RegExp(r'[,.!?]').hasMatch(ch)) return 0.6;
      return 1.0;
    }).toList();

    final totalWeight = weights.fold<double>(0.0, (s, w) => s + w);
    double curOffset = 0.0;

    final List<LyricChar> result = [];
    for (int i = 0; i < chars.length; i++) {
      final charDur = (weights[i] / totalWeight) * wordDuration;
      final start = wordStart + curOffset;
      final end = start + charDur;
      curOffset += charDur;

      result.add(LyricChar(
        char: chars[i],
        startTime: start,
        endTime: end,
        duration: charDur,
      ));
    }

    return result;
  }
}
