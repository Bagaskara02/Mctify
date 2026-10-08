import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';

class QueueView extends StatefulWidget {
  final AudioPlayerManager player;

  const QueueView({
    super.key,
    required this.player,
  });

  static void show(BuildContext context, AudioPlayerManager player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QueueView(player: player),
    );
  }

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.player,
      builder: (context, _) {
        final current = widget.player.currentTrack;
        final fullQueue = widget.player.queue;

        // Separate upcoming tracks from current track
        int currentIndex = -1;
        if (current != null) {
          currentIndex = fullQueue.indexWhere((t) => t.id == current.id);
        }

        final List<Track> upcoming = [];
        if (currentIndex != -1 && currentIndex < fullQueue.length - 1) {
          upcoming.addAll(fullQueue.sublist(currentIndex + 1));
        } else if (currentIndex == -1 && fullQueue.isNotEmpty) {
          upcoming.addAll(fullQueue);
        }

        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0F1E36),
                Color(0xFF0A1424),
                Color(0xFF060B14),
              ],
            ),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                // Pull down handle
                const SizedBox(height: 12),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),

                // Top Header Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.queue_music, color: AppTheme.primaryAzure, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Antrean Lagu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (upcoming.isNotEmpty)
                        TextButton.icon(
                          onPressed: () {
                            HapticFeedback.mediumImpact();
                            widget.player.clearQueue();
                          },
                          icon: const Icon(Icons.clear_all, size: 16, color: Colors.white70),
                          label: const Text(
                            'Bersihkan',
                            style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.white.withAlpha(15),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white12, height: 16),

                // Scrollable Queue Content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    children: [
                      // Section 1: Sedang Memutar
                      if (current != null) ...[
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            'SEDANG MEMUTAR',
                            style: TextStyle(
                              color: AppTheme.primaryAzure,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF162A4D),
                                const Color(0xFF141923),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppTheme.primaryAzure.withAlpha(80)),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryAzure.withAlpha(30),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              OptimizedImage(
                                imageUrl: current.artwork,
                                width: 50,
                                height: 50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      current.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      current.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Equalizer Indicator Animation
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryAzure.withAlpha(30),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  children: const [
                                    Icon(Icons.graphic_eq, color: AppTheme.primaryAzure, size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      'PLAYING',
                                      style: TextStyle(
                                        color: AppTheme.primaryAzure,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Section 2: Berikutnya dalam Antrean
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Text(
                              'BERIKUTNYA DALAM ANTREAN',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                          Text(
                            '${upcoming.length} Lagu',
                            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      if (upcoming.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(28),
                          margin: const EdgeInsets.only(top: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141923),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withAlpha(15)),
                          ),
                          child: Column(
                            children: const [
                              Icon(Icons.music_off_outlined, color: Colors.white30, size: 38),
                              SizedBox(height: 10),
                              Text(
                                'Antrean Lagu Kosong',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Pilih lagu dari playlist atau beranda untuk diputar selanjutnya.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                              ),
                            ],
                          ),
                        )
                      else
                        ReorderableListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: upcoming.length,
                          onReorder: (oldIndex, newIndex) {
                            HapticFeedback.selectionClick();
                            final realOld = (currentIndex != -1 ? currentIndex + 1 : 0) + oldIndex;
                            final realNew = (currentIndex != -1 ? currentIndex + 1 : 0) + newIndex;
                            widget.player.reorderQueue(realOld, realNew);
                          },
                          itemBuilder: (context, idx) {
                            final track = upcoming[idx];
                            return Container(
                              key: ValueKey(track.id + idx.toString()),
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141923),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white.withAlpha(12)),
                              ),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                                leading: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReorderableDragStartListener(
                                      index: idx,
                                      child: const Icon(Icons.drag_indicator, color: Colors.white38, size: 20),
                                    ),
                                    const SizedBox(width: 8),
                                    OptimizedImage(
                                      imageUrl: track.artwork,
                                      width: 42,
                                      height: 42,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ],
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${track.artist} • ${_formatDuration(track.duration)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white38, size: 18),
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    final realIdx = (currentIndex != -1 ? currentIndex + 1 : 0) + idx;
                                    widget.player.removeFromQueue(realIdx);
                                  },
                                ),
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  widget.player.playTrack(track);
                                },
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
