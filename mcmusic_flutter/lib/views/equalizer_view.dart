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

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF121212),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Equalizer & Efek Suara',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => eq.reset(),
                child: const Text(
                  'Reset',
                  style: TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            children: [
              // Equalizer Master Switch Card
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: eq.isEnabled ? AppTheme.primaryAzure.withValues(alpha: 0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.graphic_eq,
                            color: eq.isEnabled ? AppTheme.primaryAzure : Colors.white38,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Aktifkan Equalizer',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              eq.isEnabled ? 'Preset: ${eq.selectedPresetName}' : 'Nonaktif (Suara Asli)',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Switch(
                      value: eq.isEnabled,
                      activeThumbColor: AppTheme.primaryAzure,
                      onChanged: (_) => eq.toggleEnabled(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Preset Horizontal Pills
              const Text(
                'PRESET SUARA',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: EqualizerPreset.defaultPresets.length,
                  separatorBuilder: (_, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final preset = EqualizerPreset.defaultPresets[index];
                    final isSelected = eq.selectedPresetName == preset.name;

                    return GestureDetector(
                      onTap: eq.isEnabled ? () => eq.selectPreset(preset) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.primaryAzure
                              : const Color(0xFF242424),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.primaryAzure.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: Text(
                          preset.name,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 28),

              // 5-Band Equalizer Sliders
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('+10 dB', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text('0 dB', style: TextStyle(color: Colors.white38, fontSize: 10)),
                        Text('-10 dB', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(5, (index) {
                          final val = eq.currentBands[index];

                          return Column(
                            children: [
                              Text(
                                '${val >= 0 ? '+' : ''}${val.toStringAsFixed(1)}',
                                style: TextStyle(
                                  color: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Expanded(
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: eq.isEnabled ? AppTheme.primaryAzure : Colors.white24,
                                      inactiveTrackColor: Colors.white12,
                                      thumbColor: eq.isEnabled ? Colors.white : Colors.white38,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                      trackHeight: 4,
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
                              Text(
                                _bandLabels[index],
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Bass Boost & Virtualizer Controls
              const Text(
                'EFEK TAMBAHAN',
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 14),

              // Bass Boost
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.speaker, color: AppTheme.primaryAzure, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Bass Boost (Subwoofer)',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Text(
                          '${(eq.bassBoost * 100).round()}%',
                          style: const TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: eq.bassBoost,
                      activeColor: AppTheme.primaryAzure,
                      inactiveColor: Colors.white12,
                      onChanged: eq.isEnabled ? (v) => eq.setBassBoost(v) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 3D Virtualizer / Surround
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: const [
                            Icon(Icons.surround_sound, color: AppTheme.primaryAzure, size: 20),
                            SizedBox(width: 10),
                            Text(
                              '3D Surround Virtualizer',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ],
                        ),
                        Text(
                          '${(eq.virtualizer * 100).round()}%',
                          style: const TextStyle(color: AppTheme.primaryAzure, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: eq.virtualizer,
                      activeColor: AppTheme.primaryAzure,
                      inactiveColor: Colors.white12,
                      onChanged: eq.isEnabled ? (v) => eq.setVirtualizer(v) : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
