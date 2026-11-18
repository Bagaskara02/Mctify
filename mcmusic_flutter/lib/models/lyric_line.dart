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

  LyricLine copyWith({
    double? time,
    double? endTime,
    String? text,
    String? rawText,
    List<LyricWord>? words,
    bool? isInstrumental,
    bool? isInterlude,
    bool? isBackgroundVocal,
  }) {
    return LyricLine(
      time: time ?? this.time,
      endTime: endTime ?? this.endTime,
      text: text ?? this.text,
      rawText: rawText ?? this.rawText,
      words: words ?? this.words,
      isInstrumental: isInstrumental ?? this.isInstrumental,
      isInterlude: isInterlude ?? this.isInterlude,
      isBackgroundVocal: isBackgroundVocal ?? this.isBackgroundVocal,
    );
  }
}
