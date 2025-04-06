import 'package:better_player/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/blocs/tv/tv_bloc.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final customCacheManager = CacheManager(
  Config(
    'tvChannelsCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 100,
  ),
);

class TVChannelsScreen extends StatelessWidget {
  const TVChannelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();
    final apiService = ApiService(storage);

    return BlocProvider(
      create: (_) => TVBloc(apiService)..add(FetchTVDataEvent()),
      child: BlocBuilder<TVBloc, TVState>(
        builder: (context, state) {
          final themeProvider = context.watch<ThemeProvider>();
          return Scaffold(
            backgroundColor:
                themeProvider.isDarkMode
                    ? const Color(0xFF111827)
                    : Colors.grey[100],
            appBar: AppBar(
              backgroundColor:
                  themeProvider.isDarkMode
                      ? const Color(0xFF1F2937)
                      : Colors.white,
              elevation: 2,
              leading: IconButton(
                icon: Icon(
                  Icons.chevron_left,
                  color:
                      themeProvider.isDarkMode ? Colors.white : Colors.black87,
                  size: 30,
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(
                "TV Kanallar", // S.of(context).tvChannels o‘rniga
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color:
                      themeProvider.isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ),
            body:
                state.isLoading
                    ? Center(
                      child: CircularProgressIndicator(
                        color:
                            themeProvider.isDarkMode
                                ? Colors.white
                                : Colors.blue,
                      ),
                    )
                    : state.channels.isEmpty
                    ? const Center(child: Text("Kanallar mavjud emas"))
                    : Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Kanallar soni: ${state.totalChannels}", // S.of(context).channelCount o‘rniga
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
                            height: 50,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: ElevatedButton(
                                      onPressed:
                                          () => context.read<TVBloc>().add(
                                            SelectCategoryEvent(null),
                                          ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            state.selectedCategoryId == null
                                                ? Colors.blue[500]
                                                : (themeProvider.isDarkMode
                                                    ? const Color(0xFF1F2937)
                                                    : Colors.grey[200]),
                                        foregroundColor:
                                            state.selectedCategoryId == null
                                                ? Colors.white
                                                : (themeProvider.isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        "Hammasi",
                                      ), // S.of(context).all o‘rniga
                                    ),
                                  ),
                                  ...state.categories.map(
                                    (category) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4.0,
                                      ),
                                      child: ElevatedButton(
                                        onPressed:
                                            () => context.read<TVBloc>().add(
                                              SelectCategoryEvent(
                                                category['id'],
                                              ),
                                            ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              state.selectedCategoryId ==
                                                      category['id']
                                                  ? Colors.blue[500]
                                                  : (themeProvider.isDarkMode
                                                      ? const Color(0xFF1F2937)
                                                      : Colors.grey[200]),
                                          foregroundColor:
                                              state.selectedCategoryId ==
                                                      category['id']
                                                  ? Colors.white
                                                  : (themeProvider.isDarkMode
                                                      ? Colors.white
                                                      : Colors.black87),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                        ),
                                        child: Text(category['title_uz']),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Expanded(
                            child: GridView.builder(
                              controller:
                                  context.read<TVBloc>().scrollController,
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount:
                                        MediaQuery.of(context).orientation ==
                                                Orientation.portrait
                                            ? 2
                                            : 3,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio:
                                        MediaQuery.of(context).size.width /
                                        (MediaQuery.of(context).size.height *
                                            0.4),
                                  ),
                              itemCount:
                                  state.channels.length +
                                  (state.isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == state.channels.length)
                                  return const Center(
                                    child: CircularProgressIndicator(),
                                  );
                                final channel = state.channels[index];
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
                                          () => context.read<TVBloc>().add(
                                            PlayChannelEvent(
                                              channel['url'],
                                              channel['title_uz'],
                                            ),
                                          ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            CachedNetworkImage(
                                              imageUrl:
                                                  channel['image'] ??
                                                  'https://placehold.co/150x150',
                                              cacheManager: customCacheManager,
                                              width: double.infinity,
                                              height: 80,
                                              fit: BoxFit.cover,
                                              placeholder:
                                                  (context, url) => Container(
                                                    height: 80,
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
                                                  ) => Container(
                                                    height: 80,
                                                    color:
                                                        themeProvider.isDarkMode
                                                            ? const Color(
                                                              0xFF374151,
                                                            )
                                                            : Colors.grey[300],
                                                    child: const Center(
                                                      child: Icon(
                                                        Icons.broken_image,
                                                        size: 40,
                                                      ),
                                                    ),
                                                  ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              _shortenText(
                                                channel['title_uz'] ??
                                                    "Noma'lum", // S.of(context).unknown o‘rniga
                                              ),
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
                            ),
                          ),
                        ],
                      ),
                    ),
          );
        },
      ),
    );
  }

  String _shortenText(String text, {int maxLength = 20}) =>
      text.length <= maxLength ? text : '${text.substring(0, maxLength)}...';
}

class TVBloc extends Bloc<TVEvent, TVState> {
  final ApiService apiService;
  final ScrollController scrollController = ScrollController();

  TVBloc(this.apiService) : super(TVState.initial()) {
    scrollController.addListener(_onScroll);

    on<FetchTVDataEvent>((event, emit) async {
      emit(state.copyWith(isLoading: true));
      try {
        final categoryData = await apiService.getTVCategories();
        final channelData = await apiService.getTVChannels(page: state.page);
        emit(
          state.copyWith(
            categories: categoryData,
            channels: channelData['tv_channels'] ?? [],
            totalChannels: channelData['count'] ?? 0,
            isLoading: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoading: false));
      }
    });

    on<SelectCategoryEvent>((event, emit) async {
      emit(
        state.copyWith(
          selectedCategoryId: event.categoryId,
          isLoading: true,
          channels: [],
          page: 1,
        ),
      );
      try {
        final channelData = await apiService.getTVChannels(
          page: 1,
          categoryId: event.categoryId,
        );
        emit(
          state.copyWith(
            channels: channelData['tv_channels'] ?? [],
            totalChannels: channelData['count'] ?? 0,
            isLoading: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoading: false));
      }
    });

    on<FetchMoreChannelsEvent>((event, emit) async {
      if (state.isLoadingMore || !state.hasMoreChannels) return;
      emit(state.copyWith(isLoadingMore: true));
      try {
        final channelData = await apiService.getTVChannels(
          page: state.page + 1,
          categoryId: state.selectedCategoryId,
        );
        emit(
          state.copyWith(
            channels: [...state.channels, ...channelData['tv_channels'] ?? []],
            page: state.page + 1,
            isLoadingMore: false,
            hasMoreChannels: channelData['tv_channels'].length == 24,
          ),
        );
      } catch (e) {
        emit(state.copyWith(isLoadingMore: false));
      }
    });

    on<PlayChannelEvent>(
      (event, emit) => Navigator.push(
        event.context,
        MaterialPageRoute(
          builder:
              (_) => ChannelPlayerScreen(url: event.url, title: event.title),
        ),
      ),
    );
  }

  void _onScroll() {
    if (scrollController.position.pixels >=
            scrollController.position.maxScrollExtent - 100 &&
        !state.isLoadingMore &&
        state.hasMoreChannels) {
      add(FetchMoreChannelsEvent());
    }
  }

  @override
  Future<void> close() {
    scrollController.dispose();
    return super.close();
  }
}

sealed class TVEvent {
  BuildContext get context => BuildContext();
}

class FetchTVDataEvent extends TVEvent {}

class SelectCategoryEvent extends TVEvent {
  final String? categoryId;
  SelectCategoryEvent(this.categoryId);
}

class FetchMoreChannelsEvent extends TVEvent {}

class PlayChannelEvent extends TVEvent {
  final String url;
  final String title;
  @override
  final BuildContext context;

  PlayChannelEvent(this.url, this.title, {this.context = const BuildContext()});
}

class TVState {
  final List<dynamic> categories;
  final List<dynamic> channels;
  final String? selectedCategoryId;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMoreChannels;
  final int totalChannels;
  final int page;

  TVState({
    required this.categories,
    required this.channels,
    this.selectedCategoryId,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMoreChannels,
    required this.totalChannels,
    required this.page,
  });

  factory TVState.initial() => TVState(
    categories: [],
    channels: [],
    isLoading: true,
    isLoadingMore: false,
    hasMoreChannels: true,
    totalChannels: 0,
    page: 1,
  );

  TVState copyWith({
    List<dynamic>? categories,
    List<dynamic>? channels,
    String? selectedCategoryId,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMoreChannels,
    int? totalChannels,
    int? page,
  }) => TVState(
    categories: categories ?? this.categories,
    channels: channels ?? this.channels,
    selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
    isLoading: isLoading ?? this.isLoading,
    isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    hasMoreChannels: hasMoreChannels ?? this.hasMoreChannels,
    totalChannels: totalChannels ?? this.totalChannels,
    page: page ?? this.page,
  );
}

class ChannelPlayerScreen extends StatefulWidget {
  final String url;
  final String title;

  const ChannelPlayerScreen({
    required this.url,
    required this.title,
    super.key,
  });

  @override
  State<ChannelPlayerScreen> createState() => _ChannelPlayerScreenState();
}

class _ChannelPlayerScreenState extends State<ChannelPlayerScreen> {
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
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsOnFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        autoDetectFullscreenDeviceOrientation: true,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableFullscreen: true,
          enablePlayPause: true,
          enableMute: true,
          enableSkips: false,
        ),
        errorBuilder:
            (context, errorMessage) => Center(
              child: Text(
                "Video xatoligi: $errorMessage", // S.of(context).videoError o‘rniga
                style: const TextStyle(color: Colors.red),
              ),
            ),
      ),
      betterPlayerDataSource: BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.url,
        liveStream: true,
        notificationConfiguration: BetterPlayerNotificationConfiguration(
          showNotification: true,
          title: widget.title,
          author: "SalomTV",
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
        title: Text(widget.title),
      ),
      body: BetterPlayer(controller: _betterPlayerController),
    );
  }
}
