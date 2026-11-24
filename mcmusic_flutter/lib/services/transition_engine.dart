import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import '../models/audio_quality.dart';
import '../models/track.dart';
import 'audio_proxy_server.dart';
import 'music_api_service.dart';

/// Immutable or mutable configuration for a transition between two tracks.
class TransitionConfig {
  final bool enabled;
  final String bars; // '1 bar', '2 bars', '4 bars', '8 bars'
  final double durationSec;
  final String volumeMode; // 'overlap', 'crossfade', 'fade', 'rise_drop', 'cut'
  final String eqMode; // 'none', 'bass_swap', 'high_pass', 'smooth_blend'
  final String effectsMode; // 'high_pass', 'low_pass', 'echo_fade', 'reverb_tail', 'none'
  final bool syncTempo;
  final double outroOffsetSec;
  final double introOffsetSec;
  final int bpmA;
  final int bpmB;
  final String? pairKey;

  const TransitionConfig({
    this.enabled = true,
    this.bars = '2 bars',
    this.durationSec = 5.5,
    this.volumeMode = 'overlap',
    this.eqMode = 'none',
    this.effectsMode = 'high_pass',
    this.syncTempo = true,
    this.outroOffsetSec = 0.0,
    this.introOffsetSec = 0.0,
    this.bpmA = 120,
    this.bpmB = 120,
    this.pairKey,
  });

  TransitionConfig copyWith({
    bool? enabled,
    String? bars,
    double? durationSec,
    String? volumeMode,
    String? eqMode,
    String? effectsMode,
    bool? syncTempo,
    double? outroOffsetSec,
    double? introOffsetSec,
    int? bpmA,
    int? bpmB,
    String? pairKey,
  }) {
    return TransitionConfig(
      enabled: enabled ?? this.enabled,
      bars: bars ?? this.bars,
      durationSec: durationSec ?? this.durationSec,
      volumeMode: volumeMode ?? this.volumeMode,
      eqMode: eqMode ?? this.eqMode,
      effectsMode: effectsMode ?? this.effectsMode,
      syncTempo: syncTempo ?? this.syncTempo,
      outroOffsetSec: outroOffsetSec ?? this.outroOffsetSec,
      introOffsetSec: introOffsetSec ?? this.introOffsetSec,
      bpmA: bpmA ?? this.bpmA,
      bpmB: bpmB ?? this.bpmB,
      pairKey: pairKey ?? this.pairKey,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'bars': bars,
      'durationSec': durationSec,
      'volumeMode': volumeMode,
      'eqMode': eqMode,
      'effectsMode': effectsMode,
      'syncTempo': syncTempo,
      'outroOffsetSec': outroOffsetSec,
      'introOffsetSec': introOffsetSec,
      'bpmA': bpmA,
      'bpmB': bpmB,
      if (pairKey != null) 'pairKey': pairKey,
    };
  }

  factory TransitionConfig.fromJson(Map<String, dynamic> json) {
    return TransitionConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      bars: (json['bars'] as String?) ?? '2 bars',
      durationSec: (json['durationSec'] is num)
          ? (json['durationSec'] as num).toDouble().clamp(1.2, 24.0)
          : 5.5,
      volumeMode: (json['volumeMode'] as String?) ?? 'overlap',
      eqMode: (json['eqMode'] as String?) ?? 'none',
      effectsMode: (json['effectsMode'] as String?) ?? 'high_pass',
      syncTempo: json['syncTempo'] is bool ? json['syncTempo'] as bool : true,
      outroOffsetSec: (json['outroOffsetSec'] is num)
          ? (json['outroOffsetSec'] as num).toDouble().clamp(-15.0, 15.0)
          : 0.0,
      introOffsetSec: (json['introOffsetSec'] is num)
          ? (json['introOffsetSec'] as num).toDouble().clamp(0.0, 30.0)
          : 0.0,
      bpmA: (json['bpmA'] is num) ? (json['bpmA'] as num).round().clamp(55, 210) : 120,
      bpmB: (json['bpmB'] is num) ? (json['bpmB'] as num).round().clamp(55, 210) : 120,
      pairKey: json['pairKey'] as String?,
    );
  }
}

class TrackBpmAndKey {
  final int bpm;
  final String camelot;
  final String keyName;
  final double energy;

  const TrackBpmAndKey({
    required this.bpm,
    required this.camelot,
    required this.keyName,
    required this.energy,
  });
}

class CamelotCompatibility {
  final String tier; // 'perfect', 'harmonic', 'relative', 'energy_boost', 'clash'
  final int score; // 0..100
  final String label;
  final int colorValue;

  const CamelotCompatibility({
    required this.tier,
    required this.score,
    required this.label,
    required this.colorValue,
  });
}

class BarDurationStats {
  final int barCount;
  final int beats;
  final int avgBpm;
  final double foldedBpmB;
  final int bpmDelta;
  final double beatDurationSec;
  final double durationSec;

  const BarDurationStats({
    required this.barCount,
    required this.beats,
    required this.avgBpm,
    required this.foldedBpmB,
    required this.bpmDelta,
    required this.beatDurationSec,
    required this.durationSec,
  });
}

class TransitionEnvelope {
  final double progress;
  final double outGain;
  final double inGain;
  final double outHighpassHz;
  final double inHighpassHz;
  final double outLowpassHz;
  final double inLowpassHz;
  final double outLowDb;
  final double inLowDb;
  final double outMidDb;
  final double inMidDb;
  final double outEchoFeedback;
  final double outEchoWet;
  final double outPlaybackRate;
  final double inPlaybackRate;

  const TransitionEnvelope({
    required this.progress,
    required this.outGain,
    required this.inGain,
    required this.outHighpassHz,
    required this.inHighpassHz,
    required this.outLowpassHz,
    required this.inLowpassHz,
    required this.outLowDb,
    required this.inLowDb,
    required this.outMidDb,
    required this.inMidDb,
    required this.outEchoFeedback,
    required this.outEchoWet,
    required this.outPlaybackRate,
    required this.inPlaybackRate,
  });

  /// Effective perceptual deck A volume (0..1) factoring EQ & filter attenuation
  /// for dual-deck native players.
  double get effectiveOutVolume {
    double eqFactor = 1.0;
    if (outLowDb < -2.0) {
      eqFactor *= (1.0 + (outLowDb / 48.0)).clamp(0.72, 1.0);
    }
    if (outHighpassHz > 120.0) {
      final norm = ((outHighpassHz - 20.0) / 2200.0).clamp(0.0, 1.0);
      eqFactor *= (1.0 - norm * 0.24);
    }
    if (outLowpassHz < 16000.0) {
      final norm = ((20000.0 - outLowpassHz) / 19400.0).clamp(0.0, 1.0);
      eqFactor *= (1.0 - norm * 0.28);
    }
    // Echo/Reverb tail boost near cut/drop
    final tailBoost = outEchoWet > 0.08 ? (outEchoWet * 0.18 * (1.0 - progress * 0.5)) : 0.0;
    return ((outGain * eqFactor) + tailBoost).clamp(0.0, 1.0);
  }

