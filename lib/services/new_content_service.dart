import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/notification_service.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Katalogda yangi kontent paydo bo'lganini aniqlaydi va bildirishnoma
/// ko'rsatadi.
///
/// Yagona mezon — `publish_time`. Ro'yxat `-updated_at` bo'yicha kelgani uchun
/// birinchi yozuv eng yangi *nashr* bo'lishi shart emas: eski filmga yangi
/// qism qo'shilsa ham u yuqoriga chiqadi, lekin `publish_time` o'zgarmaydi.
/// Shuning uchun butun sahifa ko'rib chiqiladi va oxirgi ko'rilgan
/// `publish_time` dan kattalari yangi hisoblanadi.
class NewContentService {
  NewContentService._();

  /// Oxirgi ko'rilgan eng katta `publish_time` (soniyalarda, server vaqti).
  static const String prefsLastPublishTime = 'new_content_last_publish_time';

  /// Bildirishnomalar yoqilganmi. Profil ekranidagi kalit shu qiymatni
  /// o'zgartiradi; `null` bo'lsa yoqilgan deb hisoblanadi.
  static const String prefsEnabled = 'new_content_notifications_enabled';

  /// Bir tekshiruvda ko'pi bilan shuncha bildirishnoma chiqadi.
  ///
  /// Katalogga birdaniga 20 ta film qo'shilsa (bu odatiy hol), har biriga
  /// alohida xabar berish panelni to'ldirib yuboradi.
  static const int _maxNotificationsPerCheck = 5;

  static const Map<int, String> _typeNames = {
    1: 'Serial',
    2: 'Film',
    5: 'Multfilm',
  };

  /// Bir marta tekshiradi. Nechta bildirishnoma ko'rsatilgani qaytadi.
  ///
  /// Hech qachon istisno tashlamaydi — uni chaqiradigan ikkala joy ham
  /// (taymer va signal izolyati) xatoni ko'rsatadigan ekranga ega emas.
  static Future<int> checkOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Qiymatni boshqa izolyat yozgan bo'lishi mumkin: `getInstance` ochilish
      // paytidagi nusxani qaytaradi, `reload` esa diskdagi haqiqiy holatni.
      await prefs.reload();

      if (prefs.getBool(prefsEnabled) == false) return 0;

      final films = await ApiService.getLatestPublished();
      if (films.isEmpty) return 0;

      final published = <Map<String, dynamic>>[];
      for (final film in films) {
        if (film is! Map) continue;
        if (film['status'] != 1) continue;
        final publishTime = _asInt(film['publish_time']);
        final id = _asInt(film['id']);
        if (publishTime == null || id == null) continue;
        published.add({...film.cast<String, dynamic>(), 'id': id});
      }
      if (published.isEmpty) return 0;

      final newest = published
          .map((f) => _asInt(f['publish_time'])!)
          .reduce((a, b) => a > b ? a : b);

      final lastSeen = prefs.getInt(prefsLastPublishTime) ?? 0;
      if (lastSeen == 0) {
        // Birinchi ishga tushish: hozirgi holat "ko'rilgan" deb belgilanadi.
        // Aks holda o'rnatilgan zahoti butun sahifa yangi ko'rinib, 5 ta
        // bildirishnoma chiqib ketardi.
        await prefs.setInt(prefsLastPublishTime, newest);
        return 0;
      }

      if (newest <= lastSeen) return 0;

      final fresh =
          published
              .where((f) => _asInt(f['publish_time'])! > lastSeen)
              .toList()
            ..sort(
              (a, b) => _asInt(
                b['publish_time'],
              )!.compareTo(_asInt(a['publish_time'])!),
            );

      var shown = 0;
      for (final film in fresh.take(_maxNotificationsPerCheck)) {
        await NotificationService.showNewContent(
          filmId: film['id'] as int,
          title: 'Yangi kontent mavjud',
          body: describe(film),
          posterUrl: posterUrl(film),
        );
        shown++;
      }

      // Ko'rsatilmagan yozuvlar ham "ko'rilgan" deb belgilanadi: ular baribir
      // eskirib boradi va keyingi tekshiruvda qayta chiqishi shart emas.
      await prefs.setInt(prefsLastPublishTime, newest);

      appLogger.d('Yangi kontent: ${fresh.length} ta, $shown ta bildirishnoma');
      return shown;
    } catch (e) {
      appLogger.d('Yangi kontent tekshiruvi xatosi: $e');
      return 0;
    }
  }

  /// Bildirishnoma matni: "Karantindagi qiz (2026) · Film · Triller, Dramma".
  static String describe(Map<String, dynamic> film) {
    final parts = <String>[];

    final name = _name(film);
    final year = _asInt(film['year']);
    parts.add(year == null ? name : '$name ($year)');

    final type = _typeNames[_asInt(film['type'])];
    if (type != null) parts.add(type);

    final genres = film['genres'];
    if (genres is List) {
      final names = genres
          .whereType<Map>()
          .map((g) => (g['name_uz'] ?? g['name_ru'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .take(2)
          .join(', ');
      if (names.isNotEmpty) parts.add(names);
    }

    return parts.join(' · ');
  }

  static String _name(Map<String, dynamic> film) {
    for (final key in ['name_uz', 'name_ru', 'name_en']) {
      final value = film[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return 'Yangi kontent';
  }

  /// Bildirishnomadagi kichik rasm uchun `small` (320 px) varianti — panelga
  /// shundan kattasi baribir sig'maydi.
  static String? posterUrl(Map<String, dynamic> film) {
    final files = film['files'];
    if (files is! List || files.isEmpty) return null;
    final first = files.first;
    if (first is! Map) return null;
    final thumbnails = first['thumbnails'];
    if (thumbnails is! Map) return null;
    final small = thumbnails['small'] ?? thumbnails['icon'];
    if (small is! Map) return null;
    final src = small['src'];
    return src is String && src.isNotEmpty ? src : null;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}
