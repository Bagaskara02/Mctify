enum AudioQuality {
  dataSaver(
    label: 'Hemat Kuota',
    bitrate: '64 kbps',
    description: 'Sangat hemat kuota, streaming cepat untuk sinyal lemah',
  ),
  standard(
    label: 'Standar',
    bitrate: '128 kbps',
    description: 'Keseimbangan ideal antara kualitas audio dan pemakaian data',
  ),
  high(
    label: 'Kualitas Tinggi (HD)',
    bitrate: '256 - 320 kbps',
    description: 'Audio studio jernih resolusi penuh YouTube Music',
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
      case 'high':
      default:
        return AudioQuality.high;
    }
  }
}
