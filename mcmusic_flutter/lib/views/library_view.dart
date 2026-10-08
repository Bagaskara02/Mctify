import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/playlist_importer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';
import 'import_playlist_view.dart';
import 'playlist_detail_view.dart';

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
  final PlaylistImporterService _importer = PlaylistImporterService();

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

  void _openImportPlaylist() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImportPlaylistView(
          player: widget.player,
          onPlaylistImported: _loadLibrary,
        ),
      ),
    );
  }

  void _createPlaylist() {
    final controller = TextEditingController(text: 'Playlist #${_playlists.length + 1}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161F30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Beri nama playlist kamu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nama Playlist',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: const Color(0xFF0F1523),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAzure,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
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

  void _showPlaylistOptions(Playlist pl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141923),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              ListTile(
                leading: OptimizedImage(imageUrl: pl.cover, width: 44, height: 44, borderRadius: BorderRadius.circular(6)),
                title: Text(pl.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text('${pl.tracks.length} lagu', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.play_circle_fill, color: AppTheme.primaryAzure),
                title: const Text('Putar Semua Lagu', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  if (pl.tracks.isNotEmpty) {
                    widget.player.playTrack(pl.tracks.first, pl.tracks);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: AppTheme.primaryAzure),
                title: const Text('Ekspor / Salin JSON Playlist', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final jsonStr = _importer.exportToJson(pl);
                  await Clipboard.setData(ClipboardData(text: jsonStr));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Data JSON playlist berhasil disalin ke clipboard!'),
                        backgroundColor: Color(0xFF1E293B),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Hapus Playlist', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  Navigator.pop(context);
                  final updated = _playlists.where((p) => p.id != pl.id).toList();
                  await _storage.savePlaylists(updated);
                  setState(() => _playlists = updated);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
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
            icon: const Icon(Icons.cloud_download_outlined, color: AppTheme.primaryAzure),
            onPressed: _openImportPlaylist,
            tooltip: 'Import Playlist',
          ),
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
                // Prominent Import Banner Card (Lyra & Spotify style)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF0F1E36),
                        Color(0xFF162A4D),
                        Color(0xFF0D172A),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primaryAzure.withAlpha(60)),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryAzure.withAlpha(20),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryAzure.withAlpha(40),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_download, color: AppTheme.primaryAzure, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Import Playlist Baru',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Dari Spotify, YouTube, teks, atau preset',
                              style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _openImportPlaylist,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryAzure,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text(
                          'Impor',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

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
                        selectedColor: AppTheme.primaryAzure,
                        backgroundColor: const Color(0xFF141923),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PlaylistDetailView(
                            playlist: Playlist(
                              id: 'liked',
                              name: 'Lagu yang Disukai',
                              cover: 'https://images.unsplash.com/photo-1518609878373-06d740f60d8b?auto=format&fit=crop&q=80&w=400',
                              tracks: _likedTracks,
                            ),
                            player: widget.player,
                            onPlaylistChanged: _loadLibrary,
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141923),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withAlpha(15)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0072CE), AppTheme.primaryAzure],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.favorite, color: Colors.white, size: 28),
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
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlaylistDetailView(
                                playlist: pl,
                                player: widget.player,
                                onPlaylistChanged: _loadLibrary,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141923),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withAlpha(15)),
                          ),
                          child: Row(
                            children: [
                              OptimizedImage(
                                imageUrl: pl.cover,
                                width: 56,
                                height: 56,
                                borderRadius: BorderRadius.circular(8),
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
                              IconButton(
                                icon: const Icon(Icons.more_vert, color: Colors.white60, size: 20),
                                onPressed: () => _showPlaylistOptions(pl),
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
