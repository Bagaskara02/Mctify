import 'package:flutter_test/flutter_test.dart';
import 'package:mcmusic_flutter/services/lyrics_service.dart';

void main() {
  final lyricsService = LyricsService();

  group('LyricsParser Tests', () {
    test('Parses standard 2-digit minute and 2-digit centisecond timestamps [mm:ss.xx]', () {
      const lrc = '''
[00:12.30]Bila kau butuh telinga
[00:15.80]Tuk mendengar
[00:20.10]Bahu tuk bersandar
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 3);
      expect(vocalLines[0].time, closeTo(12.30, 0.01));
      expect(vocalLines[0].text, 'Bila kau butuh telinga');
      expect(vocalLines[1].time, closeTo(15.80, 0.01));
      expect(vocalLines[1].text, 'Tuk mendengar');
      expect(vocalLines[2].time, closeTo(20.10, 0.01));
      expect(vocalLines[2].text, 'Bahu tuk bersandar');
    });

    test('Parses 3-digit millisecond timestamps [mm:ss.xxx]', () {
      const lrc = '''
[01:05.450]Kini kau telah pergi
[01:10.125]Meninggalkan kenangan
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 2);
      expect(vocalLines[0].time, closeTo(65.45, 0.01));
      expect(vocalLines[0].text, 'Kini kau telah pergi');
      expect(vocalLines[1].time, closeTo(70.125, 0.01));
      expect(vocalLines[1].text, 'Meninggalkan kenangan');
    });

    test('Parses single-digit minute timestamps [m:ss.xx]', () {
      const lrc = '''
[1:02.15]Satu menit berlalu
[2:30.00]Dua menit tiga puluh detik
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 2);
      expect(vocalLines[0].time, closeTo(62.15, 0.01));
      expect(vocalLines[0].text, 'Satu menit berlalu');
      expect(vocalLines[1].time, closeTo(150.0, 0.01));
      expect(vocalLines[1].text, 'Dua menit tiga puluh detik');
    });

    test('Parses colon fraction timestamps [mm:ss:xx]', () {
      const lrc = '''
[00:30:50]Format titik dua
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 1);
      expect(vocalLines[0].time, closeTo(30.50, 0.05));
      expect(vocalLines[0].text, 'Format titik dua');
    });

    test('Detects background vocals formatted with parentheses', () {
      const lrc = '''
[00:10.00]Suara utama
[00:12.00](suara latar pelan)
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 2);
      expect(vocalLines[0].isBackgroundVocal, false);
      expect(vocalLines[1].isBackgroundVocal, true);
    });

    test('Calculates explicit end time from blank timestamp marker', () {
      const lrc = '''
[00:05.00]Baris pertama
[00:08.50]
[00:12.00]Baris kedua
''';

      final allLines = lyricsService.parseLrc(lrc);
      final vocalLines = allLines.where((l) => !l.isInstrumental).toList();

      expect(vocalLines.length, 2);
      expect(vocalLines[0].time, 5.0);
      expect(vocalLines[0].endTime, closeTo(8.5, 0.01));
      expect(vocalLines[1].time, 12.0);
    });

    test('Automatically injects Intro and Musik instrumental lines when appropriate', () {
      const lrc = '''
[00:15.00]Baris setelah intro lama
[00:35.00]Baris setelah jeda musik panjang
''';

      final lines = lyricsService.parseLrc(lrc);
      expect(lines.any((l) => l.isInstrumental && l.text.contains('Intro')), true);
      expect(lines.any((l) => l.isInstrumental && l.text.contains('Musik')), true);
    });

    test('Clean title and artist strips common noisy video suffixes', () {
      final cleaned = LyricsService.cleanTitleAndArtist(
        'Gala Bunga Matahari (Official Music Video) [4K]',
        'Sal Priadi',
      );
      expect(cleaned['title'], 'Gala Bunga Matahari');
      expect(cleaned['artist'], 'Sal Priadi');
    });
  });
}
