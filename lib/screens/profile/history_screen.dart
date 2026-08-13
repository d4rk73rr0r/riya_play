import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/widgets/poster_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final PaginationController<dynamic> _pagination;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _pagination =
        PaginationController<dynamic>(
            fetchPage:
                (page) async => PageResult(
                  items:
                      (await ApiService.getWatchHistory(
                        page: page,
                      ))['data'],
                ),
            idOf: (item) => item['id'],
            onPageLoaded: _precacheImages,
          )
          ..addListener(() => setState(() {}))
          ..init();
  }

  void _precacheImages(List<dynamic> items) {
    Future.microtask(() {
      for (var item in items) {
        final coverUrl =
            (item['files'] != null &&
                    item['files'].isNotEmpty &&
                    item['files'][0]['linkAbsolute'] != null)
                ? item['files'][0]['linkAbsolute']
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

  Future<void> _clearAllHistory() async {
    _pagination.clear();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ko‘rishlar tarixi tozalandi")),
      );
    }
  }

  void _showClearAllDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ClearAllDialog(onConfirm: _clearAllHistory),
    );
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
          icon: Icon(Icons.arrow_back, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ko‘rishlar tarixi',
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
          watchHistory: _pagination.items,
          isLoading: _pagination.isLoading,
          error: _pagination.error,
          isEditing: _isEditing,
          hasMore: _pagination.hasMore,
          scrollController: _pagination.scrollController,
          onToggleEditMode: _toggleEditMode,
          onShowClearAllDialog: _showClearAllDialog,
        ),
      ),
    );
  }
}

class ContentWidget extends StatelessWidget {
  final List<dynamic> watchHistory;
  final bool isLoading;
  final String? error;
  final bool isEditing;
  final bool hasMore;
  final ScrollController scrollController;
  final VoidCallback onToggleEditMode;
  final VoidCallback onShowClearAllDialog;

  const ContentWidget({
    super.key,
    required this.watchHistory,
    required this.isLoading,
    required this.error,
    required this.isEditing,
    required this.hasMore,
    required this.scrollController,
    required this.onToggleEditMode,
    required this.onShowClearAllDialog,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (isLoading && watchHistory.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: themeProvider.accentColor),
      );
    }

    if (watchHistory.isEmpty) {
      return Center(
        child: Text(
          error ?? "Hozircha ko‘rishlar tarixi yo‘q",
          style: TextStyle(
            fontSize: 16,
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
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.65,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) =>
                  HistoryCard(item: watchHistory[index], isEditing: isEditing),
              childCount: watchHistory.length,
            ),
          ),
        ),
        if (isLoading && watchHistory.isNotEmpty)
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
        if (!hasMore && watchHistory.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: themeProvider.cardColor,
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: themeProvider.borderColor,
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: themeProvider.shadowColor,
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    "Barcha ko‘rishlar tarixi yuklandi",
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

  PinnedButtonsHeader({
    required this.isEditing,
    required this.onToggleEditMode,
    required this.onShowClearAllDialog,
    required this.themeProvider,
  });

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: themeProvider.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (!isEditing) ...[
            ElevatedButton(
              onPressed: onShowClearAllDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.deleteButtonColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                elevation: 5,
              ),
              child: const Text(
                "Barchasini tozalash",
                style: TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: onToggleEditMode,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.buttonColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                elevation: 5,
              ),
              child: const Text("Tozalash", style: TextStyle(fontSize: 14)),
            ),
          ] else ...[
            ElevatedButton(
              onPressed: onToggleEditMode,
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.cancelButtonColor,
                foregroundColor: themeProvider.textColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                elevation: 5,
              ),
              child: const Text("Bekor qilish", style: TextStyle(fontSize: 14)),
            ),
          ],
        ],
      ),
    );
  }

  @override
  double get maxExtent => 52.0;

  @override
  double get minExtent => 52.0;

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) {
    return true;
  }
}

class HistoryCard extends StatelessWidget {
  final dynamic item;
  final bool isEditing;

  const HistoryCard({super.key, required this.item, required this.isEditing});

  String _getGenresText(List<dynamic> genres) {
    if (genres.isEmpty) return 'Noma\'lum';
    return genres.map((genre) => genre['name_uz'] ?? 'Noma\'lum').join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final coverUrl =
        (item['files'] != null &&
                item['files'].isNotEmpty &&
                item['files'][0]['linkAbsolute'] != null)
            ? item['files'][0]['linkAbsolute']
            : 'https://placehold.co/150x150';

    return PosterCard(
      imageUrl: coverUrl,
      title: item['name_uz'] ?? item['name_ru'] ?? 'Noma\'lum',
      heroTag: 'history_${item['id']}',
      subtitle:
          "${item['year'] ?? 'Noma\'lum'} · ${_getGenresText(item['genres'] ?? [])}",
      onTap:
          isEditing
              ? () {}
              : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => FilmScreen(
                        filmId: item['id'],
                        heroTag: 'history_${item['id']}',
                      ),
                ),
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
          Text(
            "Haqiqatdan ham ko‘rishlar tarixini tozalamoqchimisiz?",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: themeProvider.textColor,
            ),
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
                  backgroundColor: themeProvider.deleteButtonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                child: const Text("Tozalash"),
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
