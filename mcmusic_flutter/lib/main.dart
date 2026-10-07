import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_player_manager.dart';
import 'services/media_audio_handler.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';
import 'views/library_view.dart';
import 'views/search_view.dart';
import 'widgets/mini_player.dart';

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
    ];

    return Scaffold(
      body: Stack(
        children: [
          // Current Tab View
          IndexedStack(
            index: _currentIndex,
            children: pages,
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
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
            icon: Icon(Icons.library_music),
            label: 'Koleksi',
          ),
        ],
      ),
    );
  }
}
