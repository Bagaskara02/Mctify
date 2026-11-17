import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'services/audio_player_manager.dart';
import 'services/equalizer_service.dart';
import 'services/media_audio_handler.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';
import 'views/library_view.dart';
import 'views/search_view.dart';
import 'views/import_playlist_view.dart';
import 'widgets/mini_player.dart';
import 'widgets/floating_bubble_player.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure AudioSession for iOS background audio & silent switch override
  if (!kIsWeb && Platform.isIOS) {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
    } catch (e) {
      debugPrint('AudioSession init note: $e');
    }
  }

  MediaAudioHandler? mediaHandler;
  try {
    mediaHandler = await AudioService.init(
      builder: () => MediaAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.mcmusic.app.channel.audio',
        androidNotificationChannelName: 'McTify Playback',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
        androidNotificationIcon: 'mipmap/ic_launcher',
      ),
    );
  } catch (e) {
    debugPrint('AudioService init note: $e');
  }

  runApp(McTifyApp(mediaHandler: mediaHandler));
}

class McTifyApp extends StatelessWidget {
  final MediaAudioHandler? mediaHandler;

  const McTifyApp({super.key, this.mediaHandler});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'McTify',
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
    // Cold start pre-warm: ensure persisted equalizer settings are restored immediately
    EqualizerService.instance;
    _checkBatteryOptimizations();
  }

  Future<void> _checkBatteryOptimizations() async {
    try {
      const channel = MethodChannel('com.mcmusic.app/wakelock');
      final isIgnoring = await channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (isIgnoring == false) {
        await channel.invokeMethod('requestIgnoreBatteryOptimizations');
      }
    } catch (_) {}
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
      ImportPlaylistView(
        player: _player,
        onPlaylistImported: () {
          setState(() {
            _currentIndex = 2; // Auto-switch to Library (Koleksi) so imported playlist is visible immediately!
          });
        },
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          // Current Tab View
          IndexedStack(
            index: _currentIndex,
            children: pages,
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.0),
              Colors.black.withValues(alpha: 0.85),
              Colors.black.withValues(alpha: 0.98),
              Colors.black,
            ],
            stops: const [0.0, 0.22, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Floating Mini Player (Seamlessly docked right above Bottom Navigation Bar)
              ListenableBuilder(
                listenable: _player,
                builder: (context, _) {
                  if (_player.currentTrack == null) return const SizedBox.shrink();

                  return MiniPlayer(
                    player: _player,
                    isLiked: _isLiked,
                    onToggleLike: _toggleLike,
                    onToggleBubble: () {
                      setState(() => _isBubbleActive = !_isBubbleActive);
                    },
                    isBubbleActive: _isBubbleActive,
                  );
                },
              ),
              if (!kIsWeb && Platform.isIOS)
                _buildIosInstagramNavbar()
              else
                BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  HapticFeedback.selectionClick();
                  setState(() => _currentIndex = index);
                },
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: Colors.white,
                unselectedItemColor: AppTheme.textMuted,
                selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                items: const [
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.home_outlined, size: 24),
                    ),
                    activeIcon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.home_filled, color: AppTheme.primaryAzure, size: 25),
                    ),
                    label: 'Beranda',
                  ),
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.search, size: 24),
                    ),
                    activeIcon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.search_rounded, color: AppTheme.primaryAzure, size: 25),
                    ),
                    label: 'Cari',
                  ),
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.library_music_outlined, size: 24),
                    ),
                    activeIcon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.library_music_rounded, color: AppTheme.primaryAzure, size: 25),
                    ),
                    label: 'Koleksi',
                  ),
                  BottomNavigationBarItem(
                    icon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.swap_horizontal_circle_outlined, size: 24),
                    ),
                    activeIcon: Padding(
                      padding: EdgeInsets.only(bottom: 2),
                      child: Icon(Icons.swap_horizontal_circle_rounded, color: AppTheme.primaryAzure, size: 25),
                    ),
                    label: 'Impor',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Custom Instagram-style floating capsule navbar exclusively for iOS
  Widget _buildIosInstagramNavbar() {
    final navItems = [
      (Icons.home_outlined, Icons.home_filled, 'Beranda'),
      (Icons.search_rounded, Icons.search_rounded, 'Cari'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Koleksi'),
      (Icons.swap_horizontal_circle_outlined, Icons.swap_horizontal_circle_rounded, 'Impor'),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 20, right: 20, bottom: 8, top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xE614161C),
              borderRadius: BorderRadius.circular(35),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.14),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(navItems.length, (idx) {
                final isSelected = _currentIndex == idx;
                final (unselectedIcon, selectedIcon, _) = navItems[idx];

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _currentIndex = idx);
                  },
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    padding: isSelected
                        ? const EdgeInsets.symmetric(horizontal: 22, vertical: 8)
                        : const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF383838) : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Icon(
                      isSelected ? selectedIcon : unselectedIcon,
                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.72),
                      size: isSelected ? 24 : 23,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
