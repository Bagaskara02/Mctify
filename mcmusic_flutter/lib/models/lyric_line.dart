class LyricChar {
  final String char;
  final double startTime;
  final double endTime;
  final double duration;

  LyricChar({
    required this.char,
    required this.startTime,
    required this.endTime,
    required this.duration,
  });
}

class LyricWord {
  final String word;
  final double startTime;
  final double endTime;
  final double duration;
  final List<LyricChar> chars;

  LyricWord({
    required this.word,
    required this.startTime,
    required this.endTime,
    required this.duration,
    this.chars = const [],
  });
}

class LyricLine {
  final double time; // in seconds
  final double endTime;
  final String text;
  final String rawText;
  final List<LyricWord> words;
  final bool isInstrumental;
  final bool isInterlude;
  final bool isBackgroundVocal;

  LyricLine({
    required this.time,
    double? endTime,
    required this.text,
    this.rawText = '',
    this.words = const [],
    this.isInstrumental = false,
    this.isInterlude = false,
    this.isBackgroundVocal = false,
  }) : endTime = endTime ?? (time + 4.0);
}
