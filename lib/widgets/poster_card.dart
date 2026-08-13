import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/theme/app_dimens.dart';
import 'package:riya_play/utils/image_cache_manager.dart';

/// Netflix-style poster tile: the artwork fills the whole card and the
/// title/subtitle sit inside a bottom gradient scrim directly over the
/// image, instead of a separate text footer below a smaller thumbnail.
/// [badge] is an optional top-right slot (favorite heart, "last seen" tag,
/// quality label, ...).
class PosterCard extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? badge;

  /// Must be unique among every Hero simultaneously mounted on this route
  /// (Flutter throws if two Heroes on the same route share a tag). Leave
  /// null to skip the poster-to-detail transition animation entirely —
  /// safest default for screens that can show the same film twice at once
  /// (e.g. a "browse everything" tab next to a per-category tab).
  final String? heroTag;

  const PosterCard({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.heroTag,
  });

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildImage(ThemeProvider themeProvider) {
    final image = CachedNetworkImage(
      imageUrl: widget.imageUrl,
      cacheManager: filmImagesCacheManager,
      fit: BoxFit.cover,
      maxWidthDiskCache: 300,
      maxHeightDiskCache: 400,
      fadeInDuration: const Duration(milliseconds: 250),
      placeholder: (context, url) => Container(color: themeProvider.cardColor),
      errorWidget:
          (context, url, error) => Container(
            color: themeProvider.cardColor,
            child: Icon(Icons.broken_image, color: themeProvider.subTextColor),
          ),
    );
    return widget.heroTag == null
        ? image
        : Hero(tag: widget.heroTag!, child: image);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder:
            (context, child) =>
                Transform.scale(scale: _scale.value, child: child),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(themeProvider),
              // Rasm ustidagi matnni o'qish uchun pastki qorong'ilashtirish
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.45, 1.0],
                      colors: [Colors.transparent, Color(0xE6000000)],
                    ),
                  ),
                ),
              ),
              if (widget.badge != null)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: widget.badge!,
                ),
              Positioned(
                left: AppSpacing.sm,
                right: AppSpacing.sm,
                bottom: AppSpacing.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xBFFFFFFF),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
