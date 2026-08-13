import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:riya_play/utils/app_logger.dart';

/// Short-lived JSON cache for home-screen content.
///
/// Only posters were cached before, so every cold start showed empty
/// sections until the network answered — and showed nothing at all offline.
/// This keeps the last successful payload for a few minutes so the screen
/// can paint immediately and then refresh in the background.
///
/// Deliberately short-lived: this is a "don't stare at a spinner" cache, not
/// an offline library. Anything the user must see fresh (favourites state,
/// playback position) is not cached here.
class CacheService {
  static const String bannersKey = 'cached_banners';
  static const String recommendedKey = 'cached_recommended';
  static const String genresKey = 'cached_genres';
  static const String categoriesKey = 'cached_categories';
  static const String latestViewedKey = 'cached_latest_viewed';

  static const Duration _ttl = Duration(minutes: 5);

  /// Returns the stored payload, or null when absent, expired or unreadable.
  /// Expired entries are dropped on read so stale data can't pile up.
  static Future<T?> get<T>(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null) return null;

      final decoded = json.decode(raw);
      if (decoded is! Map) return null;

      final storedAt = decoded['timestamp'] as int?;
      if (storedAt == null || !_isFresh(storedAt)) {
        await prefs.remove(key);
        return null;
      }
      final data = decoded['data'];
      return data is T ? data : null;
    } catch (e) {
      appLogger.d('Keshni o‘qishda xato ($key): $e');
      return null;
    }
  }

  static Future<void> put(String key, Object? data) async {
    if (data == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        json.encode({
          'data': data,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (e) {
      // Kesh — qulaylik, majburiyat emas. Yozib bo'lmasa jim o'tamiz.
      appLogger.d('Keshga yozishda xato ($key): $e');
    }
  }

  /// Per-category film lists share one namespace so they can be cleared
  /// together with everything else.
  static String categoryFilmsKey(int categoryId) =>
      'cached_category_films_$categoryId';

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('cached_'));
      for (final key in keys.toList()) {
        await prefs.remove(key);
      }
    } catch (e) {
      appLogger.d('Keshni tozalashda xato: $e');
    }
  }

  static bool _isFresh(int storedAtMillis) {
    final age = DateTime.now().millisecondsSinceEpoch - storedAtMillis;
    return age >= 0 && age < _ttl.inMilliseconds;
  }
}
