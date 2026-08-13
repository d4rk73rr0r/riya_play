import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