  /// Effective perceptual deck B volume (0..1) factoring EQ & filter attenuation.
  double get effectiveInVolume {
    double eqFactor = 1.0;
    if (inLowDb < -2.0) {
      eqFactor *= (1.0 + (inLowDb / 48.0)).clamp(0.74, 1.0);
    }
    if (inHighpassHz > 120.0) {
      final norm = ((inHighpassHz - 20.0) / 1800.0).clamp(0.0, 1.0);
      eqFactor *= (1.0 - norm * 0.20);
    }
    return (inGain * eqFactor).clamp(0.0, 1.0);
  }
}

class SmartAutomixPreset {
  final TransitionConfig config;
  final TrackBpmAndKey metaA;
  final TrackBpmAndKey metaB;
  final CamelotCompatibility harmonic;
  final BarDurationStats barStats;
  final int compatibilityScore;
  final String summary;

  const SmartAutomixPreset({
    required this.config,
    required this.metaA,
    required this.metaB,
    required this.harmonic,
    required this.barStats,
    required this.compatibilityScore,
    required this.summary,
  });
}

class TransitionPresetOption {
  final String id;
  final String label;
  final String desc;
  final String badge;

  const TransitionPresetOption({
    required this.id,
    required this.label,
    required this.desc,
    required this.badge,
  });
}

/// Core DSP, Beat/Bar, Camelot Wheel & Smart Automix Engine for Mobile (Android & iOS).
/// Ported 1:1 from Web `src/services/transitionEngine.js`.
class TransitionEngine {
  static const List<TransitionPresetOption> volumePresets = [
    TransitionPresetOption(
      id: 'mashup',
      label: 'Mashup Blend',
      desc: 'Style Spotify Mix: energi penuh di kedua deck dengan Hard Bass Swap di bar tengah & Pink S-Curve Filter',
      badge: 'Spotify Mix',
    ),
    TransitionPresetOption(
      id: 'overlap',
      label: 'Overlap',
      desc: 'Lagu baru masuk penuh sementara lagu lama tetap utuh hingga paruh bar lalu turun halus',
      badge: 'Spotify Default',
    ),
    TransitionPresetOption(
      id: 'crossfade',
      label: 'Crossfade',
      desc: 'Kurva Equal-Power (cos/sin) menjaga energi desibel konstan di titik tengah',
      badge: 'Equal Power',
    ),
    TransitionPresetOption(
      id: 'fade',
      label: 'Fade',
      desc: 'Lagu lama meredup dramatis sebelum lagu baru naik perlahan (breath gap tipis)',
      badge: 'Dramatic',
    ),
    TransitionPresetOption(
      id: 'rise_drop',
      label: 'Rise & Drop',
      desc: 'Lagu baru membangun tensi (build-up) lalu lagu lama memotong tepat di drop bar',
      badge: 'Club Drop',
    ),
    TransitionPresetOption(
      id: 'cut',
      label: 'Beat Cut',
      desc: 'Transisi potong cepat presisi pada ketukan downbeat terakhir',
      badge: 'Hard Cut',
    ),
  ];

  static const List<TransitionPresetOption> eqPresets = [
    TransitionPresetOption(
      id: 'none',
      label: 'None',
      desc: 'Frekuensi penuh kedua lagu tanpa pemotongan EQ',
      badge: 'Flat',
    ),
    TransitionPresetOption(
      id: 'bass_swap',
      label: 'Bass Swap',
      desc: 'Tukar frekuensi sub-bass (<180Hz) di tengah bar agar kick drum tidak bertabrakan',
      badge: 'Pro DJ',
    ),
    TransitionPresetOption(
      id: 'high_pass',
      label: 'Low Cut Fade',
      desc: 'Pangkas low-end lagu baru saat masuk lalu kembalikan bass penuh saat drop',
      badge: 'Clean Intro',
    ),
    TransitionPresetOption(
      id: 'smooth_blend',
      label: 'Warm Mid Blend',
      desc: 'Redam sedikit vokal/midrange saat kedua lagu bertumpuk agar vokal tidak bentrok',
      badge: 'Vocal Safe',
    ),
  ];

  static const List<TransitionPresetOption> effectPresets = [
    TransitionPresetOption(
      id: 'high_pass',
      label: 'High-pass',
      desc: 'Sapuan filter High-Pass (20Hz -> 2.2kHz) menyapu lagu lama ke atas seperti efek mixer DJ',
      badge: 'HPF Sweep',
    ),
    TransitionPresetOption(
      id: 'low_pass',
      label: 'Low-pass',
      desc: 'Sapuan filter Low-Pass (20kHz -> 420Hz) meredam treble lagu lama seperti di balik dinding',
      badge: 'LPF Underwater',
    ),
    TransitionPresetOption(
      id: 'echo_fade',
      label: 'Echo Out',
      desc: 'Pantulan delay sinkron-tempo (1/2 beat) membiarkan ekor lagu lama menggema saat menghilang',
      badge: 'Beat Delay',
    ),
    TransitionPresetOption(
      id: 'reverb_tail',
      label: 'Space Wash',
      desc: 'Atmosfer stereo shimmer + filter lembut pada ekor lagu yang keluar',
      badge: 'Atmospheric',
    ),
    TransitionPresetOption(
      id: 'none',
      label: 'None',
      desc: 'Tanpa sapuan efek filter maupun delay tambahan',
      badge: 'Dry',
    ),
  ];

  static const List<String> barOptions = ['1 bar', '2 bars', '4 bars', '8 bars'];

