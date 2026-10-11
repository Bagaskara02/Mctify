import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../models/artist.dart';
import '../services/audio_player_manager.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../views/artist_view.dart';
import 'optimized_image.dart';

/// Shows the Spotify-styled Track Action Bottom Sheet (matching user's screenshot)
void showTrackActionSheet({
  required BuildContext context,
  required Track track,
  required AudioPlayerManager player,
  VoidCallback? onPlaylistModified,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF141923),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _TrackActionSheetContent(
      track: track,
      player: player,
      onPlaylistModified: onPlaylistModified,
    ),
  );
}

class _TrackActionSheetContent extends StatelessWidget {
  final Track track;
  final AudioPlayerManager player;
  final VoidCallback? onPlaylistModified;

  const _TrackActionSheetContent({
    required this.track,
    required this.player,
    this.onPlaylistModified,
  });

  void _showAddToPlaylist(BuildContext context) async {
    final storage = StorageService();
    final playlists = await storage.getPlaylists();

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141923),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Tambahkan ke Playlist',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Option: Create New Playlist
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFF202636),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.add, color: AppTheme.primaryAzure, size: 24),
                ),
                title: const Text(
                  'Playlist Baru',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Buat playlist baru dan masukkan lagu ini',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(bCtx);
                  _showCreatePlaylistDialog(context);
                },
              ),
              const Divider(color: Colors.white10),

              // Existing playlists
              if (playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'Belum ada playlist. Buat playlist baru di atas!',
                      style: TextStyle(color: AppTheme.textMuted),
                    ),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.45,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: playlists.length,
                    itemBuilder: (ctx, idx) {
                      final pl = playlists[idx];
                      final alreadyInPlaylist = pl.tracks.any((t) => t.id == track.id);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: OptimizedImage(
                            imageUrl: pl.cover,
                            width: 48,
                            height: 48,
                            memCacheWidth: 100,
                            memCacheHeight: 100,
                          ),
                        ),
                        title: Text(
                          pl.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${pl.tracks.length} lagu',
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                        trailing: alreadyInPlaylist
                            ? const Icon(Icons.check_circle, color: AppTheme.primaryAzure, size: 22)
                            : const Icon(Icons.add_circle_outline, color: Colors.white38, size: 22),
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          Navigator.pop(bCtx);

                          if (alreadyInPlaylist) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Lagu sudah ada di playlist "${pl.name}"'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            return;
                          }

                          final updatedTracks = [...pl.tracks, track];
                          final updatedPlaylist = Playlist(
                            id: pl.id,
                            name: pl.name,
                            description: pl.description,
                            cover: pl.cover.contains('unsplash') && track.artwork.isNotEmpty
                                ? track.artwork
                                : pl.cover,
                            tracks: updatedTracks,
                          );

                          final allPlaylists = await storage.getPlaylists();
                          final newPlaylists = allPlaylists.map((p) => p.id == pl.id ? updatedPlaylist : p).toList();
                          await storage.savePlaylists(newPlaylists);

                          onPlaylistModified?.call();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: AppTheme.primaryAzure),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Ditambahkan ke "${pl.name}"')),
                                  ],
                                ),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: '${track.artist} Favorites');
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF141923),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Beri Nama Playlist Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nama Playlist',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: const Color(0xFF0B0E14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Batal', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryAzure,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(dCtx);

              final storage = StorageService();
              final currentPlaylists = await storage.getPlaylists();

              final newPlaylist = Playlist(
                id: 'pl-${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                cover: track.artwork.isNotEmpty ? track.artwork : 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?auto=format&fit=crop&q=80&w=400',
                tracks: [track],
              );

              await storage.savePlaylists([newPlaylist, ...currentPlaylists]);
              onPlaylistModified?.call();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.check_circle, color: AppTheme.primaryAzure),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Playlist "$name" berhasil dibuat & lagu ditambahkan!')),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('Buat & Simpan', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final albumSubtitle = track.album.isNotEmpty && track.album != 'Single'
        ? '${track.artist} • ${track.album}'
        : track.artist;

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Album cover, Title, Artist • Album (Matching screenshot)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: OptimizedImage(
                    imageUrl: track.artwork,
                    width: 52,
                    height: 52,
                    memCacheWidth: 110,
                    memCacheHeight: 110,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
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
                        albumSubtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 16),

          // 1. Share
          _buildActionTile(
            icon: Icons.ios_share,
            title: 'Share',
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: '${track.title} - ${track.artist} https://mctify.vercel.app'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tautan lagu disalin ke papan klip!'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // 2. Add to playlist (CRITICAL USER REQUEST)
          _buildActionTile(
            icon: Icons.add_circle_outline,
            title: 'Add to playlist',
            onTap: () {
              Navigator.pop(context);
              _showAddToPlaylist(context);
            },
          ),

          // 3. Add to Queue
          _buildActionTile(
            icon: Icons.playlist_add,
            title: 'Add to Queue',
            onTap: () {
              Navigator.pop(context);
              player.addToQueue(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('"${track.title}" ditambahkan ke antrean'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // 4. Go to album
          _buildActionTile(
            icon: Icons.album_outlined,
            title: 'Go to album',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Album: ${track.album} (${track.artist})'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // 5. Go to artists (with trailing chevron)
          _buildActionTile(
            icon: Icons.person_outline,
            title: 'Go to artists',
            showChevron: true,
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArtistView(
                    artist: Artist(
                      id: 'art-${track.artist.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
                      name: track.artist.split(',')[0].trim(),
                      headerBanner: track.artwork,
                      avatar: track.artwork,
                      monthlyListeners: '4,9 jt pendengar bulanan',
                    ),
                    player: player,
                  ),
                ),
              );
            },
          ),

          // 6. Go to artists concerts (with trailing chevron)
          _buildActionTile(
            icon: Icons.confirmation_number_outlined,
            title: 'Go to artists concerts',
            showChevron: true,
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Jadwal tur konser ${track.artist} belum tersedia di kota Anda.'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          // 7. Go to radio
          _buildActionTile(
            icon: Icons.podcasts,
            title: 'Go to radio',
            onTap: () {
              Navigator.pop(context);
              player.playTrackFromSearch(track);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Memutar Radio berdasarkan "${track.title}"'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool showChevron = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: showChevron
          ? const Icon(Icons.chevron_right, color: Colors.white38, size: 20)
          : null,
      onTap: onTap,
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
    );
  }
}
