import 'package:better_player/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/blocs/film/film_bloc.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final customCacheManager = CacheManager(
  Config(
    'filmImagesCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 100,
  ),
);

class FilmScreen extends StatelessWidget {
  final int filmId;

  const FilmScreen({required this.filmId, super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final apiService = ApiService(storage);

    return BlocProvider(
      create: (_) => FilmBloc(apiService)..add(FetchFilmDetailsEvent(filmId)),
      child: BlocBuilder<FilmBloc, FilmState>(
        builder: (context, state) {
          final themeProvider = context.watch<ThemeProvider>();
          return Scaffold(
            backgroundColor:
                themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
            appBar: AppBar(
              backgroundColor:
                  themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
              elevation: 2,
              leading: IconButton(
                icon: Icon(
                  forEachIcons.chevron_left,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  size: 32,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                state.film?['name_uz'] ?? "Noma'lum", // S.of(context).unknown o‘rniga
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            body: state.isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: themeProvider.isDarkMode ? Colors.white : Colors.blue,
                    ),
                  )
                : state.film == null
                    ? Center(
                        child: Text(
                          "Film ma'lumotlari yo'q", // S.of(context).noFilmData o‘rniga
                          style: TextStyle(
                            fontSize: 16,
                            color: themeProvider.isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CachedNetworkImage(
                                    imageUrl:
                                        state.film?['files']?.isNotEmpty == true
                                            ? state.film!['files'][0]['linkAbsolute'] ??
                                                ''
                                            : 'https://placehold.co/150x150',
                                    cacheManager: customCacheManager,
                                    width: 150,
                                    height: 200,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 150,
                                      height: 200,
                                      color: themeProvider.isDarkMode
                                          ? const Color(0xFF374151)
                                          : Colors.grey[300],
                                      child: const Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      width: 150,
                                      height: 200,
                                      color: themeProvider.isDarkMode
                                          ? const Color(0xFF374151)
                                          : Colors.grey[300],
                                      child: const Center(
                                        child: Text("Rasm yuklanmadi"),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          "${state.film?['name_uz']} (${state.film?['year'] ?? "Noma'lum"})", // S.of(context).unknown o‘rniga
                                          style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: themeProvider.isDarkMode
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (state.isSerial &&
                                            state.film?['season_count'] != null &&
                                            state.film?['episode_count'] != null)
                                          Text(
                                            "${state.film?['season_count']} Mavsum, ${state.film?['episode_count']} Epizod", // S.of(context).seasons va .episodes o‘rniga
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: themeProvider.isDarkMode
                                                  ? Colors.grey[400]
                                                  : Colors.grey,
                                            ),
                                          ),
                                        Text(
                                          "Janr: ${_getGenresText(state.film?['genres'] ?? [])}", // S.of(context).genre o‘rniga
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: themeProvider.isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          "Kinopoisk: ${state.film?['kinopoisk_rating'] ?? "Noma'lum"}", // S.of(context).kinopoisk o‘rniga
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: themeProvider.isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          "IMDb: ${state.film?['imdb_rating'] ?? "Noma'lum"}", // S.of(context).unknown o‘rniga
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: themeProvider.isDarkMode
                                                ? Colors.grey[400]
                                                : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "Tavsif", // S.of(context).description o‘rniga
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: themeProvider.isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                              ),
                              Text(
                                state.film?['description_uz'] ?? "Tavsif yo'q", // S.of(context).noDescription o‘rniga
                                style: TextStyle(
                                  fontSize: 14,
                                  color: themeProvider.isDarkMode
                                      ? Colors.grey[400]
                                      : Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (!state.isSerial &&
                                  state.film?['lastSeries']?.isNotEmpty == true)
                                ElevatedButton(
                                  onPressed: () {
                                    final trackList =
                                        state.film!['lastSeries'][0]['track']
                                            as List<dynamic>?;
                                    if (trackList != null && trackList.isNotEmpty) {
                                      context.read<FilmBloc>().add(
                                            PlayVideoEvent(
                                              trackList[0]['stream_url'] ?? '',
                                              state.film!['name_uz'],
                                            ),
                                          );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue[500],
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text("Filmni ko'rish"), // S.of(context).watchFilm o‘rniga
                                ),
                              if (state.isSerial) ...[
                                const SizedBox(height: 16),
                                Text(
                                  "Mavsumlar", // S.of(context).seasons o‘rniga
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: themeProvider.isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: List.generate(
                                      state.film!['season_count'] ?? 1,
                                      (index) {
                                        final season = index + 1;
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4.0,
                                          ),
                                          child: ElevatedButton(
                                            onPressed: () =>
                                                context.read<FilmBloc>().add(
                                                      SelectSeasonEvent(season),
                                                    ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  state.selectedSeason == season
                                                      ? Colors.blue[500]
                                                      : (themeProvider.isDarkMode
                                                          ? const Color(0xFF1F2937)
                                                          : Colors.grey[200]),
                                              foregroundColor:
                                                  state.selectedSeason == season
                                                      ? Colors.white
                                                      : (themeProvider.isDarkMode
                                                          ? Colors.white
                                                          : Colors.black87),
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 10,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                            ),
                                            child: Text(
                                              "Mavsum $season", // S.of(context).season o‘rniga
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  "Epizodlar (Mavsum ${state.selectedSeason ?? 1})", // S.of(context).episodes va .season o‘rniga
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: themeProvider.isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                SizedBox(
                                  height: MediaQuery.of(context).size.height * 0.5,
                                  child: state.episodes.isEmpty && !state.isLoadingMore
                                      ? Center(
                                          child: Text(
                                            "Epizodlar yo'q", // S.of(context).noEpisodes o‘rniga
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: themeProvider.isDarkMode
                                                  ? Colors.grey[400]
                                                  : Colors.grey,
                                            ),
                                          ),
                                        )
                                      : GridView.builder(
                                          controller:
                                              context.read<FilmBloc>().scrollController,
                                          gridDelegate:
                                              const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 2,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 12,
                                            childAspectRatio: 2.5,
                                          ),
                                          itemCount: state.episodes.length +
                                              (state.isLoadingMore ? 1 : 0),
                                          itemBuilder: (context, index) {
                                            if (index == state.episodes.length)
                                              return const Center(
                                                child: CircularProgressIndicator(),
                                              );
                                            final episode = state.episodes[index];
                                            return Container(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                color: themeProvider.isDarkMode
                                                    ? const Color(0xFF1F2937)
                                                    : Colors.white,
                                                boxShadow: [
                                                  BoxShadow(
                                                    color:
                                                        Colors.black.withOpacity(0.1),
                                                    blurRadius: 6,
                                                    offset: const Offset(0, 2),
                                                  ),
                                                ],
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  onTap: () {
                                                    final trackList =
                                                        episode['track']
                                                            as List<dynamic>?;
                                                    if (trackList != null &&
                                                        trackList.isNotEmpty) {
                                                      context.read<FilmBloc>().add(
                                                            PlayVideoEvent(
                                                              trackList[0]
                                                                      ['stream_url'] ??
                                                                  '',
                                                              episode['name_uz'] ??
                                                                  "Epizod ${index + 1}", // S.of(context).episode o‘rniga
                                                            ),
                                                          );
                                                    }
                                                  },
                                                  child: Padding(
                                                    padding: const EdgeInsets.all(12.0),
                                                    child: Row(
                                                      children: [
                                                        Container(
                                                          width: 40,
                                                          height: 40,
                                                          decoration: BoxDecoration(
                                                            color: themeProvider
                                                                    .isDarkMode
                                                                ? Colors.blue[700]
                                                                : Colors.blue[200],
                                                            shape: BoxShape.circle,
                                                          ),
                                                          child: Center(
                                                            child: Text(
                                                              "${index + 1}",
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight.bold,
                                                                color: themeProvider
                                                                        .isDarkMode
                                                                    ? Colors.white
                                                                    : Colors.blue[800],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment.start,
                                                            mainAxisAlignment:
                                                                MainAxisAlignment.center,
                                                            children: [
                                                              Text(
                                                                episode['name_uz'] ??
                                                                    "Epizod ${index + 1}", // S.of(context).episode o‘rniga
                                                                style: TextStyle(
                                                                  fontSize: 14,
                                                                  fontWeight:
                                                                      FontWeight.w500,
                                                                  color: themeProvider
                                                                          .isDarkMode
                                                                      ? Colors.white
                                                                      : Colors.black87,
                                                                ),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow.ellipsis,
                                                              ),
                                                              if (episode['duration'] != null)
                                                                Text(
                                                                  _formatDuration(
                                                                    episode['duration'],
                                                                  ),
                                                                  style: TextStyle(
                                                                    fontSize: 12,
                                                                    color: themeProvider
                                                                            .isDarkMode
                                                                        ? Colors.grey[400]
                                                                        : Colors.grey[600],
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                        ),
                                                        Icon(
                                                          Icons.play_arrow_rounded,
                                                          color: themeProvider.isDarkMode
                                                              ? Colors.blue[300]
                                                              : Colors.blue[600],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
          );
        },
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$secs' : '$minutes:$secs';
  }

  String _getGenresText(List<dynamic> genres) => genres.isEmpty
      ? "Noma'lum" // S.current.unknown o‘rniga
      : genres.map((g) => g['name_uz'] ?? "Noma'lum").join(', ');
}

class FilmBloc extends Bloc<FilmEvent, FilmState> {
  final ApiService apiService;
  final ScrollController scrollController = ScrollController();

  FilmBloc(this.apiService) : super(FilmState.initial()) {
    scrollController.addListener(_onScroll);

    on<FetchFilmDetailsEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true));
      try {
        final filmData = await apiService.getFilmDetails(event.filmId);
        emit(
          state.copyWith(
            film: filmData,
            isLoading: false,
            isSerial: filmData['type']?['name_uz'] == "Serial",
          ),
        );
        if (state.isSerial && filmData['season_count'] != null) {
          final seasonsData = await apiService.getSeasons(event.filmId);
          final seasonMapping = {
            for (var i = 0; i < seasonsData.length; i++)
              i + 1: seasonsData[i]['season_id'] as int?,
          };
          emit(state.copyWith(seasonMapping: seasonMapping, selectedSeason: 1));
          add(FetchEpisodesEvent(clearExisting: true));
        }
      } catch (e) {
        emit(state.copyWith(isLoading: false));
      }
    });

    on<SelectSeasonEvent>((event, emit) async {
      emit(state.copyWith(selectedSeason: event.season));
      add(FetchEpisodesEvent(clearExisting: true));
    });

    on<FetchEpisodesEvent>((event, emit) async {
      if (state.selectedSeason == null || state.isLoadingMore) return;
      emit(
        state.copyWith(
          isLoadingMore: true,
          episodes: event.clearExisting ? [] : state.episodes,
        ),
      );
      try {
        final effectiveSeason = state.seasonMapping[state.selectedSeason];
        if (effectiveSeason != null) {
          final episodeData = await apiService.getEpisodes(
            state.film!['id'],
            effectiveSeason,
            page: state.page,
            perPage: 20,
          );
          final newEpisodes = episodeData
              .where(
                (e) => !state.episodes.any((existing) => existing['id'] == e['id']),
              )
              .toList();
          emit(
            state.copyWith(
              episodes:
                  event.clearExisting ? newEpisodes : [...state.episodes, ...newEpisodes],
              page: event.clearExisting ? 2 : state.page + 1,
              isLoadingMore: false,
              hasMoreEpisodes: episodeData.length == 20,
            ),
          );
        } else {
          emit(
            state.copyWith(
              episodes: [],
              isLoadingMore: false,
              hasMoreEpisodes: false,
            ),
          );
        }
      } catch (e) {
        emit(state.copyWith(isLoadingMore: false));
      }
    });

    on<PlayVideoEvent>((event, emit) async {
      final validUrl = await _getValidStreamUrl(event.url);
      if (validUrl.isNotEmpty) {
        Navigator.push(
          event.context,
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(videoUrl: validUrl, title: event.title),
          ),
        );
      }
    });
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 100 &&
        !state.isLoadingMore &&
        state.hasMoreEpisodes &&
        state.isSerial) {
      add(FetchEpisodesEvent());
    }
  }

  Future<String> _getValidStreamUrl(String initialUrl) async {
    try {
      final response = await apiService.checkUrlValidity(initialUrl);
      if (response['isValid'] == true) return initialUrl;
    } catch (e) {}
    try {
      final updatedFilmData = await apiService.getFilmDetails(state.film!['id']);
      final newUrl =
          updatedFilmData['lastSeries']?[0]?['track']?[0]?['stream_url'] ?? '';
      emit(state.copyWith(film: updatedFilmData));
      return newUrl;
    } catch (e) {
      return initialUrl;
    }
  }

  @override
  Future<void> close() {
    scrollController.dispose();
    return super.close();
  }
}

sealed class FilmEvent {
  BuildContext get context => BuildContext();
}

class FetchFilmDetailsEvent extends FilmEvent {
  final int filmId;
  FetchFilmDetailsEvent(this.filmId);
}

class SelectSeasonEvent extends FilmEvent {
  final int season;
  SelectSeasonEvent(this.season);
}

class FetchEpisodesEvent extends FilmEvent {
  final bool clearExisting;
  FetchEpisodesEvent({this.clearExisting = false});
}

class PlayVideoEvent extends FilmEvent {
  final String url;
  final String title;
  @override
  final BuildContext context;

  PlayVideoEvent(this.url, this.title, {this.context = const BuildContext()});
}

class FilmState {
  final Map<String, dynamic>? film;
  final List<dynamic> episodes;
  final int? selectedSeason;
  final Map<int, int?> seasonMapping;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMoreEpisodes;
  final int page;
  final bool isSerial;

  FilmState({
    this.film,
    required this.episodes,
    this.selectedSeason,
    required this.seasonMapping,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMoreEpisodes,
    required this.page,
    required this.isSerial,
  });

  factory FilmState.initial() => FilmState(
        episodes: [],
        seasonMapping: {},
        isLoading: true,
        isLoadingMore: false,
        hasMoreEpisodes: true,
        page: 1,
        isSerial: false,
      );

  FilmState copyWith({
    Map<String, dynamic>? film,
    List<dynamic>? episodes,
    int? selectedSeason,
    Map<int, int?>? seasonMapping,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMoreEpisodes,
    int? page,
    bool? isSerial,
  }) =>
      FilmState(
        film: film ?? this.film,
        episodes: episodes ?? this.episodes,
        selectedSeason: selectedSeason ?? this.selectedSeason,
        seasonMapping: seasonMapping ?? this.seasonMapping,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMoreEpisodes: hasMoreEpisodes ?? this.hasMoreEpisodes,
        page: page ?? this.page,
        isSerial: isSerial ?? this.isSerial,
      );
}

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;

  const VideoPlayerScreen({
    required this.videoUrl,
    required this.title,
    super.key,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late BetterPlayerController _betterPlayerController;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    WakelockPlus.enable();
  }

  void _initializePlayer() {
    _betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: true,
        fit: BoxFit.contain,
        fullScreenByDefault: true,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enablePlayPause: true,
          enableMute: true,
          enableProgressText: true,
          enableSkips: true,
          enableQualities: true,
          enableAudioTracks: true,
        ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.videoUrl,
        resolutions: widget.videoUrl.endsWith('.m3u8') ? null : {"SD": widget.videoUrl},
        notificationConfiguration: const BetterPlayerNotificationConfiguration(
          showNotification: false,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      _betterPlayerController.dispose();
      _isDisposed = true;
    }
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: Colors.white, size: 30),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: BetterPlayer(controller: _betterPlayerController),
    );
  }
}