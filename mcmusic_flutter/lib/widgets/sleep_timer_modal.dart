import 'package:flutter/material.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';

class SleepTimerModal extends StatelessWidget {
  final AudioPlayerManager player;

  const SleepTimerModal({
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
      builder: (_) => SleepTimerModal(player: player),
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      {'label': '5 Menit', 'minutes': 5},
      {'label': '15 Menit', 'minutes': 15},
      {'label': '30 Menit', 'minutes': 30},
      {'label': '45 Menit', 'minutes': 45},
      {'label': '1 Jam', 'minutes': 60},
      {'label': 'Akhir Lagu Ini', 'minutes': -1}, // -1 means end of track
    ];

    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final isActive = player.isSleepTimerActive;
        final formatted = player.sleepTimerFormatted;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.bedtime, color: AppTheme.primaryAzure, size: 24),
                        SizedBox(width: 10),
                        Text(
                          'Pengatur Waktu Tidur',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    if (isActive)
                      TextButton(
                        onPressed: () {
                          player.cancelSleepTimer();
                          Navigator.pop(context);
                        },
                        child: const Text('Matikan Timer', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                if (isActive && formatted != null)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryAzure.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.primaryAzure.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer, color: AppTheme.primaryAzure, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          'Musik akan berhenti dalam $formatted',
                          style: const TextStyle(color: AppTheme.primaryAzure, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                const Divider(color: Colors.white12),

                // Options
                ...options.map((opt) {
                  final mins = opt['minutes'] as int;
                  final label = opt['label'] as String;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    leading: Icon(
                      mins == -1 ? Icons.skip_next : Icons.access_time,
                      color: Colors.white70,
                    ),
                    title: Text(
                      label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      if (mins == -1) {
                        player.setSleepTimerAtTrackEnd();
                      } else {
                        player.setSleepTimerMinutes(mins);
                      }
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF242424),
                          content: Text(
                            mins == -1
                                ? 'Pengatur waktu tidur diatur: Berhenti di akhir lagu'
                                : 'Pengatur waktu tidur diatur: $mins menit',
                            style: const TextStyle(color: Colors.white),
                          ),
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }
}
