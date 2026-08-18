import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:riya_play/utils/app_logger.dart';

/// Muqovalar setkasining zichligi: qatorda nechta karta ko'rinadi.
///
/// Foydalanuvchi Profil bo'limidan tanlaydi: `2` — kattaroq muqovalar,
/// `3` — kichikroq, lekin ekranga ko'proq sig'adi. Tanlov
/// `SharedPreferences` da `grid_columns` kaliti ostida saqlanadi va bosh
/// sahifadagi gorizontal qatorlarga, Katalog hamda Sevimlilar setkalariga
/// birdek qo'llanadi — shuning uchun qiymat bitta joyda turadi.
class GridDensityProvider extends ChangeNotifier {
  static const String _prefsKey = 'grid_columns';

  /// Ruxsat etilgan qiymatlar. Ikkitadan kam bo'lsa muqova ekranga sig'maydi,
  /// uchtadan ko'p bo'lsa nomlar o'qib bo'lmas darajada kichrayadi.
  static const List<int> allowedColumns = [2, 3];
  static const int defaultColumns = 2;

  int _columns = defaultColumns;

  int get columns => _columns;

  /// Setka nomi: "2x2" / "3x3" — Profil bo'limida ko'rsatiladi.
  String get label => '${_columns}x$_columns';

  /// Saqlangan tanlovni o'qiydi. `runApp` dan oldin chaqiriladi, aks holda
  /// birinchi kadr 2 ustunda chizilib, keyin 3 ga sakraydi.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsKey);
      if (saved != null && allowedColumns.contains(saved)) {
        _columns = saved;
      }
    } catch (e) {
      appLogger.d('Setka zichligini o‘qishda xato: $e');
    }
  }

  Future<void> setColumns(int value) async {
    if (!allowedColumns.contains(value) || value == _columns) return;
    _columns = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, value);
    } catch (e) {
      appLogger.d('Setka zichligini saqlashda xato: $e');
    }
  }
}
