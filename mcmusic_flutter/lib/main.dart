import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_player_manager.dart';
import 'services/media_audio_handler.dart';
import 'services/storage_service.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart' as ytp;
import 'theme/app_theme.dart';
import 'views/home_view.dart';
import 'views/library_view.dart';
import 'views/search_view.dart';
import 'views/import_playlist_view.dart';
import 'widgets/mini_player.dart';
import 'widgets/floating_bubble_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  MediaAudioHandler? mediaHandler;
  try {
    mediaHandler = await AudioService.init(
      builder: () => MediaAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.mcmusic.app.channel.audio',
        androidNotificationChannelName: 'McMusic Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init note: $e');
  }

  runApp(McMusicApp(mediaHandler: mediaHandler));
}

class McMusicApp extends StatelessWidget {
  final MediaAudioHandler? mediaHandler;

  const McMusicApp({super.key, this.mediaHandler});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'McMusic',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: MainNavigationScreen(mediaHandler: mediaHandler),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final MediaAudioHandler? mediaHandler;

  const MainNavigationScreen({super.key, this.mediaHandler});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  late final AudioPlayerManager _player;
  final StorageService _storage = StorageService();

  int _currentIndex = 0;
  bool _isLiked = false;
  bool _isBubbleActive = false;
  String? _lastCheckedTrackId;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayerManager(mediaHandler: widget.mediaHandler);
    _player.addListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() async {
    final track = _player.currentTrack;
    if (track != null && track.id != _lastCheckedTrackId) {
      _lastCheckedTrackId = track.id;
      final liked = await _storage.isTrackLiked(track.id);
      if (mounted) {
        setState(() => _isLiked = liked);
      }
    }
  }

  void _toggleLike() async {
    final track = _player.currentTrack;
    if (track != null) {
      await _storage.toggleLikeTrack(track);
      if (mounted) {
        setState(() => _isLiked = !_isLiked);
      }
    }
  }

  @override
  void dispose() {
    _player.removeListener(_onPlayerStateChanged);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeView(player: _player),
      SearchView(player: _player),
      LibraryView(player: _player),
      ImportPlaylistView(player: _player),
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Current Tab View
          IndexedStack(
            index: _currentIndex,
            children: pages,
          ),

          // Official YouTube Audio/Video Engine for Flutter
          if (_player.ytController != null)
            Positioned(
              left: 0,
              top: 0,
              width: 1,
              height: 1,
              child: Opacity(
                opacity: 0.001,
                child: ytp.YoutubePlayer(
                  controller: _player.ytController!,
                ),
              ),
            ),

          // Floating Mini Player (Positioned above Bottom Navigation Bar)
          ListenableBuilder(
            listenable: _player,
            builder: (context, _) {
              if (_player.currentTrack == null) return const SizedBox.shrink();

              return Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MiniPlayer(
                  player: _player,
                  isLiked: _isLiked,
                  onToggleLike: _toggleLike,
                  onToggleBubble: () {
                    setState(() => _isBubbleActive = !_isBubbleActive);
                  },
                  isBubbleActive: _isBubbleActive,
                ),
              );
            },
          ),

          // Spotify-style Draggable Floating Bubble Player Overlay
          ListenableBuilder(
            listenable: _player,
            builder: (context, _) {
              if (!_isBubbleActive || _player.currentTrack == null) {
                return const SizedBox.shrink();
              }

              return FloatingBubblePlayer(
                player: _player,
                isLiked: _isLiked,
                onToggleLike: _toggleLike,
                onClose: () => setState(() => _isBubbleActive = false),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFF0F141C),
        selectedItemColor: AppTheme.primaryAzure,
        unselectedItemColor: AppTheme.textMuted,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_filled),
            label: 'Beranda',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.search),
            label: 'Cari',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.library_music_rounded),
            label: 'Koleksi',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.swap_horizontal_circle_rounded),
            label: 'Impor',
          ),
        ],
      ),
    );
  }
}
