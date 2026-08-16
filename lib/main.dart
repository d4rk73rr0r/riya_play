import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/screens/index_screen.dart';
import 'package:riya_play/screens/catalog_screen.dart';
import 'package:riya_play/screens/tv_channels_screen.dart';
import 'package:riya_play/screens/favorites_screen.dart';
import 'package:riya_play/screens/profile_screen.dart';
import 'package:riya_play/services/download_manager.dart';
import 'package:riya_play/services/update_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:riya_play/utils/system_ui.dart';
import 'package:riya_play/widgets/glass_bottom_bar.dart';

/// Ekranlar qaysi biri ustiga qaysi biri qo'yilganini kuzatadi.
///
/// "Ko'rishni davom ettirish" ro'yxatlari pleer yopilganda yangilanishi
/// kerak, lekin pleer bir necha yo'l bilan ochiladi (kartochka, film sahifasi,
/// epizodlar ro'yxati). Har bir chaqiruv joyiga qayta yuklashni ulash o'rniga
/// ekranning o'zi `RouteAware.didPopNext()` orqali "menga qaytishdi" xabarini
/// oladi.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Tizim navigatsiya paneli yashiriladi — pastdagi shisha menyu ekran
  // chetigacha chizilsin.
  await AppSystemUi.apply();
  // Yuklashlar ro'yxati ekran ochilishidan oldin tiklanadi, aks holda
  // "Yuklab olishlar" bir zumga bo'sh ko'rinib qoladi. O'lchangan: 68–93 ms,
  // va uni kutmaslik birinchi kadr vaqtini o'zgartirmadi — shuning uchun
  // tartib ataylab shunday qoldirildi.
  await DownloadManager.instance.restore();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: const RiyaPlayApp(),
    ),
  );
}

class RiyaPlayApp extends StatefulWidget {
  const RiyaPlayApp({super.key});

  @override
  State<RiyaPlayApp> createState() => _RiyaPlayAppState();
}

class _RiyaPlayAppState extends State<RiyaPlayApp> {
  @override
  void initState() {
    super.initState();
    initialization();
  }

  /// Splash faqat haqiqiy tayyorgarlik uchun ushlab turiladi.
  ///
  /// Ilgari bu yerda uchta kutish bor edi va ikkitasi sun'iy: `Future.doWhile`
  /// `themeProvider.isInitialized` ni kutardi, lekin u doim `true` — ya'ni
  /// bitta 100 ms uyquga teng edi; ustiga yana 500 ms `Future.delayed`
  /// qo'shilgandi. O'lchov: splash 572 ms da olib tashlanardi, shundan ~600 ms
  /// shu ikki kutish edi. `SharedPreferences` esa haqiqatan kerak — undan
  /// keyin darrov `_checkAuthToken` o'qiydi.
  void initialization() async {
    try {
      await SharedPreferences.getInstance();
    } catch (e) {
      appLogger.d('Initialization error: $e');
    } finally {
      if (mounted) {
        FlutterNativeSplash.remove();
      }
    }
  }

