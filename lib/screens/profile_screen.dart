import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/screens/profile/activate_tv_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/screens/profile/profile_details_screen.dart';
import 'package:riya_play/screens/profile/devices_screen.dart';
import 'package:riya_play/screens/profile/history_screen.dart';
import 'package:riya_play/screens/download_screen.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riya_play/utils/navigation.dart'; // createSlideRoute uchun import
import 'package:riya_play/services/update_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String appVersion = "1.0.0";

  @override
  void initState() {
    super.initState();
    _fetchAppVersion();
  }

  Future<void> _fetchAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        appVersion = packageInfo.version;
      });
    } catch (e) {
      setState(() {
        appVersion = "Noma'lum";
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Versiya ma\'lumotini olishda xato: $e')),
        );
      }
    }
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();
      return connectivityResult.any(
        (result) => result != ConnectivityResult.none,
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> _logout(BuildContext context) async {
    if (!(await _checkInternetConnection())) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Internet aloqasi yo‘q')));
      }
      return;
    }

    try {
      await ApiService.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const AuthScreen()),
        );
      }
    } catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (mounted) {
        final themeProvider = Provider.of<ThemeProvider>(
          context,
          listen: false,
        );
        showDialog(
          context: context,
          builder:
              (context) => AlertDialog(
                backgroundColor: themeProvider.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  "Xato",
                  style: TextStyle(color: themeProvider.textColor),
                  semanticsLabel: "Xato",
                ),
                content: Text(
                  "Chiqishda xato: $e",
                  style: TextStyle(color: themeProvider.subTextColor),
                  semanticsLabel: "Chiqishda xato: $e",
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (mounted) {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const AuthScreen(),
                          ),
                        );
                      }
                    },
                    child: Text(
                      "OK",
                      style: TextStyle(color: themeProvider.accentColor),
                      semanticsLabel: "OK",
                    ),
                  ),
                ],
              ),
        );
      }
    }
  }

  void _showLogoutDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder:
          (dialogContext) => LogoutDialog(
            onConfirm: () async {
              Navigator.pop(dialogContext);
              await _logout(context);
            },
          ),
    );
  }

  Future<void> _refresh() async {
    await _fetchAppVersion();
    // Agar profil ma'lumotlari API orqali yuklansa, bu yerga qo'shish mumkin
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ma\'lumotlar yangilandi')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final double padding = MediaQuery.of(context).size.width * 0.04;

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        title: Text(
          'Profil',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
          semanticsLabel: 'Profil',
        ),
      ),
      body: SafeArea(
        top: true,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: padding, vertical: 16),
              child: Column(
                children: [
                  _buildListTile(
                    context,
                    icon: IconlyLight.profile,
                    title: "Profil ma'lumotlari",
                    onTap: () {
                      Navigator.push(
                        context,
                        createSlideRoute(
                          const ProfileDetailsScreen(),
                        ), // PageRouteBuilder bilan o‘tish
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.setting,
                    title: "Qurilmalar",
                    onTap: () {
                      Navigator.push(
                        context,
                        createSlideRoute(
                          const DevicesScreen(),
                        ), // PageRouteBuilder bilan o‘tish
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.timeCircle,
                    title: "Ko'rishlar tarixi",
                    onTap: () {
                      Navigator.push(
                        context,
                        createSlideRoute(
                          const HistoryScreen(),
                        ), // PageRouteBuilder bilan o‘tish
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.download,
                    title: "Yuklab olishlar",
                    onTap: () {
                      Navigator.push(
                        context,
                        createSlideRoute(const DownloadScreen.queue()),
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.ticket,
                    title: "Promokod",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Promokod funksiyasi tez kunda!'),
                        ),
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.infoSquare,
                    title: "Qo'llab-quvvatlash",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Qo‘llab-quvvatlash funksiyasi tez kunda!',
                          ),
                        ),
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.document,
                    title: "Foydalanish shartlari",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Foydalanish shartlari tez kunda!'),
                        ),
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.video,
                    title: "RiyaPlay TVni faollashtirish",
                    onTap: () {
                      Navigator.push(
                        context,
                        createSlideRoute(
                          const ActivateRiyaPlayTVScreen(),
                        ), // PageRouteBuilder bilan o‘tish
                      );
                    },
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.download,
                    title: "Yangilanishni tekshirish",
                    onTap: () => UpdateService.checkManually(context),
                  ),
                  _buildListTile(
                    context,
                    icon: IconlyLight.infoSquare,
                    title: "Biz haqimizda",
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Biz haqimizda funksiyasi tez kunda!'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTapDown: (_) => setState(() {}), // Animatsiya uchun
                    onTapUp: (_) {
                      setState(() {});
                      _showLogoutDialog();
                    },
                    onTapCancel: () => setState(() {}),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      transform: Matrix4.identity()..scale(1.0),
                      padding: const EdgeInsets.symmetric(
                        vertical: 15,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: themeProvider.cardColor,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: themeProvider.deleteButtonColor,
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: themeProvider.shadowColor,
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: themeProvider.deleteButtonColor
                                  .withOpacity(0.2),
                            ),
                            child: Icon(
                              IconlyLight.logout,
                              color: themeProvider.deleteButtonColor,
                              size: 28,
                              semanticLabel: "Chiqish",
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              "Chiqish",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: themeProvider.deleteButtonColor,
                              ),
                              semanticsLabel: "Chiqish",
                            ),
                          ),
                          Icon(
                            IconlyLight.arrowRight2,
                            color: themeProvider.deleteButtonColor,
                            semanticLabel: "O‘ngga",
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Ilova versiyasi: $appVersion",
                    style: TextStyle(
                      fontSize: 14,
                      color: themeProvider.subTextColor,
                    ),
                    semanticsLabel: "Ilova versiyasi: $appVersion",
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    bool isPressed = false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: StatefulBuilder(
        builder: (context, setState) {
          return GestureDetector(
            onTapDown: (_) => setState(() => isPressed = true),
            onTapUp: (_) {
              setState(() => isPressed = false);
              onTap();
            },
            onTapCancel: () => setState(() => isPressed = false),
            child: AnimatedScale(
              scale: isPressed ? 0.95 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: themeProvider.cardColor,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: themeProvider.borderColor,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themeProvider.shadowColor,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: themeProvider.iconCircleColor,
                      ),
                      child: Icon(
                        icon,
                        color: themeProvider.iconColor,
                        size: 28,
                        semanticLabel: title,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.textColor,
                        ),
                        semanticsLabel: title,
                      ),
                    ),
                    Icon(
                      IconlyLight.arrowRight2,
                      color: themeProvider.subTextColor,
                      semanticLabel: "O‘ngga",
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LogoutDialog extends StatelessWidget {
  final Future<void> Function() onConfirm;

  const LogoutDialog({super.key, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: themeProvider.borderColor, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Haqiqatdan ham chiqmoqchimisiz?",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: themeProvider.textColor,
            ),
            semanticsLabel: "Haqiqatdan ham chiqmoqchimisiz?",
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton(
                onPressed: () async {
                  await onConfirm();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.deleteButtonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                child: const Text("Chiqish", semanticsLabel: "Chiqish"),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.cancelButtonColor,
                  foregroundColor: themeProvider.textColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 5,
                ),
                child: const Text(
                  "Bekor qilish",
                  semanticsLabel: "Bekor qilish",
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
