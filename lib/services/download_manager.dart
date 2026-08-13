import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:riya_play/services/download_service.dart';
import 'package:riya_play/utils/app_logger.dart';

enum DownloadStatus { queued, running, completed, failed, cancelled }

/// Why the queue is standing still even though items are waiting.
enum QueuePause {
  none,

  /// No usable connection at all.
  network,

  /// There is a connection, but the user asked for Wi-Fi only and this
  /// isn't it.
  wifi,
}

/// One queued or finished video. Mutable because the manager updates it in
/// place and notifies once, rather than rebuilding the whole list per tick.
class DownloadTask {
  final String id;
  final String title;
  final String videoUrl;
  final String? mediaPlaylistUrl;
  final String? qualityLabel;
  final int? bandwidth;

  /// Tier the user asked for ("720p") when the exact variant URL isn't known
  /// yet. Batch-queueing a whole season can't resolve every episode's master
  /// playlist up front — that would be one request per episode before
  /// anything starts — so the choice is carried as a label and resolved when
  /// the episode's turn comes.
  final String? preferredQuality;

  DownloadStatus status = DownloadStatus.queued;
  DownloadStage stage = DownloadStage.downloading;
  DownloadProgress? progress;
  String? savedPath;
  String? error;

  /// Set when the download finished but something about it is worth saying —
  /// currently, tail segments the source never served.
  String? warning;

  bool cancelRequested = false;

  /// Like [cancelRequested], but the partial file is kept and the item goes
  /// back to the queue — used when the connection stops being one the user
  /// allows, mid-transfer.
  bool pauseRequested = false;

  DownloadTask({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.mediaPlaylistUrl,
    this.qualityLabel,
    this.bandwidth,
    this.preferredQuality,
  });

  bool get isPending =>
      status == DownloadStatus.queued || status == DownloadStatus.running;

  bool get isFinished => !isPending;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'videoUrl': videoUrl,
    'mediaPlaylistUrl': mediaPlaylistUrl,
    'qualityLabel': qualityLabel,
    'bandwidth': bandwidth,
    'preferredQuality': preferredQuality,
    'status': status.name,
    'savedPath': savedPath,
    'error': error,
    'warning': warning,
  };

  /// Rebuilds a task from disk. Anything that was mid-flight when the
  /// process died comes back as [DownloadStatus.failed]: the bytes are still
  /// on disk so "Davom ettirish" picks up where it stopped, but the app
  /// doesn't start pulling data on its own the moment it is opened.
  static DownloadTask fromJson(Map<String, dynamic> map) {
    final stored = DownloadStatus.values.firstWhere(
      (s) => s.name == map['status'],
      orElse: () => DownloadStatus.failed,
    );
    final interrupted =
        stored == DownloadStatus.running || stored == DownloadStatus.queued;

    return DownloadTask(
      id: map['id'] as String,
      title: map['title'] as String,
      videoUrl: map['videoUrl'] as String,
      mediaPlaylistUrl: map['mediaPlaylistUrl'] as String?,
      qualityLabel: map['qualityLabel'] as String?,
      bandwidth: map['bandwidth'] as int?,
      preferredQuality: map['preferredQuality'] as String?,
    )
    ..status = interrupted ? DownloadStatus.failed : stored
    ..savedPath = map['savedPath'] as String?
    ..warning = map['warning'] as String?
    ..error =
        interrupted
            ? 'Ilova yopilgani uchun to‘xtadi.'
            : map['error'] as String?;
  }
}

/// Owns every download in the app.
///
/// Downloads used to live inside `DownloadScreen`'s State, so navigating
/// away from that screen disposed it, flipped the cancel flag and threw
/// away a partly-fetched file. Keeping the work in a process-wide singleton
/// means leaving the screen — or browsing the rest of the app — no longer
/// touches it, and several episodes can be lined up in one go.
///
/// Items run one at a time on purpose: segments are buffered in memory and
/// parallel downloads would multiply both that and the bandwidth contention.
class DownloadManager extends ChangeNotifier {
  DownloadManager._();

