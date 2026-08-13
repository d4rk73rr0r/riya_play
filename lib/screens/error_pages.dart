import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:riya_play/screens/auth_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/app_logger.dart';

class NetworkErrorPage extends StatelessWidget {
  final VoidCallback? onRetry;

  const NetworkErrorPage({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.signal_wifi_off,
              size: 80,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
            const SizedBox(height: 20),
            Text(
              "Ma'lumot yuklanmadi",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              "Internet aloqasini tekshiring va qayta urinib ko'ring",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 30,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                "Qayta urinish",
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ServerErrorPage extends StatelessWidget {
  final int? statusCode;
  final String? errorMessage;
  final VoidCallback? onRetry;

  const ServerErrorPage({
    super.key,
    this.statusCode,
    this.errorMessage,
    this.onRetry,
  });

  Future<void> _logout(BuildContext context) async {
    try {
      await ApiService.logout();
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false,
      );
    } catch (e) {
      appLogger.d('Logout error: $e');
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    final isUnauthorized = statusCode == 401 || statusCode == 403;
    final isTooManyRequests = statusCode == 429;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF111827) : Colors.grey[100],
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 80,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
            const SizedBox(height: 20),
            Text(
              isTooManyRequests ? "Juda ko‘p so‘rovlar" : "Server xatosi",
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isTooManyRequests
                  ? "Iltimos, bir oz kuting va qayta urinib ko‘ring"
                  : statusCode != null
                  ? "Xato kodi: $statusCode"
                  : errorMessage ?? "Server bilan aloqa o'rnatib bo'lmadi",
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            if (!isUnauthorized && !isTooManyRequests)
              ElevatedButton(
                onPressed: onRetry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  "Qayta urinish",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (isTooManyRequests)
              ElevatedButton(
                onPressed: () async {
                  await Future.delayed(
                    const Duration(seconds: 5),
                  ); // 5 soniya kutish
                  if (context.mounted) onRetry?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  "Qayta urinish",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (isUnauthorized) ...[
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => _logout(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: Text(
                  "Chiqish",
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
