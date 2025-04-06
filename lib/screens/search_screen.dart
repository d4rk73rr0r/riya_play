import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riya_play/blocs/search/search_bloc.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';
import 'package:riya_play/theme_provider.dart';

final customCacheManager = CacheManager(
  Config(
    'filmImagesCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 100,
  ),
);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;
  late AnimationController _animationController;
  late Animation<double> _widthAnimation;

  @override
  void initState() {
    super.initState();
    final storage = StorageService();
    final apiService = ApiService(storage);
    context.read<SearchBloc>().add(FetchInitialDataEvent());
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _widthAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      context.read<SearchBloc>().add(
        SearchFilmsEvent(_searchController.text.trim()),
      );
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<SearchBloc>().add(FetchMoreFilmsEvent());
    }
  }

  void _toggleSearch() {
    final bloc = context.read<SearchBloc>();
    bloc.add(ToggleSearchEvent());
    if (bloc.state.isSearchActive) {
      _animationController.forward();
    } else {
      _animationController.reverse();
      _searchController.clear();
    }
  }

  String _getGenresText(List<dynamic> genres) =>
      genres.isEmpty
          ? "Noma'lum" // S.of(context).unknown o‘rniga
          : genres.map((g) => g['name_uz'] ?? "Noma'lum").join(', ');

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: BlocBuilder<SearchBloc, SearchState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (!state.isSearchActive)
                        Text(
                          "Katalog", // S.of(context).catalog o‘rniga
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      Flexible(
                        child: AnimatedBuilder(
                          animation: _widthAnimation,
                          builder:
                              (context, child) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (state.isSearchActive)
                                    Flexible(
                                      child: SizedBox(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.6 *
                                            _widthAnimation.value,
                                        child: TextField(
                                          controller: _searchController,
                                          decoration: InputDecoration(
                                            hintText:
                                                "Qidirish...", // S.of(context).searchHint o‘rniga
                                            hintStyle: TextStyle(
                                              color:
                                                  themeProvider.isDarkMode
                                                      ? Colors.grey[400]
                                                      : Colors.grey,
                                            ),
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              borderSide: BorderSide.none,
                                            ),
                                            filled: true,
                                            fillColor:
                                                themeProvider.isDarkMode
                                                    ? const Color(0xFF1F2937)
                                                    : Colors.white,
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  vertical: 14,
                                                  horizontal: 12,
                                                ),
                                            suffixIcon:
                                                _searchController
                                                        .text
                                                        .isNotEmpty
                                                    ? IconButton(
                                                      icon: Icon(
                                                        Icons.close,
                                                        color:
                                                            themeProvider
                                                                    .isDarkMode
                                                                ? Colors
                                                                    .grey[400]
                                                                : Colors.grey,
                                                      ),
                                                      onPressed: () {
                                                        _searchController
                                                            .clear();
                                                        context
                                                            .read<SearchBloc>()
                                                            .add(
                                                              SearchFilmsEvent(
                                                                '',
                                                              ),
                                                            );
                                                      },
                                                    )
                                                    : null,
                                          ),
                                          style: TextStyle(
                                            color:
                                                themeProvider.isDarkMode
                                                    ? Colors.white
                                                    : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: _toggleSearch,
                                    child:
                                        state.isSearchActive
                                            ? Text(
                                              "Bekor qilish", // S.of(context).cancel o‘rniga
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    themeProvider.isDarkMode
                                                        ? Colors.blue[300]
                                                        : Colors.blue,
                                              ),
                                            )
                                            : Icon(
                                              Icons.search,
                                              size: 28,
                                              color:
                                                  themeProvider.isDarkMode
                                                      ? Colors.white
                                                      : Colors.black87,
                                            ),
                                  ),
                                ],
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 50,
                    child:
                        state.categories.isEmpty && state.isLoading
                            ? Center(
                              child: Text(
                                "Kategoriyalar yuklanmoqda...", // S.of(context).loadingCategories o‘rniga
                                style: TextStyle(
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey,
                                ),
                              ),
                            )
                            : SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _buildCategoryButton(
                                    "Hammasi", // S.of(context).all o‘rniga
                                    '',
                                    state.selectedCategory,
                                    themeProvider.isDarkMode,
                                  ),
                                  ...state.categories.map(
                                    (category) => _buildCategoryButton(
                                      category['name_uz'] ??
                                          "Noma'lum", // S.of(context).unknown o‘rniga
                                      category['id'].toString(),
                                      state.selectedCategory,
                                      themeProvider.isDarkMode,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child:
                        state.isLoading && state.films.isEmpty
                            ? Center(
                              child: CircularProgressIndicator(
                                color:
                                    themeProvider.isDarkMode
                                        ? Colors.white
                                        : Colors.blue,
                              ),
                            )
                            : state.films.isEmpty
                            ? Center(
                              child: Text(
                                state.error ??
                                    "Kontent yuklanmoqda...", // S.of(context).loadingContent o‘rniga
                                style: TextStyle(
                                  fontSize: 16,
                                  color:
                                      themeProvider.isDarkMode
                                          ? Colors.grey[400]
                                          : Colors.grey,
                                ),
                              ),
                            )
                            : GridView.builder(
                              controller: _scrollController,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 0.65,
                                  ),
                              itemCount:
                                  state.films.length +
                                  (state.isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == state.films.length)
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                final film = state.films[index];
                                final coverUrl =
                                    film['files']?.isNotEmpty == true
                                        ? film['files'][0]['link'] ??
                                            'https://placehold.co/150x150'
                                        : 'https://placehold.co/150x150';
                                return GestureDetector(
                                  onTap:
                                      () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder:
                                              (_) => FilmScreen(
                                                filmId: film['id'],
                                              ),
                                        ),
                                      ),
                                  child: Card(
                                    elevation: 4,
                                    color:
                                        themeProvider.isDarkMode
                                            ? const Color(0xFF1F2937)
                                            : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                  top: Radius.circular(12),
                                                ),
                                            child: CachedNetworkImage(
                                              imageUrl: coverUrl,
                                              cacheManager: customCacheManager,
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              placeholder:
                                                  (context, url) => Container(
                                                    color:
                                                        themeProvider.isDarkMode
                                                            ? const Color(
                                                              0xFF374151,
                                                            )
                                                            : Colors.grey[300],
                                                    child: const Center(
                                                      child:
                                                          CircularProgressIndicator(),
                                                    ),
                                                  ),
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Image.network(
                                                    'https://placehold.co/150x150',
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.all(8.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                film['name_uz'] ??
                                                    "Noma'lum", // S.of(context).unknown o‘rniga
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                                  color:
                                                      themeProvider.isDarkMode
                                                          ? Colors.white
                                                          : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Yil: ${film['year'] ?? "Noma'lum"}', // S.of(context).year o‘rniga
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      themeProvider.isDarkMode
                                                          ? Colors.grey[400]
                                                          : Colors.grey,
                                                ),
                                              ),
                                              Text(
                                                'Janr: ${_getGenresText(film['genres'] ?? [])}', // S.of(context).genre o‘rniga
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      themeProvider.isDarkMode
                                                          ? Colors.grey[400]
                                                          : Colors.grey,
                                                ),
                                              ),
                                            ],
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
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryButton(
    String title,
    String category,
    String selectedCategory,
    bool isDarkMode,
  ) {
    final isSelected = selectedCategory == category;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton(
        onPressed:
            () => context.read<SearchBloc>().add(SelectCategoryEvent(category)),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              isSelected
                  ? Colors.blue[500]
                  : (isDarkMode ? const Color(0xFF1F2937) : Colors.grey[200]),
          foregroundColor:
              isSelected
                  ? Colors.white
                  : (isDarkMode ? Colors.white : Colors.black87),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: isSelected ? 4 : 0,
        ),
        child: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    _animationController.dispose();
    super.dispose();
  }
}

class SearchBloc extends Bloc<SearchEvent, SearchState> {
  final ApiService apiService;

  SearchBloc(this.apiService) : super(SearchState.initial()) {
    on<FetchInitialDataEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true));
      try {
        final categories = await apiService.sendRequest(
          url: '${ApiService.baseUrl}/v1/types?filter[status]=1&sort=sort',
          headers: {
            "Authorization": "Bearer ${await apiService._storage.getToken()}",
          },
        );
        final films = await apiService.searchFilms('', 1, '');
        emit(
          state.copyWith(
            categories: categories['data'] ?? [],
            films: films,
            isLoading: false,
          ),
        );
      } catch (e) {
        emit(
          state.copyWith(
            isLoading: false,
            error:
                "Kategoriyalarni yuklashda xatolik: $e", // S.current.errorLoadingCategories o‘rniga
          ),
        );
      }
    });

    on<SearchFilmsEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true, films: [], page: 1));
      try {
        final films = await apiService.searchFilms(
          event.query,
          1,
          state.selectedCategory,
        );
        emit(state.copyWith(films: films, isLoading: false));
      } catch (e) {
        emit(
          state.copyWith(isLoading: false, error: "Xatolik: $e"),
        ); // S.current.error o‘rniga
      }
    });

    on<FetchMoreFilmsEvent>((event, emit) async {
      if (state.isLoadingMore) return;
      emit(state.copyWith(isLoadingMore: true));
      try {
        final films = await apiService.searchFilms(
          state.query,
          state.page + 1,
          state.selectedCategory,
        );
        emit(
          state.copyWith(
            films: [...state.films, ...films],
            page: state.page + 1,
            isLoadingMore: false,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoadingMore: false));
      }
    });

    on<SelectCategoryEvent>((event, emit) async {
      emit(
        state.copyWith(
          selectedCategory: event.category,
          isLoading: true,
          films: [],
          page: 1,
        ),
      );
      try {
        final films = await apiService.searchFilms(
          state.query,
          1,
          event.category,
        );
        emit(state.copyWith(films: films, isLoading: false));
      } catch (e) {
        emit(
          state.copyWith(isLoading: false, error: "Xatolik: $e"),
        ); // S.current.error o‘rniga
      }
    });

    on<ToggleSearchEvent>(
      (event, emit) =>
          emit(state.copyWith(isSearchActive: !state.isSearchActive)),
    );
  }
}

