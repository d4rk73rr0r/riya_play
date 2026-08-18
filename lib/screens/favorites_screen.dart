import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme/glass.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/utils/grid_density.dart';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/widgets/poster_card.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
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
            fetchPage:
                (page) async => PageResult(
                  items: await ApiService.getFavorites(page: page),
                ),
            idOf: (film) => film['id'],
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

  void _precacheImages(List<dynamic> films) {
    Future.microtask(() {
      for (var film in films) {
        final coverUrl =
            (film['files'] != null &&
                    film['files'].isNotEmpty &&
                    film['files'][0]['linkAbsolute'] != null)
                ? film['files'][0]['linkAbsolute']
                : 'https://placehold.co/150x150';
        precacheImage(
          CachedNetworkImageProvider(
            coverUrl,
            cacheManager: filmImagesCacheManager,
          ),
          context,
          onError: (_, __) {},
        );
      }
    });
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

  Future<void> _removeFavorite(int filmId) async {
    final success = await ApiService.removeFromFavorite(filmId);
    if (success && mounted) {
      _pagination.removeWhere((film) => film['id'] == filmId);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Kontentni o'chirishda xatolik")),
      );
    }
  }

  Future<void> _clearAllFavorites() async {
    final success = await ApiService.clearAllFavorites();
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
            child: ClearAllDialog(onConfirm: _clearAllFavorites),
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
          'Sevimlilar',
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
          favorites: _pagination.items,
          isLoading: _pagination.isLoading,
          error: _pagination.error,
          isEditing: _isEditing,
          hasMore: _pagination.hasMore,
          scrollController: _pagination.scrollController,
          onToggleEditMode: _toggleEditMode,
          onShowClearAllDialog: _showClearAllDialog,
          onRemoveFavorite: _removeFavorite,
          animationController: _animationController,
          scaleAnimation: _scaleAnimation,
        ),
      ),
    );
  }
}

class ContentWidget extends StatelessWidget {
  final List<dynamic> favorites;
  final bool isLoading;
  final String? error;
  final bool isEditing;
  final bool hasMore;
  final ScrollController scrollController;
  final VoidCallback onToggleEditMode;
  final VoidCallback onShowClearAllDialog;
  final ValueChanged<int> onRemoveFavorite;
  final AnimationController animationController;
  final Animation<double> scaleAnimation;

  const ContentWidget({
    super.key,
    required this.favorites,
    required this.isLoading,
    required this.error,
    required this.isEditing,
    required this.hasMore,
    required this.scrollController,
    required this.onToggleEditMode,
    required this.onShowClearAllDialog,
    required this.onRemoveFavorite,
    required this.animationController,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (isLoading && favorites.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: themeProvider.accentColor),
      );
    }

    if (favorites.isEmpty) {
      return Center(
        child: Text(
          error ?? "Hozircha sevimli kontentlar yo'q",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w500,
            color: themeProvider.subTextColor,
          ),
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
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              // Ustunlar soni Profil bo'limidagi 2x2 / 3x3 sozlamasidan.
              crossAxisCount:
                  Provider.of<GridDensityProvider>(context).columns,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => FavoriteCard(
                film: favorites[index],
                isEditing: isEditing,
                onRemove: () => onRemoveFavorite(favorites[index]['id']),
              ),
              childCount: favorites.length,
            ),
          ),
        ),
        if (isLoading && favorites.isNotEmpty)
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
        if (!hasMore && favorites.isNotEmpty)
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
                    "Barcha sevimli kontentlar yuklandi",
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

class FavoriteCard extends StatelessWidget {
  final dynamic film;
  final bool isEditing;
  final VoidCallback onRemove;

  const FavoriteCard({
    super.key,
    required this.film,
    required this.isEditing,
    required this.onRemove,
  });

  String _getGenresText(List<dynamic> genres) {
    if (genres.isEmpty) return 'Noma\'lum';
    return genres.map((genre) => genre['name_uz'] ?? 'Noma\'lum').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final coverUrl =
        (film['files'] != null &&
                film['files'].isNotEmpty &&
                film['files'][0]['linkAbsolute'] != null)
            ? film['files'][0]['linkAbsolute']
            : 'https://placehold.co/150x150';

    return PosterCard(
      imageUrl: coverUrl,
      title: film['name_uz'] ?? 'Noma\'lum',
      heroTag: 'favorites_${film['id']}',
      subtitle:
          "${film['year'] ?? 'Noma\'lum'} · ${_getGenresText(film['genres'] ?? [])}",
      onTap:
          isEditing
              ? () {}
              : () => Navigator.push(
                context,
                createSlideRoute(
                  FilmScreen(
                    filmId: film['id'],
                    heroTag: 'favorites_${film['id']}',
                  ),
                ),
              ),
      badge:
          isEditing
              ? GestureDetector(
                onTap: onRemove,
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
              )
              : null,
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
      // Pastdan chiqadigan oyna tizim navigatsiya paneli ostidan boshlanadi,
      // shuning uchun tugmalar uning ustiga tushib qolmasin.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: GlassSurface.gradient,
        borderRadius: GlassSurface.sheetBorderRadius,
        border: GlassSurface.sheetBorder,
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
                  "Hammasini o'chirmoqchimisiz?",
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
