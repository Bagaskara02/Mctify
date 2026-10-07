class EqualizerPreset {
  final String name;
  final List<double> bands; // 5 bands in dB (-10.0 to +10.0)

  const EqualizerPreset({
    required this.name,
    required this.bands,
  });

  static const List<EqualizerPreset> defaultPresets = [
    EqualizerPreset(name: 'Datar (Flat)', bands: [0.0, 0.0, 0.0, 0.0, 0.0]),
    EqualizerPreset(name: 'Bass Boost', bands: [7.5, 4.5, 0.0, -1.0, -2.0]),
    EqualizerPreset(name: 'Rock', bands: [4.5, 2.5, -1.5, 2.0, 4.0]),
    EqualizerPreset(name: 'Pop', bands: [-1.5, 2.0, 4.5, 2.5, -1.0]),
    EqualizerPreset(name: 'Jazz', bands: [3.5, 2.0, -1.5, 2.0, 3.5]),
    EqualizerPreset(name: 'Elektronik', bands: [5.5, 3.0, 0.0, 2.0, 4.5]),
    EqualizerPreset(name: 'Vokal Jernih', bands: [-2.0, 1.0, 4.0, 3.0, 1.0]),
    EqualizerPreset(name: 'Klasik', bands: [4.0, 2.5, -2.0, 3.0, 3.5]),
    EqualizerPreset(name: 'Akustik', bands: [3.5, 2.5, 1.0, 3.0, 2.5]),
  ];
}
