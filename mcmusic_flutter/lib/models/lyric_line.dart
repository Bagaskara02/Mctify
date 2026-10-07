class LyricWord {
  final String word;
  final double startTime;
  final double endTime;
  final double duration;

  LyricWord({
    required this.word,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });
}

class LyricLine {
  final double time; // in seconds
  final double endTime;
  final String text;
  final String rawText;
  final List<LyricWord> words;
  final bool isInstrumental;
  final bool isBackgroundVocal;

  LyricLine({
    required this.time,
    double? endTime,
    required this.text,
    this.rawText = '',
    this.words = const [],
    this.isInstrumental = false,
    this.isBackgroundVocal = false,
  }) : endTime = endTime ?? (time + 4.0);
}
