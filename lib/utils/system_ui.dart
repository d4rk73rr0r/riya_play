import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tizim panellarini boshqarishning yagona joyi.
///
/// Ikkala panel ham **ko'rinib turadi**: ilova ularning ostiga chizadi
/// (`edgeToEdge`), lekin ularni yashirmaydi. Shisha menyu `SafeArea` ichida
/// bo'lgani uchun navigatsiya panelidan yuqorida turadi.
///
/// Buni bir joyda ushlab turish shart: pleer to'liq ekranga o'tganda rejimni
/// o'zgartiradi va chiqishda qaytaradi. Har bir ekran o'zicha
/// `setEnabledSystemUIMode` chaqirsa, holat bir-biriga zid bo'lib qoladi.
class AppSystemUi {
  AppSystemUi._();

  /// Ikkala panel ham shaffof, ikonkalari oq.
  ///
  /// `systemNavigationBarContrastEnforced: true` — kontent navigatsiya paneli
  /// ostidan ham o'tadi, ya'ni tizim tugmalari yorqin poster ustiga tushishi
  /// mumkin va oq tugmalar ko'rinmay qolardi. Bu bayroq bilan tizim panel
  /// ortiga o'zining yarim shaffof qatlamini qo'yadi. O'lchangan (yorqin
  /// poster ustida): `#C5AF58` → `#766935`, ya'ni ~40 % quyuqlashadi.
  ///
  /// `systemNavigationBarColor` ni qo'lda berish **ish bermaydi**:
  /// `SystemUiMode.edgeToEdge` da uni tizim e'tiborsiz qoldiradi (sinab
  /// ko'rilgan — 0xA3000000 hech qanday farq bermadi). Shuning uchun rang
  /// shaffof qoladi va quyuqlik yuqoridagi bayroq orqali olinadi.
  static const SystemUiOverlayStyle overlayStyle = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: true,
  );

  /// Ilovaning odatiy holati: status bar ham, navigatsiya paneli ham ko'rinadi.
  static Future<void> apply() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
  }

  /// Pleer to'liq ekranda: vaqtincha ikkala panel ham yashirinadi.
  ///
  /// Bu yagona istisno va u pleerdan chiqishda [apply] bilan qaytariladi —
  /// video to'liq ekranda panellar ustida turishi kutilgan xatti-harakat.
  static Future<void> applyFullscreen() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }
}