  static const List<({int bpm, String camelot, String keyName, double energy})> _camelotProfiles = [
    (bpm: 118, camelot: '4B', keyName: 'Ab Major', energy: 0.78),
    (bpm: 115, camelot: '4B', keyName: 'Ab Major', energy: 0.74),
    (bpm: 120, camelot: '5B', keyName: 'Eb Major', energy: 0.80),
    (bpm: 122, camelot: '8A', keyName: 'A Minor', energy: 0.82),
    (bpm: 124, camelot: '8B', keyName: 'C Major', energy: 0.85),
    (bpm: 126, camelot: '9A', keyName: 'E Minor', energy: 0.87),
    (bpm: 128, camelot: '11B', keyName: 'A Major', energy: 0.91),
    (bpm: 105, camelot: '6A', keyName: 'G Minor', energy: 0.68),
    (bpm: 98, camelot: '7B', keyName: 'F Major', energy: 0.62),
    (bpm: 92, camelot: '2A', keyName: 'Eb Minor', energy: 0.58),
    (bpm: 110, camelot: '10B', keyName: 'D Major', energy: 0.72),
    (bpm: 132, camelot: '1A', keyName: 'Ab Minor', energy: 0.89),
    (bpm: 86, camelot: '3B', keyName: 'Db Major', energy: 0.55),
    (bpm: 116, camelot: '5A', keyName: 'C Minor', energy: 0.76),
    (bpm: 125, camelot: '6B', keyName: 'Bb Major', energy: 0.84),
    (bpm: 108, camelot: '12A', keyName: 'Db Minor', energy: 0.70),
  ];

  static final List<({RegExp match, int bpm, String camelot, String keyName, double energy})> _curatedSignatures = [
    (match: RegExp(r'keep you safe|new west', caseSensitive: false), bpm: 118, camelot: '4B', keyName: 'Ab Major', energy: 0.74),
    (match: RegExp(r'fall in love alone|stacey ryan', caseSensitive: false), bpm: 115, camelot: '4B', keyName: 'Ab Major', energy: 0.76),
    (match: RegExp(r'muria|brangkat', caseSensitive: false), bpm: 126, camelot: '8A', keyName: 'A Minor', energy: 0.86),
    (match: RegExp(r'perfect|ed sheeran', caseSensitive: false), bpm: 95, camelot: '4B', keyName: 'Ab Major', energy: 0.60),
    (match: RegExp(r'blinding lights|weeknd', caseSensitive: false), bpm: 171, camelot: '5A', keyName: 'F Minor', energy: 0.92),
    (match: RegExp(r'starboy', caseSensitive: false), bpm: 93, camelot: '7A', keyName: 'D Minor', energy: 0.77),
    (match: RegExp(r'die with a smile|bruno', caseSensitive: false), bpm: 158, camelot: '11B', keyName: 'A Major', energy: 0.79),
    (match: RegExp(r'birds of a feather|billie', caseSensitive: false), bpm: 105, camelot: '10B', keyName: 'D Major', energy: 0.75),
    (match: RegExp(r'espresso|sabrina', caseSensitive: false), bpm: 104, camelot: '8A', keyName: 'A Minor', energy: 0.81),
    (match: RegExp(r'cruel summer|taylor', caseSensitive: false), bpm: 170, camelot: '11B', keyName: 'A Major', energy: 0.88),
    (match: RegExp(r'as it was|harry styles', caseSensitive: false), bpm: 174, camelot: '11A', keyName: 'F# Minor', energy: 0.86),
    (match: RegExp(r'sial|mahalini', caseSensitive: false), bpm: 120, camelot: '8B', keyName: 'C Major', energy: 0.68),
    (match: RegExp(r'komang|raim laode', caseSensitive: false), bpm: 134, camelot: '9B', keyName: 'G Major', energy: 0.66),
    (match: RegExp(r'hati-hati di jalan|tulus', caseSensitive: false), bpm: 73, camelot: '7B', keyName: 'F Major', energy: 0.56),
    (match: RegExp(r'gala bunga matahari|sal priadi', caseSensitive: false), bpm: 112, camelot: '6B', keyName: 'Bb Major', energy: 0.65),
    (match: RegExp(r'untungnya|bernadya', caseSensitive: false), bpm: 108, camelot: '8B', keyName: 'C Major', energy: 0.64),
    (match: RegExp(r"ain'?t in la|ad[eé]la", caseSensitive: false), bpm: 139, camelot: '12B', keyName: 'E Major', energy: 0.88),
    (match: RegExp(r'close to me|ellie goulding|diplo', caseSensitive: false), bpm: 72, camelot: '12B', keyName: 'E Major', energy: 0.85),
  ];

  /// Computes deterministic BPM, Camelot key (`1A-12B`), musical key name, and energy for a [Track].
  static TrackBpmAndKey computeTrackBpmAndKey(Track? track) {
    if (track == null) {
      return const TrackBpmAndKey(
        bpm: 120,
        camelot: '4B',
        keyName: 'Ab Major',
        energy: 0.75,
      );
    }

    final combined = '${track.title} ${track.artist}'.trim();
    for (final item in _curatedSignatures) {
      if (item.match.hasMatch(combined)) {
        return TrackBpmAndKey(
          bpm: item.bpm,
          camelot: item.camelot,
          keyName: item.keyName,
          energy: item.energy,
        );
      }
    }

    final seedStr = '${track.id}-${track.title}-${track.artist}';
    int hash = 2166136261;
    for (int i = 0; i < seedStr.length; i++) {
      hash ^= seedStr.codeUnitAt(i);
      hash = (hash * 16777619) & 0x7fffffff;
    }

    final base = _camelotProfiles[hash % _camelotProfiles.length];
    final jitter = ((hash >> 4) % 7) - 3;
    final bpm = (base.bpm + jitter).clamp(72, 176);
    return TrackBpmAndKey(
      bpm: bpm,
      camelot: base.camelot,
      keyName: base.keyName,
      energy: base.energy,
    );
  }

  static ({int num, String letter})? _parseCamelot(String code) {
    final m = RegExp(r'^(\d{1,2})([AB])$', caseSensitive: false).firstMatch(code.trim());
    if (m == null) return null;
    return (num: int.parse(m.group(1)!), letter: m.group(2)!.toUpperCase());
  }

