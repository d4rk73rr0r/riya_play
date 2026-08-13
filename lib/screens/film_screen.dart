import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/screens/films_full_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/services/preferences_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:shimmer/shimmer.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/utils/episode_naming.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:riya_play/screens/download_screen.dart';
import 'package:riya_play/screens/actor_films_screen.dart';
import 'package:riya_play/utils/video_launcher.dart';
import 'package:flutter_iconly/flutter_iconly.dart';

class FilmScreen extends StatefulWidget {
  final int filmId;

  /// Matches the tag the source [PosterCard] used, if any, so the poster
  /// morphs into this banner instead of just cutting to the new screen.
  /// Left null (default), this banner renders without a [Hero] wrapper —
  /// safe for callers that don't set up a matching tag on their side.
  final String? heroTag;

  const FilmScreen({required this.filmId, super.key, this.heroTag});

  @override
  State<FilmScreen> createState() => _FilmScreenState();
}

class _FilmScreenState extends State<FilmScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? film;
  Map<int, List<dynamic>> episodesBySeason = {};
  Map<int, Set<int>> loadedEpisodeIdsBySeason = {};
  int? selectedSeason;
  Map<int, int?> seasonMapping = {};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool isFavorite = false;
  double _scale = 1.0;
  bool _isAnimating = false;
  TabController? _tabController;
  DateTime? _lastSelectionTime;

  static final Map<int, Map<String, dynamic>> _filmCache = {};
  static final Map<int, DateTime> _filmCacheTimestamps = {};
  static final Map<int, List<dynamic>> _seasonsCache = {};
  static final Map<int, DateTime> _seasonsCacheTimestamps = {};
  static final Map<String, List<dynamic>> _episodesCache = {};
  static final Map<String, DateTime> _episodesCacheTimestamps = {};

  @override
  void initState() {
    super.initState();
    _loadFilmDetails();
    StorageUtils().cleanOldPlaybackPositions();
  }

  Future<void> _toggleFavorite() async {
    if (_isAnimating || !mounted) return;

    setState(() {
      _isAnimating = true;
      _scale = 1.5;
    });

    await Future.delayed(const Duration(milliseconds: 150));

    setState(() {
      _scale = 1.0;
    });

    try {
      setState(() {
        isFavorite = !isFavorite;
      });

      bool success;
      if (isFavorite) {
        success = await ApiService.addToFavorite(widget.filmId);
      } else {
        success = await ApiService.removeFromFavorite(widget.filmId);
      }

      if (!success && mounted) {
        setState(() {
          isFavorite = !isFavorite;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Sevimlilarni yangilashda xato yuz berdi"),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isFavorite = !isFavorite;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Xato yuz berdi, qayta urinib ko‘ring")),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnimating = false;
        });
      }
    }
  }

  Future<void> _loadFilmDetails() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final results = await Future.wait<Map<String, dynamic>>([
        _filmCache.containsKey(widget.filmId) &&
                _filmCacheTimestamps[widget.filmId] != null &&
                DateTime.now()
                        .difference(_filmCacheTimestamps[widget.filmId]!)
                        .inHours <
                    24
            ? Future.value(_filmCache[widget.filmId]!)
            : ApiService.getFilmDetails(widget.filmId).timeout(
              const Duration(seconds: 10),
              onTimeout:
                  () =>
                      throw Exception("Film ma‘lumotlari yuklanmadi: Timeout"),
            ),
      ]);

      final filmData = results[0];

      if (mounted) {
        setState(() {
          film = filmData;
          _filmCache[widget.filmId] = filmData;
          _filmCacheTimestamps[widget.filmId] = DateTime.now();
          isFavorite =
              filmData.containsKey('favorite') && filmData['favorite'] == 1;
          _isLoading = false;
        });

        if (isSerial() && film?['season_count'] != null) {
          await _mapSeasons();
          if (mounted) {
            final seasonCount = film!['season_count'] as int? ?? 1;
            if (seasonCount > 0) {
              setState(() {
                selectedSeason = 1;
                _tabController = TabController(
                  length: seasonCount,
                  vsync: this,
                );
                for (var i = 1; i <= seasonCount; i++) {
                  episodesBySeason[i] = [];
                  loadedEpisodeIdsBySeason[i] = {};
                }
                _tabController!.addListener(() {
                  if (!_tabController!.indexIsChanging) {
                    _onSeasonSelected(_tabController!.index + 1);
                  }
                });
              });
              await _loadEpisodes(selectedSeason!, clearExisting: true);
            }
          }
        }
        _precacheImages();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Film ma‘lumotlarini yuklashda xato yuz berdi"),
          ),
        );
      }
    }
  }

  Future<void> _mapSeasons() async {
    try {
      final seasonsData =
          _seasonsCache.containsKey(widget.filmId) &&
                  _seasonsCacheTimestamps[widget.filmId] != null &&
                  DateTime.now()
                          .difference(_seasonsCacheTimestamps[widget.filmId]!)
                          .inHours <
                      24
              ? _seasonsCache[widget.filmId]!
              : await ApiService.getSeasons(widget.filmId).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw Exception("Fasllar yuklanmadi: Timeout"),
              );

      appLogger.d("Seasons data: $seasonsData");

      _seasonsCache[widget.filmId] = seasonsData;
      _seasonsCacheTimestamps[widget.filmId] = DateTime.now();

      final Map<int, int?> seasonMappingTemp = {};
      for (var i = 0; i < seasonsData.length; i++) {
        seasonMappingTemp[i + 1] = seasonsData[i]['season_id'] as int?;
      }
      if (mounted) {
        setState(() => seasonMapping = seasonMappingTemp);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Fasllarni yuklashda xato yuz berdi")),
        );
      }
    }
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      film = null;
      episodesBySeason.clear();
      loadedEpisodeIdsBySeason.clear();
      seasonMapping.clear();
      selectedSeason = null;
    });
    await _loadFilmDetails();
  }

  Future<void> _loadEpisodes(
    int seasonNumber, {
    bool clearExisting = false,
  }) async {
    if (_isLoadingMore || !mounted) return;

    setState(() => _isLoadingMore = true);

    final int? effectiveSeason = seasonMapping[seasonNumber];
    if (effectiveSeason == null) {
      if (mounted) {
        setState(() {
          episodesBySeason[seasonNumber] = [];
          _isLoadingMore = false;
        });
      }
      return;
    }

    final cacheKey = "${widget.filmId}_$effectiveSeason";
    try {
      if (_episodesCache.containsKey(cacheKey) &&
          !clearExisting &&
          _episodesCache[cacheKey]!.isNotEmpty &&
          _episodesCacheTimestamps[cacheKey] != null &&
          DateTime.now()
                  .difference(_episodesCacheTimestamps[cacheKey]!)
                  .inHours <
              24) {
        if (mounted) {
          setState(() {
            if (clearExisting) {
              episodesBySeason[seasonNumber] = [];
              loadedEpisodeIdsBySeason[seasonNumber] = {};
            }
            episodesBySeason[seasonNumber] = _episodesCache[cacheKey]!;
            for (var episode in episodesBySeason[seasonNumber]!) {
              final episodeId = episode['id'] as int?;
              if (episodeId != null) {
                loadedEpisodeIdsBySeason[seasonNumber]!.add(episodeId);
              }
            }
            _isLoadingMore = false;
          });
        }
      } else {
        final stopwatch = Stopwatch()..start();
        final episodeData = await ApiService.getEpisodes(
          widget.filmId,
          effectiveSeason,
          page: 1,
          perPage: 20,
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception("Epizodlar yuklanmadi: Timeout"),
        );
        appLogger.d(
          "Epizodlar yuklash vaqti: ${stopwatch.elapsedMilliseconds} ms",
        );
        if (mounted) {
          setState(() {
            if (clearExisting) {
              episodesBySeason[seasonNumber] = [];
              loadedEpisodeIdsBySeason[seasonNumber] = {};
            }
            if (episodeData.isNotEmpty) {
              episodesBySeason[seasonNumber] = episodeData;
              _episodesCache[cacheKey] = episodeData;
              _episodesCacheTimestamps[cacheKey] = DateTime.now();
              for (var episode in episodeData) {
                final episodeId = episode['id'] as int?;
                if (episodeId != null &&
                    !loadedEpisodeIdsBySeason[seasonNumber]!.contains(
                      episodeId,
                    )) {
                  loadedEpisodeIdsBySeason[seasonNumber]!.add(episodeId);
                }
              }
            } else {
              episodesBySeason[seasonNumber] = [];
            }
            _isLoadingMore = false;
          });
        }
      }
      _precacheImages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Epizodlarni yuklashda xato yuz berdi")),
        );
      }
    }
  }

  void _onSeasonSelected(int season) {
    HapticFeedback.lightImpact();
    final now = DateTime.now();
    if (_lastSelectionTime != null &&
        now.difference(_lastSelectionTime!).inMilliseconds < 500) {
      return;
    }
    _lastSelectionTime = now;
    if (mounted) {
      setState(() => selectedSeason = season);
      if (episodesBySeason[season] == null ||
          episodesBySeason[season]!.isEmpty) {
        _loadEpisodes(season, clearExisting: true);
      }
    }
  }

  Future<String> _getValidStreamUrl(String initialUrl) async {
    try {
      final response = await ApiService.checkUrlValidity(initialUrl).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception("URL tekshiruvi: Timeout"),
      );
      if (response['isValid'] == true) return initialUrl;
    } catch (e) {}

    try {
      final updatedFilmData = await ApiService.getFilmDetails(
        widget.filmId,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw Exception("Yangi URL olish: Timeout"),
      );
      final newUrl =
          updatedFilmData['lastSeries']?[0]?['track']?[0]?['stream_url'] ?? '';
      if (mounted) {
        setState(() => film = updatedFilmData);
        _filmCache[widget.filmId] = updatedFilmData;
        _filmCacheTimestamps[widget.filmId] = DateTime.now();
      }
      return newUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Video URL olishda xato yuz berdi")),
        );
      }
      return initialUrl;
    }
  }

  bool isSerial() {
    return film?['type']?['name_uz'] == "Serial";
  }

  Future<void> _startDownload() async {
    if (!mounted) return;
    HapticFeedback.lightImpact();

    // Serialda "film" degan yagona fayl yo'q — foydalanuvchi qaysi qismni
    // yuklashini epizodlar ro'yxatidan tanlaydi.
    if (isSerial()) {
      Navigator.push(
        context,
        createSlideRoute(
          FilmsFullScreen(
            filmId: widget.filmId,
            filmName: film?['name_uz'] ?? 'Noma‘lum',
          ),
        ),
      );
      return;
    }

    final lastSeriesList = film?['lastSeries'] as List<dynamic>?;
    final trackList =
        (lastSeriesList != null && lastSeriesList.isNotEmpty)
            ? lastSeriesList[0]['track'] as List<dynamic>?
            : null;
    if (trackList == null || trackList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Yuklab olish uchun video topilmadi")),
      );
      return;
    }

    final streamUrl = trackList[0]['stream_url'] ?? '';
    final validUrl = await _getValidStreamUrl(streamUrl);
    if (!mounted) return;
    if (validUrl.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Video URL topilmadi")));
      return;
    }

    Navigator.push(
      context,
      createSlideRoute(
        DownloadScreen(
          videoUrl: validUrl,
          title: film?['name_uz'] ?? 'Noma‘lum',
        ),
      ),
    );
  }

  /// Director first, then cast. `getFilmDetails` already asks for
  /// `actors.files` and `maker.files`, so this costs no extra request — the
  /// data was being fetched and thrown away.
  List<Map<String, dynamic>> _buildCast() {
    final cast = <Map<String, dynamic>>[];

    String? photoOf(Map person) {
      final files = person['files'];
      if (files is List && files.isNotEmpty) {
        return files[0]['linkAbsolute'] as String?;
      }
      return null;
    }

    final maker = film?['maker'];
    if (maker is Map) {
      cast.add({
        'id': maker['id'],
        'name': maker['name_uz'] ?? maker['name_ru'] ?? 'Rejissyor',
        'photo': photoOf(maker),
        'role': 'Rejissyor',
      });
    }

    final actors = film?['actors'];
    if (actors is List) {
      for (final actor in actors) {
        if (actor is! Map) continue;
        cast.add({
          'id': actor['id'],
          'name': actor['name_uz'] ?? actor['name_ru'] ?? 'Aktyor',
          'photo': photoOf(actor),
          'role': 'Aktyor',
        });
      }
    }
    return cast;
  }

  Widget _buildCastStrip(ThemeProvider themeProvider) {
    final cast = _buildCast();
    if (cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Aktyorlar va rejissyor",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: themeProvider.textColor,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final person = cast[index];
              final id = person['id'] as int?;
              return _CastTile(
                name: person['name'] as String,
                role: person['role'] as String,
                photoUrl: person['photo'] as String?,
                themeProvider: themeProvider,
                // Rejissyor uchun alohida endpoint yo'q — faqat aktyorlar
                // bosiladigan bo'ladi.
                onTap:
                    (id == null || person['role'] != 'Aktyor')
                        ? null
                        : () {
                          HapticFeedback.lightImpact();
                          Navigator.push(
                            context,
                            createSlideRoute(
                              ActorFilmsScreen(
                                actorId: id,
                                actorName: person['name'] as String,
                              ),
                            ),
                          );
                        },
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  /// Serial bo'lmagan film uchun "Ko'rishni boshlash".
  ///
  /// Epizod odatda `film.lastSeries` da keladi, lekin ba'zi javoblarda u
  /// umuman yo'q yoki `track` siz keladi — o'shanda tugma umuman ishlamasdi.
  /// Bunday holda epizod to'g'ridan-to'g'ri so'raladi.
  Future<void> _playSingleFilm() async {
    final lastSeries = film?['lastSeries'] as List<dynamic>? ?? const [];
    Map<String, dynamic>? episode =
        lastSeries.isNotEmpty ? lastSeries.first as Map<String, dynamic>? : null;
    var trackList = episode?['track'] as List<dynamic>?;

    if (trackList == null || trackList.isEmpty) {
      episode = await ApiService.getFirstEpisode(widget.filmId);
      trackList = episode?['track'] as List<dynamic>?;
    }
    if (!mounted) return;

    final streamUrl =
        (trackList != null && trackList.isNotEmpty)
            ? (trackList.first['stream_url'] as String? ?? '')
            : '';
    if (episode == null || streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Film uchun video mavjud emas")),
      );
      return;
    }

    await _playVideo(
      streamUrl,
      film?['name_uz'] ?? 'Noma‘lum',
      episodeId: episode['id'] as int?,
    );
  }

  /// [title] pleer sarlavhasi uchun ("3-qism" kabi qisqa nom), [downloadTitle]
  /// esa fayl nomi uchun — epizodlar uchun ular farq qiladi.
  Future<void> _playVideo(
    String url,
    String title, {
    String? downloadTitle,
    int? episodeId,
  }) async {
    if (!mounted) return;

    HapticFeedback.lightImpact();
    final validUrl = await _getValidStreamUrl(url);
    if (validUrl.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Video URL topilmadi")));
      }
      return;
    }
    if (!mounted) return;

    // Pozitsiya so'rovi, "Davom ettirish?" va pleer tanlash dialoglari
    // `VideoLauncher` da — bu ekran bilan `FilmsFullScreen` da bir xil nusxa
    // turardi va faqat bittasi tuzatilar edi.
    await VideoLauncher.playWithChooser(
      context,
      url: validUrl,
      title: title,
      downloadTitle: downloadTitle,
      episodeId: episodeId,
    );
  }

  void _precacheImages() {
    Future.microtask(() {
      final coverUrl =
          film != null && film!['files'] != null && film!['files'].isNotEmpty
              ? film!['files'][0]['linkAbsolute'] ??
                  'https://placehold.co/150x150'
              : 'https://placehold.co/150x150';
      precacheImage(
        CachedNetworkImageProvider(coverUrl, cacheManager: filmImagesCacheManager),
        context,
        onError: (_, __) {},
      );

      final episodes = episodesBySeason[selectedSeason] ?? [];
      for (var episode in episodes) {
        final screenshot =
            episode['screenshots'] != null &&
                    episode['screenshots'].isNotEmpty &&
                    episode['screenshots'][0]['file'] != null &&
                    episode['screenshots'][0]['file'].isNotEmpty &&
                    episode['screenshots'][0]['file'][0]['thumbnails'] !=
                        null &&
                    episode['screenshots'][0]['file'][0]['thumbnails']['small'] !=
                        null
                ? episode['screenshots'][0]['file'][0]['thumbnails']['small']['src']
                : 'https://placehold.co/150x150';
        precacheImage(
          CachedNetworkImageProvider(
            screenshot,
            cacheManager: filmImagesCacheManager,
          ),
          context,
          onError: (_, __) {},
        );
      }
    });
  }

  String _getGenresText(List<dynamic> genres) {
    if (genres.isEmpty) return 'Noma‘lum';
    return genres.map((genre) => genre['name_uz'] ?? 'Noma‘lum').join(', ');
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Widget _buildSkeletonLoader() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 5,
      itemBuilder:
          (context, index) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Shimmer.fromColors(
              baseColor:
                  themeProvider.isDarkMode
                      ? Colors.grey[700]!
                      : Colors.grey[300]!,
              highlightColor:
                  themeProvider.isDarkMode
                      ? Colors.grey[600]!
                      : Colors.grey[100]!,
              child: SizedBox(
                width: (MediaQuery.of(context).size.width - 32) / 2 - 12,
                height: 136,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: (MediaQuery.of(context).size.width - 32) / 2 - 12,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: themeProvider.cardColor,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, right: 8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 100,
                            height: 12,
                            color: themeProvider.cardColor,
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 50,
                            height: 12,
                            color: themeProvider.cardColor,
                          ),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildBannerImage() {
    final coverUrl =
        film != null && film!['files'] != null && film!['files'].isNotEmpty
            ? film!['files'][0]['linkAbsolute'] ??
                'https://placehold.co/150x150'
            : 'https://placehold.co/150x150';
    final image = CachedNetworkImage(
      imageUrl: coverUrl,
      cacheManager: filmImagesCacheManager,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
    return widget.heroTag == null
        ? image
        : Hero(tag: widget.heroTag!, child: image);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      extendBodyBehindAppBar: true, // Muqova AppBar orqasiga cho‘ziladi
      appBar: AppBar(
        backgroundColor: Colors.transparent, // Fonni to‘liq shaffof qilamiz
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.chevron_left,
            color: themeProvider.iconColor,
            size: 32,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : film == null
              ? Center(
                child: Text(
                  "Film ma‘lumotlari topilmadi",
                  style: TextStyle(
                    fontSize: 16,
                    color: themeProvider.subTextColor,
                  ),
                ),
              )
              : RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // To‘liq ekran kengligida muqova bilan qoramtir gradient
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          // Tasvir qatlami
                          SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _buildBannerImage(),
                          ),
                          // Gradient qatlami
                          Container(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height * 0.6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent, // Yuqori qism shaffof
                                  Colors.black.withOpacity(
                                    0.7,
                                  ), // Pastroq qoramtirlik
                                ],
                                stops: const [
                                  0.6,
                                  1.0,
                                ], // Gradient pastki 40% da qorayadi
                              ),
                            ),
                          ),
                          // Status bar va orqaga tugmasi uchun qoramtirlik.
                          // Muqova endi status bar ortidan ko'rinadi, shuning
                          // uchun ochiq rangli muqovada oq ikonkalar yo'qolib
                          // ketmasligi kerak. Bu qatlam AppBar'ning
                          // flexibleSpace'i o'rniga shu yerda: muqova bilan
                          // bitta Stack'da bo'lgani uchun aniq ustiga tushadi.
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Container(
                                height:
                                    MediaQuery.of(context).padding.top +
                                    kToolbarHeight,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withOpacity(0.65),
                                      Colors.black.withOpacity(0.25),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.55, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // "Ko‘rishni boshlash" va "Sevimli" tugmalari yonma-yon
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      if (isSerial()) {
                                        Navigator.push(
                                          context,
                                          createSlideRoute(
                                            FilmsFullScreen(
                                              filmId: widget.filmId,
                                              filmName:
                                                  film?['name_uz'] ??
                                                  'Noma‘lum',
                                            ),
                                          ),
                                        );
                                      } else {
                                        _playSingleFilm();
                                      }
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          themeProvider
                                              .buttonColor, // Asosiy tugma rangi
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ), // Balandlikni belgilash
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.play_arrow, size: 20),
                                        SizedBox(width: 8),
                                        Text(
                                          "Ko‘rishni boshlash",
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _startDownload,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: themeProvider.buttonColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    minimumSize: const Size(56, 0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: const Icon(
                                    IconlyLight.download,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  onPressed: _toggleFavorite,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        themeProvider
                                            .buttonColor, // Xuddi shu rang
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ), // Xuddi shu balandlik
                                    minimumSize: const Size(
                                      56,
                                      0,
                                    ), // Minimal kenglikni belgilash
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: AnimatedScale(
                                    scale: _scale,
                                    duration: const Duration(milliseconds: 150),
                                    curve: Curves.easeInOut,
                                    child: Icon(
                                      isFavorite
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color:
                                          isFavorite
                                              ? Colors.red
                                              : themeProvider
                                                  .iconColor, // Qizil rang shartli
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Kontent nomi, yili va boshqa ma‘lumotlar
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${film?['name_uz'] ?? 'Noma‘lum'} (${film?['year'] ?? 'Noma‘lum'})",
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: themeProvider.textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (isSerial() &&
                                    film?['season_count'] != null &&
                                    film?['episode_count'] != null)
                                  Text(
                                    "${film?['season_count']} fasl, ${film?['episode_count']} qism",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: themeProvider.subTextColor,
                                    ),
                                  ),
                                Text(
                                  "Janr: ${_getGenresText(film?['genres'] ?? [])}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: themeProvider.subTextColor,
                                  ),
                                ),
                                Text(
                                  "Kinopoisk: ${film?['kinopoisk_rating'] ?? 'Noma‘lum'}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: themeProvider.subTextColor,
                                  ),
                                ),
                                Text(
                                  "IMDb: ${film?['imdb_rating'] ?? 'Noma‘lum'}",
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: themeProvider.subTextColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Tavsif sarlavhasi olib tashlandi, faqat matn qoldi
                            Text(
                              film?['description_uz'] ?? "Tavsif mavjud emas",
                              style: TextStyle(
                                fontSize: 14,
                                color: themeProvider.subTextColor,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildCastStrip(themeProvider),
                            if (!isSerial() &&
                                film != null &&
                                film!['lastSeries'] != null &&
                                film!['lastSeries'].isNotEmpty)
                              const SizedBox.shrink(),
                            if (isSerial()) ...[
                              const SizedBox(height: 16),
                              if (_tabController != null &&
                                  (film?['season_count'] ?? 0) > 0)
                                TabBar(
                                  controller: _tabController,
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  indicatorColor:
                                      themeProvider.currentDeviceIconColor,
                                  labelColor: themeProvider.textColor,
                                  unselectedLabelColor:
                                      themeProvider.subTextColor,
                                  tabs: List.generate(
                                    film != null &&
                                            film!['season_count'] != null
                                        ? film!['season_count'] as int
                                        : 1,
                                    (index) => Tab(text: "Fasl ${index + 1}"),
                                  ),
                                  onTap: (index) {
                                    _onSeasonSelected(index + 1);
                                  },
                                )
                              else
                                const SizedBox.shrink(),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 136,
                                child:
                                    _isLoadingMore
                                        ? _buildSkeletonLoader()
                                        : (episodesBySeason[selectedSeason] ??
                                                [])
                                            .isEmpty
                                        ? Center(
                                          child: Text(
                                            "Bu fasl uchun epizodlar topilmadi yoki ularga kirish imkoni yo‘q",
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: themeProvider.subTextColor,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        )
                                        : ListView.builder(
                                          scrollDirection: Axis.horizontal,
                                          cacheExtent: 1000,
                                          itemCount:
                                              episodesBySeason[selectedSeason]
                                                  ?.length ??
                                              0,
                                          itemBuilder: (context, index) {
                                            final episode =
                                                episodesBySeason[selectedSeason]![index];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                right: 12,
                                              ),
                                              child: EpisodeCard(
                                                episode: episode,
                                                index: index,
                                                onTap: () {
                                                  final trackList =
                                                      episode['track']
                                                          as List<dynamic>?;
                                                  if (trackList != null &&
                                                      trackList.isNotEmpty) {
                                                    final streamUrl =
                                                        trackList[0]['stream_url'] ??
                                                        '';
                                                    _playVideo(
                                                      streamUrl,
                                                      episode['name_uz'] ??
                                                          "Qism ${index + 1}",
                                                      downloadTitle:
                                                          buildEpisodeDownloadTitle(
                                                            seriesName:
                                                                film?['name_uz'] ??
                                                                'Noma‘lum',
                                                            seasonNumber:
                                                                selectedSeason ??
                                                                1,
                                                            episodeIndex: index,
                                                            episodeName:
                                                                episode['name_uz'],
                                                          ),
                                                      episodeId:
                                                          episode['id'] as int?,
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                          "Epizod uchun video mavjud emas",
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                },
                                              ),
                                            );
                                          },
                                        ),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    createSlideRoute(
                                      FilmsFullScreen(
                                        filmId: widget.filmId,
                                        filmName:
                                            film?['name_uz'] ?? 'Noma‘lum',
                                      ),
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: themeProvider.buttonColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  minimumSize: const Size(double.infinity, 0),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                child: const Text(
                                  "Barcha qismlar",
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
    );
  }
}

class EpisodeCard extends StatelessWidget {
  final dynamic episode;
  final int index;
  final VoidCallback onTap;

  const EpisodeCard({
    super.key,
    required this.episode,
    required this.index,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isLastSeen = episode['is_last_seen'] == true;

    return SizedBox(
      width: (MediaQuery.of(context).size.width - 32) / 2 - 12,
      height: 136,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: (MediaQuery.of(context).size.width - 32) / 2 - 12,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: themeProvider.cardColor,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  HapticFeedback.lightImpact();
                  onTap();
                },
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(
                        imageUrl:
                            episode['screenshots'] != null &&
                                    episode['screenshots'].isNotEmpty &&
                                    episode['screenshots'][0]['file'] != null &&
                                    episode['screenshots'][0]['file']
                                        .isNotEmpty &&
                                    episode['screenshots'][0]['file'][0]['thumbnails'] !=
                                        null &&
                                    episode['screenshots'][0]['file'][0]['thumbnails']['small'] !=
                                        null
                                ? episode['screenshots'][0]['file'][0]['thumbnails']['small']['src']
                                : 'https://placehold.co/150x150',
                        cacheManager: filmImagesCacheManager,
                        width:
                            (MediaQuery.of(context).size.width - 32) / 2 - 12,
                        height: 100,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => Container(
                              width:
                                  (MediaQuery.of(context).size.width - 32) / 2 -
                                  12,
                              height: 100,
                              color: Colors.transparent,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: themeProvider.accentColor,
                                ),
                              ),
                            ),
                        errorWidget:
                            (context, url, error) => Container(
                              width:
                                  (MediaQuery.of(context).size.width - 32) / 2 -
                                  12,
                              height: 100,
                              color: themeProvider.cardColor,
                              child: const Icon(Icons.broken_image),
                            ),
                      ),
                    ),
                    if (isLastSeen)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54.withOpacity(
                              themeProvider.isDarkMode ? 0.7 : 0.5,
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            "So'nggi ko'rilgan",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4.0, right: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  episode['name_uz'] ?? "Qism ${index + 1}",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: themeProvider.textColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (episode['duration'] != null)
                  Text(
                    _formatDuration(episode['duration']),
                    style: TextStyle(
                      fontSize: 12,
                      color: themeProvider.subTextColor,
                    ),
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final duration = Duration(seconds: seconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final secs = twoDigits(duration.inSeconds.remainder(60));

    if (duration.inHours > 0) {
      return '$hours:$minutes:$secs';
    } else {
      return '$minutes:$secs';
    }
  }
}

/// One person in the cast strip. Directors are rendered the same way but
/// without a tap target, since there is no per-director listing endpoint.
class _CastTile extends StatelessWidget {
  final String name;
  final String role;
  final String? photoUrl;
  final ThemeProvider themeProvider;
  final VoidCallback? onTap;

  const _CastTile({
    required this.name,
    required this.role,
    required this.photoUrl,
    required this.themeProvider,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;

    return SizedBox(
      width: 84,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(42),
        child: Column(
          children: [
            ClipOval(
              child: SizedBox(
                width: 72,
                height: 72,
                child:
                    url == null || url.isEmpty
                        ? Container(
                          color: themeProvider.cardColor,
                          child: Icon(
                            Icons.person,
                            color: themeProvider.subTextColor,
                          ),
                        )
                        : CachedNetworkImage(
                          imageUrl: url,
                          cacheManager: filmImagesCacheManager,
                          fit: BoxFit.cover,
                          placeholder:
                              (_, __) =>
                                  Container(color: themeProvider.cardColor),
                          errorWidget:
                              (_, __, ___) => Container(
                                color: themeProvider.cardColor,
                                child: Icon(
                                  Icons.person,
                                  color: themeProvider.subTextColor,
                                ),
                              ),
                        ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: themeProvider.textColor),
            ),
            Text(
              role,
              style: TextStyle(fontSize: 10, color: themeProvider.subTextColor),
            ),
          ],
        ),
      ),
    );
  }
}