  static final DownloadManager instance = DownloadManager._();

  final List<DownloadTask> _tasks = [];
  bool _draining = false;
  int _lastNotifiedPercent = -1;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _networkRetryTimer;

  /// Set when the queue stopped for a reason outside the videos themselves —
  /// no connection, or a connection the user doesn't want used.
  QueuePause _pause = QueuePause.none;

  QueuePause get pauseState => _pause;

  bool get isPaused => _pause != QueuePause.none;

  bool _wifiOnly = false;

  /// When on, downloads only run over Wi-Fi (or Ethernet). Mobile data is
  /// left alone — a 500 MB episode is real money on a metered plan.
  bool get wifiOnly => _wifiOnly;

  Future<void> setWifiOnly(bool value) async {
    if (_wifiOnly == value) return;
    _wifiOnly = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_wifiOnlyKey, value);
    } catch (e) {
      appLogger.d('Wi-Fi sozlamasini saqlashda xato: $e');
    }
    if (value) {
      // Cheklov yoqilganda ayni damdagi yuklash ham to'xtashi kerak, aks
      // holda sozlama mobil trafikni to'xtatmagan bo'lardi.
      unawaited(_enforceGateOnActive());
    } else if (_pause == QueuePause.wifi) {
      _retryNow('sozlama o‘zgardi');
    }
  }

  /// Stops the running transfer when the live connection is no longer one
  /// downloads may use. The bytes already fetched stay on disk.
  Future<void> _enforceGateOnActive() async {
    final active = activeTask;
    if (active == null) return;
    if (await _connectionGate() == QueuePause.none) return;
    active.pauseRequested = true;
  }

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  static const String _storageKey = 'download_tasks';
  static const String _wifiOnlyKey = 'download_wifi_only';

  /// Keeping the newest N is enough to answer "what did I download?" without
  /// letting the record grow without bound.
  static const int _maxStoredTasks = 100;

  /// Loads the previously saved queue. Called once from `main()` so the list
  /// is in place before any screen reads it.
  Future<void> restore() async {
    if (_tasks.isNotEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _wifiOnly = prefs.getBool(_wifiOnlyKey) ?? false;
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = json.decode(raw) as List<dynamic>;
      _tasks.addAll(
        decoded.map((e) => DownloadTask.fromJson(e as Map<String, dynamic>)),
      );
      notifyListeners();
    } catch (e) {
      appLogger.d('Yuklashlar ro‘yxatini o‘qishda xato: $e');
    }
  }

  /// Writes the list back after anything that changes it. Deliberately not
  /// called on progress ticks — only on status transitions.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final kept =
          _tasks.length > _maxStoredTasks
              ? _tasks.sublist(_tasks.length - _maxStoredTasks)
              : _tasks;
      await prefs.setString(
        _storageKey,
        json.encode(kept.map((t) => t.toJson()).toList()),
      );
    } catch (e) {
      appLogger.d('Yuklashlar ro‘yxatini saqlashda xato: $e');
    }
  }

  DownloadTask? get activeTask {
    for (final task in _tasks) {
      if (task.status == DownloadStatus.running) return task;
    }
    return null;
  }

  int get pendingCount => _tasks.where((t) => t.isPending).length;

  bool get hasPendingWork => pendingCount > 0;

  /// Adds a video to the queue, or returns the existing entry when the same
  /// video is already queued or running — a second tap shouldn't download
  /// the same episode twice.
  DownloadTask enqueue({
    required String videoUrl,
    required String title,
    String? mediaPlaylistUrl,
    String? qualityLabel,
    int? bandwidth,
    String? preferredQuality,
  }) {
    for (final task in _tasks) {
      if (task.isPending && task.title == title) return task;
    }

    final task = DownloadTask(
      id: '${DateTime.now().microsecondsSinceEpoch}_${_tasks.length}',
      title: title,
      videoUrl: videoUrl,
      mediaPlaylistUrl: mediaPlaylistUrl,
      qualityLabel: qualityLabel ?? preferredQuality,
      bandwidth: bandwidth,
      preferredQuality: preferredQuality,
    );
    _tasks.add(task);
    _watchConnectivity();
    notifyListeners();
    unawaited(_persist());
    unawaited(_drain());
    return task;
  }

  /// True when this exact title already finished downloading, so a
  /// season-wide request can skip it instead of fetching it twice.
  bool isAlreadyDownloaded(String title) {
    for (final task in _tasks) {
      if (task.title == title && task.status == DownloadStatus.completed) {
        return true;
      }
    }
    return false;
  }

  /// Queues a whole batch (a season, typically) in one go, skipping anything
  /// already downloaded or already waiting. Returns how many were added.
  int enqueueAll(
    List<({String videoUrl, String title})> items, {
    String? preferredQuality,
  }) {
    var added = 0;
    for (final item in items) {
      if (isAlreadyDownloaded(item.title)) continue;
      final before = _tasks.length;
      enqueue(
        videoUrl: item.videoUrl,
        title: item.title,
        preferredQuality: preferredQuality,
      );
      if (_tasks.length > before) added++;
    }
    return added;
  }

  /// Restarts the queue by itself once the connection comes back, so a
  /// tunnel or a lift doesn't turn every pending episode into a failure the
  /// user has to retry by hand.
  ///
  /// The connectivity stream alone is not enough. It reports the *type* of
  /// the active network, so walking out of Wi-Fi range and back emits no
  /// event at all — the type never stopped being `wifi` — and the queue sat
  /// idle until something else changed it. It also fires the moment an
  /// interface comes up, which is before DHCP and DNS are necessarily
  /// usable. So the event is treated as a hint to try sooner, while
  /// [_networkRetryTimer] is what actually guarantees recovery.
  void _watchConnectivity() {
    _connectivitySub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) return;
      // Wi-Fi'dan mobil tarmoqqa o'tilgan bo'lishi mumkin — ketayotgan
      // yuklashni ham qayta baholaymiz.
      unawaited(_enforceGateOnActive());
      _retryNow('ulanish hodisasi');
    });
  }

  /// Enters the paused state and starts polling for its end.
  void _beginWait(QueuePause reason) {
    _pause = reason;
    _networkRetryTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _retryNow('taymer'),
    );
  }

  void _endWait() {
    _networkRetryTimer?.cancel();
    _networkRetryTimer = null;
    _pause = QueuePause.none;
  }

  /// Attempts the queue again. If the condition still holds the next check
  /// simply re-enters the paused state and the timer keeps ticking.
  void _retryNow(String source) {
    if (!isPaused) return;
    if (_nextQueued() == null) {
      _endWait();
      notifyListeners();
      return;
    }
    appLogger.d('Navbat qayta urinilmoqda ($source)');
    _pause = QueuePause.none;
    notifyListeners();
    unawaited(_drain());
  }

  /// Whether the current connection is one downloads may use.
  Future<QueuePause> _connectionGate() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online) return QueuePause.network;
      if (!_wifiOnly) return QueuePause.none;
      final unmetered =
          results.contains(ConnectivityResult.wifi) ||
          results.contains(ConnectivityResult.ethernet);
      return unmetered ? QueuePause.none : QueuePause.wifi;
    } catch (e) {
      // Aniqlab bo'lmasa to'sib qo'ymaymiz — yuklash o'zi urinib ko'radi.
      appLogger.d('Ulanish turini aniqlashda xato: $e');
      return QueuePause.none;
    }
  }

  /// Connectivity failures are treated as "try again later" rather than as a
  /// broken download: the queue pauses instead of burning through every
  /// remaining item with the same error.
  static bool _isNetworkError(Object error) {
    // Server javob bergan bo'lsa, bu tarmoq muammosi emas — aloqa tiklanishini
    // kutish hech narsani o'zgartirmaydi.
    if (error is HttpStatusException) return false;
    if (error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException) {
      return true;
    }
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection closed') ||
        text.contains('Connection reset') ||
        text.contains('Software caused connection abort');
  }

  /// Turns an exception into something worth showing a user. Raw messages
  /// carry the whole signed stream URL — pages of noise, and the access
  /// token along with it.
  static String _friendlyError(Object error) {
    if (error is InsufficientStorageException) return error.toString();
    if (error is HttpStatusException) {
      switch (error.statusCode) {
        case 401:
        case 403:
          return 'Havola muddati tugagan. Film sahifasidan qaytadan '
              'yuklashni boshlang — yuklangan qismi saqlanib qoladi.';
        case 404:
        case 410:
          return 'Videoning bir qismi serverda topilmadi (404). '
              'Bu ilova emas, manba tomonidagi muammo.';
        default:
          return 'Server xatosi (HTTP ${error.statusCode}). '
              'Keyinroq urinib ko‘ring.';
      }
    }
    if (_isNetworkError(error)) {
      return 'Internet aloqasi uzildi. Tarmoq tiklangach davom ettiriladi.';
    }
    // ", uri=…" dan keyingi qism — imzolangan manzil; uni ko'rsatmaymiz.
    var text = error.toString().split(', uri=').first.trim();
    if (text.startsWith('Exception: ')) text = text.substring(11);
    return text.length > 200 ? '${text.substring(0, 200)}…' : text;
  }

  /// Stops a running item or drops a queued one. The partial file is
  /// discarded, since an explicit cancel means the user doesn't want it.
  void cancel(String taskId) {
    final task = _byId(taskId);
    if (task == null || task.isFinished) return;

    task.cancelRequested = true;
    if (task.status == DownloadStatus.queued) {
      // Hech qachon boshlanmagan — darhol yopamiz.
      task.status = DownloadStatus.cancelled;
      unawaited(_discard(task));
    }
    // Navbatda kutayotgan yagona vazifa bekor qilinsa, tarmoq kutishini ham
    // to'xtatamiz — aks holda taymer bekorga aylanaveradi.
    if (_nextQueued() == null) _endWait();
    notifyListeners();
    unawaited(_persist());
  }

  /// Re-queues a failed item. The `.part` file and its resume marker are
  /// kept, so this continues instead of starting over.
  void retry(String taskId) {
    final task = _byId(taskId);
    if (task == null || task.isPending) return;

    task.cancelRequested = false;
    task.error = null;
    task.status = DownloadStatus.queued;
    _watchConnectivity();
    notifyListeners();
    unawaited(_persist());
    unawaited(_drain());
  }

  void remove(String taskId) {
    final task = _byId(taskId);
    if (task == null) return;
    if (task.isPending) {
      cancel(taskId);
      return;
    }
    _tasks.remove(task);
    notifyListeners();
    unawaited(_persist());
  }

  void clearFinished() {
    _tasks.removeWhere((task) => task.isFinished);
    notifyListeners();
    unawaited(_persist());
  }

  DownloadTask? _byId(String id) {
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  DownloadTask? _nextQueued() {
    for (final task in _tasks) {
      if (task.status == DownloadStatus.queued) return task;
    }
    return null;
  }

  Future<void> _discard(DownloadTask task) async {
    try {
      await DownloadService.discardPartial(
        task.mediaPlaylistUrl ?? task.videoUrl,
        task.title,
      );
    } catch (e) {
      appLogger.d('Yarim faylni tozalashda xato: $e');
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    var serviceStarted = false;

    try {
      while (true) {
        if (isPaused) break;
        final task = _nextQueued();
        if (task == null) break;

        // Har element oldidan tekshiramiz: navbat o'rtasida foydalanuvchi
        // Wi-Fi'dan mobil tarmoqqa o'tgan bo'lishi mumkin.
        final gate = await _connectionGate();
        if (gate != QueuePause.none) {
          _beginWait(gate);
          notifyListeners();
          break;
        }

        if (!serviceStarted) {
          await DownloadService.startForegroundService(
            task.title,
            'Yuklab olinmoqda...',
          );
          serviceStarted = true;
        }
        await _run(task);
      }
    } finally {
      if (serviceStarted) await DownloadService.stopForegroundService();
      _draining = false;
    }

    // Oxirgi tekshiruv bilan drain tugash payti orasida yangi vazifa
    // qo'shilgan bo'lishi mumkin — u navbatda qolib ketmasin.
    if (!isPaused && _nextQueued() != null) unawaited(_drain());
  }

  Future<void> _run(DownloadTask task) async {
    task.status = DownloadStatus.running;
    task.error = null;
    task.stage = DownloadStage.downloading;
    _lastNotifiedPercent = -1;
    notifyListeners();
    unawaited(_persist());

    try {
      final result = await DownloadService.download(
        videoUrl: task.videoUrl,
        title: task.title,
        mediaPlaylistUrl: task.mediaPlaylistUrl,
        preferredQualityLabel: task.preferredQuality,
        bandwidthHint: task.bandwidth,
        onProgress: (progress) {
          task.progress = progress;
          notifyListeners();
          _pushNotification(task);
        },
        onStage: (stage) {
          task.stage = stage;
          notifyListeners();
          _pushNotification(task, force: true);
        },
        isCancelled: () => task.cancelRequested || task.pauseRequested,
      );
      task.status = DownloadStatus.completed;
      task.savedPath = result.path;
      task.warning =
          result.skippedSegments > 0
              ? 'Manbada oxirgi ${result.skippedSegments} ta qism yo‘q — '
                  'video bir necha soniyaga qisqa.'
              : null;
      _endWait();
    } on DownloadCancelledException {
      if (task.pauseRequested) {
        // Bekor qilish emas — to'xtatib turish: yarim fayl saqlanadi va
        // ruxsat etilgan tarmoq paydo bo'lgach o'sha joydan davom etadi.
        task.pauseRequested = false;
        task.status = DownloadStatus.queued;
        task.progress = null;
        final gate = await _connectionGate();
        _beginWait(gate == QueuePause.none ? QueuePause.wifi : gate);
      } else {
        task.status = DownloadStatus.cancelled;
        await _discard(task);
      }
    } catch (e) {
      // Yarim fayl ataylab saqlanadi: keyingi urinish shu yerdan davom etadi.
      appLogger.e('Yuklab olishda xato (${task.title}): $e');
      if (_isNetworkError(e)) {
        // Video emas, tarmoq aybdor — vazifa navbatda qoladi va aloqa
        // tiklangach o'zi davom etadi.
        _beginWait(QueuePause.network);
        task.status = DownloadStatus.queued;
        task.progress = null;
      } else {
        task.status = DownloadStatus.failed;
      }
      task.error = _friendlyError(e);
    } finally {
      notifyListeners();
      unawaited(_persist());
    }
  }

  void _pushNotification(DownloadTask task, {bool force = false}) {
    final remaining = pendingCount;
    final suffix = remaining > 1 ? ' (navbatda yana ${remaining - 1} ta)' : '';

    switch (task.stage) {
      case DownloadStage.remuxing:
        DownloadService.updateForegroundService(
          task.title,
          'MP4 formatiga o‘tkazilmoqda...$suffix',
          -1,
        );
        return;
      case DownloadStage.saving:
        DownloadService.updateForegroundService(
          task.title,
          'Xotiraga saqlanmoqda...$suffix',
          -1,
        );
        return;
      case DownloadStage.downloading:
        break;
    }

    final fraction = task.progress?.fraction;
    if (fraction == null) {
      if (force) {
        DownloadService.updateForegroundService(
          task.title,
          'Yuklab olinmoqda...$suffix',
          -1,
        );
      }
      return;
    }

    final percent = (fraction * 100).round();
    if (!force && percent == _lastNotifiedPercent) return;
    _lastNotifiedPercent = percent;
    DownloadService.updateForegroundService(
      task.title,
      'Yuklab olinmoqda... $percent%$suffix',
      percent,
    );
  }
}
