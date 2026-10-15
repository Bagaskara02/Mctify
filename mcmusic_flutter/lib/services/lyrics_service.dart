import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsResult {
  final List<LyricLine> lines;
  final double autoOffset;
  final bool isSynced;
  final String source;

  const LyricsResult({
    required this.lines,
    this.autoOffset = 0.0,
    this.isSynced = false,
    this.source = 'LRCLIB',
  });
}

class LyricsService {
  static final Map<String, LyricsResult> _cache = {};

  /// Aggressively clean dirty YouTube/streaming metadata
  static Map<String, dynamic> cleanTrackMetadata(String rawTitle, String rawArtist) {
    var title = rawTitle.trim();
    var artist = rawArtist.trim();

    // Strip Topic, VEVO, Official from artist
    artist = artist.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
                   .replaceAll(RegExp(r'\s*VEVO$', caseSensitive: false), '')
                   .replaceAll(RegExp(r'\s*Official$', caseSensitive: false), '')
                   .trim();

    // If title has 'Artist - Title' format
    if (title.contains(' - ')) {
      final parts = title.split(' - ');
      if (parts.length >= 2) {
        final p0 = parts[0].trim();
        final p1 = parts.sublist(1).join(' - ').trim();
        if (artist.isNotEmpty && (p0.toLowerCase().contains(artist.toLowerCase()) || artist.toLowerCase().contains(p0.toLowerCase()))) {
          title = p1;
        } else if (artist.isNotEmpty && (p1.toLowerCase().contains(artist.toLowerCase()) || artist.toLowerCase().contains(p1.toLowerCase()))) {
          title = p0;
        } else if (artist.isEmpty) {
          artist = p0;
          title = p1;
        }
      }
    }

    // Strip common YouTube tags and suffixes
    title = title.replaceAll(
      RegExp(r'\s*[\(\[](official\s*(music\s*)?video|official\s*audio|official\s*lyric(\s*video)?|visualizer|audio|video|clip\s*officiel|mv|hd|4k|remastered|live|session|brooklyn\s*session|10\s*years|lirik|lyrics|feat\.?|ft\.?)[^\)\]]*[\)\]]', caseSensitive: false),
      '',
    );
    title = title.replaceAll(
      RegExp(r'\s*(feat\.|ft\.)\s+[^-\(\]]+', caseSensitive: false),
      '',
    );
    title = title.replaceAll(RegExp(r'[◐◑]'), '').trim();

    // Clean remaining lonely brackets
    title = title.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();
    artist = artist.replaceAll(RegExp(r'[\(\)\[\]]'), '').trim();

    final List<String> subTitles = [title];
    if (title.contains(' / ')) {
      final subParts = title.split(' / ').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      subTitles.addAll(subParts);
    }

    return {
      'title': title,
      'artist': artist,
      'subTitles': subTitles,
    };
  }

  // Backwards compatibility alias for existing unit tests
  static Map<String, String> cleanTitleAndArtist(String rawTitle, String rawArtist) {
    final meta = cleanTrackMetadata(rawTitle, rawArtist);
    return {
      'title': meta['title'] as String,
      'artist': meta['artist'] as String,
    };
  }

