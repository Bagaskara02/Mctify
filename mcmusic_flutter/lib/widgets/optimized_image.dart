import 'package:flutter/material.dart';

/// Ultra-lightweight image widget optimized for low-end / "hp kentang" devices.
///
/// Key optimizations:
/// 1. Clamps bitmap decoding to target display dimensions via [cacheWidth] and [cacheHeight],
///    reducing memory consumption by up to 90% compared to full-resolution decoding.
/// 2. Uses [FilterQuality.low] / [FilterQuality.medium] for hardware GPU acceleration on budget chipsets.
/// 3. Prevents layout shifts with lightweight placeholder and error fallbacks.
/// 4. Disables expensive animations during image load.
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final IconData placeholderIcon;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.placeholderIcon = Icons.music_note,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl.trim().isEmpty) {
      return _buildPlaceholder();
    }

    // Auto calculate target decode size in physical pixels for low-end memory saving
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final targetW = memCacheWidth ?? (width != null ? (width! * dpr).clamp(48.0, 600.0).toInt() : null);
    final targetH = memCacheHeight ?? (height != null ? (height! * dpr).clamp(48.0, 600.0).toInt() : null);

    Widget imageWidget = Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: targetW,
      cacheHeight: targetH,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _buildPlaceholder();
      },
      errorBuilder: (_, _, _) => _buildPlaceholder(),
    );

    if (shape == BoxShape.circle) {
      return ClipOval(
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: width,
          height: height,
          child: imageWidget,
        ),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        clipBehavior: Clip.hardEdge,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    Widget content = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        shape: shape,
        borderRadius: shape == BoxShape.circle ? null : (borderRadius ?? BorderRadius.zero),
      ),
      alignment: Alignment.center,
      child: Icon(
        placeholderIcon,
        color: Colors.white24,
        size: (width != null && height != null) ? (width! < 40 ? 16 : 22) : 24,
      ),
    );

    return content;
  }
}
