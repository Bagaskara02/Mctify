import 'package:flutter/material.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';

class LibraryView extends StatefulWidget {
  final AudioPlayerManager player;

  const LibraryView({
    super.key,
    required this.player,
  });

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final StorageService _storage = StorageService();

  List<Track> _likedTracks = [];
  List<Playlist> _playlists = [];
  bool _isLoading = true;
  String _activeFilter = 'Semua';

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    final liked = await _storage.getLikedTracks();
    final playlists = await _storage.getPlaylists();
    if (mounted) {
      setState(() {
        _likedTracks = liked;
        _playlists = playlists;
        _isLoading = false;
      });
    }
  }

  void _createPlaylist() {
    final controller = TextEditingController(text: 'Playlist #${_playlists.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF242424),
        title: const Text('Beri nama playlist kamu', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Nama Playlist',
            hintStyle: TextStyle(color: AppTheme.textMuted),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryAzure),
            child: const Text('Buat', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final newPl = Playlist(
                  id: 'pl-${DateTime.now().millisecondsSinceEpoch}',
                  name: controller.text.trim(),
                  cover: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=400',
                  tracks: [],
                );
                final updated = [..._playlists, newPl];
                await _storage.savePlaylists(updated);
                setState(() => _playlists = updated);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: const [
            Icon(Icons.library_music, color: AppTheme.primaryAzure, size: 24),
            SizedBox(width: 10),
            Text(
              'Koleksi Kamu',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.white),
            onPressed: _createPlaylist,
            tooltip: 'Buat Playlist',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAzure))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                // Filter Pills
                Row(
                  children: ['Semua', 'Playlist', 'Disukai'].map((f) {
                    final isSel = _activeFilter == f;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(f),
                        selected: isSel,
                        onSelected: (_) => setState(() => _activeFilter = f),
                        selectedColor: Colors.white,
                        backgroundColor: const Color(0xFF242424),
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Liked Songs Card (Always pinned on top)
                if (_activeFilter != 'Playlist') ...[
                  InkWell(
                    onTap: () {
                      if (_likedTracks.isNotEmpty) {
                        widget.player.playTrack(_likedTracks.first, _likedTracks);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.darkCard,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0072CE), AppTheme.primaryAzure],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.favorite, color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Lagu yang Disukai',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.push_pin, color: AppTheme.primaryAzure, size: 13),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Playlist • ${_likedTracks.length} lagu',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (_likedTracks.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.play_circle_fill, color: AppTheme.primaryAzure, size: 36),
                              onPressed: () => widget.player.playTrack(_likedTracks.first, _likedTracks),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Playlists List
                ..._playlists.map((pl) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        onTap: () {
                          if (pl.tracks.isNotEmpty) {
                            widget.player.playTrack(pl.tracks.first, pl.tracks);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.darkCard,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              OptimizedImage(
                                imageUrl: pl.cover,
                                width: 60,
                                height: 60,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      pl.name,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Playlist • ${pl.tracks.length} lagu',
                                      style: const TextStyle(
                                        color: AppTheme.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )),

                const SizedBox(height: 100),
              ],
            ),
    );
  }
}
