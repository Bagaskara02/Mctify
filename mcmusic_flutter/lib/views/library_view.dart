import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/playlist_importer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';
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
  String _activeFilter = 'Playlists'; // Playlists, Albums, Artists
  String _sortBy = 'Recents'; // Recents, Recently Added, Alphabetical
  bool _isGridView = false;

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
        backgroundColor: const Color(0xFF1E1E24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Beri nama playlist kamu', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nama Playlist',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: const Color(0xFF121216),
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

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('Urutkan Berdasarkan', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              ListTile(
                title: const Text('Terakhir Diputar (Recents)', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'Recents' ? const Icon(Icons.check, color: AppTheme.primaryAzure) : null,
                onTap: () {
                  setState(() => _sortBy = 'Recents');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Baru Ditambahkan (Recently Added)', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'Recently Added' ? const Icon(Icons.check, color: AppTheme.primaryAzure) : null,
                onTap: () {
                  setState(() => _sortBy = 'Recently Added');
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Abjad (Alphabetical)', style: TextStyle(color: Colors.white)),
                trailing: _sortBy == 'Alphabetical' ? const Icon(Icons.check, color: AppTheme.primaryAzure) : null,
                onTap: () {
                  setState(() => _sortBy = 'Alphabetical');
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showPlaylistMenu(Playlist pl) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
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
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: _buildPlaylistArtwork(pl, 48),
                ),
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
                title: const Text('Ekspor JSON Playlist', style: TextStyle(color: Colors.white)),
                onTap: () async {
                  Navigator.pop(context);
                  final jsonStr = _importer.exportToJson(pl);
                  await Clipboard.setData(ClipboardData(text: jsonStr));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('JSON playlist disalin!'), behavior: SnackBarBehavior.floating),
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
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // Spotify 4-Grid Collage Artwork generation
  Widget _buildPlaylistArtwork(Playlist pl, double size) {
    if (pl.tracks.length >= 4) {
      final half = size / 2;
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFF242426),
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Row(
              children: [
                OptimizedImage(imageUrl: pl.tracks[0].artwork, width: half, height: half, memCacheWidth: 60, memCacheHeight: 60),
                OptimizedImage(imageUrl: pl.tracks[1].artwork, width: half, height: half, memCacheWidth: 60, memCacheHeight: 60),
              ],
            ),
            Row(
              children: [
                OptimizedImage(imageUrl: pl.tracks[2].artwork, width: half, height: half, memCacheWidth: 60, memCacheHeight: 60),
                OptimizedImage(imageUrl: pl.tracks[3].artwork, width: half, height: half, memCacheWidth: 60, memCacheHeight: 60),
              ],
            ),
          ],
        ),
      );
    } else if (pl.tracks.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: OptimizedImage(imageUrl: pl.tracks.first.artwork, width: size, height: size, memCacheWidth: 100, memCacheHeight: 100),
      );
    } else {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: const Color(0xFF242426), borderRadius: BorderRadius.circular(4)),
        child: const Icon(Icons.music_note, color: Colors.white38),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top Bar: "Your Library", Search, Add - NO PROFILE ICON!
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Your Library',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, color: Colors.white, size: 24),
                        onPressed: () {},
                      ),
                      IconButton(
                        icon: const Icon(Icons.add, color: Colors.white, size: 28),
                        tooltip: 'Buat Playlist',
                        onPressed: _createPlaylist,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Filter Pills Row ("Playlists", "Albums", "Artists")
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: ['Playlists', 'Albums', 'Artists'].map((filter) {
                  final isSelected = _activeFilter == filter;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _activeFilter = filter),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: isSelected ? AppTheme.primaryAzure : const Color(0xFF242426),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          filter,
                          style: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 8),

            // Sort & View Toggle Row (Recents with arrow + Grid toggle)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _showSortOptions,
                    child: Row(
                      children: [
                        const Icon(Icons.swap_vert, color: Colors.white70, size: 18),
                        const SizedBox(width: 4),
                        Text(
                          _sortBy,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, color: Colors.white70, size: 20),
                    onPressed: () => setState(() => _isGridView = !_isGridView),
                  ),
                ],
              ),
            ),

            // Main List / Grid
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAzure))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                      children: [
                        // Pinned: "Liked Songs" Card (Spotify exact match with Blue pin!)
                        InkWell(
                          onTap: () {
                            if (_likedTracks.isNotEmpty) {
                              widget.player.playTrack(_likedTracks.first, _likedTracks);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Icon(Icons.favorite, color: Colors.white, size: 28),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Liked Songs',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          const Icon(Icons.push_pin, color: AppTheme.primaryAzure, size: 13),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Playlist • ${_likedTracks.length} songs',
                                            style: const TextStyle(
                                              color: AppTheme.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Playlists List
                        ..._playlists.map((pl) {
                          return InkWell(
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
                            onLongPress: () => _showPlaylistMenu(pl),
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  _buildPlaylistArtwork(pl, 60),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          pl.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          'Playlist • McMusic • ${pl.tracks.length} songs',
                                          style: const TextStyle(
                                            color: AppTheme.textMuted,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.more_horiz, color: Colors.white60, size: 20),
                                    onPressed: () => _showPlaylistMenu(pl),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
