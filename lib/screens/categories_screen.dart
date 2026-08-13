import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/widgets/poster_card.dart';
import 'package:riya_play/widgets/poster_grid_skeleton.dart';
import 'package:riya_play/theme/app_dimens.dart';

class CategoriesScreen extends StatefulWidget {
  final Map<String, dynamic>? initialCategory;

  const CategoriesScreen({super.key, this.initialCategory});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  static const int _perPage = 20;
  List<dynamic> _categories = [];
  dynamic _selectedCategory;
  bool _isLoadingCategories = false;
  String? _categoriesError;
  late final PaginationController<dynamic> _pagination;

  @override
  void initState() {
    super.initState();
    _pagination =
        PaginationController<dynamic>(
            fetchPage: _fetchFilmsPage,
            onPageLoaded: _precacheImages,
            onError: (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiErrorHandler.handle(e).userMessage)),
                );
              }
            },
          )
          ..addListener(() => setState(() {}))
          ..init(loadImmediately: false);
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    if (!mounted) return;
    setState(() {
      _isLoadingCategories = true;
      _categoriesError = null;
    });

    try {
      final response = await ApiService.getCategories();
      if (!mounted) return;

      setState(() {
        _categories = response['data'] ?? [];
        _isLoadingCategories = false;

        if (_categories.isNotEmpty) {
          _selectedCategory =
              widget.initialCategory != null
                  ? _categories.firstWhere(
                    (category) =>
                        category['id'] == widget.initialCategory!['id'],
                    orElse: () => _categories.first,
                  )
                  : _categories.first;
        } else {
          _categoriesError = "Kategoriyalar mavjud emas";
        }
      });
      if (_selectedCategory != null) {
        _pagination.loadInitial();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingCategories = false;
        _categoriesError = "Kategoriyalarni yuklashda xato: $e";
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiErrorHandler.handle(e).userMessage)),
      );
    }
  }

  Future<PageResult<dynamic>> _fetchFilmsPage(int page) async {
    final response = await ApiService.getFilmsByCategory(
      categoryId: _selectedCategory['id'],
      page: page,
      perPage: _perPage,
    );

    final newFilms = response['data'] as List<dynamic>? ?? [];
    final meta = response['meta'] is Map ? response['meta'] : {};

    bool hasMore;
    if (meta['currentPage'] != null && meta['pageCount'] != null) {
      final current = int.tryParse(meta['currentPage'].toString()) ?? 1;
      final total = int.tryParse(meta['pageCount'].toString()) ?? 1;
      hasMore = current < total;
    } else {
      hasMore = newFilms.length == _perPage;
    }
    if (!hasMore) HapticFeedback.mediumImpact();
    return PageResult(items: newFilms, hasMore: hasMore);
  }

  void _selectCategory(dynamic category) {
    setState(() => _selectedCategory = category);
    _pagination.refresh();
  }

  void _precacheImages(List<dynamic> films) {
    for (var film in films.take(10)) {
      String coverUrl = 'https://placehold.co/320x180';
      if (film['files'] != null && film['files'].isNotEmpty) {
        final file = film['files'][0];
        if (file['thumbnails'] != null &&
            file['thumbnails']['small'] != null &&
            file['thumbnails']['small']['src'] != null) {
          coverUrl = file['thumbnails']['small']['src'];
        } else if (file['link'] != null) {
          coverUrl = file['link'];
        }
      }
      precacheImage(
        CachedNetworkImageProvider(coverUrl, cacheManager: filmImagesCacheManager),
        context,
      );
    }
  }

  Future<void> _onRefresh() async {
    await _pagination.refresh();
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
          widget.initialCategory?['title_uz'] ?? "Kategoriyalar",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
        leading: IconButton(
          icon: Icon(IconlyLight.arrowLeft, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          color: themeProvider.accentColor,
          child: CustomScrollView(
            controller: _pagination.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child:
                      _categories.isNotEmpty && widget.initialCategory == null
                          ? SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              itemCount: _categories.length,
                              itemBuilder: (context, index) {
                                final category = _categories[index];
                                final isSelected =
                                    category['id'] == _selectedCategory?['id'];
                                return GestureDetector(
                                  onTap: () => _selectCategory(category),
                                  child: Container(
                                    margin: const EdgeInsets.only(right: 12),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          isSelected
                                              ? themeProvider.accentColor
                                              : themeProvider.cardColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: themeProvider.borderColor,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: themeProvider.shadowColor,
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        category['title_uz'] ?? 'Noma’lum',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color:
                                              isSelected
                                                  ? Colors.white
                                                  : themeProvider.textColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                          : const SizedBox.shrink(),
                ),
              ),
              if ((_isLoadingCategories || _pagination.isLoading) &&
                  _pagination.items.isEmpty)
                const SliverToBoxAdapter(child: PosterGridSkeleton()),
              if (!_isLoadingCategories &&
                  !_pagination.isLoading &&
                  _pagination.items.isEmpty &&
                  (_categoriesError ?? _pagination.error) != null)
                SliverToBoxAdapter(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          (_categoriesError ?? _pagination.error)!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: themeProvider.subTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchCategories,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: themeProvider.accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 5,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          child: const Text("Qayta urinish"),
                        ),
                      ],
                    ),
                  ),
                ),
              if (!_isLoadingCategories &&
                  !_pagination.isLoading &&
                  _pagination.items.isEmpty &&
                  (_categoriesError ?? _pagination.error) == null)
                SliverToBoxAdapter(
                  child: Center(
                    child: Text(
                      "Filmlar mavjud emas",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: themeProvider.subTextColor,
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: AppSpacing.md,
                    mainAxisSpacing: AppSpacing.md,
                    childAspectRatio: 0.65,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        FilmCard(film: _pagination.items[index]),
                    childCount: _pagination.items.length,
                  ),
                ),
              ),
              if (_pagination.isLoading && _pagination.items.isNotEmpty)
                const SliverToBoxAdapter(child: PosterGridSkeleton()),
              if (!_pagination.hasMore && _pagination.items.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
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
                          "Barcha filmlar ko‘rsatildi",
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
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pagination.dispose();
    super.dispose();
  }
}

class FilmCard extends StatelessWidget {
  final dynamic film;

  const FilmCard({super.key, required this.film});

  @override
  Widget build(BuildContext context) {
    final files = film['files'] ?? [];
    final imageUrl =
        files.isNotEmpty
            ? (files[0]['thumbnails'] != null &&
                    files[0]['thumbnails']['small'] != null &&
                    files[0]['thumbnails']['small']['src'] != null
                ? files[0]['thumbnails']['small']['src']
                : files[0]['link'] ?? 'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    final title = film['name_uz'] ?? 'Noma’lum';
    final year = film['year']?.toString() ?? '';
    final genres = film['genres'] ?? [];
    final genreName = genres.isNotEmpty ? genres[0]['name_uz'] ?? '' : '';
    final filmId = film['id'];

    return PosterCard(
      imageUrl: imageUrl,
      title: title,
      heroTag: 'categories_$filmId',
      subtitle:
          year.isNotEmpty && genreName.isNotEmpty
              ? "$year · $genreName"
              : year.isNotEmpty
              ? year
              : genreName,
      onTap:
          () => Navigator.push(
            context,
            createSlideRoute(
              FilmScreen(filmId: filmId, heroTag: 'categories_$filmId'),
            ),
          ),
    );
  }
}
