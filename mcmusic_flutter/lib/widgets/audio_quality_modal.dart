import 'package:flutter/material.dart';
import '../models/audio_quality.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';

class AudioQualityModal extends StatelessWidget {
  final AudioPlayerManager player;

  const AudioQualityModal({
    super.key,
    required this.player,
  });

  static void show(BuildContext context, AudioPlayerManager player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AudioQualityModal(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final current = player.audioQuality;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: const [
                    Icon(Icons.high_quality, color: AppTheme.primaryAzure, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Kualitas Audio Streaming',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Pilih bitrate audio YouTube Music sesuai preferensi kuota dan kecepatan jaringanmu.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),

                ...AudioQuality.values.map((q) {
                  final isSelected = current == q;

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: isSelected ? AppTheme.primaryAzure.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected ? Border.all(color: AppTheme.primaryAzure.withValues(alpha: 0.4)) : null,
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: isSelected ? AppTheme.primaryAzure : Colors.white38,
                      ),
                      title: Row(
                        children: [
                          Text(
                            q.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isSelected ? AppTheme.primaryAzure : Colors.white12,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              q.bitrate,
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        q.description,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      onTap: () {
                        player.setAudioQuality(q);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF242424),
                            content: Text(
                              'Kualitas diatur: ${q.label} (${q.bitrate})',
                              style: const TextStyle(color: Colors.white),
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  );
                }),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}
