import 'package:flutter/material.dart';
import 'package:riya_play/services/error_handler.dart';

/// Result of fetching a single page: the items on that page, plus whether
/// more pages remain. Callers decide `hasMore` however fits their API shape
/// (an explicit page-count field, or simply "page came back non-empty").
class PageResult<T> {
  final List<T> items;
  final bool hasMore;

  const PageResult({required this.items, this.hasMore = true});
}

/// Drives an infinite-scroll paginated list: tracks items/loading/error
/// state, owns the [ScrollController] that triggers `loadMore()` near the
/// bottom, and de-duplicates items across pages when [idOf] is supplied.
///
/// Screens wire it up once in `initState`:
/// ```dart
/// _controller = PaginationController<Film>(
///   fetchPage: (page) async {
///     final res = await ApiService.getFavorites(page: page);
///     return PageResult(items: res);
///   },
///   idOf: (film) => film['id'],
/// )..addListener(() => setState(() {}))..loadInitial();
/// ```
class PaginationController<T> extends ChangeNotifier {
  PaginationController({
    required Future<PageResult<T>> Function(int page) fetchPage,
    Object? Function(T item)? idOf,
    void Function(List<T> newItems)? onPageLoaded,
    void Function(Object error)? onError,
    this.loadMoreThreshold = 200,
  }) : _fetchPage = fetchPage,
       _idOf = idOf,
       _onPageLoaded = onPageLoaded,
       _onError = onError;

  final Future<PageResult<T>> Function(int page) _fetchPage;
  final Object? Function(T item)? _idOf;
  final void Function(List<T> newItems)? _onPageLoaded;
  final void Function(Object error)? _onError;
  final double loadMoreThreshold;

  final List<T> items = [];
  final ScrollController scrollController = ScrollController();

  bool isLoading = false;
  bool hasMore = true;
  String? error;
  int _page = 1;

  /// Starts listening for scroll-triggered pagination. Pass
  /// [loadImmediately]: false when several controllers are created upfront
  /// (e.g. one per tab) and only the active one should fetch right away —
  /// call [loadInitial] later for the rest once they become active.
  void init({bool loadImmediately = true}) {
    scrollController.addListener(_onScroll);
    if (loadImmediately) loadInitial();
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!hasMore || isLoading || !scrollController.hasClients) return;
    if (scrollController.position.pixels >=
        scrollController.position.maxScrollExtent - loadMoreThreshold) {
      loadMore();
    }
  }

  Future<void> loadInitial() => _load(reset: true);

  Future<void> loadMore() => _load(reset: false);

  Future<void> refresh() => _load(reset: true);

  Future<void> _load({required bool reset}) async {
    if (isLoading || (!hasMore && !reset)) return;

    if (reset) {
      _page = 1;
      hasMore = true;
      error = null;
      items.clear();
    }
    isLoading = true;
    notifyListeners();

    try {
      final result = await _fetchPage(_page);
      var newItems = result.items;
      if (_idOf != null) {
        final existingIds = items.map(_idOf).toSet();
        newItems = newItems.where((e) => !existingIds.contains(_idOf(e))).toList();
      }
      items.addAll(newItems);
      hasMore = result.hasMore && newItems.isNotEmpty;
      if (newItems.isNotEmpty) _page++;
      if (newItems.isNotEmpty) _onPageLoaded?.call(newItems);
    } catch (e) {
      // Xom `$e` emas: `sendRequest` hech qachon otmaydi, shuning uchun bu
      // yerga kelgan narsa odatda tarmoq yoki parsing istisnosi — ularning
      // `toString()` i foydalanuvchiga hech narsa aytmaydi.
      error = ApiErrorHandler.handle(e).userMessage;
      _onError?.call(e);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void removeWhere(bool Function(T item) test) {
    items.removeWhere(test);
    notifyListeners();
  }

  /// Moves the first item matching [test] to the head of the list.
  ///
  /// Server-sorted lists (e.g. "Ko'rishni davom ettirish", sorted by
  /// `updated_at`) would otherwise need a full refetch just to show that one
  /// entry moved to the front. Returns false when nothing matched.
  bool moveToFront(bool Function(T item) test) {
    final index = items.indexWhere(test);
    if (index < 0) return false;
    if (index > 0) items.insert(0, items.removeAt(index));
    notifyListeners();
    return true;
  }

  void clear() {
    items.clear();
    notifyListeners();
  }
}