  /// Evaluates Camelot wheel harmonic distance between two tracks (`1A-12B`).
  static CamelotCompatibility computeCamelotCompatibility(String? camelotA, String? camelotB) {
    final a = _parseCamelot(camelotA ?? '');
    final b = _parseCamelot(camelotB ?? '');
    if (a == null || b == null) {
      return const CamelotCompatibility(
        tier: 'neutral',
        score: 75,
        label: 'Harmonic Match',
        colorValue: 0xFF38BDF8,
      );
    }

    final rawDiff = (a.num - b.num).abs();
    final wheelDist = math.min(rawDiff, 12 - rawDiff);

    if (wheelDist == 0 && a.letter == b.letter) {
      return const CamelotCompatibility(
        tier: 'perfect',
        score: 99,
        label: 'Perfect Key Match',
        colorValue: 0xFF1ED760,
      );
    }
    if (wheelDist == 0 && a.letter != b.letter) {
      return const CamelotCompatibility(
        tier: 'relative',
        score: 94,
        label: 'Relative Major/Minor',
        colorValue: 0xFF22D3EE,
      );
    }
    if (wheelDist == 1 && a.letter == b.letter) {
      return const CamelotCompatibility(
        tier: 'harmonic',
        score: 92,
        label: 'Harmonic Fifths (±1)',
        colorValue: 0xFF38BDF8,
      );
    }
    if (wheelDist == 2 && a.letter == b.letter) {
      return const CamelotCompatibility(
        tier: 'energy_boost',
        score: 82,
        label: 'Energy Boost (±2)',
        colorValue: 0xFFA855F7,
      );
    }
    if (wheelDist == 1 && a.letter != b.letter) {
      return const CamelotCompatibility(
        tier: 'diagonal',
        score: 78,
        label: 'Diagonal Key Shift',
        colorValue: 0xFFF59E0B,
      );
    }
    return const CamelotCompatibility(
      tier: 'clash',
      score: 60,
      label: 'Cross-Key Contrast',
      colorValue: 0xFFFB7185,
    );
  }

  /// Converts a bar label (`1 bar`, `2 bars`, `4 bars`, `8 bars`) and BPM pair
  /// into exact musical 4/4 duration in seconds (with half/double-time folding).
  static BarDurationStats computeBarDurationSec(num bpmA, num bpmB, String barsLabel) {
    final match = RegExp(r'(\d+)').firstMatch(barsLabel);
    final barCount = match != null ? int.parse(match.group(1)!).clamp(1, 16) : 2;
    final cleanA = bpmA.toDouble().isFinite && bpmA > 40 ? bpmA.toDouble() : 120.0;
    final rawB = bpmB.toDouble().isFinite && bpmB > 40 ? bpmB.toDouble() : cleanA;

    double foldedB = rawB;
    if ((rawB * 2.0 - cleanA).abs() < (rawB - cleanA).abs()) {
      foldedB = rawB * 2.0;
    } else if ((rawB / 2.0 - cleanA).abs() < (rawB - cleanA).abs()) {
      foldedB = rawB / 2.0;
    }

    final avgBpm = ((cleanA + foldedB) / 2.0).clamp(60.0, 200.0);
    final beats = barCount * 4;
    final beatDurationSec = 60.0 / avgBpm;
    final rawSec = beats * beatDurationSec;
    final durationSec = ((rawSec * 10.0).round() / 10.0).clamp(1.2, 22.0);

    return BarDurationStats(
      barCount: barCount,
      beats: beats,
      avgBpm: avgBpm.round(),
      foldedBpmB: (foldedB * 10.0).round() / 10.0,
      bpmDelta: (cleanA - foldedB).abs().round(),
      beatDurationSec: (beatDurationSec * 1000.0).round() / 1000.0,
      durationSec: durationSec,
    );
  }

  /// Evaluates instantaneous DSP gains, filter cutoffs, EQ gains, delay parameters,
  /// and tempo-sync playback rates at normalized transition progress `p` in `[0..1]`.
  static TransitionEnvelope evaluateTransitionEnvelope(double progress, TransitionConfig config) {
    final p = progress.clamp(0.0, 1.0);
    final volumeMode = config.volumeMode;
    final eqMode = config.eqMode;
    final effectsMode = config.effectsMode;
    final syncTempo = config.syncTempo;
    final bpmA = config.bpmA.toDouble().clamp(60.0, 200.0);
    final rawBpmB = config.bpmB.toDouble().clamp(60.0, 200.0);

    double bpmB = rawBpmB;
    if ((rawBpmB * 2.0 - bpmA).abs() < (rawBpmB - bpmA).abs()) bpmB = rawBpmB * 2.0;
    if ((rawBpmB / 2.0 - bpmA).abs() < (rawBpmB - bpmA).abs()) bpmB = rawBpmB / 2.0;

    // 1. Volume Gain Curves (0.0 .. 1.0)
    double outGain = 1.0;
    double inGain = 0.0;

    switch (volumeMode) {
      case 'mashup':
        outGain = p < 0.95 ? 1.0 : math.cos(((p - 0.95) / 0.05) * (math.pi / 2.0));
        inGain = 1.0;
        break;
      case 'overlap':
        outGain = p < 0.45 ? 1.0 : math.cos(((p - 0.45) / 0.55) * (math.pi / 2.0));
        inGain = p < 0.65 ? math.sin((p / 0.65) * (math.pi / 2.0)) : 1.0;
        break;
      case 'crossfade':
        outGain = math.cos(p * (math.pi / 2.0));
        inGain = math.sin(p * (math.pi / 2.0));
        break;
      case 'fade':
        outGain = p < 0.58 ? math.pow(1.0 - p / 0.58, 1.45).toDouble() : 0.0;
        inGain = p < 0.36 ? 0.0 : math.pow((p - 0.36) / 0.64, 1.25).toDouble();
        break;
      case 'rise_drop':
        outGain = p < 0.78 ? 1.0 - p * 0.12 : math.max(0.0, 1.0 - (p - 0.78) / 0.22);
        inGain = p < 0.75
            ? 0.2 + 0.55 * math.pow(p / 0.75, 1.4).toDouble()
            : math.min(1.0, 0.75 + ((p - 0.75) / 0.25) * 0.25);
        break;
      case 'cut':
        outGain = p < 0.50 ? 1.0 : math.max(0.0, 1.0 - (p - 0.50) / 0.08);
        inGain = p < 0.46 ? 0.0 : math.min(1.0, (p - 0.46) / 0.08);
        break;
      default:
        outGain = math.cos(p * (math.pi / 2.0));
        inGain = math.sin(p * (math.pi / 2.0));
    }

    outGain = outGain.clamp(0.0, 1.0);
    inGain = inGain.clamp(0.0, 1.0);

    // 2. EQ & Filter Frequencies / Gains
    double outHighpassHz = 20.0;
    double inHighpassHz = 20.0;
    double outLowpassHz = 20000.0;
    const double inLowpassHz = 20000.0;
    double outLowDb = 0.0;
    double inLowDb = 0.0;
    double outMidDb = 0.0;
    double inMidDb = 0.0;

    if (volumeMode == 'mashup') {
      if (p < 0.49) {
        outLowDb = 0.0;
        inLowDb = -20.0;
        inMidDb = -1.5;
      } else if (p <= 0.51) {
        final swapP = (p - 0.49) / 0.02;
        outLowDb = -20.0 * swapP;
        inLowDb = -20.0 + 21.5 * swapP;
        outMidDb = -4.5 * swapP;
      } else {
        outLowDb = -20.0;
        inLowDb = 1.5;
        outMidDb = -5.5;
      }
    } else if (eqMode == 'bass_swap') {
      if (p < 0.48) {
        outLowDb = 0.0;
        inLowDb = -16.0 * (1.0 - (p / 0.48) * 0.25);
        inHighpassHz = 185.0 - p * 110.0;
      } else {
        final swapP = ((p - 0.48) / 0.52).clamp(0.0, 1.0);
        outLowDb = -18.0 * swapP;
        inLowDb = -12.0 * (1.0 - swapP);
        outHighpassHz = math.max(outHighpassHz, 20.0 + swapP * 210.0);
        inHighpassHz = 20.0 + (1.0 - swapP) * 110.0;
      }
    } else if (eqMode == 'high_pass') {
      inHighpassHz = 420.0 * math.pow(1.0 - p, 1.6).toDouble() + 20.0;
      inLowDb = -10.0 * (1.0 - p);
    } else if (eqMode == 'smooth_blend') {
      final overlapIntensity = math.sin(p * math.pi);
      outMidDb = -4.5 * overlapIntensity;
      inMidDb = -3.5 * overlapIntensity;
      inLowDb = -6.0 * (1.0 - p);
    }

    // 3. Effects Sweep
    double outEchoFeedback = 0.0;
    double outEchoWet = 0.0;

    if (effectsMode == 'high_pass') {
      final sweep = 20.0 * math.pow(110.0, math.pow(p, 1.25).toDouble()).toDouble();
      outHighpassHz = math.max(outHighpassHz, math.min(2400.0, sweep));
    } else if (effectsMode == 'low_pass') {
      final sweep = 20000.0 * math.pow(0.022, math.pow(p, 1.15).toDouble()).toDouble();
      outLowpassHz = math.max(380.0, sweep);
    } else if (effectsMode == 'echo_fade') {
      outEchoFeedback = (0.18 + p * 0.38).clamp(0.0, 0.58);
      outEchoWet = math.sin(p * math.pi * 0.85) * 0.55;
      outHighpassHz = math.max(outHighpassHz, 20.0 + p * 360.0);
    } else if (effectsMode == 'reverb_tail') {
      outEchoFeedback = (0.25 + p * 0.42).clamp(0.0, 0.65);
      outEchoWet = math.sin(p * math.pi * 0.9) * 0.45;
      outLowpassHz = math.min(outLowpassHz, 20000.0 - p * 11500.0);
      outHighpassHz = math.max(outHighpassHz, 20.0 + p * 260.0);
    }

    // 4. Tempo Sync Playback Rate
    double outPlaybackRate = 1.0;
    double inPlaybackRate = 1.0;
    if (syncTempo && bpmA > 0 && bpmB > 0) {
      final targetBpm = bpmA + (bpmB - bpmA) * p;
      outPlaybackRate = (targetBpm / bpmA).clamp(0.92, 1.08);
      inPlaybackRate = (targetBpm / bpmB).clamp(0.92, 1.08);
    }

    return TransitionEnvelope(
      progress: p,
      outGain: outGain,
      inGain: inGain,
      outHighpassHz: outHighpassHz.roundToDouble(),
      inHighpassHz: inHighpassHz.roundToDouble(),
      outLowpassHz: outLowpassHz.roundToDouble(),
      inLowpassHz: inLowpassHz,
      outLowDb: outLowDb,
      inLowDb: inLowDb,
      outMidDb: outMidDb,
      inMidDb: inMidDb,
      outEchoFeedback: outEchoFeedback,
      outEchoWet: outEchoWet,
      outPlaybackRate: outPlaybackRate,
      inPlaybackRate: inPlaybackRate,
    );
  }

