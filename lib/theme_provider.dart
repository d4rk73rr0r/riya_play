import 'package:flutter/material.dart';

/// Color palette for the app.
///
/// Riya Play is dark-only, matching Netflix/HBO Max/Prime Video — none of
/// them offer a light theme either. A previous light/dark toggle was
/// removed after it caused status-bar rendering glitches on some devices
/// (icons disappearing against a black bar) that only showed up after
/// switching themes at runtime; a permanently dark theme sidesteps that
/// whole bug class instead of chasing it screen by screen.
class ThemeProvider extends ChangeNotifier {
  bool get isDarkMode => true;
  bool get isInitialized => true;

  // Brend ranglari — ilova logotipidagi gradientdan olingan (pushti -> binafsha).
  static const Color brandPink = Color(0xFFE6007E);
  static const Color brandPinkLight = Color(0xFFFF4FA3);
  static const Color brandPurple = Color(0xFF5B1458);

  // Ranglar palitrasi
  Color get backgroundColor => const Color(0xFF111827);
  Color get cardColor => const Color(0xFF1F2937);
  Color get currentDeviceColor => const Color(0xFF2A3447);
  Color get appBarColor => const Color(0xFF1F2937);
  Color get textColor => Colors.white;
  Color get subTextColor => Colors.grey[400]!;
  Color get iconColor => Colors.grey[400]!;
  Color get currentDeviceIconColor => accentColor;
  Color get accentColor => brandPinkLight;
  Color get borderColor => Colors.grey[700]!;
  Color get buttonColor => brandPink;
  Color get cancelButtonColor => Colors.grey[700]!;
  Color get deleteButtonColor => Colors.red[700]!;
  Color get iconCircleColor => Colors.white.withOpacity(0.2);
  Color get shadowColor => Colors.black.withOpacity(0.3);

  /// Tugmalar, banner overlay va aksentli elementlar uchun brend gradienti.
  LinearGradient get accentGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandPink, brandPurple],
  );
}
