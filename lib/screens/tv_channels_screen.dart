import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:riya_play/services/tv_api_service.dart';
import 'package:riya_play/screens/video_player_screen.dart';
import 'package:better_player/better_player.dart';
import 'package:flutter/services.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/utils/image_cache_manager.dart';

// TV kanal ma'lumotlari (JSON) uchun alohida kesh — rasm keshidan farqli
final dataCacheManager = CacheManager(
  Config(
    'tvDataCache',
    stalePeriod: const Duration(minutes: 30),
    maxNrOfCacheObjects: 50,
  ),
);

class TVChannelsScreen extends StatefulWidget {
  const TVChannelsScreen({super.key});

  @override
  State<TVChannelsScreen> createState() => _TVChannelsScreenState();
}

class _TVChannelsScreenState extends State<TVChannelsScreen>
    with TickerProviderStateMixin {
  TabController? _tabController;
  List<dynamic> categories = [];
  Map<String, List<dynamic>> channelsByCategory = {};
  String selectedSource = TVApiService.baseUrls.keys.first;
  bool _isLoading = true;
  int totalChannels = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _loadTVData();
  }

  Future<void> _loadTVData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final categoryCacheKey = 'categories_$selectedSource';
      final cachedCategories = await dataCacheManager.getFileFromCache(
        categoryCacheKey,
      );

      if (cachedCategories != null) {
        categories = jsonDecode(await cachedCategories.file.readAsString());
      } else {
        categories = await TVApiService.getTVCategories(selectedSource);
        await dataCacheManager.putFile(
          categoryCacheKey,
          utf8.encode(jsonEncode(categories)),
          fileExtension: 'json',
        );
      }

      await _loadChannelsForAllCategories();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _tabController?.dispose();
        _tabController = TabController(
          length: categories.isEmpty ? 1 : categories.length + 1,
          vsync: this,
        );
        _tabController!.addListener(() {
          if (_tabController!.indexIsChanging) return;
          setState(() {});
        });
      });

      _precacheImages();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showErrorSnackBar(ApiErrorHandler.handle(e).userMessage);
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      categories.clear();
      channelsByCategory.clear();
      _isLoading = true;
      _tabController?.dispose();
      _tabController = null;
    });
    await _loadTVData();
  }

  Future<void> _loadChannelsForAllCategories() async {
    channelsByCategory['all'] = await _fetchChannels(null);
    totalChannels = channelsByCategory['all']!.length;

    if (categories.isNotEmpty) {
      final futures = categories.map(
        (category) => _fetchChannels(category['id']),
      );
      final results = await Future.wait(futures);
      for (var i = 0; i < categories.length; i++) {
        channelsByCategory[categories[i]['id']] = results[i];
      }
    }
  }

  Future<List<dynamic>> _fetchChannels(String? categoryId) async {
    final channelCacheKey =
        'channels_${selectedSource}_page_1${categoryId ?? "all"}';
    Map<String, dynamic> channelData;

    if (selectedSource == "OqTV" || selectedSource == "OnTV") {
      // Ikkalasi ham kanallarni kategoriyalari bilan bitta so'rovda beradi va
      // `TVApiService` javobni jarayon davomida keshda tutadi — bu yerda
      // diskka yozish faqat o'sha nusxani takrorlash bo'lardi. OnTV uchun
      // diskka yozish zararli ham: uning strim manzillari muddatli.
      channelData = await TVApiService.getTVChannels(
        source: selectedSource,
        categoryId: categoryId,
      );
    } else {
      final cachedChannels = await dataCacheManager.getFileFromCache(
        channelCacheKey,
      );
      if (cachedChannels != null) {
        channelData = jsonDecode(await cachedChannels.file.readAsString());
      } else {
        channelData = await TVApiService.getTVChannels(
          source: selectedSource,
          page: 1,
          categoryId: categoryId,
        );
        await dataCacheManager.putFile(
          channelCacheKey,
          utf8.encode(jsonEncode(channelData)),
          fileExtension: 'json',
        );
      }
    }
    return channelData['tv_channels'] ?? [];
  }

  void _precacheImages() {
    for (var channels in channelsByCategory.values) {
      for (var channel in channels.take(10)) {
        precacheImage(
          CachedNetworkImageProvider(
            channel['image'] ?? 'https://placehold.co/150x150',
            cacheManager: filmImagesCacheManager,
          ),
          context,
          onError: (_, __) {},
        );
      }
    }
  }

  Future<void> _playChannel(
    String channelId,
    String title,
    String source,
  ) async {
    String? videoUrl;
    try {
      videoUrl = await TVApiService.getStreamUrl(
        source: source,
        channelId: channelId,
      );
      // `ErrorInfo` otiladi, `Exception` emas: `ApiErrorHandler.handle` uni
      // o'zgartirmasdan qaytaradi, shuning uchun bu aniq xabar saqlanadi,
      // tarmoq xatosi esa o'zining klassifikatsiyasini oladi.
      if (videoUrl == null) {
        throw const ErrorInfo(
          type: ErrorType.notFound,
          message: 'stream url missing',
          userMessage: 'Bu kanal uchun strim topilmadi.',
          canRetry: false,
        );
      }
    } catch (e) {
      _showErrorSnackBar(ApiErrorHandler.handle(e).userMessage);
      return;
    }

    // Foydalanuvchiga ichki yoki tashqi pleerni tanlash imkonini berish
    final selectedPlayer = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Pleerni tanlang"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_circle_filled),
                    title: const Text("Ichki pleer: Better Player"),
                    onTap: () => Navigator.pop(context, 'better_player'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: const Text("Tashqi pleer bilan ochish"),
                    onTap: () => Navigator.pop(context, 'external'),
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

    if (selectedPlayer == null) return;

    if (selectedPlayer == 'better_player') {
      // Ichki pleer bilan ochish
      if (mounted) {
        Navigator.push(
          context,
          createSlideRoute(
            // PageRouteBuilder bilan o‘tish
            VideoPlayerScreen(
              videoUrl: videoUrl,
              title: title,
              liveStream: true,
              autoPlay: true,
              fullScreenByDefault: true,
              deviceOrientationsOnFullScreen: const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
              deviceOrientationsAfterFullScreen: const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.portraitDown,
              ],
              autoDetectFullscreenDeviceOrientation: true,
              controlsConfiguration: const BetterPlayerControlsConfiguration(
                enableFullscreen: true,
                enablePlayPause: true,
                enableMute: true,
                enableSkips: false,
              ),
              notificationConfiguration: BetterPlayerNotificationConfiguration(
                showNotification: false,
                title: title,
                author: source,
              ),
            ),
          ),
        );
      }
    } else if (selectedPlayer == 'external') {
      // Tashqi pleer bilan ochish
      try {
        final intent = AndroidIntent(
          action: 'action_view',
          data: videoUrl,
          type: 'video/*',
        );
        await intent.launch();
      } catch (e) {
        if (mounted) {
          // Bu API xatosi emas — intent xatosining `toString()` i
          // foydalanuvchiga hech narsa bermaydi.
          _showErrorSnackBar('Tashqi pleerni ochib bo‘lmadi.');
        }
      }
    }
  }

  void _onSourceChanged(String? newSource) {
    if (newSource != null && newSource != selectedSource && mounted) {
      setState(() {
        selectedSource = newSource;
        categories.clear();
        channelsByCategory.clear();
        _isLoading = true;
        _tabController?.dispose();
        _tabController = null;
      });
      _loadTVData();
    }
  }

  String _shortenText(String text, {int maxLength = 20}) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength)}...';

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  int _getCurrentCategoryChannelCount() {
    final currentIndex = _tabController?.index ?? 0;
    if (currentIndex == 0 || categories.isEmpty) {
      return totalChannels;
    } else {
      final categoryId = categories[currentIndex - 1]['id'];
      return channelsByCategory[categoryId]?.length ?? 0;
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        elevation: 2,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              "TV Kanallar",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            DropdownButton<String>(
              value: selectedSource,
              items:
                  TVApiService.baseUrls.keys
                      .map(
                        (source) => DropdownMenuItem(
                          value: source,
                          child: Text(source),
                        ),
                      )
                      .toList(),
              onChanged: _onSourceChanged,
            ),
          ],
        ),
      ),
      body:
          _isLoading
              ? Center(
                child: CircularProgressIndicator(
                  color: themeProvider.isDarkMode ? Colors.white : Colors.blue,
                ),
              )
              : channelsByCategory.isEmpty
              ? const Center(child: Text("Kanallar mavjud emas"))
              : _tabController == null
              ? const Center(child: Text("Tablarni yuklashda xato"))
              : RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8.0,
                      vertical: 8.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (categories.isNotEmpty)
                          SizedBox(
                            height: 40,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              physics: const BouncingScrollPhysics(),
                              children: [
                                _buildCategoryButton(
                                  text: "Barchasi",
                                  isSelected: _tabController?.index == 0,
                                  onTap: () {
                                    _tabController?.animateTo(0);
                                    setState(() {});
                                  },
                                ),
                                ...categories.asMap().entries.map(
                                  (entry) => _buildCategoryButton(
                                    text:
                                        entry.value['title_uz']?.length <= 20
                                            ? entry.value['title_uz']
                                            : '${entry.value['title_uz']?.substring(0, 17)}...',
                                    isSelected:
                                        _tabController?.index == entry.key + 1,
                                    onTap: () {
                                      _tabController?.animateTo(entry.key + 1);
                                      setState(() {});
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          "Kanallar soni: ${_getCurrentCategoryChannelCount()} ta",
                          style: TextStyle(
                            fontSize: 16,
                            color:
                                themeProvider.isDarkMode
                                    ? Colors.grey[400]
                                    : Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.7,
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildChannelGrid('all'),
                              if (categories.isNotEmpty)
                                ...categories.map(
                                  (category) =>
                                      _buildChannelGrid(category['id']),
                                ),
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

  Widget _buildCategoryButton({
    required String text,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.blue[500]! : Colors.transparent,
                width: 2.0,
              ),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color:
                  isSelected
                      ? (themeProvider.isDarkMode
                          ? Colors.white
                          : Colors.black87)
                      : (themeProvider.isDarkMode
                          ? Colors.grey[400]
                          : Colors.grey),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelGrid(String categoryId) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final channels = channelsByCategory[categoryId] ?? [];
    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount:
            MediaQuery.of(context).orientation == Orientation.portrait ? 2 : 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio:
            MediaQuery.of(context).size.width /
            (MediaQuery.of(context).size.height * 0.4),
      ),
      cacheExtent: 500,
      itemCount: channels.length,
      itemBuilder: (context, index) {
        final channel = channels[index];
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color:
                themeProvider.isDarkMode
                    ? const Color(0xFF1F2937)
                    : Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap:
                  () => _playChannel(
                    channel['id'],
                    channel['title_uz'],
                    selectedSource,
                  ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CachedNetworkImage(
                      imageUrl:
                          channel['image'] ?? 'https://placehold.co/150x150',
                      cacheManager: filmImagesCacheManager,
                      width: double.infinity,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder:
                          (context, url) => Container(
                            height: 80,
                            color:
                                themeProvider.isDarkMode
                                    ? const Color(0xFF374151)
                                    : Colors.grey[300],
                            child: const Center(
                              child: CircularProgressIndicator(),
                            ),
                          ),
                      errorWidget:
                          (context, url, error) => Container(
                            height: 80,
                            color:
                                themeProvider.isDarkMode
                                    ? const Color(0xFF374151)
                                    : Colors.grey[300],
                            child: const Center(
                              child: Icon(Icons.broken_image, size: 40),
                            ),
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _shortenText(channel['title_uz'] ?? 'Noma\'lum'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color:
                            themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
