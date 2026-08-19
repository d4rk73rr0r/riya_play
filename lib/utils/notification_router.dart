import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:riya_play/screens/film_screen.dart';
import 'package:riya_play/services/notification_service.dart';
import 'package:riya_play/utils/navigation.dart';

/// Ilova navigatoriga bildirishnomadan kirish uchun kalit.
///
/// Bildirishnoma bosilganda `BuildContext` yo'q — bosish ilovadan tashqarida
/// sodir bo'ladi, ba'zan ilova umuman yopiq bo'lganda. Shu sababli marshrut
/// global kalit orqali ochiladi.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Bildirishnoma bosilishini film sahifasiga aylantiradi.
///
/// Ikki holat bor va ikkalasi ham bir joyga keladi:
///
/// * **Ilova ochiq** — plagin `onDidReceiveNotificationResponse` ni chaqiradi.
/// * **Ilova yopiq** — bosish ilovani ishga tushiradi, payload esa
///   `NotificationService.pendingLaunchFilmId()` dan olinadi.
///
/// Ikkinchi holatda navigator hali qurilmagan bo'ladi, shuning uchun film id
/// [_pendingFilmId] da kutib turadi va `MainScreen` tayyor bo'lgach ochiladi.
/// Kutish `MainScreen` ga bog'langani muhim: tizimga kirmagan foydalanuvchida
/// film sahifasi baribir yuklanmaydi (u tokensiz ishlamaydi), shuning uchun
/// `AuthScreen` ustiga hech narsa ochilmaydi.
class NotificationRouter {
  NotificationRouter._();

  static int? _pendingFilmId;
  static bool _canNavigate = false;

  /// Bildirishnoma plaginining qayta chaqiruvi. Ilova jarayoni tirik bo'lganda
  /// ishlaydi.
  static void handleResponse(NotificationResponse response) {
    final filmId = NotificationService.filmIdFromPayload(response.payload);
    if (filmId != null) open(filmId);
  }

  static void open(int filmId) {
    _pendingFilmId = filmId;
    _flush();
  }

  /// `MainScreen` birinchi kadrdan keyin chaqiradi.
  static void markNavigatorReady() {
    _canNavigate = true;
    _flush();
  }

  /// `MainScreen` yopilganda (masalan, chiqishdan keyin) — kutayotgan id
  /// ataylab saqlanmaydi: chiqqan foydalanuvchiga film ochish mantiqsiz.
  static void markNavigatorGone() {
    _canNavigate = false;
    _pendingFilmId = null;
  }

  static void _flush() {
    if (!_canNavigate) return;
    final filmId = _pendingFilmId;
    if (filmId == null) return;

    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;

    _pendingFilmId = null;
    navigator.push(createSlideRoute(FilmScreen(filmId: filmId)));
  }
}
