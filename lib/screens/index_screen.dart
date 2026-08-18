import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:riya_play/screens/latestviewed_screen.dart';
import 'package:riya_play/screens/recommended_films_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/widgets/recommended_films_widget.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:riya_play/screens/error_pages.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riya_play/screens/genres_screen.dart';
import 'package:riya_play/screens/genres_films_screen.dart';
import 'package:riya_play/screens/categories_screen.dart';
import 'package:riya_play/utils/navigation.dart';
import 'package:riya_play/utils/image_cache_manager.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:riya_play/utils/grid_density.dart';
import 'package:riya_play/main.dart' show MainScreen, routeObserver;
import 'package:riya_play/services/cache_service.dart';
import 'package:riya_play/utils/latest_viewed.dart';
import 'package:riya_play/utils/video_launcher.dart';

// Holatni boshqarish uchun Provider
class IndexScreenProvider with ChangeNotifier {
  List<dynamic> _banners = [];
  List<dynamic> _latestViewed = [];
  List<dynamic> _recommendedFilms = [];
  List<dynamic> _genresPreview = [];
  List<dynamic> _categories = [];
  Map<int, List<dynamic>> _categoryFilms = {};
  bool _isLoadingBanners = true;
  bool _isLoadingLatestViewed = true;
  bool _isLoadingRecommended = true;
  bool _isLoadingGenres = true;
  bool _isLoadingCategories = true;
  Map<int, bool> _isLoadingCategoryFilms = {};
  String? _globalError;
  int? _globalErrorStatusCode;
  String? _genresError;

  List<dynamic> get banners => _banners;
  List<dynamic> get latestViewed => _latestViewed;
  List<dynamic> get recommendedFilms => _recommendedFilms;
  List<dynamic> get genresPreview => _genresPreview;
  List<dynamic> get categories => _categories;
  Map<int, List<dynamic>> get categoryFilms => _categoryFilms;
  bool get isLoadingBanners => _isLoadingBanners;
  bool get isLoadingLatestViewed => _isLoadingLatestViewed;
  bool get isLoadingRecommended => _isLoadingRecommended;
  bool get isLoadingGenres => _isLoadingGenres;
  bool get isLoadingCategories => _isLoadingCategories;
  Map<int, bool> get isLoadingCategoryFilms => _isLoadingCategoryFilms;
  String? get globalError => _globalError;
  int? get globalErrorStatusCode => _globalErrorStatusCode;
  String? get genresError => _genresError;

  // TUZATILISHGA MUHTOJ: notifyListeners() olib tashlangan, faqat ma'lumot yangilandi, lekin UI yangilanmaydi
  void updateBanners(List<dynamic> data) {
    _banners = data;
    _isLoadingBanners = false;
    appLogger.d('Bannerlar yuklandi: ${_banners.length} ta');
    // TUZATISH: notifyListeners(); // Ehtiyojga qarab qo'shish kerak
  }

  void updateLatestViewed(List<dynamic> data) {
    _latestViewed = data;
    _isLoadingLatestViewed = false;
    // TUZATISH: notifyListeners();
  }

  /// "Ko'rishni davom ettirish" so'rovi uchun maydonlar ro'yxati — dastlabki
  /// yuklash va pleerdan qaytgandagi yangilash bir xil shaklda kelishi kerak.
  static const String latestViewedFields =
      'name_uz,name_ru,name_en,id,films.id,films.name_uz,films.name_ru,'
      'films.publish_time,films.type,films.paid,films.year,films.tags.id,'
      'films.tags.title_uz,films.tags.title_en,films.files.thumbnails';

  /// Pleer yopilgandan keyin chaqiriladi: server pozitsiyasi o'zgargan,
  /// ekrandagi ro'yxat esa eski. Kesh ham yangilanadi, aks holda ilova
  /// qayta ochilganda yana eski qiymat chiziladi.
  Future<void> reloadLatestViewed() async {
    try {
      final response = await ApiService.getLatestViewed(
        isAll: false,
        perPage: 10,
        fields: latestViewedFields,
      );
      final films = response['data'];
      if (films is List) {
        updateLatestViewed(films);
        await CacheService.put(CacheService.latestViewedKey, films);
        notifyListeners();
      }
    } catch (e) {
      appLogger.e('So‘ngi ko‘rilganlarni yangilashda xato: $e');
    }
  }

  void updateRecommendedFilms(List<dynamic> data) {
    _recommendedFilms = data;
    _isLoadingRecommended = false;
    // TUZATISH: notifyListeners();
  }

  void updateGenresPreview(List<dynamic> data) {
    _genresPreview = data;
    _isLoadingGenres = false;
    _genresError = null;
    // TUZATISH: notifyListeners();
  }

