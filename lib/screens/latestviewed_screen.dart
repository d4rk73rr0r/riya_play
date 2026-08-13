import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:riya_play/utils/latest_viewed.dart';
import 'package:riya_play/utils/video_launcher.dart';

class LatestViewedScreen extends StatefulWidget {
  const LatestViewedScreen({super.key});

  @override
  State<LatestViewedScreen> createState() => _LatestViewedScreenState();
}

class _LatestViewedScreenState extends State<LatestViewedScreen>
    with SingleTickerProviderStateMixin {
  late final PaginationController<dynamic> _pagination;
  bool _isEditing = false;
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pagination =
        PaginationController<dynamic>(
            fetchPage: _fetchLatestViewedPage,
            idOf: (item) => item['film']['id'],
            onPageLoaded: _precacheImages,
          )
          ..addListener(() => setState(() {}))
          ..init();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  Future<PageResult<dynamic>> _fetchLatestViewedPage(int page) async {
    final response = await ApiService.getLatestViewed(
      page: page,
      perPage: 20,
      isAll: true,
      fields:
          'name_uz,name_ru,name_en,id,films.id,films.name_uz,films.name_ru,films.publish_time,films.type,films.paid,films.year,films.tags.id,films.tags.title_uz,films.tags.title_en,films.files.thumbnails,films.genres.name_uz,films.genres.name_ru,films.genres.name_en',
    );
    final results = response['data'] as List<dynamic>? ?? [];
    final meta = response['_meta'] as Map<String, dynamic>? ?? {};
    final totalCount = (meta['totalCount'] as num?)?.toInt() ?? 0;
    final pageCount = (meta['pageCount'] as num?)?.toInt() ?? 1;
    final hasMore =
        results.isNotEmpty &&
        page < pageCount &&
        _pagination.items.length + results.length < totalCount;
    return PageResult(items: results, hasMore: hasMore);
  }

  void _precacheImages(List<dynamic> items) {
    final visibleItems = items.take(10).toList();
    for (var item in visibleItems) {
      final screenshots = item['screenshots'] as List<dynamic>? ?? [];
      final file =
          screenshots.isNotEmpty
              ? (screenshots[0]['file'] as List<dynamic>?)?.first ?? {}
              : {};
      final imageUrl =
          screenshots.isNotEmpty
              ? (file['thumbnails'] != null &&
                      file['thumbnails']['small'] != null &&
                      file['thumbnails']['small']['src'] != null
                  ? file['thumbnails']['small']['src']
                  : file['link'] ?? 'https://placehold.co/320x180')
              : 'https://placehold.co/320x180';
      precacheImage(
        CachedNetworkImageProvider(imageUrl, cacheManager: filmImagesCacheManager),
        context,
        onError: (exception, stackTrace) {
          appLogger.d('Precache image error: $exception');
        },
      );
    }
  }

  Future<void> _refresh() async {
    await _pagination.refresh();
    if (mounted) {
      setState(() => _isEditing = false);
    }
  }

  void _toggleEditMode() {
    if (mounted) {
      setState(() => _isEditing = !_isEditing);
    }
  }

  Future<void> _removeLatestViewed(int filmId) async {
    appLogger.d('Removing last viewed item with filmId: $filmId');
    // Agar filmId 0 bo‘lsa, xatolik xabarini ko‘rsatamiz
    if (filmId == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Film ID topilmadi")));
      return;
    }

    final success = await ApiService.removeFromLatestViewed(filmId);
    appLogger.d('Remove success: $success');
    if (success && mounted) {
      // `second['film_id']` bilan solishtiramiz
      _pagination.removeWhere((item) => item['second']['film_id'] == filmId);
    } else if (mounted) {
      appLogger.d('Failed to remove filmId: $filmId');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kontentni o'chirishda xatolik")),
      );
    }
  }

  Future<void> _clearLatestViewed() async {
    final success = await ApiService.clearLatestViewed();
    if (success && mounted) {
      _pagination.clear();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Barchasini o'chirishda xatolik")),
      );
    }
  }

  void _showClearAllDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (context) => AnimatedOpacity(
            opacity: 1.0,
            duration: const Duration(milliseconds: 300),
            child: ClearAllDialog(onConfirm: _clearLatestViewed),
          ),
    );
  }

  @override
  void dispose() {
    _pagination.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        title: Text(
          'Ko‘rishni davom ettirish',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: themeProvider.accentColor,
        child: ContentWidget(
          latestviewed: _pagination.items,
          isLoading: _pagination.isLoading,
          error: _pagination.error,
          isEditing: _isEditing,
          hasMore: _pagination.hasMore,
          scrollController: _pagination.scrollController,
          onToggleEditMode: _toggleEditMode,
          onShowClearAllDialog: _showClearAllDialog,
          onRemoveLatestViewed: _removeLatestViewed,
          animationController: _animationController,
          scaleAnimation: _scaleAnimation,
          onRefresh: _refresh,
        ),
      ),
    );
  }
}

