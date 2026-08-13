import 'package:android_intent_plus/android_intent.dart';
import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:riya_play/screens/download_screen.dart';
import 'package:riya_play/screens/video_player_screen.dart';
import 'package:riya_play/services/api_service.dart';
import 'package:riya_play/services/error_handler.dart';
import 'package:riya_play/utils/latest_viewed.dart';
import 'package:riya_play/utils/navigation.dart';

/// Starts playback straight from a "Ko'rishni davom ettirish" card.
///
/// Those cards used to open the film page, which meant the user had to find
/// the episode again and press play — the one thing a continue-watching row
/// exists to avoid. The stream URL and the stop position both come from the
/// episode endpoint, so one call is enough to resume exactly where they were.
class VideoLauncher {
  static Future<void> playFromLatestViewed(
    BuildContext context,
    dynamic item,
  ) async {
    final episodeId = latestViewedEpisodeId(item);
    if (episodeId == null) {
      _showError(context, "Kontent ID topilmadi");
      return;
    }

    final title =
        item['film']?['name_uz'] ??
        item['name_uz'] ??
        item['film']?['name_ru'] ??
        "Noma'lum";

    _showLoading(context);
    try {
      final episode = await ApiService.getEpisodeDetails(episodeId);
      if (context.mounted) Navigator.pop(context); // Kutish oynasi
      if (!context.mounted) return;

      final tracks = episode['track'] as List<dynamic>? ?? [];
      final url = tracks.isNotEmpty ? (tracks[0]['stream_url'] ?? '') : '';
      if (url is! String || url.isEmpty) {
        _showError(context, "Video URL topilmadi");
        return;
      }

      final serverSeconds = (episode['second']?['time'] as int?) ?? 0;

      await play(
        context,
        url: url,
        title: title,
        episodeId: episodeId,
        resumeSeconds: serverSeconds,
      );
    } catch (e) {
      if (context.mounted) Navigator.pop(context); // Kutish oynasi
      if (context.mounted) {
        _showError(context, ApiErrorHandler.handle(e).userMessage);
      }
    }
  }

