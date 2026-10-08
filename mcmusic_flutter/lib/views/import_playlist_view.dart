import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/playlist.dart';
import '../services/audio_player_manager.dart';
import '../services/playlist_importer_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/optimized_image.dart';

class ImportPlaylistView extends StatefulWidget {
  final AudioPlayerManager player;
  final VoidCallback? onPlaylistImported;

  const ImportPlaylistView({
    super.key,
    required this.player,
    this.onPlaylistImported,
  });

  @override
  State<ImportPlaylistView> createState() => _ImportPlaylistViewState();
}

class _ImportPlaylistViewState extends State<ImportPlaylistView> with SingleTickerProviderStateMixin {
  final PlaylistImporterService _importer = PlaylistImporterService();
  final StorageService _storage = StorageService();

  late final TabController _tabController;
  final TextEditingController _spotifyUrlCtrl = TextEditingController();
  final TextEditingController _youtubeUrlCtrl = TextEditingController();
  final TextEditingController _textCtrl = TextEditingController();
  final TextEditingController _textNameCtrl = TextEditingController(text: 'Playlist Kustom');
  final TextEditingController _jsonCtrl = TextEditingController();

  bool _isProcessing = false;
  String _statusMessage = '';
  double _progressPercent = 0.0;
  String? _errorMessage;

