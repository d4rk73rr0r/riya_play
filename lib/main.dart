import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/blocs/auth/auth_bloc.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/screens/index_screen.dart';
import 'package:riya_play/screens/search_screen.dart';
import 'package:riya_play/screens/tv_channels_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/storage_service.dart';
import 'package:riya_play/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: const RiyaPlayApp(),
    ),
  );
}

class RiyaPlayApp extends StatelessWidget {
  const RiyaPlayApp({super.key});

  Future<String?> _checkAuthToken(StorageService storage) async {
    return await storage.getToken();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final storage = StorageService();
    final apiService = ApiService(storage);

    return MultiBlocProvider(
      providers: [BlocProvider(create: (_) => AuthBloc(apiService, storage))],
      child: MaterialApp(
        title: 'Riya Play',
        debugShowCheckedModeBanner: false,
        theme: _buildLightTheme(),
        darkTheme: _buildDarkTheme(),
        themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaleFactor: 1.0, boldText: false),
            child: child!,
          );
        },
        home: FutureBuilder<String?>(
          future: _checkAuthToken(storage),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasData && snapshot.data!.isNotEmpty) {
              return const MainScreen();
            }
            return const AuthScreen();
          },
        ),
      ),
    );
  }

  ThemeData _buildLightTheme() {
    final baseTheme = ThemeData.light();
    return baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(primary: Colors.blue),
      scaffoldBackgroundColor: Colors.grey[100],
      textTheme: GoogleFonts.poppinsTextTheme(
        baseTheme.textTheme.copyWith(
          displayLarge: const TextStyle(fontSize: 24.0, color: Colors.black87),
          displayMedium: const TextStyle(fontSize: 20.0, color: Colors.black87),
          bodyLarge: const TextStyle(fontSize: 14.0, color: Colors.black87),
          bodyMedium: const TextStyle(fontSize: 12.0, color: Colors.black87),
          labelLarge: const TextStyle(fontSize: 14.0, color: Colors.black87),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.black87, size: 24.0),
      appBarTheme: AppBarTheme(
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }

  ThemeData _buildDarkTheme() {
    final baseTheme = ThemeData.dark();
    return baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(primary: Colors.blue),
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

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const IndexScreen(),
    const TVChannelsScreen(),
    const SearchScreen(),
    const Center(child: Text("Profil ekrani (Keyinroq qo'shiladi)")),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: "Uy", // S.of(context).home o‘rniga
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.tv),
            label: "TV", // S.of(context).tv o‘rniga
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.search),
            label: "Katalog", // S.of(context).catalog o‘rniga
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: "Profil", // S.of(context).profile o‘rniga
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor:
            themeProvider.isDarkMode ? Colors.grey[400] : Colors.grey,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor:
            themeProvider.isDarkMode ? const Color(0xFF1F2937) : Colors.white,
        selectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
        unselectedLabelStyle: GoogleFonts.poppins(fontSize: 12),
      ),
    );
  }
}