class ContentWidget extends StatelessWidget {
  final List<dynamic> latestviewed;
  final bool isLoading;
  final String? error;
  final bool isEditing;
  final bool hasMore;
  final ScrollController scrollController;
  final VoidCallback onToggleEditMode;
  final VoidCallback onShowClearAllDialog;
  final ValueChanged<int> onRemoveLatestViewed;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;
  final Future<void> Function() onRefresh;

  const ContentWidget({
    super.key,
    required this.latestviewed,
    required this.isLoading,
    required this.error,
    required this.isEditing,
    required this.hasMore,
    required this.scrollController,
    required this.onToggleEditMode,
    required this.onShowClearAllDialog,
    required this.onRemoveLatestViewed,
    required this.animationController,
    required this.scaleAnimation,
    required this.onRefresh,
  });

  double calculateMainAxisExtent(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = (screenWidth / 2) - 16; // Padding hisobga olinadi
    final cardHeight = cardWidth * (9 / 16); // 16:9 nisbat
    final extraHeight = 50; // Matnlar uchun qo‘shimcha balandlik
    return cardHeight + extraHeight;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (isLoading && latestviewed.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: themeProvider.accentColor),
      );
    }

    if (latestviewed.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              error ?? "Hozircha so'ngi ko'rilganlar yo'q",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: themeProvider.subTextColor,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRefresh,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("Qayta yuklash"),
            ),
          ],
        ),
      );
    }

    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: PinnedButtonsHeader(
            isEditing: isEditing,
            onToggleEditMode: onToggleEditMode,
            onShowClearAllDialog: onShowClearAllDialog,
            themeProvider: themeProvider,
            animationController: animationController,
            scaleAnimation: scaleAnimation,
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: MediaQuery.of(context).size.width / 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 16 / 9,
              mainAxisExtent: calculateMainAxisExtent(context),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => LatestViewedCard(
                item: latestviewed[index],
                isEditing: isEditing,
                onRemove:
                    () => onRemoveLatestViewed(
                      latestviewed[index]['second']['film_id'],
                    ),
              ),
              childCount: latestviewed.length,
            ),
          ),
        ),
        if (isLoading && latestviewed.isNotEmpty)
          SliverToBoxAdapter(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: CircularProgressIndicator(
                  color: themeProvider.accentColor,
                ),
              ),
            ),
          ),
        if (!hasMore && latestviewed.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: themeProvider.cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: themeProvider.borderColor,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeProvider.shadowColor,
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Text(
                    "Barcha so'ngi ko'rilganlar yuklandi",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: themeProvider.textColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class PinnedButtonsHeader extends SliverPersistentHeaderDelegate {
  final bool isEditing;
  final VoidCallback onToggleEditMode;
  final VoidCallback onShowClearAllDialog;
  final ThemeProvider themeProvider;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;

  PinnedButtonsHeader({
    required this.isEditing,
    required this.onToggleEditMode,
    required this.onShowClearAllDialog,
    required this.themeProvider,
    required this.animationController,
    required this.scaleAnimation,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: themeProvider.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isEditing) ...[
            GestureDetector(
              onTapDown: (_) => animationController.forward(),
              onTapUp: (_) {
                animationController.reverse();
                onShowClearAllDialog();
              },
              onTapCancel: () => animationController.reverse(),
              child: AnimatedBuilder(
                animation: animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: scaleAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            IconlyLight.delete,
                            color: Colors.white,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Barchasini o'chirish",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTapDown: (_) => animationController.forward(),
              onTapUp: (_) {
                animationController.reverse();
                onToggleEditMode();
              },
              onTapCancel: () => animationController.reverse(),
              child: AnimatedBuilder(
                animation: animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: scaleAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: themeProvider.accentColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(IconlyLight.edit, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "O'chirish",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            GestureDetector(
              onTapDown: (_) => animationController.forward(),
              onTapUp: (_) {
                animationController.reverse();
                onToggleEditMode();
              },
              onTapCancel: () => animationController.reverse(),
              child: AnimatedBuilder(
                animation: animationController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: scaleAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: themeProvider.cancelButtonColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            IconlyLight.closeSquare,
                            color: themeProvider.textColor,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Bekor qilish",
                            style: TextStyle(
                              fontSize: 14,
                              color: themeProvider.textColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  double get maxExtent => 56.0;

  @override
  double get minExtent => 56.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

class LatestViewedCard extends StatefulWidget {
  final dynamic item;
  final bool isEditing;
  final VoidCallback onRemove;

  const LatestViewedCard({
    super.key,
    required this.item,
    required this.isEditing,
    required this.onRemove,
  });

  @override
  _LatestViewedCardState createState() => _LatestViewedCardState();
}

class _LatestViewedCardState extends State<LatestViewedCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final film = widget.item['film'] as Map<String, dynamic>? ?? {};
    final screenshots = widget.item['screenshots'] as List<dynamic>? ?? [];
    final file =
        screenshots.isNotEmpty
            ? (screenshots[0]['file'] as List<dynamic>?)?.first ?? {}
            : {};
    final imageUrl =
        screenshots.isNotEmpty
            ? (file['thumbnails'] != null &&
                    file['thumbnails']['small'] != null &&
                    file['thumbnails']['small']['src'] != null
                ? file['thumbnails']['small']['src']
                : file['link'] ?? 'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    // `second['film_id']` — bu film emas, epizod ID si (yonidagi `model`
    // maydoni `common\models\Series` deydi). Film sahifasini ochish uchun
    // yozuvning o'z `film_id` si kerak.
    final filmId = latestViewedFilmId(widget.item);
    final viewedTime = latestViewedSeconds(widget.item);
    final viewedTimeString = formatWatchedTime(viewedTime);
    final double progress = latestViewedProgress(widget.item);
    final year = film['year']?.toString() ?? 'Noma\'lum';
    final genres = film['genres'] as List<dynamic>? ?? [];
    final genre =
        genres.isNotEmpty ? genres[0]['name_uz'] ?? 'Noma\'lum' : 'Noma\'lum';

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        // Bosilganda ko'rish darhol davom etadi; film sahifasi uzoq bosish
        // orqali ochiladi.
        if (!widget.isEditing) {
          VideoLauncher.playFromLatestViewed(context, widget.item);
        }
      },
      onLongPress: () {
        if (widget.isEditing) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => FilmScreen(filmId: filmId)),
        );
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: double.infinity, // Kenglikni to‘liq qamrab oladi
                      height:
                          (MediaQuery.of(context).size.width / 2 - 16) *
                          (9 / 16), // 16:9 nisbat
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: themeProvider.cardColor,
                        border: Border.all(
                          color: themeProvider.borderColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          children: [
                            CachedNetworkImage(
                              imageUrl: imageUrl,
                              cacheManager: filmImagesCacheManager,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height:
                                  double
                                      .infinity, // To‘liq balandlikni qamrab oladi
                              fadeInDuration: const Duration(milliseconds: 300),
                              placeholder:
                                  (context, url) => Container(
                                    color: themeProvider.cardColor,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: themeProvider.accentColor,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                              errorWidget:
                                  (context, url, error) => Container(
                                    color: themeProvider.cardColor,
                                    child: Icon(
                                      Icons.broken_image,
                                      color: themeProvider.subTextColor,
                                      size: 40,
                                    ),
                                  ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      viewedTimeString,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  LinearProgressIndicator(
                                    value: progress.clamp(0.0, 1.0),
                                    backgroundColor: Colors.grey[400],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      themeProvider.accentColor,
                                    ),
                                    minHeight: 3,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (widget.isEditing)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: widget.onRemove,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: themeProvider.accentColor,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: themeProvider.shadowColor,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              IconlyLight.delete,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  film['name_uz'] ?? 'Noma\'lum',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: themeProvider.textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "$year, $genre",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: themeProvider.subTextColor,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class ClearAllDialog extends StatelessWidget {
  final VoidCallback onConfirm;

  const ClearAllDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: themeProvider.borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                IconlyLight.delete,
                color: themeProvider.accentColor,
                size: 24,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Barcha so'ngi ko'rilganlarni o'chirmoqchimisiz?",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: themeProvider.textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                child: const Text("O'chirish"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.cancelButtonColor,
                  foregroundColor: themeProvider.textColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                child: const Text("Bekor qilish"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