  Future<LyricsResult> fetchLyricsResult(String rawArtist, String rawTitle, int duration) async {
    final meta = cleanTrackMetadata(rawTitle, rawArtist);
    final cleanTitle = meta['title'] as String;
    final cleanArtist = meta['artist'] as String;
    final subTitles = meta['subTitles'] as List<String>;
    final targetDuration = duration > 5 ? duration : null;
    final cacheKey = '${cleanArtist.toLowerCase()}:::${cleanTitle.toLowerCase()}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    // TIER 1: NetEase Cloud Music (Studio Syllable-Synced YRC & LRC)
    final netease = await _fetchNetEase(cleanTitle, cleanArtist);
    if (netease != null && netease.lines.isNotEmpty) {
      _cache[cacheKey] = netease;
      return netease;
    }

    // TIER 2: LRCLIB (Exact & Flexible Search)
    final lrclib = await _fetchLrclib(cleanTitle, cleanArtist, targetDuration);
    if (lrclib != null && lrclib.lines.isNotEmpty) {
      _cache[cacheKey] = lrclib;
      return lrclib;
    }

    // TIER 3: Composite Sub-title retry (e.g. 'Television' from 'Television / So Far So Good')
    if (subTitles.length > 1) {
      for (int i = 1; i < subTitles.length; i++) {
        final sub = subTitles[i];
        final subNetEase = await _fetchNetEase(sub, cleanArtist);
        if (subNetEase != null && subNetEase.lines.isNotEmpty) {
          _cache[cacheKey] = subNetEase;
          return subNetEase;
        }
        final subLrc = await _fetchLrclib(sub, cleanArtist, targetDuration);
        if (subLrc != null && subLrc.lines.isNotEmpty) {
          _cache[cacheKey] = subLrc;
          return subLrc;
        }
      }
    }

    // TIER 4: Lyrist Public API Fallback
    try {
      final url = Uri.parse('https://lyrist.vercel.app/api/${Uri.encodeComponent(cleanTitle)}/${Uri.encodeComponent(cleanArtist)}');
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawLyrics = data['lyrics'] as String?;
        if (rawLyrics != null && rawLyrics.trim().isNotEmpty) {
          final lines = _parsePlain(rawLyrics);
          final result = LyricsResult(
            lines: lines,
            isSynced: false,
            source: 'Lyrist',
          );
          _cache[cacheKey] = result;
          return result;
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

  Future<LyricsResult?> _fetchNetEase(String title, String artist) async {
    try {
      final q = '$title $artist'.trim();
      final searchUrl = Uri.parse('https://music.163.com/api/cloudsearch/pc');
      final res = await http.post(
        searchUrl,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://music.163.com',
        },
        body: 's=${Uri.encodeQueryComponent(q)}&type=1&offset=0&limit=3',
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final songs = data['result']?['songs'] as List?;
        if (songs != null && songs.isNotEmpty) {
          final id = songs[0]['id'];
          final lyricUrl = Uri.parse('https://music.163.com/api/song/lyric?id=$id&lv=1&kv=1&tv=-1&yv=1');
          final lyricRes = await http.get(lyricUrl, headers: {
            'Referer': 'https://music.163.com',
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
          }).timeout(const Duration(seconds: 4));

          if (lyricRes.statusCode == 200) {
            final lyricData = jsonDecode(lyricRes.body);
            final yrc = lyricData['yrc']?['lyric'] as String?;
            if (yrc != null && yrc.isNotEmpty) {
              final lines = parseYrc(yrc);
              if (lines.isNotEmpty) {
                return LyricsResult(
                  lines: lines,
                  isSynced: true,
                  source: 'NetEase YRC (Studio Syllable-Synced)',
                );
              }
            }

            final lrc = lyricData['lrc']?['lyric'] as String?;
            if (lrc != null && lrc.isNotEmpty) {
              final lines = parseLrc(lrc);
              if (lines.isNotEmpty) {
                return LyricsResult(
                  lines: lines,
                  isSynced: true,
                  source: 'NetEase LRC',
                );
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<LyricsResult?> _fetchLrclib(String cleanTitle, String cleanArtist, int? targetDuration) async {
    // 1. Exact lookup
    try {
      final queryParams = {
        'artist_name': cleanArtist,
        'track_name': cleanTitle,
      };
      if (targetDuration != null) {
        queryParams['duration'] = targetDuration.toString();
      }
      final url = Uri.https('lrclib.net', '/api/get', queryParams);
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        final plain = data['plainLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          return LyricsResult(
            lines: parseLrc(synced),
            isSynced: true,
            source: 'LRCLIB (Exact Match)',
          );
        } else if (plain != null && plain.isNotEmpty) {
          return LyricsResult(
            lines: _parsePlain(plain),
            isSynced: false,
            source: 'LRCLIB (Plain)',
          );
        }
      }
    } catch (_) {}

    // 2. Flexible search query
    try {
      final searchUrl = Uri.parse('https://lrclib.net/api/search?q=${Uri.encodeComponent('$cleanTitle $cleanArtist')}');
      final res = await http.get(searchUrl).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final best = list.firstWhere((i) => i['syncedLyrics'] != null, orElse: () => list[0]);
          final synced = best['syncedLyrics'] as String?;
          final plain = best['plainLyrics'] as String?;
          if (synced != null && synced.isNotEmpty) {
            return LyricsResult(
              lines: parseLrc(synced),
              isSynced: true,
              source: 'LRCLIB (Search Match)',
            );
          } else if (plain != null && plain.isNotEmpty) {
            return LyricsResult(
              lines: _parsePlain(plain),
              isSynced: false,
              source: 'LRCLIB (Plain)',
            );
          }
        }
      }
    } catch (_) {}

    return null;
  }

  /// Parse NetEase YRC syllable/word-synced format
  List<LyricLine> parseYrc(String yrcContent) {
    if (yrcContent.isEmpty) return [];
    final rawLines = yrcContent.split('\n');
    final List<LyricLine> parsed = [];
    final lineHeaderRegex = RegExp(r'^\[(\d+),(\d+)\](.*)');
    final wordRegex = RegExp(r'\((\d+),(\d+),\d+\)([^(\n]+)');

    for (int i = 0; i < rawLines.length; i++) {
      final raw = rawLines[i].trim();
      if (raw.isEmpty) continue;
      final match = lineHeaderRegex.firstMatch(raw);
      if (match == null) continue;

      final lineStartMs = int.tryParse(match.group(1) ?? '0') ?? 0;
      final lineDurMs = int.tryParse(match.group(2) ?? '0') ?? 0;
      final lineContent = match.group(3) ?? '';

      // Skip credit lines
      if (RegExp(r'作词|作曲|Written by|Composer|Producer|Arranger|Mixing', caseSensitive: false).hasMatch(lineContent)) {
        continue;
      }

      final List<LyricWord> words = [];
      for (final wMatch in wordRegex.allMatches(lineContent)) {
        final wStartMs = int.tryParse(wMatch.group(1) ?? '0') ?? 0;
        final wDurMs = int.tryParse(wMatch.group(2) ?? '0') ?? 0;
        final wText = wMatch.group(3) ?? '';
        if (wText.trim().isNotEmpty) {
          final startSec = wStartMs / 1000.0;
          final durSec = math.max(0.04, wDurMs / 1000.0);
          final endSec = startSec + durSec;
          words.add(LyricWord(
            word: wText,
            startTime: startSec,
            endTime: endSec,
            duration: durSec,
            chars: _generateCharTimings(wText, startSec, durSec),
          ));
        }
      }

      if (words.isNotEmpty) {
        final lineText = words.map((w) => w.word).join('').trim();
        final lineStartSec = lineStartMs / 1000.0;
        final lineDurSec = math.max(0.6, lineDurMs / 1000.0);

        parsed.add(LyricLine(
          time: lineStartSec,
          endTime: lineStartSec + lineDurSec,
          text: lineText,
          words: words,
          isInstrumental: false,
          isInterlude: false,
        ));
      }
    }

    return _finalizeLinesWithInterludes(parsed);
  }

  /// Parse standard or enhanced LRC
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

      // Filter credit lines
      if (RegExp(r'^(作词|作曲|Written by|Composer|Producer):', caseSensitive: false).hasMatch(cleanText)) {
        continue;
      }

      final isBackgroundVocal = cleanText.startsWith('(') && cleanText.endsWith(')') ||
          cleanText.startsWith('[') && cleanText.endsWith(']');

      rawParsed.add({
        'time': time,
        'text': cleanText.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'), '').trim(),
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

      final lineText = curr['text'] as String;
      final rawText = curr['rawText'] as String;
      final isBg = curr['isBackgroundVocal'] as bool;

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

      lines.add(LyricLine(
        time: currTime,
        endTime: endTime,
        text: lineText,
        rawText: rawText,
        words: words,
        isInstrumental: false,
        isInterlude: false,
        isBackgroundVocal: isBg,
      ));
    }

    return _finalizeLinesWithInterludes(lines);
  }

  List<LyricLine> _finalizeLinesWithInterludes(List<LyricLine> parsedLines) {
    if (parsedLines.isEmpty) return [];
    final List<LyricLine> result = [];

    for (int i = 0; i < parsedLines.length; i++) {
      final curr = parsedLines[i];
      final next = i + 1 < parsedLines.length ? parsedLines[i + 1] : null;

      if (i == 0 && curr.time > 4.2) {
        result.add(LyricLine(
          time: 0.5,
          endTime: curr.time - 0.2,
          text: '♪ Intro ♪',
          isInstrumental: true,
          isInterlude: true,
        ));
      }

      result.add(curr);

      if (next != null && (next.time - curr.endTime) > 4.5) {
        result.add(LyricLine(
          time: curr.endTime + 0.15,
          endTime: next.time - 0.2,
          text: '♪ Musik ♪',
          isInstrumental: true,
          isInterlude: true,
        ));
      }
    }

    return result;
  }

  List<LyricWord> _computeWordTimings(String rawText, double lineStart, double lineDuration) {
    if (rawText.isEmpty) return [];

    // 1. Enhanced LRC inline tags <mm:ss.xx>word
    final wordTagRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
    if (wordTagRegex.hasMatch(rawText)) {
      final List<LyricWord> tokens = [];
      final splitRegex = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>([^<]+)');
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

    // 2. Standard Syllabic Word Weight Estimation
    final clean = rawText.replaceAll(RegExp(r'<\d{1,3}:\d{2}(?:[.:]\d{1,3})?>'), '').trim();
    final rawWords = clean.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (rawWords.isEmpty) return [];

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

  List<LyricLine> _parsePlain(String plainText) {
    if (plainText.isEmpty) return [];
    return plainText.split('\n').map((line) => line.trim()).where((l) => l.isNotEmpty).toList().asMap().entries.map((e) {
      final idx = e.key;
      final line = e.value;
      final time = idx * 4.0;
      return LyricLine(
        time: time,
        endTime: time + 3.8,
        text: line,
        words: _computeWordTimings(line, time, 3.8),
        isInstrumental: false,
        isInterlude: false,
      );
    }).toList();
  }
}