  Future<String?> _checkAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    if (!themeProvider.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return MaterialApp(
      title: 'RiyaPlay',
      debugShowCheckedModeBanner: false,
      navigatorObservers: [routeObserver],
      theme: _buildDarkTheme(),
      darkTheme: _buildDarkTheme(),
      themeMode: ThemeMode.dark,
      // Routes sectioni o'chirildi, chunki endi kerak emas
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.0), boldText: false),
          child: child!,
        );
      },
      home: FutureBuilder<String?>(
        future: _checkAuthToken(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
            return const MainScreen();
          }
          return const AuthScreen();
        },
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final baseTheme = ThemeData.dark();
    return baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: ThemeProvider.brandPinkLight,
        secondary: ThemeProvider.brandPurple,
      ),
      scaffoldBackgroundColor: const Color(0xFF111827),
      textTheme: GoogleFonts.poppinsTextTheme(
        baseTheme.textTheme.copyWith(
          displayLarge: const TextStyle(fontSize: 24.0, color: Colors.white),
          displayMedium: const TextStyle(fontSize: 20.0, color: Colors.white),
          bodyLarge: const TextStyle(fontSize: 14.0, color: Colors.white),
          bodyMedium: const TextStyle(fontSize: 12.0, color: Colors.white),
          labelLarge: const TextStyle(fontSize: 14.0, color: Colors.white),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white, size: 24.0),
      appBarTheme: AppBarTheme(
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  int _selectedIndex = 0;
  final List<Widget> _screens = [
    const IndexScreen(),
    const TVChannelsScreen(),
    const CatalogScreen(),
    const FavoritesScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Yangilanish tekshiruvi bosh ekran chizilgandan keyin — ochilishni
    // sekinlashtirmaydi va xato bo'lsa jim o'tadi.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkOnStartup(context);
    });
    _tabController = TabController(length: _screens.length, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index != _selectedIndex) {
        setState(() {
          _selectedIndex = _tabController.index;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && mounted) {
      // Boshqa ilovadan qaytganda tizim panellarni qaytarib chiqaradi.
      AppSystemUi.apply();
      setState(() {
        _selectedIndex = _tabController.index;
      });
    }
  }

  void _onItemTapped(int index) {
    if (_selectedIndex != index) {
      setState(() {
        _selectedIndex = index;
        _tabController.animateTo(index);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      // Shisha menyu ortida kontent bo'lishi kerak, aks holda
      // `BackdropFilter` xiralashtiradigan narsa topmaydi.
      extendBody: true,
      body: TabBarView(
        controller: _tabController,
        physics: const BouncingScrollPhysics(),
        children:
            _screens.map((screen) => KeepAliveWrapper(child: screen)).toList(),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: GlassBottomBar(
          // Ko'rsatkichning o'rni panelning o'z kengligidan hisoblanadi:
          // shisha panel chetlardan ichkariroq turadi, ekran kengligiga
          // tayanilsa ko'rsatkich tugmalardan siljib qoladi.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  // Yuqoridan bo'sh joy — ko'rsatkich chizig'i ikonkalar ustiga
                  // tushib qolmasin.
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap: _onItemTapped,
                      selectedItemColor: themeProvider.accentColor,
                      unselectedItemColor: themeProvider.subTextColor,
                      backgroundColor: Colors.transparent,
                      // Shisha panel ekran chetlaridan ichkariroq turadi, shuning
                      // uchun yorliqlar 12 pt da eng chetdagisi kesilib qolardi.
                      selectedFontSize: 11,
                      unselectedFontSize: 11,
                      selectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: themeProvider.accentColor,
                      ),
                      unselectedLabelStyle: GoogleFonts.poppins(
                        fontSize: 11,
                        color: themeProvider.subTextColor,
                      ),
                      type: BottomNavigationBarType.fixed,
                      elevation: 0,
                      items: [
                        BottomNavigationBarItem(
                          icon: AnimatedScale(
                            scale: _selectedIndex == 0 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyLight.home,
                              color:
                                  _selectedIndex == 0
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          activeIcon: AnimatedScale(
                            scale: _selectedIndex == 0 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyBold.home,
                              color:
                                  _selectedIndex == 0
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          label: 'Bosh sahifa',
                        ),
                        BottomNavigationBarItem(
                          icon: AnimatedScale(
                            scale: _selectedIndex == 1 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyLight.video,
                              color:
                                  _selectedIndex == 1
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          activeIcon: AnimatedScale(
                            scale: _selectedIndex == 1 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyBold.video,
                              color:
                                  _selectedIndex == 1
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          label: 'TV',
                        ),
                        BottomNavigationBarItem(
                          icon: AnimatedScale(
                            scale: _selectedIndex == 2 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyLight.category,
                              color:
                                  _selectedIndex == 2
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          activeIcon: AnimatedScale(
                            scale: _selectedIndex == 2 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyBold.category,
                              color:
                                  _selectedIndex == 2
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          label: 'Katalog',
                        ),
                        BottomNavigationBarItem(
                          icon: AnimatedScale(
                            scale: _selectedIndex == 3 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyLight.heart,
                              color:
                                  _selectedIndex == 3
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          activeIcon: AnimatedScale(
                            scale: _selectedIndex == 3 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyBold.heart,
                              color:
                                  _selectedIndex == 3
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          label: 'Sevimlilar',
                        ),
                        BottomNavigationBarItem(
                          icon: AnimatedScale(
                            scale: _selectedIndex == 4 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyLight.profile,
                              color:
                                  _selectedIndex == 4
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          activeIcon: AnimatedScale(
                            scale: _selectedIndex == 4 ? 1.2 : 1.0,
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Icon(
                              IconlyBold.profile,
                              color:
                                  _selectedIndex == 4
                                      ? themeProvider.accentColor
                                      : themeProvider.subTextColor,
                            ),
                          ),
                          label: 'Profil',
                        ),
                      ],
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    // Yumaloq chetdan pastroq, aks holda ko'rsatkich
                    // burchakda kesilib qoladi.
                    top: 4,
                    left:
                        _selectedIndex * (barWidth / 5) + (barWidth / 10) - 16,
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            themeProvider.accentColor.withOpacity(0.7),
                            themeProvider.accentColor,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
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
}

// KeepAliveWrapper uchun yordamchi widget
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;

  const KeepAliveWrapper({super.key, required this.child});

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin uchun zarur
    return widget.child;
  }

  @override
  bool get wantKeepAlive => true; // Har bir ekranning holatini saqlash
}
