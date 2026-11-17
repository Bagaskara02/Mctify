import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/equalizer_preset.dart';
import '../services/equalizer_service.dart';
import '../theme/app_theme.dart';

class EqualizerView extends StatefulWidget {
  final EqualizerService equalizerService;

  const EqualizerView({
    super.key,
    required this.equalizerService,
  });

  @override
  State<EqualizerView> createState() => _EqualizerViewState();
}

class _EqualizerViewState extends State<EqualizerView> {
  final List<String> _bandLabels = ['60Hz', '230Hz', '910Hz', '3.6kHz', '14kHz'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.equalizerService,
      builder: (context, _) {
        final eq = widget.equalizerService;
        final isIos = !kIsWeb && Platform.isIOS;

        return Scaffold(
          backgroundColor: const Color(0xFF0F1015),
          body: Stack(
            children: [
              // 1. Ambient Top Studio Mesh Glow
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 240,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF00A3FF).withValues(alpha: eq.isEnabled ? 0.24 : 0.08),
                        const Color(0xFF0F1015).withValues(alpha: 0.95),
                        const Color(0xFF0F1015),
                      ],
                      stops: const [0.0, 0.7, 1.0],
                    ),
                  ),
                ),
              ),

              // 2. Main Content
              SafeArea(
                child: Column(
                  children: [
                    // Header Bar
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Equalizer Studio',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.4,
                                  ),
                                ),
                                Text(
                                  isIos ? 'DSP Hardware Engine • Apple AVFoundation' : 'DSP Hardware Engine • ExoPlayer AudioFX',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () => eq.reset(),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text(
                              'Reset',
                              style: TextStyle(
                                color: AppTheme.primaryAzure,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Scrollable Options
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          // Master Equalizer Switch Card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161820),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: eq.isEnabled
                                    ? AppTheme.primaryAzure.withValues(alpha: 0.35)
                                    : Colors.white.withValues(alpha: 0.08),
                                width: 1.0,
                              ),
                              boxShadow: eq.isEnabled
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryAzure.withValues(alpha: 0.12),
                                        blurRadius: 18,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: eq.isEnabled
                                        ? AppTheme.primaryAzure.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: eq.isEnabled
                                          ? AppTheme.primaryAzure.withValues(alpha: 0.4)
                                          : Colors.transparent,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.graphic_eq_rounded,
                                    color: eq.isEnabled ? AppTheme.primaryAzure : Colors.white38,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Equalizer & Efek Audio',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        eq.isEnabled
                                            ? 'Aktif • ${eq.selectedPresetName}'
                                            : 'Nonaktif (Profil Flat Standar)',
                                        style: TextStyle(
                                          color: eq.isEnabled ? AppTheme.primaryAzure : AppTheme.textMuted,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: eq.isEnabled,
                                  activeColor: AppTheme.primaryAzure,
                                  activeTrackColor: AppTheme.primaryAzure.withValues(alpha: 0.35),
                                  inactiveThumbColor: Colors.white54,
                                  inactiveTrackColor: Colors.white12,
                                  onChanged: (_) => eq.toggleEnabled(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Preset Horizontal Filter Pills
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'PRESET FREKUENSI',
                                style: TextStyle(
                                  color: AppTheme.textMuted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              if (eq.isEnabled)
                                Text(
                                  eq.selectedPresetName,
                                  style: const TextStyle(
                                    color: AppTheme.primaryAzure,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 38,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: EqualizerPreset.defaultPresets.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, index) {
                                final preset = EqualizerPreset.defaultPresets[index];
                                final isSelected = eq.selectedPresetName == preset.name;

                                return GestureDetector(
                                  onTap: eq.isEnabled ? () => eq.selectPreset(preset) : null,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? AppTheme.primaryAzure
                                          : const Color(0xFF20222A),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: isSelected
                                            ? Colors.transparent
                                            : Colors.white.withValues(alpha: 0.08),
                                      ),
                                    ),
                                    child: Text(
                                      preset.name,
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : Colors.white.withValues(alpha: 0.8),
                                        fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 22),

                          // Interactive Visual Spectrum Curve & 5-Band Sliders Card
                          Container(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161820),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              children: [
                                // Studio Frequency Response Curve Spline Canvas
                                Container(
                                  height: 72,
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF101218),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(14),
                                    child: CustomPaint(
                                      painter: _StudioFrequencyCurvePainter(
                                        bands: eq.currentBands,
                                        isEnabled: eq.isEnabled,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // dB labels
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('+10 dB', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.bold)),
                                    Text('0 dB (Flat)', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.bold)),
                                    Text('-10 dB', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 10, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // 5 Vertical Sliders
                                SizedBox(
                                  height: 175,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: List.generate(5, (index) {
                                      final val = eq.currentBands[index];

                                      return Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: eq.isEnabled && val.abs() > 0.1
                                                  ? AppTheme.primaryAzure.withValues(alpha: 0.18)
                                                  : Colors.transparent,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}',
                                              style: TextStyle(
                                                color: eq.isEnabled && val.abs() > 0.1
                                                    ? AppTheme.primaryAzure
                                                    : Colors.white30,
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: RotatedBox(
                                              quarterTurns: 3,
                                              child: SliderTheme(
                                                data: SliderTheme.of(context).copyWith(
                                                  activeTrackColor: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                                  inactiveTrackColor: Colors.white10,
                                                  thumbColor: eq.isEnabled ? Colors.white : Colors.white38,
                                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                                  trackHeight: 3.5,
                                                ),
                                                child: Slider(
                                                  value: val,
                                                  min: -10.0,
                                                  max: 10.0,
                                                  onChanged: eq.isEnabled
                                                      ? (newVal) => eq.setBandValue(index, newVal)
                                                      : null,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _bandLabels[index],
                                            style: TextStyle(
                                              color: eq.isEnabled ? Colors.white70 : Colors.white24,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      );
                                    }),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Bass Boost & Acoustics Section
                          const Text(
                            'AKUSTIK & PENGUAT SUARA',
                            style: TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 1. Master Volume / Loudness Gain
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161820),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (eq.loudnessGain > 0 && eq.isEnabled)
                                    ? AppTheme.primaryAzure.withValues(alpha: 0.3)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryAzure.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.volume_up_rounded, color: AppTheme.primaryAzure, size: 18),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Master Volume Boost (Mobil/Speaker)',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '+${(eq.loudnessGain * 10).toStringAsFixed(1)} dB',
                                      style: const TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Meningkatkan kekuatan audio hingga setara Spotify di speaker mobil & Bluetooth tanpa distorsi.',
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                                ),
                                const SizedBox(height: 10),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                    inactiveTrackColor: Colors.white10,
                                    thumbColor: eq.isEnabled ? Colors.white : Colors.white38,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    trackHeight: 3.5,
                                  ),
                                  child: Slider(
                                    value: eq.loudnessGain,
                                    onChanged: eq.isEnabled ? (v) => eq.setLoudnessGain(v) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 2. Bass Boost Subwoofer
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161820),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryAzure.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.speaker_rounded, color: AppTheme.primaryAzure, size: 18),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          'Bass Boost Subwoofer',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${(eq.bassBoost * 100).round()}%',
                                      style: const TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                    inactiveTrackColor: Colors.white10,
                                    thumbColor: eq.isEnabled ? Colors.white : Colors.white38,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    trackHeight: 3.5,
                                  ),
                                  child: Slider(
                                    value: eq.bassBoost,
                                    onChanged: eq.isEnabled ? (v) => eq.setBassBoost(v) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 3. 3D Spatial Virtualizer
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161820),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryAzure.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Icon(Icons.surround_sound_rounded, color: AppTheme.primaryAzure, size: 18),
                                        ),
                                        const SizedBox(width: 10),
                                        const Text(
                                          '3D Spatial Virtualizer',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      '${(eq.virtualizer * 100).round()}%',
                                      style: const TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    activeTrackColor: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                    inactiveTrackColor: Colors.white10,
                                    thumbColor: eq.isEnabled ? Colors.white : Colors.white38,
                                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    trackHeight: 3.5,
                                  ),
                                  child: Slider(
                                    value: eq.virtualizer,
                                    onChanged: eq.isEnabled ? (v) => eq.setVirtualizer(v) : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 36),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Studio parametric frequency response spline curve painter
class _StudioFrequencyCurvePainter extends CustomPainter {
  final List<double> bands;
  final bool isEnabled;

  _StudioFrequencyCurvePainter({
    required this.bands,
    required this.isEnabled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bands.isEmpty) return;

    final width = size.width;
    final height = size.height;
    final midY = height / 2.0;

    // 1. Draw 0 dB center reference line
    final refPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, midY), Offset(width, midY), refPaint);

    // Compute coordinate points for 5 bands
    final points = <Offset>[];
    for (int i = 0; i < bands.length; i++) {
      final x = width * ((i + 0.5) / bands.length);
      final normalized = (bands[i] / 10.0).clamp(-1.0, 1.0);
      final y = midY - (normalized * (height * 0.40));
      points.add(Offset(x, y));
    }

    // Build smooth cubic spline
    final path = Path();
    path.moveTo(0, midY);
    path.lineTo(points[0].dx * 0.5, (midY + points[0].dy) / 2);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final controlX = (p0.dx + p1.dx) / 2;
      path.cubicTo(controlX, p0.dy, controlX, p1.dy, p1.dx, p1.dy);
    }

    final last = points.last;
    path.lineTo(width, (midY + last.dy) / 2);
    path.lineTo(width, midY);

    // Fill underneath curve
    final fillPath = Path.from(path);
    fillPath.lineTo(width, height);
    fillPath.lineTo(0, height);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          (isEnabled ? AppTheme.primaryAzure : Colors.white30).withValues(alpha: isEnabled ? 0.35 : 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, width, height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Stroke line
    final strokePaint = Paint()
      ..color = isEnabled ? AppTheme.primaryAzure : Colors.white30
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, strokePaint);

    // Draw active band dots
    for (final pt in points) {
      canvas.drawCircle(
        pt,
        3.5,
        Paint()..color = isEnabled ? Colors.white : Colors.white54,
      );
      if (isEnabled) {
        canvas.drawCircle(
          pt,
          6.0,
          Paint()
            ..color = AppTheme.primaryAzure.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StudioFrequencyCurvePainter oldDelegate) {
    return isEnabled != oldDelegate.isEnabled || !listEquals(bands, oldDelegate.bands);
  }
}