  /// Generates an intelligent Smart Automix recommendation tailored to two tracks.
  static SmartAutomixPreset computeSmartAutomixPreset(Track? outgoingTrack, Track? incomingTrack) {
    final metaA = computeTrackBpmAndKey(outgoingTrack);
    final metaB = computeTrackBpmAndKey(incomingTrack);
    final harmonic = computeCamelotCompatibility(metaA.camelot, metaB.camelot);
    final initialStats = computeBarDurationSec(metaA.bpm, metaB.bpm, '2 bars');
    final bpmDelta = initialStats.bpmDelta;

    // Specific Curated Blueprint: ADÉLA - Ain't In LA ➔ Ellie Goulding - Close To Me (TikTok Spotify Mix)
    final titleA = (outgoingTrack?.title ?? '').toLowerCase();
    final titleB = (incomingTrack?.title ?? '').toLowerCase();
    final isAintInLaToCloseToMe =
        (titleA.contains("ain't in la") && titleB.contains('close to me')) ||
        (titleA.contains('close to me') && titleB.contains("ain't in la"));

    if (isAintInLaToCloseToMe) {
      final barStats = computeBarDurationSec(metaA.bpm, metaB.bpm, '16 bars');
      final config = TransitionConfig(
        enabled: true,
        bars: '16 bars',
        durationSec: barStats.durationSec,
        volumeMode: 'mashup',
        eqMode: 'bass_swap',
        effectsMode: 'high_pass',
        syncTempo: true,
        outroOffsetSec: 0.0,
        introOffsetSec: 35.0, // starts at 0:35 on Close To Me chorus drop until 1:03
        bpmA: metaA.bpm,
        bpmB: metaB.bpm,
      );
      return SmartAutomixPreset(
        config: config,
        metaA: metaA,
        metaB: metaB,
        compatibilityScore: 99,
        explanation: 'Spotify Mix Blueprint (TikTok Reference): ADÉLA (139 BPM, 12B) ➔ Ellie Goulding/Diplo (72/144 BPM, 12B). 16 Bars Mashup: Ain\'t In LA mulai di 2:34, Close To Me mulai di 0:35 sampai 1:03. Full volume energi mashup tanpa fade, Bass Swap di Bar 8➔9, dan Pink S-Curve HPF.',
        bars: '16 bars',
        volumeMode: 'mashup',
        eqMode: 'bass_swap',
        effectsMode: 'high_pass',
      );
    }

    String bars = '2 bars';
    String volumeMode = 'overlap';
    String eqMode = 'bass_swap';
    String effectsMode = 'high_pass';
    bool syncTempo = true;

    if (bpmDelta <= 4 && harmonic.score >= 90) {
      bars = '8 bars';
      volumeMode = 'mashup';
      eqMode = 'bass_swap';
      effectsMode = 'high_pass';
      syncTempo = true;
    } else if (bpmDelta <= 10 && harmonic.score >= 78) {
      bars = '4 bars';
      volumeMode = 'mashup';
      eqMode = 'bass_swap';
      effectsMode = 'high_pass';
      syncTempo = true;
    } else if (bpmDelta <= 18) {
      bars = '2 bars';
      volumeMode = 'rise_drop';
      eqMode = 'high_pass';
      effectsMode = 'echo_fade';
      syncTempo = false;
    } else {
      bars = '1 bar';
      volumeMode = 'fade';
      eqMode = 'smooth_blend';
      effectsMode = 'reverb_tail';
      syncTempo = false;
    }

    final barStats = computeBarDurationSec(metaA.bpm, metaB.bpm, bars);
    final bpmScore = (100 - bpmDelta * 2.4).round().clamp(45, 100);
    final compatibilityScore = (harmonic.score * 0.55 + bpmScore * 0.45).round().clamp(52, 99);

    final config = TransitionConfig(
      enabled: true,
      bars: bars,
      durationSec: barStats.durationSec,
      volumeMode: volumeMode,
      eqMode: eqMode,
      effectsMode: effectsMode,
      syncTempo: syncTempo,
      outroOffsetSec: 0.0,
      introOffsetSec: 0.0,
      bpmA: metaA.bpm,
      bpmB: metaB.bpm,
    );

    return SmartAutomixPreset(
      config: config,
      metaA: metaA,
      metaB: metaB,
      harmonic: harmonic,
      barStats: barStats,
      compatibilityScore: compatibilityScore,
      summary: '${harmonic.label} • Δ$bpmDelta BPM -> $bars (${barStats.durationSec.toStringAsFixed(1)}s)',
    );
  }

