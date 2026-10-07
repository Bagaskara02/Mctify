import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/lyric_line.dart';

class LyricsService {
  Future<List<LyricLine>> fetchLyrics(String artist, String title, int duration) async {
    try {
      final url = Uri.parse(
        'https://lrclib.net/api/get?artist_name=${Uri.encodeComponent(artist)}&track_name=${Uri.encodeComponent(title)}&duration=$duration',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final synced = data['syncedLyrics'] as String?;
        if (synced != null && synced.isNotEmpty) {
          return parseLrc(synced);
        }
      }
    } catch (_) {}

    // Fallback demo lyrics for smooth visual karaoke demo
    return generateFallbackLyrics(title, artist, duration);
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

    return lines;
  }

  List<LyricLine> generateFallbackLyrics(String title, String artist, int duration) {
    return [
      LyricLine(time: 2.0, text: '♪ Intro Musik ♪'),
      LyricLine(time: 8.0, text: 'Mendengarkan $title'),
      LyricLine(time: 15.0, text: 'Karya indah dari $artist'),
      LyricLine(time: 23.0, text: 'Alunan melodi yang memikat hati'),
      LyricLine(time: 32.0, text: 'Setiap nada membawa ketenangan'),
      LyricLine(time: 44.0, text: '♪ Instrumental Melodi ♪'),
      LyricLine(time: 58.0, text: 'Bernyanyi bersama di McMusic'),
      LyricLine(time: 75.0, text: 'Harmoni yang tak terlupakan'),
      LyricLine(time: 90.0, text: '♪ Solo Musik ♪'),
      LyricLine(time: 110.0, text: 'Menikmati setiap lantunan nada'),
    ];
  }
}
