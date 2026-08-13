import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/theme_provider.dart';
import 'dart:async';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/utils/pagination_controller.dart';
import 'package:riya_play/utils/episode_naming.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/screens/download_screen.dart';
import 'package:riya_play/services/download_manager.dart';
import 'package:riya_play/services/download_service.dart';
import 'package:riya_play/utils/video_launcher.dart';

class FilmsFullScreen extends StatefulWidget {
  final int filmId;
  final String filmName;

  const FilmsFullScreen({
    required this.filmId,
    required this.filmName,
    super.key,
  });

  @override
  State<FilmsFullScreen> createState() => _FilmsFullScreenState();
}

class _FilmsFullScreenState extends State<FilmsFullScreen>
    with SingleTickerProviderStateMixin {
  List<dynamic> seasons = [];
  Map<int, int?> seasonMapping = {};
  Map<int, PaginationController<dynamic>> episodeControllers = {};
  late TabController _tabController;
  bool _isInitialLoading = true;

  /// Episodes ticked for a batch download, keyed by episode id so the same
  /// item can't be added twice and so a selection survives scrolling and
  /// season switches. Non-empty means the grid is in selection mode.
  final Map<int, ({String videoUrl, String title})> _selected = {};

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSeasons();
  }

  Future<void> _loadSeasons() async {
    if (!mounted) return;

    setState(() => _isInitialLoading = true);

    try {
      final seasonsData = await ApiService.getSeasons(widget.filmId);
      final Map<int, int?> seasonMappingTemp = {};
      for (var i = 0; i < seasonsData.length; i++) {
        seasonMappingTemp[i + 1] = seasonsData[i]['season_id'] as int?;
      }

      if (mounted) {
        setState(() {
          seasons = seasonsData;
          seasonMapping = seasonMappingTemp;
          _isInitialLoading = false;
          _tabController = TabController(length: seasons.length, vsync: this);
          // Har bir fasl uchun alohida pagination controller
          for (var i = 1; i <= seasons.length; i++) {
            episodeControllers[i] =
                PaginationController<dynamic>(
                    fetchPage: (page) => _fetchEpisodesPage(i, page),
                    idOf: (episode) => episode['id'],
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
                  ..init(loadImmediately: false);
          }
        });
        // Birinchi fasl epizodlarini yuklash
        episodeControllers[1]!.loadInitial();

        // Tab o'zgarganda epizodlarni yuklash
        _tabController.addListener(() {
          if (!_tabController.indexIsChanging) {
            final seasonNumber = _tabController.index + 1;
            final controller = episodeControllers[seasonNumber]!;
            if (controller.items.isEmpty && !controller.isLoading) {
              controller.loadInitial();
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInitialLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ApiErrorHandler.handle(e).userMessage)));
      }
    }
  }

  Future<PageResult<dynamic>> _fetchEpisodesPage(
    int seasonNumber,
    int page,
  ) async {
    final int? effectiveSeason = seasonMapping[seasonNumber];
    if (effectiveSeason == null) {
      return const PageResult(items: [], hasMore: false);
    }
    final episodeData = await ApiService.getEpisodes(
      widget.filmId,
      effectiveSeason,
      page: page,
      perPage: 20,
    );
    return PageResult(items: episodeData, hasMore: episodeData.length == 20);
  }

  /// Ticks or unticks one episode. Episodes with no playable track are
  /// rejected here rather than failing later in the queue.
  void _toggleSelection(dynamic episode, int index, int seasonNumber) {
    final episodeId = episode['id'] as int?;
    if (episodeId == null) return;

    HapticFeedback.lightImpact();

    if (_selected.containsKey(episodeId)) {
      setState(() => _selected.remove(episodeId));
      return;
    }

    final tracks = episode['track'] as List<dynamic>?;
    final url =
        (tracks != null && tracks.isNotEmpty)
            ? (tracks[0]['stream_url'] as String? ?? '')
            : '';
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Epizod uchun video mavjud emas")),
      );
      return;
    }

    setState(() {
      _selected[episodeId] = (
        videoUrl: url,
        title: buildEpisodeDownloadTitle(
          seriesName: widget.filmName,
          seasonNumber: seasonNumber,
          episodeIndex: index,
          episodeName: episode['name_uz'],
        ),
      );
    });
  }

  void _clearSelection() => setState(_selected.clear);

  /// Queues exactly the ticked episodes, asking for a quality once.
  Future<void> _downloadSelected() async {
    final items = _selected.values.toList();
    if (items.isEmpty) return;

    final granted = await DownloadService.ensureStoragePermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Yuklab olish uchun xotiraga yozish ruxsati kerak"),
        ),
      );
      return;
    }

    final preferred = await _askQuality(items.first.videoUrl, items.length);
    if (preferred == null || !mounted) return;

    final added = DownloadManager.instance.enqueueAll(
      items,
      preferredQuality: preferred.isEmpty ? null : preferred,
    );
    final skipped = items.length - added;
    _clearSelection();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped > 0
              ? "$added ta qism navbatga qo‘shildi, $skipped tasi allaqachon bor"
              : "$added ta qism navbatga qo‘shildi",
        ),
      ),
    );
    Navigator.push(context, createSlideRoute(const DownloadScreen.queue()));
  }

  /// Asks once which tier to use for a batch. Returns an empty string when
  /// the stream offers no choice, and null when the user backed out.
  Future<String?> _askQuality(String sampleUrl, int count) async {
    final qualities = await DownloadService.fetchQualities(sampleUrl);
    if (!mounted) return null;
    if (qualities.isEmpty) return '';

    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text("Sifatni tanlang ($count qism)"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final quality in qualities)
                    ListTile(
                      leading: const Icon(Icons.video_settings),
                      title: Text(quality.label),
                      subtitle:
                          quality.resolution != null
                              ? Text(quality.resolution!)
                              : null,
                      onTap: () => Navigator.pop(context, quality.label),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Bekor qilish"),
              ),
            ],
          ),
    );
  }

  /// Queues every episode of a season (or of the whole series) in one go.
  ///
  /// Downloading a series used to mean walking the grid episode by episode,
  /// through a player dialog and a quality dialog each time — around three
  /// taps per episode, and the queue only ever held one item because leaving
  /// the screen cancelled it.
  Future<void> _downloadSeason() async {
    HapticFeedback.lightImpact();

    final granted = await DownloadService.ensureStoragePermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Yuklab olish uchun xotiraga yozish ruxsati kerak"),
        ),
      );
      return;
    }

    final currentSeason = _tabController.index + 1;

    // Bir nechta fasl bo'lsa, qamrovni so'raymiz.
    var allSeasons = false;
    if (seasons.length > 1) {
      final choice = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text("Nimani yuklaymiz?"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.playlist_add_check),
                      title: Text("Faqat $currentSeason-fasl"),
                      onTap: () => Navigator.pop(context, false),
                    ),
                    ListTile(
                      leading: const Icon(Icons.video_library),
                      title: Text("Barcha fasllar (${seasons.length} ta)"),
                      onTap: () => Navigator.pop(context, true),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Bekor qilish"),
                ),
              ],
            ),
      );
      if (choice == null || !mounted) return;
      allSeasons = choice;
    }

    final targets =
        allSeasons
            ? [for (var i = 1; i <= seasons.length; i++) i]
            : [currentSeason];

    // Ro'yxat sahifalab keladi, shuning uchun navbatga qo'yishdan oldin
    // barcha sahifalarni yig'ib olishimiz kerak.
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder:
            (context) => const AlertDialog(
              content: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 20),
                  Expanded(child: Text("Qismlar ro‘yxati yig‘ilmoqda...")),
                ],
              ),
            ),
      ),
    );

    List<({String videoUrl, String title})> items;
    try {
      items = await _collectEpisodes(targets);
    } catch (e) {
      if (mounted) Navigator.pop(context); // Kutish oynasi
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Qismlarni olishda xato: $e")));
      return;
    }

    if (mounted) Navigator.pop(context); // Kutish oynasi
    if (!mounted) return;

    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Yuklab olinadigan qism topilmadi")),
      );
      return;
    }

    // Sifat bir marta so'raladi va butun to'plamga qo'llanadi. Aniq manzil
    // emas, tier nomi saqlanadi: har bir qismning o'z master playlisti bor.
    final preferred = await _askQuality(items.first.videoUrl, items.length);
    if (preferred == null || !mounted) return;

    final added = DownloadManager.instance.enqueueAll(
      items,
      preferredQuality: preferred.isEmpty ? null : preferred,
    );
    final skipped = items.length - added;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          skipped > 0
              ? "$added ta qism navbatga qo‘shildi, $skipped tasi allaqachon bor"
              : "$added ta qism navbatga qo‘shildi",
        ),
      ),
    );
    Navigator.push(
      context,
      createSlideRoute(const DownloadScreen.queue()),
    );
  }

  /// Walks every page of each requested season and returns the downloadable
  /// episodes, named the same way a single-episode download would name them.
  Future<List<({String videoUrl, String title})>> _collectEpisodes(
    List<int> seasonNumbers,
  ) async {
    const perPage = 20;
    const maxPages = 100; // Cheksiz sikldan himoya.
    final items = <({String videoUrl, String title})>[];

    for (final season in seasonNumbers) {
      for (var page = 1; page <= maxPages; page++) {
        final result = await _fetchEpisodesPage(season, page);
        for (var i = 0; i < result.items.length; i++) {
          final episode = result.items[i];
          final tracks = episode['track'] as List<dynamic>?;
          if (tracks == null || tracks.isEmpty) continue;
          final url = tracks[0]['stream_url'] as String? ?? '';
          if (url.isEmpty) continue;

          items.add((
            videoUrl: url,
            title: buildEpisodeDownloadTitle(
              seriesName: widget.filmName,
              seasonNumber: season,
              episodeIndex: (page - 1) * perPage + i,
              episodeName: episode['name_uz'],
            ),
          ));
        }
        if (!result.hasMore) break;
      }
    }
    return items;
  }

  Future<String> _getValidStreamUrl(String initialUrl) async {
    try {
      final response = await ApiService.checkUrlValidity(initialUrl);
      if (response['isValid'] == true) return initialUrl;
    } catch (e) {}

    try {
      final updatedFilmData = await ApiService.getFilmDetails(widget.filmId);
      final newUrl =
          updatedFilmData['lastSeries']?[0]?['track']?[0]?['stream_url'] ?? '';
      return newUrl;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Yangi URL olishda xato: $e")));
      }
      return initialUrl;
    }
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

    // Dialoglar va pleer tanlash `VideoLauncher` da — `FilmScreen` bilan bir
    // xil nusxa turardi.
    await VideoLauncher.playWithChooser(
      context,
      url: validUrl,
      title: title,
      downloadTitle: downloadTitle,
      episodeId: episodeId,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final controller in episodeControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return PopScope(
      // Tanlash rejimida "orqaga" avval tanlovni bekor qiladi, ekrandan
      // chiqarmaydi — tasodifan tanlovni yo'qotib qo'ymaslik uchun.
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) _clearSelection();
      },
      child: _buildScaffold(themeProvider),
    );
  }

  Widget _buildScaffold(ThemeProvider themeProvider) {
    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        leading: IconButton(
          icon: Icon(
            _selectionMode ? Icons.close : Icons.chevron_left,
            color: themeProvider.textColor,
            size: 32,
          ),
          onPressed:
              _selectionMode
                  ? _clearSelection
                  : () => Navigator.of(context).pop(),
        ),
        title: Text(
          _selectionMode
              ? "${_selected.length} ta epizod tanlandi"
              : widget.filmName,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: "Tanlanganlarni yuklab olish",
              icon: Icon(Icons.download, color: themeProvider.textColor),
              onPressed: _downloadSelected,
            )
          else if (seasons.isNotEmpty)
            IconButton(
              tooltip: "Faslni yuklab olish",
              icon: Icon(Icons.download, color: themeProvider.textColor),
              onPressed: _downloadSeason,
            ),
        ],
        bottom:
            seasons.isEmpty
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
                  tabs: List.generate(
                    seasons.length,
                    (index) => Tab(
                      child: Text(
                        "Fasl ${index + 1}",
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
      ),
      body:
          _isInitialLoading
              ? Center(
                child: CircularProgressIndicator(
                  color: themeProvider.accentColor,
                ),
              )
              : seasons.isEmpty
              ? Center(
                child: Text(
                  "Fasllar mavjud emas",
                  style: TextStyle(
                    fontSize: 16,
                    color: themeProvider.subTextColor,
                  ),
                ),
              )
              : TabBarView(
                controller: _tabController,
                children: List.generate(seasons.length, (index) {
                  final seasonNumber = index + 1;
                  final controller = episodeControllers[seasonNumber]!;
                  final episodes = controller.items;
                  return episodes.isEmpty && !controller.isLoading
                      ? Center(
                        child: CircularProgressIndicator(
                          color: themeProvider.accentColor,
                        ),
                      )
                      : RefreshIndicator(
                        onRefresh: () => controller.refresh(),
                        child: GridView.builder(
                          controller: controller.scrollController,
                          padding: const EdgeInsets.all(16.0),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 12,
                                childAspectRatio: 1.12,
                              ),
                          itemCount:
                              episodes.length + (controller.isLoading ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == episodes.length) {
                              return Center(
                                child: CircularProgressIndicator(
                                  color: themeProvider.accentColor,
                                ),
                              );
                            }
                            final episode = episodes[index];
                            final episodeId = episode['id'] as int?;
                            return EpisodeCard(
                              episode: episode,
                              index: index,
                              selectionMode: _selectionMode,
                              isSelected:
                                  episodeId != null &&
                                  _selected.containsKey(episodeId),
                              onLongPress:
                                  () => _toggleSelection(
                                    episode,
                                    index,
                                    seasonNumber,
                                  ),
                              onTap: () {
                                // Tanlash rejimida oddiy bosish ham belgilaydi,
                                // aks holda odatdagidek pleer ochiladi.
                                if (_selectionMode) {
                                  _toggleSelection(
                                    episode,
                                    index,
                                    seasonNumber,
                                  );
                                  return;
                                }
                                final trackList =
                                    episode['track'] as List<dynamic>?;
                                if (trackList != null && trackList.isNotEmpty) {
                                  final streamUrl =
                                      trackList[0]['stream_url'] ?? '';
                                  _playVideo(
                                    streamUrl,
                                    episode['name_uz'] ?? "Qism ${index + 1}",
                                    downloadTitle: buildEpisodeDownloadTitle(
                                      seriesName: widget.filmName,
                                      seasonNumber: seasonNumber,
                                      episodeIndex: index,
                                      episodeName: episode['name_uz'],
                                    ),
                                    episodeId: episode['id'] as int?,
                                  );
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Epizod uchun video mavjud emas",
                                      ),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      );
                }),
              ),
    );
  }
}

class EpisodeCard extends StatelessWidget {
  final dynamic episode;
  final int index;
  final VoidCallback onTap;

  /// Multi-select support. Optional because the film detail screen reuses
  /// this card for its preview strip, where there is nothing to select.
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;

  const EpisodeCard({
    super.key,
    required this.episode,
    required this.index,
    required this.onTap,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isLastSeen = episode['is_last_seen'] == true;

    return SizedBox(
      width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
      height: 136,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: (MediaQuery.of(context).size.width - 32 - 12) / 2,
            height: 100,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: themeProvider.cardColor,
              border:
                  isSelected
                      ? Border.all(color: themeProvider.accentColor, width: 2)
                      : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onLongPress:
                    onLongPress == null
                        ? null
                        : () {
                          HapticFeedback.mediumImpact();
                          onLongPress!();
                        },
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
                            (MediaQuery.of(context).size.width - 32 - 12) / 2,
                        height: 100,
                        fit: BoxFit.cover,
                        placeholder:
                            (context, url) => Container(
                              width:
                                  (MediaQuery.of(context).size.width -
                                      32 -
                                      12) /
                                  2,
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
                                  (MediaQuery.of(context).size.width -
                                      32 -
                                      12) /
                                  2,
                              height: 100,
                              color: themeProvider.cardColor,
                              child: const Icon(Icons.broken_image),
                            ),
                      ),
                    ),
                    // Tanlash rejimida burchakni belgiga bo'shatamiz, aks
                    // holda ikkalasi ustma-ust tushardi.
                    if (isLastSeen && !selectionMode)
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
                    if (selectionMode)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                isSelected
                                    ? themeProvider.accentColor
                                    : Colors.black54,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child:
                              isSelected
                                  ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                  : null,
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
