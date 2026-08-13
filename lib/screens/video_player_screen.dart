import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player/better_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:http/http.dart' as http;
import 'package:riya_play/utils/video_helpers.dart'; // Yordamchi funksiyalarni import qilish
import 'package:riya_play/utils/app_logger.dart';
import 'package:riya_play/services/api_service.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String title;
  final bool liveStream;
  final bool autoPlay;
  final bool fullScreenByDefault;
  final List<DeviceOrientation>? deviceOrientationsOnFullScreen;
  final List<DeviceOrientation>? deviceOrientationsAfterFullScreen;
  final bool? autoDetectFullscreenDeviceOrientation;
  final BetterPlayerControlsConfiguration? controlsConfiguration;
  final BetterPlayerNotificationConfiguration? notificationConfiguration;

  /// Series id of what is playing. When set, the stop position is mirrored
  /// to the server, so the same episode resumes on any device the account
  /// is signed in on. Null for TV channels and anything not in the series
  /// catalogue — those keep the local-only position.
  final int? episodeId;

  /// Where to start from. The caller resolves this (server position plus the
  /// "Davom ettirish?" prompt) and the player just seeks — previously this
  /// parameter was accepted and silently dropped, and the player looked the
  /// position up itself from local storage.
  final Duration? startAt;

  const VideoPlayerScreen({
    required this.videoUrl,
    required this.title,
    this.episodeId,
    this.liveStream = false,
    this.autoPlay = true,
    this.fullScreenByDefault = false,
    this.deviceOrientationsOnFullScreen,
    this.deviceOrientationsAfterFullScreen,
    this.autoDetectFullscreenDeviceOrientation,
    this.controlsConfiguration,
    this.notificationConfiguration,
    this.startAt,
    super.key,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  BetterPlayerController? _betterPlayerController;
  Map<String, String> _resolutions = {};
  bool _isPlayerInitialized = false;
  bool _isDisposed = false;
  final _logger = appLogger;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _initializePlayer();
  }

  Future<Map<String, String>> _fetchResolutions(String m3u8Url) async {
    try {
      _logger.d("Sifatlarni olish: $m3u8Url");
      final response = await http
          .get(Uri.parse(m3u8Url))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
      _logger.d("Javob holati: ${response.statusCode}");
      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        Map<String, String> resolutions = {};
        String? currentResolution;

        for (var line in lines) {
          if (line.contains('#EXT-X-STREAM-INF')) {
            final resolutionMatch = RegExp(
              r'RESOLUTION=(\d+x\d+)',
            ).firstMatch(line);
            if (resolutionMatch != null) {
              currentResolution = resolutionMatch.group(1);
            }
          } else if (line.trim().isNotEmpty &&
              currentResolution != null &&
              !line.startsWith('#')) {
            resolutions[currentResolution] = line.trim();
            currentResolution = null;
          }
        }
        return resolutions.isEmpty ? {"Auto": m3u8Url} : resolutions;
      }
      return {"Auto": m3u8Url};
    } catch (e) {
      _logger.e("Sifatlarni olishda xato: $e");
      return {"Auto": m3u8Url};
    }
  }

  Future<void> _savePlaybackPosition() async {
    if (!mounted ||
        _betterPlayerController == null ||
        !_isPlayerInitialized ||
        _isDisposed) {
      _logger.d(
        "Playback position saqlanmadi: controller yoki state mavjud emas",
      );
      return;
    }
    try {
      final position = await safeGetPosition(_betterPlayerController);
      final episodeId = widget.episodeId;
      // Server — yagona manba. Bir necha soniyalik ko'rish yuborilmaydi:
      // bu tasodifan ochib yopish bo'lishi mumkin.
      if (position != null && position.inSeconds > 5 && episodeId != null) {
        final ok = await ApiService.updateWatchProgress(
          episodeId,
          position.inSeconds,
        );
        _logger.d(
          ok
              ? "Pozitsiya serverga yozildi: ${position.inSeconds}s"
              : "Pozitsiyani serverga yozib bo‘lmadi",
        );
      }
    } catch (e) {
      _logger.e("Playback position saqlashda xato: $e");
    }
  }

  /// Seeks to the position the caller resolved from the server. Nothing is
  /// read from local storage any more.
  Future<void> _restorePlaybackPosition() async {
    final startAt = widget.startAt;
    if (widget.liveStream ||
        startAt == null ||
        startAt.inSeconds <= 0 ||
        !_isPlayerInitialized ||
        _betterPlayerController == null ||
        _isDisposed) {
      return;
    }
    try {
      await _betterPlayerController!.seekTo(startAt);
      _logger.d("Pozitsiya tiklandi: ${startAt.inSeconds} sekund");
    } catch (e) {
      _logger.e("Pozitsiyani tiklashda xato: $e");
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) async {
    if (!mounted) return;
    if (event.betterPlayerEventType == BetterPlayerEventType.initialized) {
      setState(() => _isPlayerInitialized = true);
      if (widget.autoPlay && !widget.liveStream) {
        await safePlay(_betterPlayerController);
        _logger.d("Video avtomatik o‘ynatildi");
      }
      await _restorePlaybackPosition();
    } else if (event.betterPlayerEventType ==
        BetterPlayerEventType.changedTrack) {
      _logger.d("Sifat o‘zgartirildi: ${event.parameters}");
    } else if (event.betterPlayerEventType == BetterPlayerEventType.play) {
      try {
        await WakelockPlus.enable();
        _logger.d("Wakelock yoqildi");
      } catch (e) {
        _logger.e("Wakelock yoqishda xato: $e");
      }
    } else if (event.betterPlayerEventType == BetterPlayerEventType.pause) {
      await _savePlaybackPosition();
      try {
        await WakelockPlus.disable();
        _logger.d("Wakelock o‘chirildi");
      } catch (e) {
        _logger.e("Wakelock o‘chirishda xato: $e");
      }
    }
  }

  void _onFullscreenEvent(BetterPlayerEvent event) async {
    if (!mounted) return;
    if (event.betterPlayerEventType == BetterPlayerEventType.openFullscreen) {
      try {
        await SystemChrome.setPreferredOrientations(
          widget.deviceOrientationsOnFullScreen ??
              [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ],
        );
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _logger.d("To‘liq ekran rejimi (landshaft)");
      } catch (e) {
        _logger.e("To‘liq ekran sozlamasida xato: $e");
      }
    } else if (event.betterPlayerEventType ==
        BetterPlayerEventType.hideFullscreen) {
      try {
        await SystemChrome.setPreferredOrientations(
          widget.deviceOrientationsAfterFullScreen ??
              [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
        );
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _logger.d("To‘liq ekrandan chiqildi (portret)");
      } catch (e) {
        _logger.e("To‘liq ekrandan chiqishda xato: $e");
      }
    }
  }

  Future<void> _initializePlayer() async {
    if (!mounted || _isPlayerInitialized || _isDisposed) {
      _logger.d("Player allaqachon ishga tushirilgan yoki yopilgan");
      return;
    }

    _logger.d("Player ishga tushirilmoqda: ${widget.videoUrl}");
    if (widget.videoUrl.endsWith('.m3u8')) {
      _resolutions = await _fetchResolutions(widget.videoUrl);
      _logger.d("Mavjud sifatlar: $_resolutions");
    } else {
      _resolutions = {"Auto": widget.videoUrl};
    }

    BetterPlayerDataSource dataSource = BetterPlayerDataSource(
      BetterPlayerDataSourceType.network,
      widget.videoUrl,
      liveStream: widget.liveStream,
      resolutions: _resolutions,
      notificationConfiguration:
          widget.notificationConfiguration ??
          const BetterPlayerNotificationConfiguration(showNotification: false),
    );

    _betterPlayerController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: widget.autoPlay,
        fit: BoxFit.contain,
        fullScreenByDefault: widget.fullScreenByDefault,
        handleLifecycle: true,
        autoDispose: false, // safeDispose orqali boshqaramiz
        autoDetectFullscreenDeviceOrientation:
            widget.autoDetectFullscreenDeviceOrientation ?? false,
        controlsConfiguration:
            widget.controlsConfiguration ??
            const BetterPlayerControlsConfiguration(
              enableFullscreen: true,
              enablePlayPause: true,
              enableMute: true,
              enableProgressText: true,
              enableSkips: true,
              enableQualities: true,
              enableAudioTracks: true,
            ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, color: Colors.red, size: 40),
                Text(
                  "Video xatosi: ${errorMessage ?? 'Noma’lum xato'}",
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                ElevatedButton(
                  onPressed: _initializePlayer,
                  child: const Text("Qayta urinish"),
                ),
              ],
            ),
          );
        },
      ),
      betterPlayerDataSource: dataSource,
    );

    if (!mounted) return;

    setState(() {
      _isPlayerInitialized = true;
    });

    // Event listener’lar qo‘shish
    _betterPlayerController?.addEventsListener(_onPlayerEvent);
    _betterPlayerController?.addEventsListener(_onFullscreenEvent);

    // Eng yuqori sifatni tanlash
    if (_resolutions.isNotEmpty && _resolutions.length > 1 && mounted) {
      final highestResolution = _resolutions.keys.reduce((a, b) {
        try {
          final aRes = int.parse(a.split('x')[1]);
          final bRes = int.parse(b.split('x')[1]);
          return aRes > bRes ? a : b;
        } catch (e) {
          _logger.e("Sifat parsing xatosi: $e");
          return a;
        }
      });
      await safeSetResolution(
        _betterPlayerController,
        _resolutions[highestResolution],
      );
    }
  }

  @override
  void dispose() {
    if (!_isDisposed &&
        _betterPlayerController != null &&
        _isPlayerInitialized) {
      _isDisposed = true;
      try {
        // Playback pozitsiyasini saqlash
        _savePlaybackPosition().catchError((e) {
          _logger.e("Playback position saqlashda xato: $e");
        });

        // Kontrollerni xavfsiz yopish
        safeDispose(
              _betterPlayerController,
              onPlayerEvent: _onPlayerEvent,
              onFullscreenEvent: _onFullscreenEvent,
            )
            .then((_) {
              _logger.d("BetterPlayerController muvaffaqiyatli yopildi");
            })
            .catchError((e) {
              _logger.e("safeDispose xatosi: $e");
            });

        _betterPlayerController = null;
        _isPlayerInitialized = false;
      } catch (e, stackTrace) {
        _logger.e("dispose xatosi: $e\nStackTrace: $stackTrace");
      }
    }

    // Wakelock va tizim sozlamalarini tozalash
    try {
      WakelockPlus.disable().then((_) => _logger.d("Wakelock o‘chirildi"));
      // Pleer ochilishidan oldingi holatga qaytarish — edgeToEdge'da qolib
      // ketsa, qolgan ekranlar (masalan FilmScreen) MediaQuery.size'ni
      // butun ekran balandligi deb hisoblab, joylashuvni pastga suradi.
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } catch (e) {
      _logger.e("Tizim sozlamalarini tozalashda xato: $e");
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body:
          _betterPlayerController == null || !_isPlayerInitialized
              ? const Center(child: CircularProgressIndicator())
              : BetterPlayer(controller: _betterPlayerController!),
    );
  }
}
