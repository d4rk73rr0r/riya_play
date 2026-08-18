import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/utils/grid_density.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/widgets/poster_card.dart';
import 'package:riya_play/widgets/poster_grid_skeleton.dart';
import 'package:riya_play/theme/app_dimens.dart';
import 'package:riya_play/utils/image_cache_manager.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen>
    with TickerProviderStateMixin {
  List<dynamic> _categories = [];
  Map<String, PaginationController<dynamic>> _controllers = {};
  String? _categoriesError;
  TabController? _tabController; // late o'rniga nullable
  bool _isInitialLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearchActive = false;
  late AnimationController _animationController;
  final Map<int, bool> _favorites = {};
  final Map<int, bool> _isAnimatingFavorites = {};
  final Map<int, double> _favoriteScales = {};

  @override
  void initState() {
    super.initState();
    _controllers[''] = _createController('')..init(loadImmediately: false);
    _fetchInitialData();
    _searchController.addListener(_onSearchChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  PaginationController<dynamic> _createController(String categoryId) {
    return PaginationController<dynamic>(
      fetchPage: (page) => _fetchFilmsPage(categoryId, page),
      idOf: (film) => film['id'],
      onPageLoaded: _onFilmsPageLoaded,
    )..addListener(() => setState(() {}));
  }

  void _onFilmsPageLoaded(List<dynamic> newFilms) {
    for (var film in newFilms) {
      final filmId = film['id'] as int;
      _favorites[filmId] =
          film.containsKey('favorite') && film['favorite'] == 1;
      _isAnimatingFavorites[filmId] = false;
      _favoriteScales[filmId] = 1.0;
    }
    _precacheImages(newFilms);
  }

  Future<PageResult<dynamic>> _fetchFilmsPage(
    String categoryId,
    int page,
  ) async {
    final results = await ApiService.searchFilms(
      _searchQuery,
      page,
      categoryId,
    ).timeout(const Duration(seconds: 10));
    return PageResult(items: results, hasMore: results.isNotEmpty);
  }

  Future<void> _fetchInitialData() async {
    if (!mounted) return;
    setState(() {
      _isInitialLoading = true;
    });

    try {
      // Parallel ravishda kategoriyalar va filmlarni yuklash
      await Future.wait([_fetchCategories(), _controllers['']!.loadInitial()]);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _categoriesError = "Ma'lumotlarni yuklashda xatolik: $e";
        });
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _categories.clear();
      _favorites.clear();
      _isAnimatingFavorites.clear();
      _favoriteScales.clear();
      _categoriesError = null;
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _searchController.clear();
      _isSearchActive = false;
      _animationController.reverse();
      _isInitialLoading = true;
      _tabController?.dispose();
      _tabController = null;
    });
    _controllers[''] = _createController('')..init(loadImmediately: false);
    await _fetchInitialData();
  }

  Future<void> _fetchCategories() async {
    if (!mounted) return;
    setState(() => _isInitialLoading = true);

    try {
      final response = await ApiService.sendRequest(
        url: '${ApiService.baseUrl}/v1/types?filter[status]=1&sort=sort',
        headers: {"Authorization": "Bearer ${await _getAuthToken()}"},
      ).timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          if (response['success'] == false) {
            _categoriesError =
                'Kategoriyalarni yuklashda xato: ${response['error']}';
            _categories = [];
          } else {
            _categories = (response['data'] as List<dynamic>?) ?? [];
            _categoriesError = null;
            for (var category in _categories) {
              final categoryId = category['id'].toString();
              _controllers[categoryId] = _createController(categoryId)
                ..init(loadImmediately: false);
            }
          }
          _isInitialLoading = false;
          _tabController = TabController(
            length: _categories.length + 1,
            vsync: this,
          );
          _tabController!.addListener(() {
            if (!_tabController!.indexIsChanging) {
              final categoryId =
                  _tabController!.index == 0
                      ? ''
                      : _categories[_tabController!.index - 1]['id'].toString();
              final controller = _controllers[categoryId]!;
              if (controller.items.isEmpty && !controller.isLoading) {
                controller.loadInitial();
              }
            }
          });
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialLoading = false;
          _categoriesError = 'Kategoriyalarni yuklashda xato: $e';
          _categories = [];
          _tabController = TabController(length: 1, vsync: this);
        });
      }
    }
  }

  Future<String> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token') ?? '';
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() {
        _searchQuery = _searchController.text.trim();
      });
      for (final controller in _controllers.values) {
        controller.refresh();
      }
    });
  }

  void _precacheImages(List<dynamic> films) {
    for (var film in films.take(5)) {
      final files = film['files'] ?? [];
      final coverUrl =
          files.isNotEmpty
              ? (files[0]['thumbnails']?['small']?['src'] ??
                  'https://placehold.co/320x180')
              : 'https://placehold.co/320x180';
      precacheImage(
        CachedNetworkImageProvider(
          coverUrl,
          cacheManager: filmImagesCacheManager,
        ),
        context,
      );
    }
  }

  void _toggleSearch() {
    if (!mounted) return;
    setState(() {
      _isSearchActive = !_isSearchActive;
      if (_isSearchActive) {
        _animationController.forward();
      } else {
        _animationController.reverse();
        _searchController.clear();
        _searchQuery = '';
        for (final controller in _controllers.values) {
          controller.refresh();
        }
      }
    });
  }

  void _clearSearch() {
    if (!mounted) return;
    _searchController.clear();
    _searchQuery = '';
    for (final controller in _controllers.values) {
      controller.refresh();
    }
  }

  Future<void> _toggleFavorite(int filmId) async {
    if (_isAnimatingFavorites[filmId] ?? false || !mounted) return;

    setState(() {
      _isAnimatingFavorites[filmId] = true;
      _favoriteScales[filmId] = 1.5;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    if (mounted) {
      setState(() {
        _favoriteScales[filmId] = 1.0;
      });
    }

    try {
      setState(() {
        _favorites[filmId] = !(_favorites[filmId] ?? false);
      });

      bool success;
      if (_favorites[filmId]!) {
        success = await ApiService.addToFavorite(filmId);
      } else {
        success = await ApiService.removeFromFavorite(filmId);
      }

      if (!success && mounted) {
        setState(() {
          _favorites[filmId] = !(_favorites[filmId] ?? false);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _favorites[filmId]!
                  ? "Sevimliga qo'shishda xato"
                  : "Sevimlidan o'chirishda xato",
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _favorites[filmId] = !(_favorites[filmId] ?? false);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Xato: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnimatingFavorites[filmId] = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        title:
            _isSearchActive
                ? Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
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
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: "Film, serial nomi...",
                      hintStyle: TextStyle(color: themeProvider.subTextColor),
                      prefixIcon: Icon(
                        Icons.search,
                        color: themeProvider.subTextColor,
                      ),
                      suffixIcon:
                          _searchController.text.isNotEmpty
                              ? IconButton(
                                icon: Icon(
                                  Icons.close,
                                  color: themeProvider.subTextColor,
                                ),
                                onPressed: _clearSearch,
                              )
                              : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: themeProvider.cardColor,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 20,
                      ),
                    ),
                    style: TextStyle(color: themeProvider.textColor),
                    autofocus: true,
                  ),
                )
                : Text(
                  'Katalog',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: themeProvider.textColor,
                  ),
                ),
        actions: [
          _isSearchActive
              ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: GestureDetector(
                  onTap: _toggleSearch,
                  child: Text(
                    'Bekor qilish',
                    style: TextStyle(
                      fontSize: 14,
                      color: themeProvider.accentColor,
                    ),
                  ),
                ),
              )
              : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: GestureDetector(
                  onTap: _toggleSearch,
                  child: Icon(
                    Icons.search,
                    size: 28,
                    color: themeProvider.textColor,
                  ),
                ),
              ),
        ],
        bottom:
            _tabController == null || _categories.isEmpty && !_isInitialLoading
                ? null
                : TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: themeProvider.accentColor,
                  labelColor: themeProvider.textColor,
                  unselectedLabelColor: themeProvider.subTextColor,
                  padding: const EdgeInsets.symmetric(horizontal: 0),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 8.0),
                  tabs: [
                    const Tab(
                      child: Text("Barchasi", style: TextStyle(fontSize: 14)),
                    ),
                    ..._categories.map(
                      (category) => Tab(
                        child: Text(
                          category['name_uz']?.length <= 20
                              ? category['name_uz']
                              : '${category['name_uz']?.substring(0, 17)}...',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
      ),
      // `bottom: false` — kontent shisha menyu ortidan o'tib, tizim
      // navigatsiya paneligacha ko'rinsin. Ro'yxat oxiriga esa shuncha
      // balandlikda bo'sh joy qo'shiladi.
      body: SafeArea(
        bottom: false,
        child: Container(
          color: themeProvider.backgroundColor,
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: themeProvider.accentColor,
            child:
                _isInitialLoading
                    ? const PosterGridSkeleton()
                    : _categoriesError != null
                    ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _categoriesError!,
                            style: TextStyle(
                              fontSize: 16,
                              color: themeProvider.subTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _refresh,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: themeProvider.accentColor,
                            ),
                            child: Text(
                              "Qayta urinish",
                              style: TextStyle(color: themeProvider.textColor),
                            ),
                          ),
                        ],
                      ),
                    )
                    : _tabController == null
                    ? Center(
                      child: CircularProgressIndicator(
                        color: themeProvider.accentColor,
                      ),
                    )
                    : Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: TabBarView(
                        controller: _tabController,
                        children: List.generate(_categories.length + 1, (
                          index,
                        ) {
                          final categoryId =
                              index == 0
                                  ? ''
                                  : _categories[index - 1]['id'].toString();
                          final pagination = _controllers[categoryId]!;
                          final films = pagination.items;
                          return films.isEmpty && pagination.isLoading
                              ? const PosterGridSkeleton()
                              : films.isEmpty && !pagination.isLoading
                              ? Center(
                                child: Text(
                                  pagination.error ?? "Filmlar mavjud emas",
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: themeProvider.subTextColor,
                                  ),
                                ),
                              )
                              : CustomScrollView(
                                controller: pagination.scrollController,
                                slivers: [
                                  if (pagination.error != null)
                                    SliverToBoxAdapter(
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: themeProvider.cardColor,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color:
                                                    themeProvider.borderColor,
                                              ),
                                            ),
                                            child: Text(
                                              pagination.error!,
                                              style: TextStyle(
                                                fontSize: 16,
                                                color:
                                                    themeProvider.subTextColor,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  SliverPadding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.lg,
                                    ),
                                    sliver: SliverGrid(
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                            // Ustunlar soni Profil bo'limidagi
                                            // 2x2 / 3x3 sozlamasidan keladi.
                                            crossAxisCount:
                                                Provider.of<
                                                  GridDensityProvider
                                                >(context).columns,
                                            crossAxisSpacing: AppSpacing.md,
                                            mainAxisSpacing: AppSpacing.md,
                                            childAspectRatio: 0.65,
                                          ),
                                      delegate: SliverChildBuilderDelegate(
                                        (context, index) => FilmCard(
                                          film: films[index],
                                          heroTag:
                                              'catalog_${categoryId}_${films[index]['id']}',
                                          isFavorite:
                                              _favorites[films[index]['id']] ??
                                              false,
                                          isAnimatingFavorite:
                                              _isAnimatingFavorites[films[index]['id']] ??
                                              false,
                                          favoriteScale:
                                              _favoriteScales[films[index]['id']] ??
                                              1.0,
                                          onToggleFavorite:
                                              () => _toggleFavorite(
                                                films[index]['id'],
                                              ),
                                        ),
                                        childCount: films.length,
                                      ),
                                    ),
                                  ),
                                  if (pagination.isLoading && films.isNotEmpty)
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
                                  if (!pagination.hasMore && films.isNotEmpty)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.all(12.0),
                                            decoration: BoxDecoration(
                                              color: themeProvider.cardColor,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                color:
                                                    themeProvider.borderColor,
                                                width: 1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color:
                                                      themeProvider.shadowColor,
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              "Yana kontent yo‘q",
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
                                  // Shisha menyu ortidan chiqib ketish uchun.
                                  SliverToBoxAdapter(
                                    child: SizedBox(
                                      height:
                                          MediaQuery.of(context).padding.bottom,
                                    ),
                                  ),
                                ],
                              );
                        }),
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _searchController.dispose();
    _animationController.dispose();
    _tabController?.dispose();
    _categories.clear();
    _favorites.clear();
    _isAnimatingFavorites.clear();
    _favoriteScales.clear();
    super.dispose();
  }
}

