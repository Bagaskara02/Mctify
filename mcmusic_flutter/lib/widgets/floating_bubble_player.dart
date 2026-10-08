import 'package:flutter/material.dart';
import '../models/track.dart';
import '../services/audio_player_manager.dart';
import '../theme/app_theme.dart';
import 'fullscreen_player.dart';
import 'optimized_image.dart';

/// Spotify-style Draggable Floating Bubble Player (Bubble Play).
/// Can be dragged anywhere on the screen, docks gracefully to edges,
/// features a rotating artwork disc when playing, quick play/pause,
/// and double-tap to skip / triple-tap to undo previous track.
class FloatingBubblePlayer extends StatefulWidget {
  final AudioPlayerManager player;
  final bool isLiked;
  final VoidCallback onToggleLike;
  final VoidCallback onClose;

  const FloatingBubblePlayer({
    super.key,
    required this.player,
    required this.isLiked,
    required this.onToggleLike,
    required this.onClose,
  });

  @override
  State<FloatingBubblePlayer> createState() => _FloatingBubblePlayerState();
}

class _FloatingBubblePlayerState extends State<FloatingBubblePlayer>
    with SingleTickerProviderStateMixin {
  Offset _position = const Offset(20, 160);
  bool _isExpanded = false;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );
    if (widget.player.isPlaying) {
      _rotationController.repeat();
    }
    widget.player.addListener(_onPlayerStateChanged);
  }

  void _onPlayerStateChanged() {
    if (widget.player.isPlaying && !_rotationController.isAnimating) {
      _rotationController.repeat();
    } else if (!widget.player.isPlaying && _rotationController.isAnimating) {
      _rotationController.stop();
    }
  }

  @override
  void dispose() {
    widget.player.removeListener(_onPlayerStateChanged);
    _rotationController.dispose();
    super.dispose();
  }

  void _snapToEdge(Size screenSize) {
    const bubbleSize = 64.0;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    double targetX = _position.dx < (screenWidth / 2) ? 16.0 : (screenWidth - bubbleSize - 16.0);
    double targetY = _position.dy.clamp(60.0, screenHeight - 160.0);

    setState(() {
      _position = Offset(targetX, targetY);
    });
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final screenSize = MediaQuery.of(context).size;

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onPanEnd: (_) => _snapToEdge(screenSize),
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        onDoubleTap: () => widget.player.next(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E).withAlpha(240),
            borderRadius: BorderRadius.circular(_isExpanded ? 24 : 34),
            border: Border.all(
              color: AppTheme.primaryAzure.withAlpha(widget.player.isPlaying ? 140 : 50),
              width: 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.player.isPlaying
                    ? AppTheme.primaryAzure.withAlpha(60)
                    : Colors.black.withAlpha(160),
                blurRadius: 18,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: EdgeInsets.symmetric(
            horizontal: _isExpanded ? 12 : 6,
            vertical: 6,
          ),
          child: _isExpanded
              ? _buildExpandedControls(track)
              : _buildCompactBubble(track),
        ),
      ),
    );
  }

  Widget _buildCompactBubble(Track track) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Spinning Vinyl Artwork
        Stack(
          alignment: Alignment.center,
          children: [
            RotationTransition(
              turns: _rotationController,
              child: Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black,
                ),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: OptimizedImage(
                    imageUrl: track.artwork,
                    width: 48,
                    height: 48,
                  ),
                ),
              ),
            ),
            // Mini center vinyl hole
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 1.5),
              ),
            ),
          ],
        ),

        const SizedBox(width: 6),

        // Mini Play/Pause button
        IconButton(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: Icon(
            widget.player.isPlaying ? Icons.pause : Icons.play_arrow,
            color: AppTheme.primaryAzure,
            size: 26,
          ),
          onPressed: () => widget.player.togglePlayPause(),
        ),
      ],
    );
  }

  Widget _buildExpandedControls(Track track) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Mini Artwork
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: OptimizedImage(
            imageUrl: track.artwork,
            width: 44,
            height: 44,
          ),
        ),
        const SizedBox(width: 10),

        // Title & Artist
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 8),

        // Previous (Undo)
        IconButton(
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.skip_previous, color: Colors.white, size: 20),
          onPressed: () => widget.player.previous(),
        ),

        // Play/Pause
        IconButton(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: EdgeInsets.zero,
          icon: Icon(
            widget.player.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: AppTheme.primaryAzure,
            size: 32,
          ),
          onPressed: () => widget.player.togglePlayPause(),
        ),

        // Next
        IconButton(
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.skip_next, color: Colors.white, size: 20),
          onPressed: () => widget.player.next(),
        ),

        // Expand to Fullscreen
        IconButton(
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.open_in_full, color: Colors.white70, size: 16),
          onPressed: () {
            setState(() => _isExpanded = false);
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => FullscreenPlayer(
                player: widget.player,
                isLiked: widget.isLiked,
                onToggleLike: widget.onToggleLike,
              ),
            );
          },
        ),

        // Close bubble
        IconButton(
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.close, color: Colors.white38, size: 16),
          onPressed: widget.onClose,
        ),
      ],
    );
  }
}
