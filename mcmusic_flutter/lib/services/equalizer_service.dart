import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/equalizer_preset.dart';

class EqualizerService extends ChangeNotifier {
  static final EqualizerService instance = EqualizerService();

  static const String _keyEnabled = 'eq_enabled';
  static const String _keyPreset = 'eq_preset';
  static const String _keyBands = 'eq_bands';
  static const String _keyBassBoost = 'eq_bass_boost';
  static const String _keyVirtualizer = 'eq_virtualizer';

  bool _isEnabled = true;
  String _selectedPresetName = 'Bass Boost';
  List<double> _currentBands = [7.5, 4.5, 0.0, -1.0, -2.0];
  double _bassBoost = 0.65; // 0.0 to 1.0 (65%)
  double _virtualizer = 0.30; // 0.0 to 1.0 (30%)

  bool get isEnabled => _isEnabled;
  String get selectedPresetName => _selectedPresetName;
  List<double> get currentBands => List.unmodifiable(_currentBands);
  double get bassBoost => _bassBoost;
  double get virtualizer => _virtualizer;

  EqualizerService() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_keyEnabled) ?? true;
      _selectedPresetName = prefs.getString(_keyPreset) ?? 'Bass Boost';
      final bandsStr = prefs.getStringList(_keyBands);
      if (bandsStr != null && bandsStr.length == 5) {
        _currentBands = bandsStr.map((s) => double.tryParse(s) ?? 0.0).toList();
      }
      _bassBoost = prefs.getDouble(_keyBassBoost) ?? 0.65;
      _virtualizer = prefs.getDouble(_keyVirtualizer) ?? 0.30;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleEnabled() async {
    _isEnabled = !_isEnabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, _isEnabled);
  }

  Future<void> selectPreset(EqualizerPreset preset) async {
    _selectedPresetName = preset.name;
    _currentBands = List.from(preset.bands);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPreset, preset.name);
    await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
  }

  Future<void> setBandValue(int index, double value) async {
    if (index >= 0 && index < _currentBands.length) {
      _currentBands[index] = value.clamp(-10.0, 10.0);
      _selectedPresetName = 'Kustom';
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPreset, _selectedPresetName);
      await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
    }
  }

  Future<void> setBassBoost(double value) async {
    _bassBoost = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyBassBoost, _bassBoost);
  }

  Future<void> setVirtualizer(double value) async {
    _virtualizer = value.clamp(0.0, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keyVirtualizer, _virtualizer);
  }

  Future<void> reset() async {
    final defaultPreset = EqualizerPreset.defaultPresets[0]; // Flat
    _isEnabled = true;
    _selectedPresetName = defaultPreset.name;
    _currentBands = List.from(defaultPreset.bands);
    _bassBoost = 0.0;
    _virtualizer = 0.0;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, true);
    await prefs.setString(_keyPreset, _selectedPresetName);
    await prefs.setStringList(_keyBands, _currentBands.map((b) => b.toString()).toList());
    await prefs.setDouble(_keyBassBoost, 0.0);
    await prefs.setDouble(_keyVirtualizer, 0.0);
  }
}
