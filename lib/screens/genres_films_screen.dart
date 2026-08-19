import 'dart:io';
import 'package:flutter/material.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/widgets/poster_card.dart';
import 'package:riya_play/widgets/poster_grid_skeleton.dart';
import 'package:riya_play/theme/app_dimens.dart';

class GenresFilmsScreen extends StatefulWidget {
  final Map<String, dynamic> genre;

  const GenresFilmsScreen({super.key, required this.genre});

  @override
  State<GenresFilmsScreen> createState() => _GenresFilmsScreenState();
}

class _GenresFilmsScreenState extends State<GenresFilmsScreen> {
  static const int perPage = 20;
  late final PaginationController<dynamic> _pagination;

  @override
  void initState() {
    super.initState();
    _pagination =
        PaginationController<dynamic>(
            fetchPage: _fetchFilmsPage,
            onError: (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ApiErrorHandler.handle(e).userMessage),
                  ),
                );
              }
            },
          )
          ..addListener(() => setState(() {}))
          ..init();
  }

  Future<PageResult<dynamic>> _fetchFilmsPage(int page) async {
    final response = await ApiService.getFilmsByGenre(
      genreId: widget.genre['id'],
      page: page,
      perPage: perPage,
    );

    final newFilms = (response['data'] as List<dynamic>?) ?? [];
    final meta = response['_meta'] as Map<String, dynamic>?;
    final hasMore =
        meta != null &&
        meta['currentPage'] is int &&
        meta['pageCount'] is int &&
        meta['currentPage'] < meta['pageCount'];

    if (!hasMore && (Platform.isAndroid || Platform.isIOS)) {
      HapticFeedback.mediumImpact();
    }
    return PageResult(items: newFilms, hasMore: hasMore);
  }

  Future<void> _onRefresh() async {
    await _pagination.refresh();
  }

  @override
  void dispose() {
    _pagination.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final genreName = widget.genre['name_uz'] ?? 'Janr';

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        elevation: 2,
        title: Text(
          genreName,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child:
              _pagination.error != null
                  ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Kontent yuklashda xatolik yuz berdi",
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                themeProvider.isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _pagination.refresh(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text("Qayta urinish"),
                        ),
                      ],
                    ),
                  )
                  : _pagination.items.isEmpty && _pagination.isLoading
                  ? const PosterGridSkeleton()
                  : _pagination.items.isEmpty && !_pagination.isLoading
                  ? Center(
                    child: Text(
                      "Kontent topilmadi",
                      style: TextStyle(
                        fontSize: 16,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[600],
                      ),
                    ),
                  )
                  : CustomScrollView(
                    controller: _pagination.scrollController,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
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
                      if (_pagination.isLoading)
                        const SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: CircularProgressIndicator(),
                            ),
                          ),
                        ),
                      if (!_pagination.hasMore && _pagination.items.isNotEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[800]
                                          : Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  "Barcha filmlar ko‘rsatildi",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        themeProvider.isDarkMode
                                            ? Colors.white70
                                            : Colors.grey[600],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      // `edgeToEdge` — bu ekran oynaning pastigacha chizadi,
                      // shuning uchun oxirgi qator navigatsiya paneli ostida
                      // qolmasligi uchun skroll ichida bo'shliq qoldiriladi.
                      SliverToBoxAdapter(
                        child: SizedBox(
                          height: MediaQuery.of(context).viewPadding.bottom,
                        ),
                      ),
                    ],
                  ),
        ),
      ),
    );
  }
}

class FilmCard extends StatelessWidget {
  final dynamic film;

  const FilmCard({super.key, required this.film});

  @override
  Widget build(BuildContext context) {
    final files = film['files'] ?? [];
    // Ba'zi endpointlar (masalan aktyor bo'yicha ro'yxat) `thumbnails`siz
    // keladi va `link` nisbiy yo'l bo'ladi — `linkAbsolute` bor bo'lsa
    // o'sha ishonchli.
    final imageUrl =
        files.isNotEmpty
            ? (files[0]['thumbnails']?['small']?['src'] ??
                files[0]['linkAbsolute'] ??
                files[0]['link'] ??
                'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    final title = film['name_uz'] ?? 'Noma’lum';
    final year = film['year']?.toString() ?? '';
    final genres = film['genres'] ?? [];
    final genreName = genres.isNotEmpty ? genres[0]['name_uz'] ?? '' : '';
    final filmId = film['id'];

    return PosterCard(
      imageUrl: imageUrl,
      title: title,
      heroTag: 'genres_films_$filmId',
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
              FilmScreen(filmId: filmId, heroTag: 'genres_films_$filmId'),
            ),
          ),
    );
  }
}