  void updateCategories(List<dynamic> data) {
    _categories = data;
    _isLoadingCategories = false;
    for (var category in data) {
      _isLoadingCategoryFilms[category['id']] = true;
      _categoryFilms[category['id']] = [];
    }
    // TUZATISH: notifyListeners();
  }

  void updateCategoryFilms(int categoryId, List<dynamic> films) {
    _categoryFilms[categoryId] = films;
    _isLoadingCategoryFilms[categoryId] = false;
    // TUZATISH: notifyListeners();
  }

  void setLoadingBanners(bool value) {
    _isLoadingBanners = value;
    notifyListeners();
  }

  void setLoadingLatestViewed(bool value) {
    _isLoadingLatestViewed = value;
    notifyListeners();
  }

  void setLoadingRecommended(bool value) {
    _isLoadingRecommended = value;
    notifyListeners();
  }

  void setLoadingGenres(bool value) {
    _isLoadingGenres = value;
    notifyListeners();
  }

  void setLoadingCategories(bool value) {
    _isLoadingCategories = value;
    notifyListeners();
  }

  void setGlobalError(String error, int? statusCode) {
    _globalError = error;
    _globalErrorStatusCode = statusCode;
    _isLoadingBanners = false;
    _isLoadingLatestViewed = false;
    _isLoadingRecommended = false;
    _isLoadingGenres = false;
    _isLoadingCategories = false;
    _isLoadingCategoryFilms.clear();
    _banners = [];
    _latestViewed = [];
    _recommendedFilms = [];
    _genresPreview = [];
    _categories = [];
    _categoryFilms = {};
    appLogger.d('Global error set: $error, StatusCode: $statusCode');
    notifyListeners();
  }

  void setGenresError(String error) {
    _genresError = error;
    _isLoadingGenres = false;
    notifyListeners();
  }

  void clearGlobalError() {
    _globalError = null;
    _globalErrorStatusCode = null;
    notifyListeners();
  }

  void reset() {
    _banners = [];
    _latestViewed = [];
    _recommendedFilms = [];
    _genresPreview = [];
    _categories = [];
    _categoryFilms = {};
    _isLoadingBanners = true;
    _isLoadingLatestViewed = true;
    _isLoadingRecommended = true;
    _isLoadingGenres = true;
    _isLoadingCategories = true;
    _isLoadingCategoryFilms = {};
    _globalError = null;
    _globalErrorStatusCode = null;
    _genresError = null;
    appLogger.d('Provider reset');
    notifyListeners();
  }

  // YANGI: Barcha yangilanishlardan so'ng bir marta notify qilish uchun metod
  void notifyAfterUpdates() {
    notifyListeners();
  }
}

class IndexScreen extends StatelessWidget {
  const IndexScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => IndexScreenProvider(),
      child: const IndexScreenContent(),
    );
  }
}

class IndexScreenContent extends StatefulWidget {
  const IndexScreenContent({super.key});

  @override
  State<IndexScreenContent> createState() => _IndexScreenContentState();
}

