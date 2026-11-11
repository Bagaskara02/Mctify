enum AudioQuality {
  dataSaver(
    label: 'Hemat Kuota',
    bitrate: '64 kbps',
    description: 'Sangat hemat kuota, streaming cepat untuk sinyal lemah',
  ),
  standard(
    label: 'Standar',
    bitrate: '128 kbps',
    description: 'Keseimbangan ideal kualitas audio standar YouTube AAC',
  ),
  high(
    label: 'Kualitas Tinggi',
    bitrate: '160 kbps',
    description: 'Bitrate audio jernih standar streaming tinggi (Opus/AAC)',
  ),
  lossless(
    label: 'Hi-Res Lossless',
    bitrate: 'FLAC / Hi-Fi',
    description: 'Kualitas studio tertinggi 24-bit / Hi-Fi bebas kompresi agresif',
  );

  final String label;
  final String bitrate;
  final String description;

  const AudioQuality({
    required this.label,
    required this.bitrate,
    required this.description,
  });

  static AudioQuality fromString(String? val) {
    switch (val) {
      case 'dataSaver':
        return AudioQuality.dataSaver;
      case 'standard':
        return AudioQuality.standard;
      case 'lossless':
        return AudioQuality.lossless;
      case 'high':
      default:
        return AudioQuality.high;
    }
  }
}