class SearchEvent {}

class FetchInitialDataEvent extends SearchEvent {}

class SearchFilmsEvent extends SearchEvent {
  final String query;
  SearchFilmsEvent(this.query);
}

class FetchMoreFilmsEvent extends SearchEvent {}

class SelectCategoryEvent extends SearchEvent {
  final String category;
  SelectCategoryEvent(this.category);
}

class ToggleSearchEvent extends SearchEvent {}

class SearchState {
  final List<dynamic> films;
  final List<dynamic> categories;
  final String selectedCategory;
  final bool isLoading;
  final bool isLoadingMore;
  final String? error;
  final int page;
  final bool isSearchActive;
  final String query;

  SearchState({
    required this.films,
    required this.categories,
    required this.selectedCategory,
    required this.isLoading,
    required this.isLoadingMore,
    this.error,
    required this.page,
    required this.isSearchActive,
    required this.query,
  });

  factory SearchState.initial() => SearchState(
    films: [],
    categories: [],
    selectedCategory: '',
    isLoading: false,
    isLoadingMore: false,
    page: 1,
    isSearchActive: false,
    query: '',
  );

  SearchState copyWith({
    List<dynamic>? films,
    List<dynamic>? categories,
    String? selectedCategory,
    bool? isLoading,
    bool? isLoadingMore,
    String? error,
    int? page,
    bool? isSearchActive,
    String? query,
  }) => SearchState(
    films: films ?? this.films,
    categories: categories ?? this.categories,
    selectedCategory: selectedCategory ?? this.selectedCategory,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    error: error ?? this.error,
    page: page ?? this.page,
    isSearchActive: isSearchActive ?? this.isSearchActive,
    query: query ?? this.query,
  );
}