  /// Film sahifasi va epizodlar ro'yxati uchun: serverdagi pozitsiyani
  /// so'raydi, "Davom ettirish?" va "Pleerni tanlang" dialoglarini
  /// ko'rsatadi, keyin ichki pleer / tashqi pleer / yuklab olishga yo'naltiradi.
  ///
  /// [url] allaqachon tekshirilgan bo'lishi kerak — URL ni yangilash mantig'i
  /// ekranga xos (film ma'lumotini qayta o'qish), shuning uchun bu yerda emas.
  /// [downloadTitle] fayl nomi uchun; pleer sarlavhasidan farq qiladi.
  static Future<void> playWithChooser(
    BuildContext context, {
    required String url,
    required String title,
    String? downloadTitle,
    int? episodeId,
  }) async {
    final savedPosition =
        episodeId == null ? 0 : await ApiService.getWatchedSeconds(episodeId);
    if (!context.mounted) return;

    bool? resumePlayback;
    if (savedPosition > 0) {
      resumePlayback = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text("Davom ettirish"),
              content: Text(
                "'$title' ni ${formatWatchedTime(savedPosition)} dan davom ettirishni xohlaysizmi?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("Yo‘q"),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Ha"),
                ),
              ],
            ),
      );
      if (resumePlayback == null || !context.mounted) return;
    }

    final selectedPlayer = await showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Pleerni tanlang"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_circle_filled),
                    title: const Text("Ichki pleer: Better Player"),
                    onTap: () => Navigator.pop(context, 'better_player'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.video_library),
                    title: const Text("Tashqi pleer bilan ochish"),
                    onTap: () => Navigator.pop(context, 'external'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.download),
                    title: const Text("Yuklab olish"),
                    onTap: () => Navigator.pop(context, 'download'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Bekor qilish"),
              ),
            ],
          ),
    );

    if (selectedPlayer == null || !context.mounted) return;

    switch (selectedPlayer) {
      case 'download':
        Navigator.push(
          context,
          createSlideRoute(
            DownloadScreen(videoUrl: url, title: downloadTitle ?? title),
          ),
        );
        return;
      case 'external':
        try {
          await AndroidIntent(
            action: 'action_view',
            data: url,
            type: 'video/*',
          ).launch();
        } catch (e) {
          if (context.mounted) {
            _showError(context, "Tashqi pleerni ochishda xato: $e");
          }
        }
        return;
      default:
        await _push(
          context,
          url: url,
          title: title,
          episodeId: episodeId,
          startAt:
              resumePlayback == true
                  ? Duration(seconds: savedPosition)
                  : Duration.zero,
        );
    }
  }

  /// Opens the player, asking first whether to resume when there is a
  /// position to resume from.
  static Future<void> play(
    BuildContext context, {
    required String url,
    required String title,
    required int? episodeId,
    int resumeSeconds = 0,
  }) async {
    HapticFeedback.lightImpact();

    var startAt = Duration.zero;
    if (resumeSeconds > 0) {
      final resume = await _askResume(context, resumeSeconds);
      if (resume == null || !context.mounted) return; // Bekor qilindi
      if (resume) startAt = Duration(seconds: resumeSeconds);
    }
    if (!context.mounted) return;

    await _push(
      context,
      url: url,
      title: title,
      episodeId: episodeId,
      startAt: startAt,
    );
  }

  /// Pleerni ochadi va chiqishdagi pozitsiya yozuvi tugashini kutadi.
  static Future<void> _push(
    BuildContext context, {
    required String url,
    required String title,
    required int? episodeId,
    required Duration startAt,
  }) async {
    VideoPlayerScreen.pendingPositionFlush = null;
    await Navigator.push(
      context,
      createSlideRoute(
        VideoPlayerScreen(
          videoUrl: url,
          title: title,
          episodeId: episodeId,
          liveStream: false,
          autoPlay: true,
          startAt: startAt,
          fullScreenByDefault: false,
          deviceOrientationsOnFullScreen: const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          deviceOrientationsAfterFullScreen: const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ],
          autoDetectFullscreenDeviceOrientation: false,
          controlsConfiguration: const BetterPlayerControlsConfiguration(
            enableFullscreen: true,
            enablePlayPause: true,
            enableMute: true,
            enableProgressText: true,
            enableSkips: true,
            enableQualities: true,
            enableAudioTracks: true,
          ),
          notificationConfiguration:
              const BetterPlayerNotificationConfiguration(
                showNotification: false,
              ),
        ),
      ),
    );

    await awaitPositionFlush();
  }

  /// Chiqishdagi pozitsiya yozuvi serverga yetib borsin — ro'yxatni qayta
  /// o'qiydigan ekran shundan keyingina so'rov yuboradi.
  ///
  /// Pleerning `dispose` i chiqish animatsiyasi tugagandan keyin ishlaydi,
  /// ya'ni `Navigator.push` future'i ham, `RouteAware.didPopNext` ham undan
  /// oldinroq ishga tushadi — shuning uchun yozuv boshlanishini qisqa vaqt
  /// kutib turamiz. Yozuv umuman bo'lmasa (5 soniyadan kam ko'rilgan bo'lsa)
  /// kutish shu qadar bilan tugaydi.
  static Future<void> awaitPositionFlush() async {
    for (var i = 0; i < 8; i++) {
      if (VideoPlayerScreen.pendingPositionFlush != null) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    try {
      await VideoPlayerScreen.pendingPositionFlush;
    } catch (_) {
    } finally {
      VideoPlayerScreen.pendingPositionFlush = null;
    }
  }

  static Future<bool?> _askResume(BuildContext context, int seconds) {
    return showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Davom ettirish"),
            content: Text(
              "${formatWatchedTime(seconds)} dan davom ettirishni xohlaysizmi?",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text("Boshidan"),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text("Davom ettirish"),
              ),
            ],
          ),
    );
  }

  static void _showLoading(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Expanded(child: Text("Video tayyorlanmoqda...")),
              ],
            ),
          ),
    );
  }

  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