  /// Generates 60 deterministic, beat-accented waveform bar amplitudes (`0.14..0.98`)
  /// matching the musical structure of an outgoing outro or incoming intro.
  static List<double> generateMusicalWaveformBars(
    Track? track, {
    int count = 60,
    String role = 'outgoing',
  }) {
    final seedStr = '${track?.id ?? 'track'}-${track?.title ?? 'song'}-$role';
    int h = 1779033703 ^ seedStr.length;
    for (int i = 0; i < seedStr.length; i++) {
      h = ((h ^ seedStr.codeUnitAt(i)) * 3432918353) & 0x7fffffff;
      h = ((h << 13) | (h >> 19)) & 0x7fffffff;
    }

    return List<double>.generate(count, (idx) {
      h = ((h ^ (idx * 2654435761)) * 2246822507) & 0x7fffffff;
      final rand = (h % 1000) / 1000.0;
      final isDownbeat = (idx % 4) == 0;
      final isHalfBeat = (idx % 2) == 0;
      final beatAccent = isDownbeat ? 0.24 : (isHalfBeat ? 0.11 : 0.0);

      double structuralEnvelope = 0.72;
      if (role == 'outgoing') {
        if (idx > count * 0.72) {
          final tailP = (idx - count * 0.72) / (count * 0.28);
          structuralEnvelope = 0.78 - tailP * 0.42;
        }
      } else {
        if (idx < count * 0.25) {
          final introP = idx / (count * 0.25);
          structuralEnvelope = 0.35 + introP * 0.45;
        }
      }

      return (structuralEnvelope * (0.48 + rand * 0.52) + beatAccent).clamp(0.14, 0.98);
    });
  }
}

/// Callback signature for live audition telemetry updates inside SpotifyTransitionModal.
typedef AuditionTickCallback = void Function({
  required double progress, // 0..1 across entire audition window
  required double mixProgress, // 0..1 inside the overlap transition window
  required String phase, // 'lead_in', 'transition', 'lead_out'
  required TransitionEnvelope envelope,
});

/// Real Dual-Deck Native Audio Audition Mixer for the Spotify "Edit transition BETA" Studio Modal.
/// Uses two `just_audio` [ja.AudioPlayer] decks to play the outgoing track's outro and the incoming
/// track's intro simultaneously with real-time volume envelope, tempo-sync playback speed,
/// and live scrubbing.
class TransitionAuditionMixer {
  final MusicApiService _apiService = MusicApiService();

  static ja.AudioPlayer _createAuditionDeck() {
    return ja.AudioPlayer(
      handleInterruptions: false,
      audioLoadConfiguration: const ja.AudioLoadConfiguration(
        androidLoadControl: ja.AndroidLoadControl(
          minBufferDuration: Duration(seconds: 10),
          maxBufferDuration: Duration(seconds: 25),
          bufferForPlaybackDuration: Duration(milliseconds: 200),
          bufferForPlaybackAfterRebufferDuration: Duration(milliseconds: 300),
          backBufferDuration: Duration(seconds: 30),
        ),
        darwinLoadControl: ja.DarwinLoadControl(
          automaticallyWaitsToMinimizeStalling: false,
          preferredForwardBufferDuration: Duration(seconds: 15),
        ),
      ),
    );
  }

  final ja.AudioPlayer _deckA = _createAuditionDeck();
  final ja.AudioPlayer _deckB = _createAuditionDeck();

  Track? _outgoingTrack;
  Track? _incomingTrack;
  String? _loadedKeyA;
  String? _loadedKeyB;
  Duration _durA = const Duration(seconds: 180);
  Duration _durB = const Duration(seconds: 180);

  bool _isPlaying = false;
  bool _isLoading = false;
  bool _disposed = false;
  Future<bool>? _preloadFuture;

  TransitionConfig _config = const TransitionConfig();
  Timer? _tickTimer;

  static const double _leadInSec = 1.5;
  static const double _leadOutSec = 1.5;

  double _elapsedSec = 0.0;
  DateTime? _lastTickAt;
  bool _deckBStarted = false;
  double _lastVolA = -1.0;
  double _lastVolB = -1.0;

  AuditionTickCallback? onTick;
  VoidCallback? onComplete;
  VoidCallback? onStateChanged;

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;

  double get _totalAuditionSec =>
      _leadInSec + _config.durationSec.clamp(1.2, 22.0) + _leadOutSec;

  int get _outroStartMs {
    final totalMs = _durA.inMilliseconds > 15000
        ? _durA.inMilliseconds
        : ((_outgoingTrack?.duration ?? 180) * 1000);
    final transMs = (_config.durationSec * 1000).round();
    final offsetMs = (_config.outroOffsetSec * 1000).round();
    final startMs = totalMs - transMs - (_leadInSec * 1000).round() - 3500 + offsetMs;
    return startMs.clamp(0, math.max(0, totalMs - transMs - 2000));
  }

  int get _introStartMs {
    final totalMs = _durB.inMilliseconds > 15000
        ? _durB.inMilliseconds
        : ((_incomingTrack?.duration ?? 180) * 1000);
    final offsetMs = (_config.introOffsetSec.clamp(0.0, 30.0) * 1000).round();
    return offsetMs.clamp(0, math.max(0, totalMs - 10000));
  }

