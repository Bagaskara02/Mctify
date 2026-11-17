import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'services/audio_player_manager.dart';
import 'services/audio_proxy_server.dart';
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

  // Pre-warm local AudioProxyServer socket so initial song play starts immediately
  if (!kIsWeb) {
    try {
      unawaited(AudioProxyServer.instance.ensureStarted());
    } catch (_) {}
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
                _buildIosLiquidGlassNavbar()
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

  /// Liquid Glass floating dock navbar exclusively for iOS (ref: iOS Liquid Glass / BetaProfiles)
  /// Features optical frosted glass with specular highlight refraction and fluid sliding glass pill animation.
  Widget _buildIosLiquidGlassNavbar() {
    final navItems = [
      (Icons.home_outlined, Icons.home_filled, 'Beranda'),
      (Icons.search_rounded, Icons.search_rounded, 'Cari'),
      (Icons.library_music_outlined, Icons.library_music_rounded, 'Koleksi'),
      (Icons.swap_horizontal_circle_outlined, Icons.swap_horizontal_circle_rounded, 'Impor'),
    ];

    const double dockHeight = 56.0;
    const double pillHeight = 42.0;

    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18, bottom: 8, top: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(35),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: dockHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(35),
              // Dual-layer specular refraction gradient border (glows brighter at top edge like genuine curved liquid glass)
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.38),
                  Colors.white.withValues(alpha: 0.14),
                  Colors.white.withValues(alpha: 0.06),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 26,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(1.0), // 1px specular gradient rim
            child: Container(
              decoration: BoxDecoration(
                // Semi-translucent dark liquid acrylic tint
                color: const Color(0xB813151D),
                borderRadius: BorderRadius.circular(34),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final slotWidth = totalWidth / navItems.length;
                  final pillWidth = slotWidth - 12;

                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // 1. Fluid Sliding Liquid Glass Pill Glider (morphs & slides smoothly across tabs)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeOutBack,
                        left: _currentIndex * slotWidth + 6,
                        top: (dockHeight - 2.0 - pillHeight) / 2,
                        width: pillWidth,
                        height: pillHeight,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(21),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF3E4350),
                                Color(0xFF262832),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.26),
                              width: 1.0,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.08),
                                blurRadius: 3,
                                offset: const Offset(0, -1),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Tab Items Row with interactive scale bounce & haptic feedback
                      Row(
                        children: List.generate(navItems.length, (idx) {
                          final isSelected = _currentIndex == idx;
                          final (unselectedIcon, selectedIcon, _) = navItems[idx];

                          return Expanded(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _currentIndex = idx);
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Center(
                                child: AnimatedScale(
                                  scale: isSelected ? 1.15 : 0.94,
                                  duration: const Duration(milliseconds: 280),
                                  curve: Curves.easeOutBack,
                                  child: AnimatedOpacity(
                                    opacity: isSelected ? 1.0 : 0.65,
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      isSelected ? selectedIcon : unselectedIcon,
                                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.82),
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
