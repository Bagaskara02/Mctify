import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/audio_player_manager.dart';
import '../services/music_api_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import 'optimized_image.dart';

void showImportYouTubeDialog({
  required BuildContext context,
  required AudioPlayerManager player,
  VoidCallback? onPlaylistModified,
}) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF181818),
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ImportYouTubeDialogContent(
      player: player,
      onPlaylistModified: onPlaylistModified,
    ),
  );
}

class _ImportYouTubeDialogContent extends StatefulWidget {
  final AudioPlayerManager player;
  final VoidCallback? onPlaylistModified;

  const _ImportYouTubeDialogContent({
    required this.player,
    this.onPlaylistModified,
  });

  @override
  State<_ImportYouTubeDialogContent> createState() => _ImportYouTubeDialogContentState();
}

class _ImportYouTubeDialogContentState extends State<_ImportYouTubeDialogContent> {
  final TextEditingController _controller = TextEditingController();
  final MusicApiService _apiService = MusicApiService();
  final StorageService _storageService = StorageService();

  bool _isLoading = false;
  String? _errorMessage;
  Track? _resolvedTrack;
  String? _actionStatus; // 'played' | 'next' | 'queue' | 'liked'
  List<Playlist> _playlists = [];

  void _handlePlayNow() {
    if (_resolvedTrack == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _actionStatus = 'played');
    widget.player.playTrack(_resolvedTrack!);
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _handlePlayNext() {
    if (_resolvedTrack == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _actionStatus = 'next');
    final messenger = ScaffoldMessenger.maybeOf(context);
    widget.player.addToNext(_resolvedTrack!);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('"${_resolvedTrack!.title}" akan diputar setelah lagu ini'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) Navigator.pop(context);
    });
  }

  void _handleAddToQueue() {
    if (_resolvedTrack == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _actionStatus = 'queue');
    final messenger = ScaffoldMessenger.maybeOf(context);
    widget.player.addToQueue(_resolvedTrack!);
    messenger?.showSnackBar(
      SnackBar(
        content: Text('"${_resolvedTrack!.title}" dimasukkan ke antrean'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> _handleToggleLike() async {
    if (_resolvedTrack == null) return;
    HapticFeedback.selectionClick();
    await _storageService.toggleLikeTrack(_resolvedTrack!);
    if (mounted) {
      setState(() => _actionStatus = 'liked');
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text('"${_resolvedTrack!.title}" disimpan ke favorit!'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  void _loadPlaylists() async {
    final list = await _storageService.getPlaylists();
    if (mounted) {
      setState(() => _playlists = list);
    }
  }

  void _showPlaylistPicker(Track track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              const Text('Pilih Playlist', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_playlists.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Belum ada playlist yang dibuat.', style: TextStyle(color: AppTheme.textMuted)),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _playlists.length,
                    itemBuilder: (ctx, idx) {
                      final pl = _playlists[idx];
                      return ListTile(
                        leading: const Icon(Icons.queue_music, color: AppTheme.primaryAzure),
                        title: Text(pl.name, style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${pl.tracks.length} lagu', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        onTap: () async {
                          Navigator.pop(sheetCtx);
                          await _storageService.addTrackToPlaylist(pl.id, track);
                          widget.onPlaylistModified?.call();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('"${track.title}" ditambahkan ke ${pl.name}'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!.trim();
      _handleResolve();
    }
  }

  Future<void> _handleResolve() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resolvedTrack = null;
      _actionStatus = null;
    });

    try {
      final track = await _apiService.resolveYouTubeImport(text);
      if (mounted) {
        if (track != null) {
          setState(() {
            _resolvedTrack = track;
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = 'Lagu tidak ditemukan dari link YouTube ini. Pastikan link video publik & valid.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Gagal memuat video: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: bottomInset),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Drag handle
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

          // Header
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.play_circle_filled, color: Colors.red, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Import Lagu dari YouTube',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Putar lagu apa saja dari link YouTube / video ID',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Text Field & Paste Button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.go,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tempel link YouTube (https://youtu.be/...)',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF242424),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: AppTheme.primaryAzure, width: 1.5),
                    ),
                  ),
                  onSubmitted: (_) => _handleResolve(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Tempel dari Clipboard',
                icon: const Icon(Icons.content_paste, color: AppTheme.primaryAzure),
                onPressed: _handlePaste,
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAzure,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: _isLoading ? null : _handleResolve,
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('Cari', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_resolvedTrack != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1C2230),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: OptimizedImage(
                          imageUrl: _resolvedTrack!.artwork,
                          width: 54,
                          height: 54,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'YouTube Stream',
                                style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _resolvedTrack!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text(
                              _resolvedTrack!.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white10, height: 1),
                  const SizedBox(height: 8),

                  // 1. Primary Playback Buttons (Putar Sekarang & Setelah Ini)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _actionStatus == 'played' ? const Color(0xFF10B981) : AppTheme.primaryAzure,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(
                            _actionStatus == 'played' ? Icons.check_circle : Icons.play_arrow_rounded,
                            size: 20,
                            color: Colors.black,
                          ),
                          label: Text(
                            _actionStatus == 'played' ? 'Sedang Diputar' : 'Putar Sekarang',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                          onPressed: _handlePlayNow,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _actionStatus == 'next' ? AppTheme.primaryAzure : Colors.white,
                            side: BorderSide(
                              color: _actionStatus == 'next' ? AppTheme.primaryAzure : Colors.white24,
                              width: 1.2,
                            ),
                            backgroundColor: _actionStatus == 'next' ? AppTheme.primaryAzure.withValues(alpha: 0.12) : const Color(0xFF242424),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(
                            _actionStatus == 'next' ? Icons.check : Icons.playlist_play_rounded,
                            color: AppTheme.primaryAzure,
                            size: 20,
                          ),
                          label: Text(
                            _actionStatus == 'next' ? 'Setelah Ini' : 'Putar Berikutnya',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          onPressed: _handlePlayNext,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // 2. Dedicated Full-Width "Masukkan ke Antrean" Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _actionStatus == 'queue' ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF242A38),
                        foregroundColor: _actionStatus == 'queue' ? const Color(0xFF34D399) : Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(
                          color: _actionStatus == 'queue' ? const Color(0xFF10B981) : AppTheme.primaryAzure.withValues(alpha: 0.35),
                          width: 1.2,
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(
                        _actionStatus == 'queue' ? Icons.check_circle_rounded : Icons.queue_music_rounded,
                        size: 20,
                        color: _actionStatus == 'queue' ? const Color(0xFF34D399) : AppTheme.primaryAzure,
                      ),
                      label: Text(
                        _actionStatus == 'queue' ? '✓ Dimasukkan ke Antrean' : 'Masukkan ke Antrean',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: _actionStatus == 'queue' ? const Color(0xFF34D399) : Colors.white,
                        ),
                      ),
                      onPressed: _handleAddToQueue,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 3. Secondary Actions (Tambah ke Playlist & Sukai Lagu)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white12),
                            backgroundColor: const Color(0xFF1E1E24),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.playlist_add_rounded, color: AppTheme.primaryAzure, size: 18),
                          label: const Text('Ke Playlist', style: TextStyle(fontSize: 12)),
                          onPressed: () => _showPlaylistPicker(_resolvedTrack!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _actionStatus == 'liked' ? AppTheme.primaryAzure : Colors.white,
                            side: BorderSide(
                              color: _actionStatus == 'liked' ? AppTheme.primaryAzure : Colors.white12,
                            ),
                            backgroundColor: const Color(0xFF1E1E24),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(
                            _actionStatus == 'liked' ? Icons.favorite : Icons.favorite_border_rounded,
                            color: _actionStatus == 'liked' ? AppTheme.primaryAzure : Colors.white70,
                            size: 18,
                          ),
                          label: Text(
                            _actionStatus == 'liked' ? 'Tersimpan' : 'Sukai Lagu',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed: _handleToggleLike,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  ),
);
  }
}