  /// Pre-loads both decks silently in the background as soon as the studio modal opens
  /// or when a track is changed, so tapping Play starts immediately without waiting.
  Future<bool> preloadDecks({
    required Track outgoing,
    required Track incoming,
    TransitionConfig? config,
  }) {
    if (config != null) _config = config;
    final keyA = '${outgoing.id}_${outgoing.videoId ?? outgoing.title}';
    final keyB = '${incoming.id}_${incoming.videoId ?? incoming.title}';
    if (_loadedKeyA == keyA && _loadedKeyB == keyB) {
      return Future.value(true);
    }
    if (_preloadFuture != null) return _preloadFuture!;
    final fut = _ensureDecksLoaded(outgoing, incoming);
    _preloadFuture = fut;
    fut.whenComplete(() => _preloadFuture = null);
    return fut;
  }

  Future<bool> _ensureDecksLoaded(Track outgoing, Track incoming) async {
    _outgoingTrack = outgoing;
    _incomingTrack = incoming;
    final keyA = '${outgoing.id}_${outgoing.videoId ?? outgoing.title}';
    final keyB = '${incoming.id}_${incoming.videoId ?? incoming.title}';

    if (_loadedKeyA == keyA && _loadedKeyB == keyB) {
      return true;
    }

    _isLoading = true;
    onStateChanged?.call();

    try {
      await AudioProxyServer.instance.verifyOrRestartServer();
      final results = await Future.wait<String?>([
        _resolveAuditionStream(outgoing),
        _resolveAuditionStream(incoming),
      ]);
      if (_disposed) return false;

      final urlA = results[0];
      final urlB = results[1];

      // Pre-warm RAM chunks for Deck A outro (~85% mark) and Deck B intro (head chunks 0 & 1)
      // so neither iOS AVPlayer nor Android ExoPlayer stalls waiting on network range reads!
      final prewarmTasks = <Future<void>>[];
      if (urlA != null && urlA.isNotEmpty) {
        final proxyIdA = Uri.tryParse(urlA)?.queryParameters['id'];
        if (proxyIdA != null && proxyIdA.isNotEmpty) {
          prewarmTasks.add(AudioProxyServer.instance.prewarmAtFraction(proxyIdA, 0.84));
        }
      }
      if (urlB != null && urlB.isNotEmpty) {
        final proxyIdB = Uri.tryParse(urlB)?.queryParameters['id'];
        if (proxyIdB != null && proxyIdB.isNotEmpty) {
          prewarmTasks.add(AudioProxyServer.instance.prewarmHead(proxyIdB, chunks: 2));
        }
      }
      if (prewarmTasks.isNotEmpty) {
        await Future.wait(prewarmTasks).timeout(
          const Duration(seconds: 5),
          onTimeout: () => const [],
        );
      }
      if (_disposed) return false;

      if (urlA != null && urlA.isNotEmpty && _loadedKeyA != keyA) {
        final estDurASec = outgoing.duration > 20 ? outgoing.duration : 180;
        final estStartAMs = math.max(
          0,
          (estDurASec * 1000) - (_config.durationSec * 1000).round() - 5000,
        );
        final sourceA = ja.AudioSource.uri(
          Uri.parse(urlA),
          headers: const {'Accept': '*/*'},
        );
        final dA = await _deckA
            .setAudioSource(
              sourceA,
              initialPosition: Duration(milliseconds: estStartAMs),
              preload: true,
            )
            .timeout(const Duration(seconds: 7));
        _durA = dA ?? Duration(seconds: estDurASec);
        _loadedKeyA = keyA;
      }

      if (urlB != null && urlB.isNotEmpty && _loadedKeyB != keyB) {
        final introMs = (_config.introOffsetSec.clamp(0.0, 28.0) * 1000).round();
        final sourceB = ja.AudioSource.uri(
          Uri.parse(urlB),
          headers: const {'Accept': '*/*'},
        );
        final dB = await _deckB
            .setAudioSource(
              sourceB,
              initialPosition: introMs > 0 ? Duration(milliseconds: introMs) : null,
              preload: true,
            )
            .timeout(const Duration(seconds: 7));
        _durB = dB ?? Duration(seconds: incoming.duration > 0 ? incoming.duration : 180);
        _loadedKeyB = keyB;
      }

      _isLoading = false;
      onStateChanged?.call();
      return _loadedKeyA != null && _loadedKeyB != null;
    } catch (e) {
      debugPrint('TransitionAuditionMixer load error: $e');
      _isLoading = false;
      onStateChanged?.call();
      return _loadedKeyA != null || _loadedKeyB != null;
    }
  }

  Future<String?> _resolveAuditionStream(Track track) async {
    final cached = _apiService.getCachedStream(track, AudioQuality.high);
    if (cached != null && cached.isNotEmpty) return cached;
    return _apiService.resolveDirectAudioStream(track, AudioQuality.high);
  }