  Playlist? _importedResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _spotifyUrlCtrl.dispose();
    _youtubeUrlCtrl.dispose();
    _textCtrl.dispose();
    _textNameCtrl.dispose();
    _jsonCtrl.dispose();
    super.dispose();
  }

  void _onProgress(int current, int total, String msg) {
    if (mounted) {
      setState(() {
        _progressPercent = total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
        _statusMessage = msg;
      });
    }
  }

  Future<void> _handleImportSpotify() async {
    final url = _spotifyUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Masukkan URL playlist Spotify terlebih dahulu.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _importedResult = null;
      _statusMessage = 'Menghubungkan ke Spotify...';
      _progressPercent = 0.05;
    });

    try {
      final pl = await _importer.importFromSpotify(url, onProgress: _onProgress);
      if (mounted) {
        setState(() {
          _importedResult = pl;
          _isProcessing = false;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleImportYouTube() async {
    final url = _youtubeUrlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _errorMessage = 'Masukkan link playlist YouTube terlebih dahulu.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _importedResult = null;
      _statusMessage = 'Menghubungkan ke YouTube...';
      _progressPercent = 0.05;
    });

    try {
      final pl = await _importer.importFromYouTube(url, onProgress: _onProgress);
      if (mounted) {
        setState(() {
          _importedResult = pl;
          _isProcessing = false;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleImportText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _errorMessage = 'Tempel daftar lagu terlebih dahulu.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _importedResult = null;
      _statusMessage = 'Menganalisis teks lagu...';
      _progressPercent = 0.05;
    });

    try {
      final name = _textNameCtrl.text.trim().isNotEmpty ? _textNameCtrl.text.trim() : 'Playlist Kustom';
      final pl = await _importer.importFromText(text, customName: name, onProgress: _onProgress);
      if (mounted) {
        setState(() {
          _importedResult = pl;
          _isProcessing = false;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _handleImportPreset(Map<String, dynamic> preset) async {
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _importedResult = null;
      _statusMessage = 'Menyiapkan preset "${preset['name']}"...';
      _progressPercent = 0.05;
    });

    try {
      final pl = await _importer.importFromText(
        preset['text'] as String,
        customName: preset['name'] as String,
        onProgress: _onProgress,
      );
      if (mounted) {
        setState(() {
          _importedResult = pl;
          _isProcessing = false;
        });
        HapticFeedback.mediumImpact();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _isProcessing = false;
        });
      }
    }
  }

  void _handleImportJson() {
    final jsonStr = _jsonCtrl.text.trim();
    if (jsonStr.isEmpty) {
      setState(() => _errorMessage = 'Tempel data JSON backup terlebih dahulu.');
      return;
    }

    try {
      final pl = _importer.importFromJson(jsonStr);
      setState(() {
        _importedResult = pl;
        _errorMessage = null;
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _saveImportedPlaylist() async {
    if (_importedResult == null) return;
    final currentPlaylists = await _storage.getPlaylists();
    final updated = [...currentPlaylists, _importedResult!];
    await _storage.savePlaylists(updated);

    widget.onPlaylistImported?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.primaryAzure),
              const SizedBox(width: 8),
              Expanded(child: Text('Playlist "${_importedResult!.name}" berhasil disimpan ke Koleksi!')),
            ],
          ),
          backgroundColor: const Color(0xFF141923),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }
  }

  void _playImportedNow() {
    if (_importedResult == null || _importedResult!.tracks.isEmpty) return;
    _saveImportedPlaylist();
    widget.player.playTrack(_importedResult!.tracks.first, _importedResult!.tracks);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Import Playlist',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF141923),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                color: AppTheme.primaryAzure,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.black,
              unselectedLabelColor: Colors.white70,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.link, size: 16), text: 'Spotify'),
                Tab(icon: Icon(Icons.play_circle_fill, size: 16), text: 'YouTube'),
                Tab(icon: Icon(Icons.notes, size: 16), text: 'Teks'),
                Tab(icon: Icon(Icons.auto_awesome, size: 16), text: 'Preset'),
                Tab(icon: Icon(Icons.data_object, size: 16), text: 'JSON'),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Error Banner
              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withAlpha(40),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withAlpha(120)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60, size: 16),
                        onPressed: () => setState(() => _errorMessage = null),
                      ),
                    ],
                  ),
                ),

              // Processing State Banner with Progress Bar
              if (_isProcessing)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primaryAzure.withAlpha(80)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppTheme.primaryAzure,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _statusMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: _progressPercent > 0 ? _progressPercent : null,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryAzure),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),

              // Result Preview OR Tab Form Input
              Expanded(
                child: _importedResult != null
                    ? _buildResultPreview()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSpotifyTab(),
                          _buildYouTubeTab(),
                          _buildTextTab(),
                          _buildPresetsTab(),
                          _buildJsonTab(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // TAB 1: SPOTIFY
  Widget _buildSpotifyTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Impor Playlist Spotify',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Salin link playlist Spotify publik Anda, lalu tempel di bawah. McMusic akan mencocokkan setiap lagu ke mesin pemutar berdurasi penuh.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _spotifyUrlCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141923),
              hintText: 'https://open.spotify.com/playlist/...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.link, color: AppTheme.primaryAzure),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste, color: AppTheme.primaryAzure, size: 20),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _spotifyUrlCtrl.text = data!.text!;
                  }
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryAzure, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleImportSpotify,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAzure,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.cloud_download, color: Colors.black),
              label: const Text(
                'Mulai Impor dari Spotify',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TAB 2: YOUTUBE
  Widget _buildYouTubeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Impor YouTube Playlist',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tempel link playlist YouTube atau YouTube Music (berisi ?list=...). Seluruh track akan dimuat langsung.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _youtubeUrlCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141923),
              hintText: 'https://youtube.com/playlist?list=...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixIcon: const Icon(Icons.play_circle_fill, color: AppTheme.primaryAzure),
              suffixIcon: IconButton(
                icon: const Icon(Icons.content_paste, color: AppTheme.primaryAzure, size: 20),
                onPressed: () async {
                  final data = await Clipboard.getData('text/plain');
                  if (data?.text != null) {
                    _youtubeUrlCtrl.text = data!.text!;
                  }
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.primaryAzure, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleImportYouTube,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAzure,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.download, color: Colors.black),
              label: const Text(
                'Mulai Impor dari YouTube',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TAB 3: TEXT
  Widget _buildTextTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Impor dari Daftar Teks',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tempel daftar judul lagu baris demi baris (misal: "Artis - Judul" atau "Judul").',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _textNameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141923),
              labelText: 'Nama Playlist',
              labelStyle: const TextStyle(color: AppTheme.primaryAzure, fontSize: 13),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _textCtrl,
            maxLines: 6,
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141923),
              hintText: '1. Coldplay - Yellow\n2. The Weeknd - Blinding Lights\n3. Bernadya - Satu Bulan',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleImportText,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAzure,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.playlist_add, color: Colors.black),
              label: const Text(
                'Konversi & Impor Playlist',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // TAB 4: PRESETS
  Widget _buildPresetsTab() {
    final presets = _importer.getPresets();
    return ListView.builder(
      itemCount: presets.length,
      itemBuilder: (context, index) {
        final p = presets[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF141923),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withAlpha(20)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(10),
            leading: OptimizedImage(
              imageUrl: p['cover'],
              width: 52,
              height: 52,
              borderRadius: BorderRadius.circular(8),
            ),
            title: Text(
              p['name'],
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              p['description'],
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
              maxLines: 2,
            ),
            trailing: ElevatedButton(
              onPressed: _isProcessing ? null : () => _handleImportPreset(p),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAzure,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Impor', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ),
        );
      },
    );
  }

  // TAB 5: JSON
  Widget _buildJsonTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          const Text(
            'Impor dari Backup JSON',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Pulihkan playlist dari file backup JSON yang sebelumnya diekspor dari McMusic.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _jsonCtrl,
            maxLines: 7,
            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 11),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF141923),
              hintText: '{\n  "name": "My Playlist",\n  "tracks": [...]\n}',
              hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.white12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleImportJson,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryAzure,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.restore, color: Colors.black),
              label: const Text(
                'Pulihkan Playlist',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // RESULT PREVIEW
  Widget _buildResultPreview() {
    final res = _importedResult!;
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF141923),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryAzure.withAlpha(80)),
          ),
          child: Row(
            children: [
              OptimizedImage(
                imageUrl: res.cover,
                width: 64,
                height: 64,
                borderRadius: BorderRadius.circular(10),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryAzure.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${res.tracks.length} LAGU PENUH',
                        style: const TextStyle(
                          color: AppTheme.primaryAzure,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      res.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Semua lagu siap diputar dengan durasi penuh',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Action Buttons Row
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _saveImportedPlaylist,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E293B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.bookmark_add, size: 18),
                label: const Text('Simpan Koleksi', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _playImportedNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryAzure,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.play_arrow, size: 20),
                label: const Text('Putar Sekarang', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Track List Preview
        Expanded(
          child: ListView.builder(
            itemCount: res.tracks.length,
            itemBuilder: (context, idx) {
              final t = res.tracks[idx];
              final mins = t.duration ~/ 60;
              final secs = t.duration % 60;
              final durStr = '$mins:${secs < 10 ? '0' : ''}$secs';

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF141923),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${idx + 1}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 10),
                      OptimizedImage(
                        imageUrl: t.artwork,
                        width: 38,
                        height: 38,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        durStr,
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // Reset Button
        TextButton(
          onPressed: () => setState(() => _importedResult = null),
          child: const Text('Impor Playlist Lain', style: TextStyle(color: AppTheme.primaryAzure, fontSize: 12)),
        ),
      ],
    );
  }
}
