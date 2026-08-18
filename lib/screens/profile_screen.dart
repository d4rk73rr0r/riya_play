import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/screens/profile/activate_tv_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/screens/profile/profile_details_screen.dart';
import 'package:riya_play/screens/profile/devices_screen.dart';
import 'package:riya_play/screens/profile/history_screen.dart';
import 'package:riya_play/screens/download_screen.dart';
import 'package:riya_play/theme/glass.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:riya_play/utils/grid_density.dart';
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

  void _showGridDensityDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (dialogContext) => const GridDensityDialog(),
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
      // `bottom: false` — kontent shisha menyu ortidan o'tib, tizim
      // navigatsiya paneligacha ko'rinsin. To'ldirish ro'yxat ichiga
      // ko'chiriladi, aks holda oxirgi element menyu ostida qolib ketadi.
      body: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom,
            ),
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
                    icon: IconlyLight.category,
                    title: "Muqovalar ko'rinishi",
                    value:
                        Provider.of<GridDensityProvider>(context).label,
                    onTap: _showGridDensityDialog,
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
    // Sozlama qatorlari uchun: joriy qiymat o'ng tomonda ko'rinadi ("2x2").
    String? value,
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
                    if (value != null) ...[
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: themeProvider.accentColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
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
      // Pastdan chiqadigan oyna tizim navigatsiya paneli ostidan boshlanadi,
      // shuning uchun tugmalar uning ustiga tushib qolmasin.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: GlassSurface.gradient,
        borderRadius: GlassSurface.sheetBorderRadius,
        border: GlassSurface.sheetBorder,
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

/// Muqovalar setkasini tanlash oynasi: 2x2 yoki 3x3.
///
/// Tanlov bosh sahifadagi qatorlarga, Katalog va Sevimlilar setkalariga
/// birdek ta'sir qiladi, shuning uchun oynada shu ham yozib qo'yilgan.
class GridDensityDialog extends StatelessWidget {
  const GridDensityDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final density = Provider.of<GridDensityProvider>(context);

    return Container(
      // Pastdan chiqadigan oyna tizim navigatsiya paneli ostidan boshlanadi.
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewPadding.bottom,
      ),
      decoration: BoxDecoration(
        gradient: GlassSurface.gradient,
        borderRadius: GlassSurface.sheetBorderRadius,
        border: GlassSurface.sheetBorder,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Muqovalar ko'rinishi",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: themeProvider.textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Bosh sahifa, Katalog va Sevimlilar uchun",
            style: TextStyle(fontSize: 13, color: themeProvider.subTextColor),
          ),
          const SizedBox(height: 16),
          for (final columns in GridDensityProvider.allowedColumns)
            _GridDensityOption(
              columns: columns,
              isSelected: density.columns == columns,
              onTap: () {
                density.setColumns(columns);
                Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}

class _GridDensityOption extends StatelessWidget {
  final int columns;
  final bool isSelected;
  final VoidCallback onTap;

  const _GridDensityOption({
    required this.columns,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final description =
        columns == 2
            ? "Kattaroq muqovalar, qatorda 2 ta"
            : "Kichikroq muqovalar, qatorda 3 ta";

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected
                      ? themeProvider.accentColor
                      : themeProvider.borderColor,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // Tanlovni bir qarashda ko'rsatadigan kichik setka namunasi.
              _GridPreview(columns: columns, color: themeProvider.textColor),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "${columns}x$columns",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: themeProvider.textColor,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: themeProvider.subTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle, color: themeProvider.accentColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridPreview extends StatelessWidget {
  final int columns;
  final Color color;

  const _GridPreview({required this.columns, required this.color});

  @override
  Widget build(BuildContext context) {
    const double size = 36;
    const double gap = 3;
    final cell = (size - gap * (columns - 1)) / columns;

    return SizedBox(
      width: size,
      height: size,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          columns,
          (_) => Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              columns,
              (_) => Container(
                width: cell,
                height: cell,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
