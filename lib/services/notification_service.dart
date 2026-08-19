import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:riya_play/utils/app_logger.dart';

/// Tizim bildirishnomalari ustidagi yagona qatlam.
///
/// Ikki xil izolyatda ishlatiladi: ilovaning asosiy izolyati va
/// `android_alarm_manager_plus` uyg'otadigan fon izolyati (qarang:
/// `new_content_scheduler.dart`). Ikkalasi ham [init] ni chaqiradi — plagin
/// obyekti izolyatlar orasida bo'lishilmaydi, shuning uchun har birida
/// alohida sozlanishi shart. [_ready] shu sababli izolyatga xos.
class NotificationService {
  NotificationService._();

  /// Kanal identifikatori. O'zgartirilsa Android eski kanalni saqlab qoladi va
  /// foydalanuvchi sozlamalari (ovoz, muhimlik) yangisiga ko'chmaydi.
  static const String channelId = 'riyaplay_new_content';
  static const String channelName = 'Yangi kontent';
  static const String channelDescription =
      "Katalogga yangi film yoki serial qo'shilganda xabar beradi";

  /// Bittadan ortiq bildirishnoma bir guruhga yig'iladi, aks holda birdaniga
  /// bir nechta yangi film chiqqanda panel to'lib ketadi.
  static const String _groupKey = 'uz.mrlg.riyaplay.NEW_CONTENT';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _ready = false;

  /// Plaginni shu izolyatda sozlaydi va kanalni yaratadi.
  ///
  /// [onTap] faqat ilova jarayoni tirik bo'lganda chaqiriladi. Ilova
  /// o'ldirilgan bo'lsa, bosish ilovani qaytadan ishga tushiradi va payload
  /// [pendingLaunchFilmId] orqali olinadi.
  static Future<void> init({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    if (_ready) return;

    await _plugin.initialize(
      settings: const InitializationSettings(
        // Holat qatoridagi ikonka — oq siluet. `launcher_icon` bu yerda
        // yaramaydi: Android uning ranglarini tashlab, to'rtburchak dog'
        // chizadi.
        android: AndroidInitializationSettings('ic_notification'),
      ),
      onDidReceiveNotificationResponse: onTap,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            channelName,
            description: channelDescription,
            importance: Importance.high,
          ),
        );

    _ready = true;
  }

  /// Android 13+ da bildirishnomalar uchun ruxsat so'raydi.
  ///
  /// Eski versiyalarda plagin `null` qaytaradi — ruxsat manifestdan beriladi,
  /// so'rashning hojati yo'q.
  static Future<bool> requestPermission() async {
    final granted =
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission();
    return granted ?? true;
  }

  /// Ilova bildirishnoma bosilishi tufayli ochilgan bo'lsa — o'sha filmning
  /// id'si, aks holda `null`.
  static Future<int?> pendingLaunchFilmId() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return filmIdFromPayload(details.notificationResponse?.payload);
  }

  /// Payload — film id'sining matn ko'rinishi. Boshqa formatga o'tilsa shu
  /// yagona joy o'zgaradi.
  static String payloadForFilm(int filmId) => filmId.toString();

  static int? filmIdFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    return int.tryParse(payload);
  }

  /// Bitta yangi kontent haqidagi bildirishnoma.
  ///
  /// [id] sifatida film id'si ishlatiladi: shu bilan bir film uchun ikkinchi
  /// bildirishnoma eskisini almashtiradi, ko'paytirmaydi.
  static Future<void> showNewContent({
    required int filmId,
    required String title,
    required String body,
    String? posterUrl,
  }) async {
    final poster = await _downloadPoster(posterUrl);

    final details = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: _groupKey,
      // Uzun nom bir qatorga sig'maydi — yoyilganda to'liq ko'rinsin.
      styleInformation: BigTextStyleInformation(body, contentTitle: title),
      largeIcon: poster,
    );

    await _plugin.show(
      id: filmId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(android: details),
      payload: payloadForFilm(filmId),
    );
  }

  /// Poster bildirishnomaning o'ng tomonidagi kichik rasm bo'ladi.
  ///
  /// Muvaffaqiyatsizlik jim o'tadi: rasmsiz bildirishnoma ham to'liq ishlaydi,
  /// tarmoq xatosi tufayli xabarning o'zini yo'qotish esa mantiqsiz.
  static Future<ByteArrayAndroidBitmap?> _downloadPoster(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse(url),
            // CDN ba'zi chekka nuqtalari Dart'ning standart agentini 403
            // qiladi — ilovaning qolgan qismi bilan bir xil agent yuboriladi.
            headers: const {'User-Agent': 'okhttp/4.9.2'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      return ByteArrayAndroidBitmap(Uint8List.fromList(response.bodyBytes));
    } catch (e) {
      appLogger.d('Bildirishnoma posteri yuklanmadi: $e');
      return null;
    }
  }
}
