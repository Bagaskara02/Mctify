import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mcmusic_flutter/models/audio_quality.dart';
import 'package:mcmusic_flutter/models/equalizer_preset.dart';
import 'package:mcmusic_flutter/services/equalizer_service.dart';

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

  group('Equalizer DSP & Headroom Compensation Tests', () {
    test('Equalizer initial cold-start initializes safely with default preset', () async {
      final eq = EqualizerService();
      await eq.initialized;

      expect(eq.isEnabled, isTrue);
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
}
