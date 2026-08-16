import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tizim panellarini boshqarishning yagona joyi.
///
/// Ilova pastdagi tizim navigatsiya panelini yashiradi va o'zining shisha
/// menyusini ekran chetigacha chizadi. Status bar esa qoladi — bosh sahifa va
/// film sahifasi posterni uning ostiga chizishga mo'ljallangan.
///
/// Buni bir joyda ushlab turish shart: pleer to'liq ekranga o'tganda rejimni
/// o'zgartiradi va chiqishda qaytaradi. Har bir ekran o'zicha
/// `setEnabledSystemUIMode` chaqirsa, holat bir-biriga zid bo'lib qoladi.
class AppSystemUi {
  AppSystemUi._();

  /// Panel qayta yashirilgunicha ko'rinib turadigan vaqt.
  static const Duration rehideDelay = Duration(seconds: 3);

  static Timer? _rehideTimer;
  static bool _callbackInstalled = false;

  /// Status bar shaffof (ikonkalari oq), navigatsiya paneli ham shaffof.
  ///
  /// `systemNavigationBarContrastEnforced: false` shart: Android 10+ shaffof
  /// panel ortiga o'zi yarim shaffof qora qatlam chizadi va shisha effekti
  /// ko'rinmay qoladi.
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
  );

  /// Ilovaning odatiy holati: pastki panel yashirin, status bar ko'rinadi.
  ///
  /// Foydalanuvchi pastdan yuqoriga surganda tizim panelni vaqtincha
  /// ko'rsatadi; [_installChangeCallback] uni [rehideDelay] dan keyin yana
  /// yashiradi.
  static Future<void> apply() async {
    _installChangeCallback();
    _rehideTimer?.cancel();
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: const [SystemUiOverlay.top],
    );
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
  }

  /// Pleer to'liq ekranda: ikkala panel ham yashirin.
  static Future<void> applyFullscreen() async {
    _rehideTimer?.cancel();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  static void _installChangeCallback() {
    if (_callbackInstalled) return;
    _callbackInstalled = true;
    SystemChrome.setSystemUIChangeCallback((visible) async {
      if (!visible) return;
      // Panel foydalanuvchi surgani uchun chiqdi. Darrov yashirsak, uni
      // umuman ishlatib bo'lmaydi — shuning uchun ko'rish uchun vaqt beriladi.
      _rehideTimer?.cancel();
      _rehideTimer = Timer(rehideDelay, apply);
    });
  }
}
