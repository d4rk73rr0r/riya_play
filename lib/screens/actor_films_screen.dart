import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/genres_films_screen.dart' show FilmCard;
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/theme/app_dimens.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/widgets/poster_grid_skeleton.dart';

/// Everything the given actor appears in.
///
/// Reached from the cast strip on a film's page. The film detail response
/// already carries `actors`, so the only new call is the per-actor listing.
class ActorFilmsScreen extends StatefulWidget {
  final int actorId;
  final String actorName;

  const ActorFilmsScreen({
    super.key,
    required this.actorId,
    required this.actorName,
  });

  @override
  State<ActorFilmsScreen> createState() => _ActorFilmsScreenState();
}

class _ActorFilmsScreenState extends State<ActorFilmsScreen> {
  static const int perPage = 20;
  late final PaginationController<dynamic> _pagination;

  @override
  void initState() {
    super.initState();
    _pagination =
        PaginationController<dynamic>(
            fetchPage: _fetchPage,
            idOf: (film) => film['id'],
            onError: (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ApiErrorHandler.handle(e).userMessage)),
                );
              }
            },
          )
          ..addListener(() => setState(() {}))
          ..init();
  }

  Future<PageResult<dynamic>> _fetchPage(int page) async {
    final response = await ApiService.getActorFilms(
      widget.actorId,
      page: page,
      perPage: perPage,
    );

    final films = (response['data'] as List<dynamic>?) ?? [];
    final meta = response['_meta'] as Map<String, dynamic>?;
    final hasMore =
        meta != null &&
        meta['currentPage'] is int &&
        meta['pageCount'] is int &&
        meta['currentPage'] < meta['pageCount'];

    return PageResult(items: films, hasMore: hasMore);
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
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.actorName,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _pagination.refresh(),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildBody(themeProvider),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeProvider themeProvider) {
    if (_pagination.items.isEmpty && _pagination.isLoading) {
      return const PosterGridSkeleton();
    }
    if (_pagination.items.isEmpty) {
      return Center(
        child: Text(
          "Bu aktyor uchun kontent topilmadi",
          style: TextStyle(fontSize: 16, color: themeProvider.subTextColor),
        ),
      );
    }

    return CustomScrollView(
      controller: _pagination.scrollController,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: AppSpacing.md,
              mainAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.65,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => FilmCard(film: _pagination.items[index]),
              childCount: _pagination.items.length,
            ),
          ),
        ),
        if (_pagination.isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: CircularProgressIndicator(
                  color: themeProvider.accentColor,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