  /// Starts or resumes the dual-deck audition preview.
  Future<void> start({
    required Track outgoing,
    required Track incoming,
    required TransitionConfig config,
    double startProgress = 0.0,
  }) async {
    _config = config;
    await stop(silent: true);

    await preloadDecks(outgoing: outgoing, incoming: incoming, config: config);
    if (_disposed) return;

    _elapsedSec = (startProgress.clamp(0.0, 0.98) * _totalAuditionSec);
    _deckBStarted = _elapsedSec >= _leadInSec;
    _lastVolA = -1.0;
    _lastVolB = -1.0;

    try {
      final targetAMs = _outroStartMs + (_elapsedSec * 1000).round();
      if ((_deckA.position.inMilliseconds - targetAMs).abs() > 450) {
        await _deckA.seek(Duration(milliseconds: targetAMs));
      }
      await _deckA.setVolume(1.0);
      await _deckA.setSpeed(1.0);

      final targetBMs = _introStartMs +
          math.max<int>(0, ((_elapsedSec - _leadInSec) * 1000).round());
      if ((_deckB.position.inMilliseconds - targetBMs).abs() > 450) {
        await _deckB.seek(Duration(milliseconds: targetBMs));
      }
      await _deckB.setVolume(_deckBStarted ? 0.25 : 0.0);

      // Static subtle tempo match only on Android when BPMs are close; never ramp speed per tick
      if (!kIsWeb && !Platform.isIOS && _config.syncTempo && (_config.bpmA - _config.bpmB).abs() <= 8) {
        final avgBpm = (_config.bpmA + _config.bpmB) / 2.0;
        await _deckB.setSpeed((avgBpm / _config.bpmB.clamp(60, 200)).clamp(0.95, 1.05));
      } else {
        await _deckB.setSpeed(1.0);
      }

      unawaited(_deckA.play());
      if (_deckBStarted) {
        unawaited(_deckB.play());
      }
    } catch (e) {
      debugPrint('TransitionAuditionMixer start playback notice: $e');
    }

    _isPlaying = true;
    _lastTickAt = DateTime.now();
    onStateChanged?.call();

    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(milliseconds: 80), (_) => _onTimerTick());
    _onTimerTick();
  }

  /// Updates the active [TransitionConfig] in real time while auditioning.
  void updateConfig(TransitionConfig newConfig) {
    _config = newConfig;
    if (_isPlaying) {
      _applyEnvelopeAtCurrentElapsed();
    }
  }

  /// Scrubs the live audition playhead to normalized `overallProgress` (`0.0..1.0`).
  Future<void> seek(double overallProgress) async {
    final clamped = overallProgress.clamp(0.0, 0.99);
    _elapsedSec = clamped * _totalAuditionSec;
    _lastTickAt = DateTime.now();

    final transDur = _config.durationSec.clamp(1.2, 22.0);
    if (_isPlaying && _loadedKeyA != null) {
      try {
        if (_elapsedSec <= _leadInSec + transDur) {
          final posAMs = _outroStartMs + (_elapsedSec * 1000).round();
          unawaited(_deckA.seek(Duration(milliseconds: posAMs)));
          if (!_deckA.playing) unawaited(_deckA.play());
        } else {
          unawaited(_deckA.pause());
        }
      } catch (_) {}
    }

    if (_isPlaying && _loadedKeyB != null) {
      try {
        if (_elapsedSec >= _leadInSec) {
          final inOffsetMs = ((_elapsedSec - _leadInSec) * 1000).round();
          unawaited(_deckB.seek(Duration(milliseconds: _introStartMs + inOffsetMs)));
          _deckBStarted = true;
          if (!_deckB.playing) unawaited(_deckB.play());
        } else {
          _deckBStarted = false;
          unawaited(_deckB.pause());
          unawaited(_deckB.seek(Duration(milliseconds: _introStartMs)));
        }
      } catch (_) {}
    }

    _applyEnvelopeAtCurrentElapsed();
  }

  void _onTimerTick() {
    if (!_isPlaying || _disposed) return;

    // Wait for Deck A to actually start outputting audio frames before advancing the audition clock!
    // This prevents the audition playhead from running ahead while iOS/Android is still buffering the first frame.
    if (_elapsedSec < 0.25 &&
        _deckA.processingState == ja.ProcessingState.buffering) {
      _lastTickAt = DateTime.now();
      return;
    }

    final now = DateTime.now();
    final dtSec = _lastTickAt != null
        ? (now.difference(_lastTickAt!).inMilliseconds / 1000.0).clamp(0.0, 0.25)
        : 0.08;
    _lastTickAt = now;
    _elapsedSec += dtSec;

    if (_elapsedSec >= _totalAuditionSec) {
      final finalEnv = TransitionEngine.evaluateTransitionEnvelope(1.0, _config);
      onTick?.call(
        progress: 1.0,
        mixProgress: 1.0,
        phase: 'lead_out',
        envelope: finalEnv,
      );
      stop();
      onComplete?.call();
      return;
    }

    _applyEnvelopeAtCurrentElapsed();
  }

  void _applyEnvelopeAtCurrentElapsed() {
    final totalSec = _totalAuditionSec;
    final transDur = _config.durationSec.clamp(1.2, 22.0);
    final overallProgress = (_elapsedSec / totalSec).clamp(0.0, 1.0);

    String phase = 'lead_in';
    double mixProgress = 0.0;

    if (_elapsedSec < _leadInSec) {
      phase = 'lead_in';
      mixProgress = 0.0;
    } else if (_elapsedSec <= _leadInSec + transDur) {
      phase = 'transition';
      mixProgress = ((_elapsedSec - _leadInSec) / transDur).clamp(0.0, 1.0);
    } else {
      phase = 'lead_out';
      mixProgress = 1.0;
    }

    final env = TransitionEngine.evaluateTransitionEnvelope(mixProgress, _config);

    try {
      if (phase == 'lead_in') {
        if ((_lastVolA - 1.0).abs() > 0.01) {
          _lastVolA = 1.0;
          _deckA.setVolume(1.0);
        }
        if ((_lastVolB - 0.0).abs() > 0.01) {
          _lastVolB = 0.0;
          _deckB.setVolume(0.0);
        }
      } else if (phase == 'transition') {
        if (!_deckBStarted) {
          _deckBStarted = true;
          if (_loadedKeyB != null) {
            unawaited(_deckB.play());
          }
        }
        // Apply anti-clipping headroom normalization so simultaneous bass kicks don't crackle ("brebet")
        double outVol = env.effectiveOutVolume;
        double inVol = env.effectiveInVolume;
        final sum = outVol + inVol;
        if (sum > 1.08) {
          final scale = (1.08 / sum).clamp(0.82, 1.0);
          outVol = (outVol * scale).clamp(0.0, 1.0);
          inVol = (inVol * scale).clamp(0.0, 1.0);
        }
        if ((outVol - _lastVolA).abs() >= 0.015) {
          _lastVolA = outVol;
          _deckA.setVolume(outVol);
        }
        if ((inVol - _lastVolB).abs() >= 0.015) {
          _lastVolB = inVol;
          _deckB.setVolume(inVol);
        }
      } else {
        if (_lastVolA > 0.01) {
          _lastVolA = 0.0;
          _deckA.setVolume(0.0);
        }
        if (_deckA.playing) unawaited(_deckA.pause());
        if ((_lastVolB - 1.0).abs() > 0.01) {
          _lastVolB = 1.0;
          _deckB.setVolume(1.0);
        }
      }
    } catch (_) {}

    onTick?.call(
      progress: overallProgress,
      mixProgress: mixProgress,
      phase: phase,
      envelope: env,
    );
  }

  /// Stops both audition decks immediately.
  Future<void> stop({bool silent = false}) async {
    _tickTimer?.cancel();
    _tickTimer = null;
    _isPlaying = false;
    _deckBStarted = false;
    try {
      await _deckA.pause();
      await _deckB.pause();
    } catch (_) {}
    if (!silent) {
      onStateChanged?.call();
    }
  }

  /// Disposes both native audio players when the modal closes.
  Future<void> dispose() async {
    _disposed = true;
    await stop(silent: true);
    try {
      await _deckA.dispose();
      await _deckB.dispose();
    } catch (_) {}
  }
}
