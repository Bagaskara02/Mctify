import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/playlist_importer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';

class PlaylistDetailView extends StatefulWidget {
  final Playlist playlist;
  final AudioPlayerManager player;
  final VoidCallback? onPlaylistChanged;

  const PlaylistDetailView({
    super.key,
    required this.playlist,
    required this.player,
    this.onPlaylistChanged,
  });

  @override
  State<PlaylistDetailView> createState() => _PlaylistDetailViewState();
}

class _PlaylistDetailViewState extends State<PlaylistDetailView> {
  final StorageService _storage = StorageService();
  final PlaylistImporterService _importer = PlaylistImporterService();
  final MusicApiService _apiService = MusicApiService();

  late Playlist _currentPlaylist;
  String _filterQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Auto-clean any duplicate tracks that might exist in storage
    final seen = <String>{};
    final uniqueTracks = <Track>[];
    bool hadDuplicates = false;
    for (final t in widget.playlist.tracks) {
      final key = '${t.title.trim().toLowerCase()}_${t.artist.trim().toLowerCase()}';
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueTracks.add(t);
      } else {
        hadDuplicates = true;
      }
    }
    if (hadDuplicates) {
      _currentPlaylist = Playlist(
        id: widget.playlist.id,
        name: widget.playlist.name,
        cover: widget.playlist.cover,
        tracks: uniqueTracks,
      );
      _cleanDuplicatesInStorage(_currentPlaylist);
    } else {
      _currentPlaylist = widget.playlist;
    }
  }

  Future<void> _cleanDuplicatesInStorage(Playlist cleanedPl) async {
    final allPl = await _storage.getPlaylists();
    final idx = allPl.indexWhere((p) => p.id == cleanedPl.id);
    if (idx != -1) {
      allPl[idx] = cleanedPl;
      await _storage.savePlaylists(allPl);
      widget.onPlaylistChanged?.call();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs < 10 ? '0' : ''}$secs';
  }

  String get _totalDurationFormatted {
    final totalSec = _currentPlaylist.tracks.fold<int>(0, (sum, t) => sum + t.duration);
    final hours = totalSec ~/ 3600;
    final mins = (totalSec % 3600) ~/ 60;
    if (hours > 0) {
      return '$hours jam $mins menit';
    }
    return '$mins menit';
  }

  void _playAll({bool shuffle = false}) {
    if (_currentPlaylist.tracks.isEmpty) return;
    HapticFeedback.mediumImpact();
    if (shuffle) {
      final shuffled = List<Track>.from(_currentPlaylist.tracks)..shuffle();
      widget.player.playTrack(shuffled.first, shuffled);
    } else {
      widget.player.playTrack(_currentPlaylist.tracks.first, _currentPlaylist.tracks);
    }
  }

  Future<void> _removeTrackFromPlaylist(Track track) async {
    final updatedTracks = _currentPlaylist.tracks.where((t) => t.id != track.id).toList();
    final updatedPl = Playlist(
      id: _currentPlaylist.id,
      name: _currentPlaylist.name,
      cover: _currentPlaylist.cover,
      tracks: updatedTracks,
    );

    final allPlaylists = await _storage.getPlaylists();
    final idx = allPlaylists.indexWhere((p) => p.id == _currentPlaylist.id);
    if (idx != -1) {
      allPlaylists[idx] = updatedPl;
      await _storage.savePlaylists(allPlaylists);
    }

    setState(() {
      _currentPlaylist = updatedPl;
    });
    widget.onPlaylistChanged?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${track.title}" dihapus dari playlist.'),
          backgroundColor: const Color(0xFF141923),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openAddSongsModal() {
    final searchAddCtrl = TextEditingController();
    List<Track> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: Color(0xFF101726),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(height: 14),
                    const Text('Tambah Lagu ke Playlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: searchAddCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Cari judul lagu atau nama artis...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          prefixIcon: const Icon(Icons.search, color: AppTheme.primaryAzure),
                          filled: true,
                          fillColor: const Color(0xFF141F33),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                        onSubmitted: (q) async {
                          if (q.trim().isEmpty) return;
                          setModalState(() => isSearching = true);
                          final results = await _apiService.searchTracks(q.trim());
                          setModalState(() {
                            searchResults = results;
                            isSearching = false;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: isSearching
                          ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryAzure))
                          : ListView.builder(
                              itemCount: searchResults.length,
                              itemBuilder: (context, i) {
                                final t = searchResults[i];
                                final isAlreadyIn = _currentPlaylist.tracks.any((item) => item.id == t.id);

                                return ListTile(
                                  leading: OptimizedImage(imageUrl: t.artwork, width: 44, height: 44, borderRadius: BorderRadius.circular(6)),
                                  title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                                  trailing: IconButton(
                                    icon: Icon(isAlreadyIn ? Icons.check_circle : Icons.add_circle, color: isAlreadyIn ? AppTheme.primaryAzure : Colors.white70),
                                    onPressed: isAlreadyIn
                                        ? null
                                        : () async {
                                            HapticFeedback.lightImpact();
                                            final updatedTracks = [..._currentPlaylist.tracks, t];
                                            final updatedPl = Playlist(
                                              id: _currentPlaylist.id,
                                              name: _currentPlaylist.name,
                                              cover: _currentPlaylist.cover,
                                              tracks: updatedTracks,
                                            );
                                            final allPl = await _storage.getPlaylists();
                                            final idx = allPl.indexWhere((p) => p.id == _currentPlaylist.id);
                                            if (idx != -1) {
                                              allPl[idx] = updatedPl;
                                              await _storage.savePlaylists(allPl);
                                            }
                                            setState(() => _currentPlaylist = updatedPl);
                                            setModalState(() {});
                                            widget.onPlaylistChanged?.call();
                                          },
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showTrackMenu(Track track) {
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
              const SizedBox(height: 12),
              ListTile(
                leading: OptimizedImage(imageUrl: track.artwork, width: 44, height: 44, borderRadius: BorderRadius.circular(6)),
                title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.playlist_play, color: AppTheme.primaryAzure),
                title: const Text('Putar Selanjutnya', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.player.addToNext(track);
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ditambahkan untuk diputar selanjutnya!'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.queue_music, color: AppTheme.primaryAzure),
                title: const Text('Tambahkan ke Antrean', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.player.addToQueue(track);
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lagu masuk ke antrean!'), duration: Duration(milliseconds: 900), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Hapus dari Playlist', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(context);
                  _removeTrackFromPlaylist(track);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTracks = _filterQuery.isEmpty
        ? _currentPlaylist.tracks
        : _currentPlaylist.tracks.where((t) {
            final q = _filterQuery.toLowerCase();
            return t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: CustomScrollView(
        slivers: [
          // Collapsible Header Sliver
          SliverAppBar(
            expandedHeight: 330.0,
            pinned: true,
            backgroundColor: const Color(0xFF0A1220),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.share, color: Colors.white70),
                tooltip: 'Salin JSON',
                onPressed: () async {
                  final json = _importer.exportToJson(_currentPlaylist);
                  await Clipboard.setData(ClipboardData(text: json));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('JSON playlist berhasil disalin ke clipboard!'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.add, color: AppTheme.primaryAzure, size: 26),
                tooltip: 'Tambah Lagu',
                onPressed: _openAddSongsModal,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF132A4F),
                      Color(0xFF0E1A30),
                      Color(0xFF080C14),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Artwork with ambient glow
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryAzure.withAlpha(50),
                              blurRadius: 30,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: OptimizedImage(
                          imageUrl: _currentPlaylist.cover,
                          width: 140,
                          height: 140,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _currentPlaylist.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_currentPlaylist.tracks.length} Lagu • $_totalDurationFormatted',
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF16253D),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppTheme.primaryAzure.withAlpha(80)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.surround_sound, size: 13, color: AppTheme.primaryAzure),
                            SizedBox(width: 4),
                            Text(
                              'DOLBY ATMOS • LOSSLESS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Action Toolbar & Search Bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Big Circular Play Button (Electric Azure)
                      GestureDetector(
                        onTap: () => _playAll(shuffle: false),
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: AppTheme.primaryAzure,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryAzure.withAlpha(90),
                                blurRadius: 18,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow, color: Colors.black, size: 32),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Shuffle Button
                      IconButton(
                        icon: const Icon(Icons.shuffle, color: Colors.white70, size: 26),
                        onPressed: () => _playAll(shuffle: true),
                        tooltip: 'Putar Acak',
                      ),
                      // Add Songs Button
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.white70, size: 26),
                        onPressed: _openAddSongsModal,
                        tooltip: 'Tambah Lagu',
                      ),
                      const Spacer(),
                      // Song counter badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141D2D),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Text(
                          '${filteredTracks.length} Lagu',
                          style: const TextStyle(color: AppTheme.primaryAzure, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Search Filter within Playlist
                  if (_currentPlaylist.tracks.length > 5)
                    TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF121B2C),
                        hintText: 'Cari dalam playlist ini...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                        suffixIcon: _filterQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Colors.white38, size: 16),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() => _filterQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onChanged: (val) => setState(() => _filterQuery = val.trim()),
                    ),
                ],
              ),
            ),
          ),

          // Track List
          if (filteredTracks.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(40.0),
                child: Column(
                  children: [
                    const Icon(Icons.music_off, color: Colors.white24, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _filterQuery.isNotEmpty
                          ? 'Tidak ada lagu yang cocok dengan "$_filterQuery"'
                          : 'Playlist ini masih kosong',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _openAddSongsModal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryAzure,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tambah Lagu Sekarang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = filteredTracks[index];
                  final isCurrentlyPlaying = widget.player.currentTrack?.id == track.id;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: isCurrentlyPlaying ? const Color(0xFF14243C) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 22,
                            child: isCurrentlyPlaying
                                ? const Icon(Icons.graphic_eq, color: AppTheme.primaryAzure, size: 18)
                                : Text(
                                    '${index + 1}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                          ),
                          const SizedBox(width: 8),
                          OptimizedImage(
                            imageUrl: track.artwork,
                            width: 44,
                            height: 44,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ],
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isCurrentlyPlaying ? const Color(0xFF00E5FF) : Colors.white,
                          fontSize: 14,
                          fontWeight: isCurrentlyPlaying ? FontWeight.w900 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${track.artist} • ${_formatDuration(track.duration)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
                        onPressed: () => _showTrackMenu(track),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.player.playTrack(track, _currentPlaylist.tracks);
                      },
                    ),
                  );
                },
                childCount: filteredTracks.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}
