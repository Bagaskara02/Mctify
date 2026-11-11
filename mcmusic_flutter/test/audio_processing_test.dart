import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcmusic_flutter/models/audio_quality.dart';
import 'package:mcmusic_flutter/models/equalizer_preset.dart';
import 'package:mcmusic_flutter/services/equalizer_service.dart';
import 'package:mcmusic_flutter/services/music_api_service.dart';
import 'package:mcmusic_flutter/services/storage_service.dart';
import 'package:mcmusic_flutter/utils/artwork_palette.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Audio Quality Tests', () {
    test('AudioQuality enum has realistic YouTube bitrates', () {
      expect(AudioQuality.dataSaver.bitrate, '64 kbps');
      expect(AudioQuality.standard.bitrate, '128 kbps');
      expect(AudioQuality.high.bitrate, '160 kbps');

      expect(AudioQuality.fromString('dataSaver'), AudioQuality.dataSaver);
      expect(AudioQuality.fromString('standard'), AudioQuality.standard);
      expect(AudioQuality.fromString('high'), AudioQuality.high);
      expect(AudioQuality.fromString('invalid'), AudioQuality.high);
    });
  });

  group('Anti-Junk & Instrumental Filter Tests', () {
    test('filters out instrumental, backing track, and minus-one tracks by default', () {
      expect(MusicApiService.isUnwantedJunkTrack('Unforgettable (Instrumental)', 'PnB Rock', 'Single'), isTrue);
      expect(MusicApiService.isUnwantedJunkTrack('Hotel California (Backing Track)', 'Eagles', 'Single'), isTrue);
      expect(MusicApiService.isUnwantedJunkTrack('Perfect - Minus One', 'Ed Sheeran', 'Single'), isTrue);
      expect(MusicApiService.isUnwantedJunkTrack('Shape of You - Karaoke Version', 'Karaoke', 'Single'), isTrue);
    });

    test('filters out slowed + reverb and fake remix uploaders', () {
      expect(MusicApiService.isUnwantedJunkTrack('Unforgettable (Slowed + Reverb)', 'French Montana', 'Single'), isTrue);
      expect(MusicApiService.isUnwantedJunkTrack('Unforgettable Freestyle', 'Ombre2Choc Remix', 'Single'), isTrue);
      expect(MusicApiService.isUnwantedJunkTrack('PnB Rock Unforgettable Type Beat', 'BeatMaker', 'Single'), isTrue);
    });

    test('permits legitimate studio original tracks', () {
      expect(MusicApiService.isUnwantedJunkTrack('Unforgettable', 'PnB Rock', 'SWAG'), isFalse);
      expect(MusicApiService.isUnwantedJunkTrack('Yellow', 'Coldplay', 'Parachutes'), isFalse);
      expect(MusicApiService.isUnwantedJunkTrack('Location Unknown (feat. BEKA)', 'HONNE', 'Love Me'), isFalse);
    });

    test('permits instrumental tracks only if user explicitly searches for instrumental', () {
      expect(MusicApiService.isUnwantedJunkTrack('Interstellar Theme (Instrumental)', 'Hans Zimmer', 'Soundtrack', 'interstellar instrumental'), isFalse);
    });
  });

  group('Equalizer DSP & Headroom Compensation Tests', () {
    test('Equalizer initial cold-start initializes safely with default preset', () async {
      final eq = EqualizerService();
      await eq.initialized;

      expect(eq.isEnabled, isFalse);
      expect(eq.currentBands.length, 5);
      expect(eq.selectedPresetName, isNotEmpty);
      expect(eq.bassBoost, inInclusiveRange(0.0, 1.0));
      expect(eq.virtualizer, inInclusiveRange(0.0, 1.0));
    });

    test('Preamp headroom compensation protects against digital clipping (>0 dBFS)', () async {
      final eq = EqualizerService();
      await eq.initialized;

      // Reset to flat
      await eq.reset();
      expect(eq.preampCompensation, 0.0);

      // Select Bass Boost preset (+7.5dB max band, +0.65 bass boost)
      final bassBoostPreset = EqualizerPreset.defaultPresets.firstWhere((p) => p.name == 'Bass Boost');
      await eq.selectPreset(bassBoostPreset);

      // Preamp must be negative to attenuate positive boost and prevent clipping
      expect(eq.preampCompensation, lessThan(0.0));
    });

    test('Changing band levels dynamically re-calculates negative preamp', () async {
      final eq = EqualizerService();
      await eq.initialized;
      await eq.reset();

      // Boost 60Hz band to +8.0 dB
      await eq.setBandValue(0, 8.0);
      expect(eq.selectedPresetName, 'Kustom');
      expect(eq.currentBands[0], 8.0);
      expect(eq.preampCompensation, lessThanOrEqualTo(-8.0));
    });
  });

  group('Spotify Search History & Artwork Palette Tests', () {
    test('StorageService stores, deduplicates, removes, and clears recent searches', () async {
      final storage = StorageService();
      await storage.addRecentSearch(query: 'Tulus', title: 'Tulus', subtitle: 'Artis', type: 'artist');
      await storage.addRecentSearch(query: 'Komang', title: 'Komang', subtitle: 'Lagu • Raim Laode', type: 'track');
      await storage.addRecentSearch(query: 'Tulus', title: 'Tulus', subtitle: 'Artis', type: 'artist');

      final recents = await storage.getRecentSearches();
      expect(recents.length, 2);
      expect(recents.first['title'], 'Tulus');

      await storage.removeRecentSearch('Tulus', type: 'artist');
      final afterRemove = await storage.getRecentSearches();
      expect(afterRemove.length, 1);

      await storage.clearRecentSearches();
      expect(await storage.getRecentSearches(), isEmpty);
    });

    test('ArtworkPalette returns deterministic harmonious fallback colors', () {
      final c1 = ArtworkPalette.getCachedOrFallback('', seed: 'Yellow');
      final c2 = ArtworkPalette.getCachedOrFallback('', seed: 'Yellow');
      expect(c1.primary, equals(c2.primary));
      expect(c1.secondary, equals(c2.secondary));
      expect(c1.surfaceTint, equals(c2.surfaceTint));
    });
  });
}