class FilmCard extends StatelessWidget {
  final dynamic film;
  final String heroTag;
  final bool isFavorite;
  final bool isAnimatingFavorite;
  final double favoriteScale;
  final VoidCallback onToggleFavorite;

  const FilmCard({
    super.key,
    required this.film,
    required this.heroTag,
    required this.isFavorite,
    required this.isAnimatingFavorite,
    required this.favoriteScale,
    required this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final files = film['files'] ?? [];
    final imageUrl =
        files.isNotEmpty
            ? (files[0]['thumbnails']?['small']?['src'] ??
                'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    final title = film['name_uz'] ?? 'Noma‘lum';
    final year = film['year']?.toString() ?? '';
    final genres = film['genres'] ?? [];
    final genreName = genres.isNotEmpty ? genres[0]['name_uz'] ?? '' : '';
    final filmId = film['id'];

    return PosterCard(
      imageUrl: imageUrl,
      title: title,
      heroTag: heroTag,
      subtitle:
          year.isNotEmpty && genreName.isNotEmpty
              ? "$year · $genreName"
              : year.isNotEmpty
              ? year
              : genreName,
      onTap:
          () => Navigator.push(
            context,
            createSlideRoute(FilmScreen(filmId: filmId, heroTag: heroTag)),
          ),
      badge: GestureDetector(
        onTap: onToggleFavorite,
        child: AnimatedScale(
          scale: favoriteScale,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeInOut,
          child: Icon(
            isFavorite ? IconlyBold.heart : IconlyLight.heart,
            color: isFavorite ? Colors.red : Colors.white,
            size: 24,
            shadows: const [
              Shadow(
                blurRadius: 4.0,
                color: Colors.black54,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
