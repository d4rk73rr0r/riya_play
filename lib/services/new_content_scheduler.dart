import 'dart:async';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:riya_play/services/new_content_service.dart';
import 'package:riya_play/services/notification_service.dart';
import 'package:riya_play/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Signal izolyatining kirish nuqtasi.
///
/// **Yuqori darajadagi funksiya bo'lishi shart.** `vm:entry-point` bilan
/// belgilangan statik metodni Android chaqira olmaydi: VM `To access
/// 'NewContentScheduler' from native code, it must be annotated` deb xato
/// beradi — metod bilan birga sinfning o'zi ham belgilanishi kerak bo'lardi.
/// Qurilmada tekshirilgan (2026-08-19).
///
/// Bu yerda ilovaning holatidan hech narsa mavjud emas — alohida izolyat,
/// alohida `FlutterEngine`. Shuning uchun bildirishnoma plagini qaytadan
/// sozlanadi.
@pragma('vm:entry-point')
Future<void> newContentAlarmCallback() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Dart tomonida ro'yxatdan o'tadigan plaginlar (`shared_preferences`) fon
  // izolyatida o'z-o'zidan ulanmaydi.
  DartPluginRegistrant.ensureInitialized();
  await NotificationService.init();
  await NewContentService.checkOnce();
}

/// Yangi kontent tekshiruvini har 5 daqiqada ishga tushiradi.
///
/// Ikki yo'l birga ishlatiladi, chunki bittasi yetmaydi:
///
/// * **Taymer** — ilova jarayoni tirik ekan (old planda yoki fonda yaqinda
///   yopilgan bo'lsa) aniq 5 daqiqada bir ishlaydi.
/// * **AlarmManager** — jarayon o'ldirilgandan keyin ham ishlaydi: Android
///   alohida izolyat ochib, [alarmCallback] ni chaqiradi.
///
/// Signal ataylab **noaniq** (`exact: false`): aniq signal Android 14+ da
/// `SCHEDULE_EXACT_ALARM` ruxsatini talab qiladi va uni foydalanuvchidan
/// alohida so'rash kerak bo'ladi. Buning evaziga Doze rejimida tizim
/// signallarni o'zining texnik oynalariga suradi — ya'ni ekran uzoq o'chib
/// yotganda tekshiruv 5 daqiqadan kechroq bo'lishi mumkin. Bu Android
/// cheklovi, kamchilik emas; undan qochishning yagona yo'li server tomonidan
/// push yuborish (FCM) bo'lardi.
class NewContentScheduler {
  NewContentScheduler._();

  static const Duration interval = Duration(minutes: 5);

  /// Signal identifikatori. O'zgartirilsa eski signal tizimda osilib qoladi —
  /// uni avval [stop] bilan bekor qilish kerak.
  static const int _alarmId = 77201;

  static Timer? _timer;
  static bool _started = false;

  /// Foydalanuvchi bildirishnomalarni o'chirib qo'yganmi.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return prefs.getBool(NewContentService.prefsEnabled) ?? true;
  }

  /// Kalitni o'zgartiradi va rejalashtirishni moslashtiradi.
  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NewContentService.prefsEnabled, enabled);
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  /// Tekshiruvni yoqadi. Faqat tizimga kirgan foydalanuvchi uchun chaqiriladi:
  /// bildirishnoma bosilganda ochiladigan film sahifasi tokensiz yuklanmaydi.
  static Future<void> start() async {
    if (_started) return;
    if (!await isEnabled()) return;
    _started = true;

    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => NewContentService.checkOnce());

    // Ilova ochilishida ham bir marta — ilova yopiq turgan vaqtdagi
    // yangiliklar signal kechikkan bo'lsa ham ko'rinadi.
    unawaited(NewContentService.checkOnce());

    try {
      final ready = await AndroidAlarmManager.initialize();
      if (!ready) {
        appLogger.d('AndroidAlarmManager ishga tushmadi');
        return;
      }
      await AndroidAlarmManager.periodic(
        interval,
        _alarmId,
        newContentAlarmCallback,
        // Qurilma qayta yuklangandan keyin signal o'zi tiklanadi.
        rescheduleOnReboot: true,
        // Ekran o'chgan bo'lsa ham qurilmani uyg'otadi.
        wakeup: true,
      );
    } catch (e) {
      // Signal rejalashtirilmasa ham taymer ishlaydi — ilova ochiq ekan
      // bildirishnomalar baribir keladi.
      appLogger.d('Yangi kontent signali rejalashtirilmadi: $e');
    }
  }

  /// Taymerni ham, signalni ham to'xtatadi (chiqish yoki sozlamadan o'chirish).
  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    try {
      await AndroidAlarmManager.cancel(_alarmId);
    } catch (e) {
      appLogger.d('Yangi kontent signali bekor qilinmadi: $e');
    }
  }
}
