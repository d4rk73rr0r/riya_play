import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/blocs/index/index_bloc.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';
import 'package:riya_play/theme_provider.dart';

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final apiService = ApiService(storage);

    return BlocProvider(
      create: (_) => IndexBloc(apiService)..add(FetchIndexDataEvent()),
      child: BlocListener<IndexBloc, IndexState>(
        listener: (context, state) {
          if (state is IndexError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
          if (state is IndexLoggedOut) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const AuthScreen()),
            );
          }
        },
        child: Builder(
          builder: (context) {
            final themeProvider = context.watch<ThemeProvider>();
            return Scaffold(
              backgroundColor:
                  themeProvider.isDarkMode
                      ? const Color(0xFF111827)
                      : Colors.grey[100],
              body: SafeArea(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context, themeProvider),
                      _buildBanners(context),
                      _buildLatestViewed(context, themeProvider),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Asosiy sahifa", // S.of(context).mainPage o‘rniga
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: themeProvider.isDarkMode ? Colors.white : Colors.grey[800],
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  themeProvider.isDarkMode
                      ? Icons.wb_sunny
                      : Icons.nightlight_round,
                  color:
                      themeProvider.isDarkMode
                          ? Colors.yellow
                          : Colors.blueGrey,
                ),
                tooltip:
                    themeProvider.isDarkMode
                        ? "Yorug'lik rejimi" // S.of(context).lightMode o‘rniga
                        : "Tungi rejim", // S.of(context).darkMode o‘rniga
                onPressed: themeProvider.toggleTheme,
              ),
              IconButton(
                icon: const Icon(Icons.exit_to_app, color: Colors.redAccent),
                tooltip: "Chiqish", // S.of(context).logout o‘rniga
                onPressed: () => context.read<IndexBloc>().add(LogoutEvent()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBanners(BuildContext context) {
    return BlocBuilder<IndexBloc, IndexState>(
      builder: (context, state) {
        if (state.isLoadingBanners)
          return const SizedBox(
            height: 200,
            child: Center(child: CircularProgressIndicator()),
          );
        if (state.banners.isEmpty)
          return SizedBox(
            height: 200,
            child: Center(
              child: Text(
                "Bannerlar yo'q", // S.of(context).noBanners o‘rniga
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ),
          );
        return CarouselSlider(
          options: CarouselOptions(
            height: 200.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
            enlargeCenterPage: true,
            viewportFraction: 0.9,
          ),
          items:
              state.banners
                  .map((banner) => _buildBannerItem(banner, context))
                  .toList(),
        );
      },
    );
  }

  Widget _buildBannerItem(dynamic banner, BuildContext context) {
    final film = banner['film'] as Map<String, dynamic>? ?? {};
    final files = banner['files'] as List<dynamic>? ?? [];
    final imageUrl =
        files.isNotEmpty
            ? files[0]['link'] ?? 'https://placehold.co/640x360'
            : 'https://placehold.co/640x360';
    final title =
        film['name_uz'] ??
        banner['title'] ??
        "Noma'lum"; // S.of(context).unknown o‘rniga
    final year = film['year'] ?? "Noma'lum"; // S.of(context).unknown o‘rniga
    final kinopoiskRating = film['kinopoisk_rating']?.toString() ?? 'N/A';
    final imdbRating = film['imdb_rating']?.toString() ?? 'N/A';
    final filmId = film['id'] ?? 0;

    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FilmScreen(filmId: filmId)),
          ),
      child: Stack(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              image: DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 5.0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.6)],
              ),
            ),
          ),
          Positioned(customBannerItemLeftColumn(title, year)),
          Positioned(customBannerItemRightColumn(kinopoiskRating, imdbRating)),
        ],
      ),
    );
  }

  Positioned customBannerItemLeftColumn(String title, String year) {
    return Positioned(
      bottom: 10,
      left: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(year, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Positioned customBannerItemRightColumn(
    String kinopoiskRating,
    String imdbRating,
  ) {
    return Positioned(
      bottom: 10,
      right: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            children: [
              Text(
                "Kinopoisk: ", // S.current.kinopoisk o‘rniga
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              Text(
                kinopoiskRating,
                style: const TextStyle(color: Colors.yellow, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                'IMDb: ',
                style: TextStyle(color: Colors.grey[400], fontSize: 12),
              ),
              Text(
                imdbRating,
                style: const TextStyle(color: Colors.yellow, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLatestViewed(BuildContext context, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Davom ettirish", // S.of(context).continueWatching o‘rniga
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color:
                      themeProvider.isDarkMode
                          ? Colors.white
                          : Colors.grey[800],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 24),
                onPressed: () {},
              ),
            ],
          ),
          SizedBox(
            height: 150,
            child: BlocBuilder<IndexBloc, IndexState>(
              builder: (context, state) {
                if (state.isLoadingLatestViewed)
                  return const Center(child: CircularProgressIndicator());
                if (state.latestViewed.isEmpty)
                  return Center(
                    child: Text(
                      "So'nggi ko'rilganlar yo'q", // S.of(context).noLatestViewed o‘rniga
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.latestViewed.length,
                  itemBuilder:
                      (context, index) => _buildLatestViewedItem(
                        state.latestViewed[index],
                        context,
                      ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLatestViewedItem(dynamic item, BuildContext context) {
    final film = item['film'] as Map<String, dynamic>? ?? {};
    final screenshots = item['screenshots'] as List<dynamic>? ?? [];
    final second = item['second'] as Map<String, dynamic>? ?? {};
    final imageUrl =
        screenshots.isNotEmpty
            ? screenshots[0]['file'][0]['link'] ??
                'https://placehold.co/320x180'
            : 'https://placehold.co/320x180';
    final title =
        film['name_uz'] ??
        item['name_uz'] ??
        "Noma'lum"; // S.of(context).unknown o‘rniga
    final filmId = film['id'] ?? 0;
    final viewedTime = second['time'] ?? 0;
    final playbackTime = film['playback_time'] ?? 1;
    final viewedMinutes = (viewedTime / 60).floor();
    final viewedSeconds = viewedTime % 60;
    final viewedTimeString =
        '${viewedMinutes.toString().padLeft(2, '0')}:${viewedSeconds.toString().padLeft(2, '0')}';
    final progress = viewedTime / (playbackTime * 60);

    return GestureDetector(
      onTap:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => FilmScreen(filmId: filmId)),
          ),
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 10),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                imageUrl,
                width: 200,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    viewedTimeString,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 180,
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: Colors.grey[400],
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.yellow,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class IndexBloc extends Bloc<IndexEvent, IndexState> {
  final ApiService apiService;

  IndexBloc(this.apiService) : super(IndexState.initial()) {
    on<FetchIndexDataEvent>((event, emit) async {
      emit(state.copyWith(isLoadingBanners: true, isLoadingLatestViewed: true));
      try {
        final banners = await apiService.getBanners();
        final latestViewed = await apiService.getLatestViewed();
        emit(
          state.copyWith(
            banners: banners,
            latestViewed: latestViewed,
            isLoadingBanners: false,
            isLoadingLatestViewed: false,
          ),
        );
      } catch (e) {
        emit(
          state.copyWith(
            isLoadingBanners: false,
            isLoadingLatestViewed: false,
            message:
                "Ma'lumotlarni yuklashda xatolik: $e", // S.current.errorLoadingData o‘rniga
          ),
        );
      }
    });

    on<LogoutEvent>((event, emit) async {
      try {
        await apiService.logout();
        emit(IndexLoggedOut());
      } catch (e) {
        emit(
          IndexError("Chiqishda xatolik: $e"),
        ); // S.current.logoutError o‘rniga
      }
    });
  }
}

sealed class IndexEvent {}

class FetchIndexDataEvent extends IndexEvent {}

class LogoutEvent extends IndexEvent {}

class IndexState {
  final List<dynamic> banners;
  final List<dynamic> latestViewed;
  final bool isLoadingBanners;
  final bool isLoadingLatestViewed;
  final String? message;

  IndexState({
    required this.banners,
    required this.latestViewed,
    required this.isLoadingBanners,
    required this.isLoadingLatestViewed,
    this.message,
  });

  factory IndexState.initial() => IndexState(
    banners: [],
    latestViewed: [],
    isLoadingBanners: true,
    isLoadingLatestViewed: true,
  );

  IndexState copyWith({
    List<dynamic>? banners,
    List<dynamic>? latestViewed,
    bool? isLoadingBanners,
    bool? isLoadingLatestViewed,
    String? message,
  }) => IndexState(
    banners: banners ?? this.banners,
    latestViewed: latestViewed ?? this.latestViewed,
    isLoadingBanners: isLoadingBanners ?? this.isLoadingBanners,
    isLoadingLatestViewed: isLoadingLatestViewed ?? this.isLoadingLatestViewed,
    message: message ?? this.message,
  );
}

class IndexError extends IndexState {
  final String message;
  IndexError(this.message)
    : super(
        banners: [],
        latestViewed: [],
        isLoadingBanners: false,
        isLoadingLatestViewed: false,
      );
}

class IndexLoggedOut extends IndexState {
  IndexLoggedOut()
    : super(
        banners: [],
        latestViewed: [],
        isLoadingBanners: false,
        isLoadingLatestViewed: false,
      );
}
