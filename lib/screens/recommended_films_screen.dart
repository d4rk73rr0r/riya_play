import 'dart:io';

import 'package:flutter/material.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/widgets/poster_card.dart';
import 'package:riya_play/widgets/poster_grid_skeleton.dart';
import 'package:riya_play/theme/app_dimens.dart';

class RecommendedFilmsScreen extends StatefulWidget {
  const RecommendedFilmsScreen({super.key});

  @override
  State<RecommendedFilmsScreen> createState() => _RecommendedFilmsScreenState();
}

class _RecommendedFilmsScreenState extends State<RecommendedFilmsScreen> {
  static const int perPage = 9;
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
    final response = await ApiService.getRecommendedFilms(
      page: page,
      perPage: perPage,
    );

    final newFilms = (response['data'] as List<dynamic>?) ?? [];
    final meta = response['meta'] as Map<String, dynamic>?;
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

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        title: Text(
          'Tavsiya etilganlar',
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
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: themeProvider.subTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => _pagination.refresh(),
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
                    )
                    : _pagination.items.isEmpty && _pagination.isLoading
                    ? const PosterGridSkeleton()
                    : _pagination.items.isEmpty && !_pagination.isLoading
                    ? Center(
                      child: Text(
                        "Kontent topilmadi",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: themeProvider.subTextColor,
                        ),
                      ),
                    )
                    : CustomScrollView(
                      controller: _pagination.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
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
                          SliverToBoxAdapter(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: CircularProgressIndicator(
                                  color: themeProvider.accentColor,
                                ),
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
                                    "Barcha tavsiyalar ko‘rsatildi",
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
      heroTag: 'recommended_$filmId',
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
              FilmScreen(filmId: filmId, heroTag: 'recommended_$filmId'),
            ),
          ),
    );
  }
}
