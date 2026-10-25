import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/equalizer_preset.dart';

class EqualizerService extends ChangeNotifier {
  static final EqualizerService instance = EqualizerService();
  static const MethodChannel _channel = MethodChannel('com.mcmusic.app/equalizer');

  static const String _keyEnabled = 'eq_enabled';
  static const String _keyPreset = 'eq_preset';
  static const String _keyBands = 'eq_bands';
  static const String _keyBassBoost = 'eq_bass_boost';
  static const String _keyVirtualizer = 'eq_virtualizer';
  static const String _keyLoudnessGain = 'eq_loudness_gain';

  bool _isEnabled = false;
  String _selectedPresetName = 'Datar (Flat)';
  List<double> _currentBands = [0.0, 0.0, 0.0, 0.0, 0.0];
  double _bassBoost = 0.0;
  double _virtualizer = 0.0;
  double _loudnessGain = 0.70; // Default +7.0 dB boost for car & Bluetooth audio

  bool get isEnabled => _isEnabled;
  String get selectedPresetName => _selectedPresetName;
  List<double> get currentBands => List.unmodifiable(_currentBands);
  double get bassBoost => _bassBoost;
  double get virtualizer => _virtualizer;
  double get loudnessGain => _loudnessGain;

  final Completer<void> _initCompleter = Completer<void>();
  Future<void> get initialized => _initCompleter.future;

  EqualizerService() {
    _loadSettings();
  }

  /// Headroom / Anti-Clipping Preamp Compensation (dB)
  /// Automatically attenuates input to prevent digital audio clipping (>0 dBFS)
  /// when boosting frequency bands or turning up bass boost.
  double get preampCompensation {
    double maxBoost = 0.0;
    for (final b in _currentBands) {
      if (b > maxBoost) maxBoost = b;
    }
    if (_bassBoost > 0) {
      maxBoost += (_bassBoost * 4.0);
    }
    return maxBoost > 0 ? -maxBoost : 0.0;
  }

  Future<void> _applyNativeSettings() async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('setEnabled', {'enabled': _isEnabled});
        await _channel.invokeMethod('setBands', {
          'bands': _currentBands,
          'preamp': preampCompensation,
          'enabled': _isEnabled,
        });
        await _channel.invokeMethod('setBassBoost', {'strength': _isEnabled ? _bassBoost : 0.0});
        await _channel.invokeMethod('setVirtualizer', {'strength': _isEnabled ? _virtualizer : 0.0});
        await _channel.invokeMethod('setLoudnessGain', {
          'gain': (_loudnessGain * 1000).round(),
          'enabled': _loudnessGain > 0,
        });
      }
    } catch (_) {}
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_keyEnabled) ?? false;
      _selectedPresetName = prefs.getString(_keyPreset) ?? 'Datar (Flat)';
      final bandsStr = prefs.getStringList(_keyBands);
      if (bandsStr != null && bandsStr.length == 5) {
        _currentBands = bandsStr.map((s) => double.tryParse(s) ?? 0.0).toList();
      } else {
        _currentBands = [0.0, 0.0, 0.0, 0.0, 0.0];
      }
      _bassBoost = prefs.getDouble(_keyBassBoost) ?? 0.0;
      _virtualizer = prefs.getDouble(_keyVirtualizer) ?? 0.0;
      _loudnessGain = prefs.getDouble(_keyLoudnessGain) ?? 0.70;
      notifyListeners();
      _applyNativeSettings();
    } catch (_) {} finally {
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    }
  }

  Future<void> toggleEnabled() async {
    _isEnabled = !_isEnabled;
    notifyListeners();
    _applyNativeSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _isEnabled);
  }

  Future<void> selectPreset(EqualizerPreset preset) async {
    _selectedPresetName = preset.name;
    _currentBands = List.from(preset.bands);
    notifyListeners();
    _applyNativeSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, preset.name);
    await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
  }

  Future<void> setBandValue(int index, double value) async {
    if (index >= 0 && index < _currentBands.length) {
      _currentBands[index] = value.clamp(-10.0, 10.0);
      _selectedPresetName = 'Kustom';
      notifyListeners();
      try {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && _isEnabled) {
          await _channel.invokeMethod('setBandLevel', {
            'band': index,
            'level': _currentBands[index],
            'preamp': preampCompensation,
          });
        }
      } catch (_) {}
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPreset, _selectedPresetName);
      await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
    }
  }

  Future<void> setBassBoost(double value) async {
    _bassBoost = value.clamp(0.0, 1.0);
    notifyListeners();
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && _isEnabled) {
        await _channel.invokeMethod('setBassBoost', {'strength': _bassBoost});
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBassBoost, _bassBoost);
  }

  Future<void> setVirtualizer(double value) async {
    _virtualizer = value.clamp(0.0, 1.0);
    notifyListeners();
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && _isEnabled) {
        await _channel.invokeMethod('setVirtualizer', {'strength': _virtualizer});
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVirtualizer, _virtualizer);
  }

  Future<void> setLoudnessGain(double value) async {
    _loudnessGain = value.clamp(0.0, 1.0);
    notifyListeners();
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod('setLoudnessGain', {
          'gain': (_loudnessGain * 1000).round(),
          'enabled': _loudnessGain > 0,
        });
      }
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyLoudnessGain, _loudnessGain);
  }

  Future<void> reset() async {
    final defaultPreset = EqualizerPreset.defaultPresets[0]; // Flat
    _isEnabled = true;
    _selectedPresetName = defaultPreset.name;
    _currentBands = List.from(defaultPreset.bands);
    _bassBoost = 0.0;
    _virtualizer = 0.0;
    _loudnessGain = 0.60;
    notifyListeners();
    _applyNativeSettings();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
    await prefs.setString(_keyPreset, _selectedPresetName);
    await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
    await prefs.setDouble(_keyBassBoost, 0.0);
    await prefs.setDouble(_keyVirtualizer, 0.0);
    await prefs.setDouble(_keyLoudnessGain, 0.60);
  }
}