class _IndexScreenContentState extends State<IndexScreenContent>
    with RouteAware {
  bool _isShowingError = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityDebounce;

  /// Oxirgi ma'lum tarmoq holati.
  ///
  /// `onConnectivityChanged` obuna bo'lgan zahoti joriy holatni ham yuboradi,
  /// ya'ni "ulanish tiklandi" tarmoqqa hech narsa bo'lmaganda ham ishga
  /// tushardi. Natijada bosh sahifa har ochilishda ikki marta to'liq
  /// yuklanardi (o'lchangan: 5 ta umumiy so'rov + har kategoriya uchun
  /// bittadan, ikki barobar). Shuning uchun qayta yuklash faqat oflayndan
  /// onlayn holatiga o'tishda bo'ladi.
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    appLogger.d('IndexScreen initState called');
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      appLogger.d('Connectivity changed: $results');
      if (_connectivityDebounce?.isActive ?? false)
        _connectivityDebounce!.cancel();
      _connectivityDebounce = Timer(const Duration(seconds: 1), () {
        final offline = results.every(
          (result) => result == ConnectivityResult.none,
        );
        if (offline) {
          appLogger.d('No network connection detected, showing error page');
          _wasOffline = true;
          final provider = Provider.of<IndexScreenProvider>(
            context,
            listen: false,
          );
          provider.setGlobalError('Tarmoq xatosi', null);
        } else if (_wasOffline) {
          appLogger.d('Network connection restored, fetching initial data');
          _wasOffline = false;
          _fetchInitialData();
        }
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      appLogger.d('Initial data fetch triggered');
      // Kesh avval chiziladi, keyin tarmoqdan yangilanadi.
      await _primeFromCache();
      if (mounted) _fetchInitialData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
  }

  /// Ustimizdagi ekran (pleer, film sahifasi, epizodlar ro'yxati) yopilganda
  /// chaqiriladi. Ko'rish pozitsiyasi shu orada o'zgargan bo'lishi mumkin,
  /// shuning uchun "Ko'rishni davom ettirish" qatorini qayta o'qiymiz.
  @override
  void didPopNext() async {
    if (!mounted) return;
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    await VideoLauncher.awaitPositionFlush();
    if (mounted) await provider.reloadLatestViewed();
  }

  @override
  void dispose() {
    appLogger.d('IndexScreen dispose called');
    routeObserver.unsubscribe(this);
    _connectivitySubscription?.cancel();
    _connectivityDebounce?.cancel();
    super.dispose();
  }

  /// Paints the last known content before the network is consulted, so a
  /// cold start isn't a screen of empty sections. Anything stale is replaced
  /// a moment later by [_fetchInitialData]; anything missing just stays
  /// empty as before.
  Future<void> _primeFromCache() async {
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);

    final banners = await CacheService.get<List>(CacheService.bannersKey);
    if (banners != null) provider.updateBanners(banners);

    final recommended = await CacheService.get<List>(
      CacheService.recommendedKey,
    );
    if (recommended != null) {
      provider.updateRecommendedFilms(await _processFilms(recommended));
    }

    final genres = await CacheService.get<List>(CacheService.genresKey);
    if (genres != null) provider.updateGenresPreview(genres);

    final latestViewed = await CacheService.get<List>(
      CacheService.latestViewedKey,
    );
    if (latestViewed != null) provider.updateLatestViewed(latestViewed);

    if (mounted) provider.notifyAfterUpdates();
  }

  Future<void> _fetchInitialData() async {
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    provider.clearGlobalError();
    if (!(await _checkInternetConnection())) {
      appLogger.d('No internet connection, setting global error');
      provider.setGlobalError('Tarmoq xatosi', null);
      return;
    }
    try {
      appLogger.d('Fetching initial data');
      // Bosh sahifaning beshta bo'limi bir-biriga bog'liq emas, shuning uchun
      // ular parallel so'raladi. Ketma-ket bo'lganda kutish vaqtlari
      // qo'shilardi (o'lchangan: banner 0.65 s, so'nggi ko'rilganlar +1.0 s,
      // tavsiyalar +0.7 s, janrlar +0.25 s, kategoriyalar +1.7 s = ~4.3 s).
      await Future.wait([
        _fetchData(
          fetchFunction: ApiService.getBanners,
          onSuccess: (data) {
            provider.updateBanners(data);
            CacheService.put(CacheService.bannersKey, data);
          },
          onError: (error, statusCode) {
            provider.setGlobalError(error, statusCode);
          },
          errorMessage: 'Bannerlarni yuklashda xato',
        ),
        _fetchData(
          fetchFunction:
              () => ApiService.getLatestViewed(
                isAll: false,
                perPage: 10,
                fields: IndexScreenProvider.latestViewedFields,
              ),
          onSuccess: (response) {
            final films = response['data'] ?? [];
            provider.updateLatestViewed(films);
            CacheService.put(CacheService.latestViewedKey, films);
          },
          onError: (error, statusCode) {
            provider.setGlobalError(error, statusCode);
          },
          errorMessage: 'So‘ngi ko‘rilganlarni yuklashda xato',
        ),
        _fetchData(
          fetchFunction: ApiService.getRecommendedFilms,
          onSuccess: (response) async {
            final films = response['data'] ?? [];
            final processedFilms = await _processFilms(films);
            provider.updateRecommendedFilms(processedFilms);
            // Xom javob keshlanadi — ilova qayta ochilganda _processFilms
            // yana ishlaydi, shunda kesh ishlov mantig'iga bog'lanmaydi.
            CacheService.put(CacheService.recommendedKey, films);
          },
          onError: (error, statusCode) {
            provider.setGlobalError(error, statusCode);
          },
          errorMessage: 'Tavsiya etilganlarni yuklashda xato',
        ),
        _fetchData(
          fetchFunction: ApiService.getGenresPreview,
          onSuccess: (data) {
            provider.updateGenresPreview(data);
            CacheService.put(CacheService.genresKey, data);
          },
          onError: (error, statusCode) {
            provider.setGenresError(error);
            provider.setGlobalError(error, statusCode);
          },
          errorMessage: 'Janrlar yuklashda xatolik',
        ),
        _fetchCategories(),
      ]);
      appLogger.d('Initial data fetched successfully');
      provider.notifyAfterUpdates(); // YANGI QO'SHILDI: Bir marta notify
    } catch (e, stackTrace) {
      appLogger.d('Error fetching initial data: $e');
      appLogger.d('StackTrace: $stackTrace');
      provider.setGlobalError('Umumiy xato: $e', null);
    }
  }

  Future<void> _fetchData<T>({
    required Future<T> Function() fetchFunction,
    required Function(T) onSuccess,
    required Function(String, int?) onError,
    required String errorMessage,
  }) async {
    try {
      final data = await fetchFunction();
      if (data is Map<String, dynamic> && data['success'] == false) {
        final statusCode = data['statusCode'] as int?;
        final error = data['error']?.toString() ?? 'Noma’lum xato';
        onError(error, statusCode);
      } else {
        onSuccess(data);
      }
    } catch (e, stackTrace) {
      final error = e.toString();
      onError(error, null);
      appLogger.d('$errorMessage xatosi: $e\nStackTrace: $stackTrace');
    }
  }

  // notifyAfterUpdates() qo'shildi va notifyListeners() kamaytirildi
  Future<void> _fetchCategories() async {
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    await _fetchData(
      fetchFunction: ApiService.getCategories,
      onSuccess: (response) async {
        final List categoryList = response['data'] ?? [];
        if (categoryList.isEmpty) {
          appLogger.d('Kategoriyalar bo‘sh, loading holatini o‘chirish');
          provider.updateCategories([]);
          provider.notifyAfterUpdates();
          return;
        }
        provider.updateCategories(categoryList);
        provider.notifyAfterUpdates();
        try {
          await Future.wait(
            categoryList.map(
              (category) => _fetchFilmsForCategory(category['id']),
            ),
          );
          provider.notifyAfterUpdates();
        } catch (e, stackTrace) {
          appLogger.d('Kategoriya filmlarini yuklashda xato: $e');
          appLogger.d('StackTrace: $stackTrace');
          for (var category in categoryList) {
            provider.updateCategoryFilms(category['id'], []);
          }
          provider.notifyAfterUpdates();
        }
      },
      onError: (error, statusCode) {
        appLogger.d('Kategoriyalarni yuklashda xato: $error');
        provider.setGlobalError(error, statusCode);
      },
      errorMessage: 'Kategoriyalarni yuklashda xato',
    );
  }

  Future<void> _fetchFilmsForCategory(int categoryId) async {
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    await _fetchData(
      fetchFunction:
          () => ApiService.getFilmsByCategory(
            categoryId: categoryId,
            page: 1,
            perPage: 10,
          ),
      onSuccess: (response) async {
        final films = response['data'] ?? [];
        appLogger.d(
          'Kategoriya $categoryId uchun filmlar yuklandi: ${films.length} ta',
        );
        final processedFilms = await _processFilms(films);
        provider.updateCategoryFilms(categoryId, processedFilms);
      },
      onError: (error, statusCode) {
        appLogger.d('Kategoriya $categoryId filmlarini yuklashda xato: $error');
        provider.updateCategoryFilms(categoryId, []);
      },
      errorMessage: 'Kategoriya filmlarini yuklashda xato',
    );
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      final isConnected = connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );
      appLogger.d(
        'Connectivity check: $connectivityResult, Connected: $isConnected',
      );
      if (!isConnected) return false;

      final result = await InternetAddress.lookup('google.com').timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          appLogger.d('Internet check timed out');
          return [];
        },
      );
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        appLogger.d('Internet check successful');
        return true;
      }
      appLogger.d('Internet check failed: No address');
      return false;
    } catch (e) {
      appLogger.d('Internet check error: $e');
      return false;
    }
  }

  void _showErrorPage(BuildContext context) {
    if (_isShowingError || !mounted) return;

    _isShowingError = true;
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    final error = provider.globalError;
    final statusCode = provider.globalErrorStatusCode;

    if (error == null) {
      _isShowingError = false;
      return;
    }

    provider.clearGlobalError();

    _checkInternetConnection().then((isConnected) {
      if (!mounted) return;

      if (!isConnected || error.contains('Tarmoq xatosi')) {
        appLogger.d('Showing NetworkErrorPage');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => NetworkErrorPage(onRetry: () => _onRetry(context)),
          ),
        );
      } else {
        appLogger.d('Showing ServerErrorPage');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder:
                (context) => ServerErrorPage(
                  statusCode: statusCode,
                  errorMessage: error,
                  onRetry:
                      statusCode == 401 || statusCode == 403
                          ? null
                          : () => _onRetry(context),
                ),
          ),
        );
      }

      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          setState(() {
            _isShowingError = false;
          });
        }
      });
    });
  }

  void _showLoading(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(child: CircularProgressIndicator());
      },
    );
  }

  Future<void> _onRetry(BuildContext context) async {
    appLogger.d('Retry button pressed');
    _showLoading(context);

    try {
      final isConnected = await _checkInternetConnection();

      if (isConnected) {
        appLogger.d('Internet connected, proceeding with retry');
        await Future.delayed(const Duration(seconds: 2));
        Navigator.of(context).pop();
        // MainScreen'ga qaytamiz, IndexScreen'ga emas: pastki navigatsiya
        // MainScreen'da joylashgan, shuning uchun bevosita IndexScreen'ni
        // ochish tablarni butunlay yo'qotib yuboradi.
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
          (route) => false,
        );
      } else {
        appLogger.d('No internet connection, showing snackbar');
        Navigator.of(context).pop();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Internet aloqasi hali ham yo‘q')),
          );
        }
      }
    } catch (e, stackTrace) {
      appLogger.d('Error in _onRetry: $e');
      appLogger.d('StackTrace: $stackTrace');
      Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Xatolik yuz berdi: $e')));
      }
    }
  }

  Future<List<dynamic>> _processFilms(List<dynamic> newFilms) async {
    return newFilms.take(20).toList();
  }

  Future<void> _refresh() async {
    final provider = Provider.of<IndexScreenProvider>(context, listen: false);
    if (!(await _checkInternetConnection())) {
      appLogger.d('No internet connection during refresh');
      provider.setGlobalError('Tarmoq xatosi', null);
      return;
    }
    appLogger.d('Refreshing data');
    provider.reset();
    await _fetchInitialData();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ma\'lumotlar yangilandi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    appLogger.d('IndexScreen build called');
    final themeProvider = Provider.of<ThemeProvider>(context);
    final provider = Provider.of<IndexScreenProvider>(context);

    if (provider.globalError != null && !_isShowingError) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appLogger.d('Global error detected, showing error page');
        _showErrorPage(context);
      });
    }

    if (provider.isLoadingBanners ||
        provider.isLoadingLatestViewed ||
        provider.isLoadingRecommended ||
        provider.isLoadingGenres ||
        provider.isLoadingCategories) {
      return Scaffold(
        backgroundColor:
            themeProvider.isDarkMode
                ? const Color(0xFF111827)
                : Colors.grey[100],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      appBar: AppBar(
        backgroundColor:
            themeProvider.isDarkMode
                ? const Color(0xFF111827)
                : Colors.grey[100],
        elevation: 0,
        title: Text(
          "Asosiy sahifa",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: themeProvider.isDarkMode ? Colors.white : Colors.grey[800],
          ),
        ),
      ),
      // `bottom: false` — kontent shisha menyu ortidan o'tib, tizim
      // navigatsiya paneligacha ko'rinsin. O'rniga bir xil balandlikdagi
      // to'ldirish ro'yxatning ichiga qo'yiladi, shunda oxirgi element
      // baribir menyu ostida qolib ketmaydi.
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                provider.banners.isNotEmpty && !provider.isLoadingBanners
                    ? const BannerCarousel()
                    : const SizedBox(
                      height: 200,
                      child: Center(child: Text('Bannerlar mavjud emas')),
                    ),
                if (provider.latestViewed.isNotEmpty)
                  const LatestViewedSection(),
                const RecommendedFilmsSection(),
                GenresSection(onRetry: () => _onRetry(context)),
                const CategoriesSection(),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// BannerCarousel
class BannerCarousel extends StatefulWidget {
  const BannerCarousel({super.key});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel>
    with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _animationController;
  final CarouselSliderController _carouselController =
      CarouselSliderController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<IndexScreenProvider>(context);
    final banners = provider.banners;
    final isLoading = provider.isLoadingBanners;

    if (isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (banners.isEmpty) {
      appLogger.d('BannerCarousel: Bannerlar bo‘sh');
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            "Bannerlar topilmadi",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        CarouselSlider(
          carouselController: _carouselController,
          options: CarouselOptions(
            height: 200.0,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 6),
            enlargeCenterPage: true,
            viewportFraction: 0.9,
            onPageChanged: (index, reason) {
              setState(() {
                _currentIndex = index;
                _animationController.reset();
                _animationController.forward();
              });
            },
          ),
          items:
              banners.map((banner) {
                return Builder(
                  builder: (BuildContext context) {
                    return BannerItem(banner: banner);
                  },
                );
              }).toList(),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children:
                banners.asMap().entries.map((entry) {
                  final index = entry.key;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child:
                        _currentIndex == index
                            ? _buildAnimatedIndicator()
                            : Container(
                              width: 8.0,
                              height: 8.0,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey.withOpacity(0.5),
                              ),
                            ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  /// Halqa animatsiyasi widget qayta qurilmasdan chiziladi.
  ///
  /// Ilgari bu `ValueListenableBuilder` ichida edi, ya'ni 6 soniyalik
  /// kontroller har vsync'da widgetni qayta qurardi. O'lchov: bosh sahifa
  /// bo'sh turganda kadr qurish vaqti 3.5 ms (p50) edi, `CustomPainter`ni
  /// to'g'ridan-to'g'ri kontrollerga ulagandan keyin 1.2 ms. Ko'rinish
  /// o'zgarmagan — faqat qayta chizish qatlami qoldi.
  Widget _buildAnimatedIndicator() {
    return SizedBox(
      width: 16.0,
      height: 16.0,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // `RepaintBoundary` shart: usiz halqaning har tikida qayta chizish
          // yuqoriga tarqalib, kadr qurish vaqti yana 3.5 ms ga qaytadi
          // (o'lchangan).
          RepaintBoundary(
            child: CustomPaint(
              painter: CircleProgressPainter(_animationController),
              child: const SizedBox(width: 16.0, height: 16.0),
            ),
          ),
          Container(
            width: 8.0,
            height: 8.0,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// Aylana animatsiyasi uchun CustomPainter.
//
// Animatsiyani `repaint:` orqali oladi — shunda har kadrda widget daraxti
// emas, faqat shu rasm qayta chiziladi.
class CircleProgressPainter extends CustomPainter {
  final Animation<double> progress;

  CircleProgressPainter(this.progress) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 2) / 2;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress.value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CircleProgressPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// Banner Item
class BannerItem extends StatelessWidget {
  final dynamic banner;

  const BannerItem({super.key, required this.banner});

  @override
  Widget build(BuildContext context) {
    final film = banner['film'] as Map<String, dynamic>? ?? {};
    final files = banner['files'] as List<dynamic>? ?? [];
    final imageUrl =
        files.isNotEmpty
            ? files[0]['link'] ?? 'https://placehold.co/640x360'
            : 'https://placehold.co/640x360';
    final title = film['name_uz'] ?? banner['title'] ?? 'Noma’lum';
    final year = film['year']?.toString() ?? 'Noma’lum';
    final kinopoiskRating = film['kinopoisk_rating']?.toString() ?? 'N/A';
    final imdbRating = film['imdb_rating']?.toString() ?? 'N/A';
    final filmId = film['id'] ?? 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(context, createSlideRoute(FilmScreen(filmId: filmId)));
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5.0),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                cacheManager: filmImagesCacheManager,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) =>
                        const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) {
                  appLogger.d('Banner rasm yuklash xatosi: $error');
                  return Container(
                    width: double.infinity,
                    height: 200,
                    color: Colors.grey[300],
                    child: const Center(
                      child: Text(
                        'Rasmni yuklashda xato',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.6), // TUZATILDI
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // TUZATILISHA MUHTOJ: substring o‘rniga ellipsis ishlatish yaxshi
                  Text(
                    title.length > 16 ? '${title.substring(0, 16)}...' : title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    year,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 10,
              right: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Text(
                        'Kinopoisk: ',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      Text(
                        kinopoiskRating,
                        style: const TextStyle(
                          color: Colors.yellow,
                          fontSize: 12,
                        ),
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
                        style: const TextStyle(
                          color: Colors.yellow,
                          fontSize: 12,
                        ),
                      ),
                    ],
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

// Latest Viewed Section
class LatestViewedSection extends StatelessWidget {
  const LatestViewedSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final provider = Provider.of<IndexScreenProvider>(context);
    final latestViewed = provider.latestViewed;
    final isLoading = provider.isLoadingLatestViewed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Ko‘rishni davom ettirish",
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
                onPressed: () {
                  Navigator.push(
                    context,
                    createSlideRoute(const LatestViewedScreen()),
                  );
                },
              ),
            ],
          ),
          SizedBox(
            // 120 px muqova + nomi va yili uchun qo'shimcha joy.
            height: 120 + _latestViewedCaptionHeight,
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: latestViewed.length,
                      itemExtent: 180,
                      cacheExtent: 9999, // TUZATILISHGA MUHTOJ: juda katta
                      itemBuilder: (context, index) {
                        return LatestViewedItem(item: latestViewed[index]);
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

/// Muqova ostidagi nom va yil uchun ajratilgan balandlik.
const double _latestViewedCaptionHeight = 40;

// Latest Viewed Item
class LatestViewedItem extends StatelessWidget {
  final dynamic item;

  const LatestViewedItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final film = item['film'] as Map<String, dynamic>? ?? {};
    final screenshots = item['screenshots'] as List<dynamic>? ?? [];
    final second = item['second'] as Map<String, dynamic>? ?? {};
    final file =
        screenshots.isNotEmpty
            ? (screenshots[0]['file'] as List<dynamic>?)?.first ?? {}
            : {};
    final imageUrl =
        screenshots.isNotEmpty
            ? (file['thumbnails'] != null &&
                    file['thumbnails']['small'] != null &&
                    file['thumbnails']['small']['src'] != null
                ? file['thumbnails']['small']['src']
                : file['link'] ?? 'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    final filmId = film['id'] ?? item['film_id'] ?? 0;
    final viewedTime = second['time'] ?? 0;
    final double progress = latestViewedProgress(item);
    final viewedTimeString = formatWatchedTime(viewedTime);
    final themeProvider = Provider.of<ThemeProvider>(context);

    final filmName = (film['name_uz'] ?? film['name_ru'] ?? 'Noma’lum').toString();
    final year = film['year']?.toString() ?? '';
    // Seriallar uchun yozuvning o'z nomi qism nomi bo'ladi ("3-qism"), film
    // uchun esa u film nomining o'zi yoki bo'sh keladi.
    final episodeName = (item['name_uz'] ?? '').toString().trim();
    final isEpisode = episodeName.isNotEmpty && episodeName != filmName;

    return GestureDetector(
      // Film sahifasini ochish o'rniga to'g'ridan-to'g'ri o'ynatamiz:
      // "Ko'rishni davom ettirish" aynan shu ortiqcha qadamlarni yo'q qilish
      // uchun bor. Film sahifasi uzoq bosish orqali ochiladi.
      // Pleerdan qaytgach ro'yxatni ekranning o'zi `didPopNext` da
      // yangilaydi — bu yerda takroran so'rov yubormaymiz.
      onTap: () => VideoLauncher.playFromLatestViewed(context, item),
      onLongPress: () {
        Navigator.push(context, createSlideRoute(FilmScreen(filmId: filmId)));
      },
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(
                    imageUrl,
                    cacheManager: filmImagesCacheManager,
                    // TUZATILISHGA MUHTOJ: errorListener faqat rasm yuklash xatolarini tutadi, UI errorWidget emas!
                  ),
                  fit: BoxFit.cover,
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            viewedTimeString,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 154,
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.grey[400],
                            // "So'nggi ko'rilganlar" ekrani bilan bir xil rang.
                            valueColor: AlwaysStoppedAnimation<Color>(
                              themeProvider.accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Muqovaning o'zi qaysi film ekanini aytmaydi — nomi ostida
            // yoziladi. Serial bo'lsa nomi qisqartiriladi, qism raqami esa
            // doim ko'rinib turadi: "Kalmar o'yini | 3-qism".
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          filmName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: themeProvider.textColor,
                          ),
                        ),
                      ),
                      if (isEpisode)
                        Text(
                          " | $episodeName",
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: themeProvider.textColor,
                          ),
                        ),
                    ],
                  ),
                  if (year.isNotEmpty)
                    Text(
                      year,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: themeProvider.subTextColor,
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

// Recommended Films Section
class RecommendedFilmsSection extends StatelessWidget {
  const RecommendedFilmsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final provider = Provider.of<IndexScreenProvider>(context);
    final films = provider.recommendedFilms;
    final isLoading = provider.isLoadingRecommended;

    return RecommendedFilmsWidget(
      films: films,
      isLoading: isLoading,
      isDark: themeProvider.isDarkMode,
      onTap: (film) {
        final filmId = film['id'];
        Navigator.push(context, createSlideRoute(FilmScreen(filmId: filmId)));
      },
      onMoreTap: () {
        Navigator.push(
          context,
          createSlideRoute(const RecommendedFilmsScreen()),
        );
      },
    );
  }
}

// Genres Section
class GenresSection extends StatelessWidget {
  final VoidCallback onRetry;

  const GenresSection({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final provider = Provider.of<IndexScreenProvider>(context);
    final genres = provider.genresPreview;
    final isLoading = provider.isLoadingGenres;
    final error = provider.genresError;

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            children: [
              Text(
                "Janrlarni yuklashda xato: $error",
                style: const TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Qayta urinish'),
              ),
            ],
          ),
        ),
      );
    }
    if (genres.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text(
            "Janrlar topilmadi",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Janrlar",
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
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  Navigator.push(
                    context,
                    createSlideRoute(const GenresScreen()),
                  );
                },
              ),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: genres.length,
            itemBuilder: (context, index) {
              final genre = genres[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GenreCard(
                  genre: genre,
                  onTap: () async {
                    final connectivityResult =
                        await Connectivity().checkConnectivity();
                    if (connectivityResult.every(
                      (result) => result == ConnectivityResult.none,
                    )) {
                      appLogger.d(
                        'No internet connection, navigating to NetworkErrorPage',
                      );
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => NetworkErrorPage(onRetry: onRetry),
                        ),
                      );
                    } else {
                      Navigator.push(
                        context,
                        createSlideRoute(GenresFilmsScreen(genre: genre)),
                      );
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// Categories Section
class CategoriesSection extends StatelessWidget {
  const CategoriesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final provider = Provider.of<IndexScreenProvider>(context);
    final categories = provider.categories;
    final categoryFilms = provider.categoryFilms;
    final isLoadingCategoryFilms = provider.isLoadingCategoryFilms;

    if (provider.isLoadingCategories) {
      return const SizedBox.shrink();
    }
    return Column(
      children:
          categories.map((category) {
            final categoryId = category['id'];
            final films = categoryFilms[categoryId] ?? [];
            final isLoading = isLoadingCategoryFilms[categoryId] ?? true;

            return CategorySection(
              category: category,
              films: films,
              isLoading: isLoading,
              isDarkMode: themeProvider.isDarkMode,
            );
          }).toList(),
    );
  }
}

// Category Section
class CategorySection extends StatelessWidget {
  final dynamic category;
  final List<dynamic> films;
  final bool isLoading;
  final bool isDarkMode;

  const CategorySection({
    super.key,
    required this.category,
    required this.films,
    required this.isLoading,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const horizontalPadding = 16.0 * 2;
    const itemMargin = 12.0;
    // Nechta muqova bir ekranga sig'ishi Profil bo'limidagi sozlamadan
    // keladi (2x2 yoki 3x3).
    final columns = Provider.of<GridDensityProvider>(context).columns;
    final itemWidth =
        (screenWidth - horizontalPadding - itemMargin * (columns - 1)) /
        columns;
    final itemHeight = itemWidth * 1.5;
    final sectionHeight = itemHeight + 40 + 8;

    appLogger.d(
      'Category ${category['id']}: isLoading=$isLoading, films=${films.length}',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category['title_uz'] ?? 'Noma’lum',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.grey[800],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  Navigator.push(
                    context,
                    createSlideRoute(
                      CategoriesScreen(initialCategory: category),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: sectionHeight,
            child:
                isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : films.isEmpty
                    ? const Center(
                      child: Text(
                        "Kontent mavjud emas",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: films.length,
                      itemExtent: itemWidth + itemMargin,
                      cacheExtent: 9999, // TUZATILISHGA MUHTOJ: juda katta
                      itemBuilder: (context, index) {
                        return FilmItem(
                          film: films[index],
                          itemWidth: itemWidth,
                          itemHeight: itemHeight,
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

// Film Item
class FilmItem extends StatelessWidget {
  final dynamic film;
  final double itemWidth;
  final double itemHeight;

  const FilmItem({
    super.key,
    required this.film,
    required this.itemWidth,
    required this.itemHeight,
  });

  @override
  Widget build(BuildContext context) {
    final files = film['files'] ?? [];
    final imageUrl =
        files.isNotEmpty
            ? (files[0]['thumbnails'] != null &&
                    files[0]['thumbnails']['small'] != null &&
                    files[0]['thumbnails']['small']['src'] != null
                ? files[0]['thumbnails']['small']['src']
                : files[0]['link'] ?? 'https://placehold.co/320x180')
            : 'https://placehold.co/320x180';
    final title = film['name_uz'] ?? 'Noma’lum';
    final year = film['year']?.toString() ?? '';
    final genres = film['genres'] ?? [];
    final genreName = genres.isNotEmpty ? genres[0]['name_uz'] ?? '' : '';
    final filmId = film['id'];

    return GestureDetector(
      onTap: () {
        Navigator.push(context, createSlideRoute(FilmScreen(filmId: filmId)));
      },
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        width: itemWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: itemHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                image: DecorationImage(
                  image: CachedNetworkImageProvider(
                    imageUrl,
                    cacheManager: filmImagesCacheManager,
                  ),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    year.isNotEmpty && genreName.isNotEmpty
                        ? "$year · $genreName"
                        : year.isNotEmpty
                        ? year
                        : genreName,
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// GenreCard
class GenreCard extends StatelessWidget {
  final Map<String, dynamic> genre;
  final VoidCallback onTap;

  const GenreCard({super.key, required this.genre, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl =
        genre['photo'] != null
            ? (genre['photo']['thumbnails'] != null &&
                    genre['photo']['thumbnails']['small'] != null &&
                    genre['photo']['thumbnails']['small']['src'] != null
                ? genre['photo']['thumbnails']['small']['src']
                : genre['photo']['link'] ?? 'https://placehold.co/305x200')
            : 'https://placehold.co/305x200';
    final name = genre['name_uz'] ?? 'Noma’lum';

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              cacheManager: filmImagesCacheManager,
              width: 305,
              height: 200,
              fit: BoxFit.cover,
              placeholder:
                  (context, url) =>
                      const Center(child: CircularProgressIndicator()),
              errorWidget: (context, url, error) {
                appLogger.d('Genre rasm yuklash xatosi: $error');
                return Container(
                  width: 305,
                  height: 200,
                  color: Colors.grey[300],
                  child: const Center(
                    child: Text(
                      'Rasmni yuklashda xato',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            width: 305,
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.6), // TUZATILDI
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 16,
            child: Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
