import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_iconly/flutter_iconly.dart';
import 'package:riya_play/services/download_manager.dart';
import 'package:riya_play/services/download_service.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/theme/app_dimens.dart';

/// Quality picker plus a live view of the download queue.
///
/// The transfer itself belongs to [DownloadManager], not to this widget:
/// leaving the screen no longer cancels anything, and several episodes can
/// be queued by opening it once per episode.
class DownloadScreen extends StatefulWidget {
  /// Null when opened purely to inspect the queue rather than to add to it.
  final String? videoUrl;
  final String? title;

  const DownloadScreen({
    super.key,
    required String this.videoUrl,
    required String this.title,
  });

  /// Entry point for "Yuklab olishlar" — shows the queue without starting a
  /// new download. Without this the queue was only reachable by beginning
  /// another download, so a user who navigated away couldn't get back to it.
  const DownloadScreen.queue({super.key}) : videoUrl = null, title = null;

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

enum _Stage { requestingPermission, permissionDenied, choosingQuality, queue }

class _DownloadScreenState extends State<DownloadScreen> {
  final DownloadManager _manager = DownloadManager.instance;

  _Stage _stage = _Stage.requestingPermission;
  List<VideoQuality> _qualities = const [];

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final videoUrl = widget.videoUrl;
    if (videoUrl == null) {
      setState(() => _stage = _Stage.queue);
      return;
    }

    setState(() => _stage = _Stage.requestingPermission);

    final granted = await DownloadService.ensureStoragePermission();
    if (!mounted) return;
    if (!granted) {
      setState(() => _stage = _Stage.permissionDenied);
      return;
    }

    // Bir nechta sifat mavjud bo'lsa, tanlashni foydalanuvchiga qoldiramiz.
    final qualities = await DownloadService.fetchQualities(videoUrl);
    if (!mounted) return;
    if (qualities.isNotEmpty) {
      setState(() {
        _qualities = qualities;
        _stage = _Stage.choosingQuality;
      });
      return;
    }

    _enqueue(null);
  }

  void _enqueue(VideoQuality? quality) {
    _manager.enqueue(
      videoUrl: widget.videoUrl!,
      title: widget.title!,
      mediaPlaylistUrl: quality?.playlistUrl,
      qualityLabel: quality?.label,
      bandwidth: quality?.bandwidth,
    );
    if (!mounted) return;
    setState(() => _stage = _Stage.queue);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Navbatga qo‘shildi. Ekrandan chiqsangiz ham davom etadi.",
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return "${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB";
    }
    if (bytes >= 1024 * 1024) {
      return "${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB";
    }
    if (bytes >= 1024) return "${(bytes / 1024).toStringAsFixed(0)} KB";
    return "$bytes B";
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: themeProvider.backgroundColor,
      appBar: AppBar(
        backgroundColor: themeProvider.appBarColor,
        elevation: 2,
        leading: IconButton(
          icon: Icon(IconlyLight.arrowLeft, color: themeProvider.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Yuklab olish",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: themeProvider.textColor,
          ),
        ),
        actions: [
          if (_stage == _Stage.queue)
            TextButton(
              onPressed: () => _manager.clearFinished(),
              child: Text(
                "Tozalash",
                style: TextStyle(color: themeProvider.accentColor),
              ),
            ),
        ],
      ),
      body: Padding(
        // `edgeToEdge` — ekran oynaning pastigacha chizadi, ya'ni navbatning
        // oxirgi kartochkasi tizim navigatsiya paneli ostida qolardi. Bu yerda
        // bo'shliq skroll ichida emas, tashqarisida: fon bir tekis, panel
        // ortidan o'tayotgan kartochkani ko'rsatishdan foyda yo'q.
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + MediaQuery.of(context).viewPadding.bottom,
        ),
        child: _buildBody(themeProvider),
      ),
    );
  }

  Widget _wifiOnlyToggle(ThemeProvider themeProvider) {
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SwitchListTile(
        value: _manager.wifiOnly,
        onChanged: (value) => _manager.setWifiOnly(value),
        activeColor: themeProvider.accentColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
        ),
        title: Text(
          "Faqat Wi-Fi orqali",
          style: TextStyle(fontSize: 14, color: themeProvider.textColor),
        ),
        subtitle: Text(
          "Mobil internetda yuklash kutib turadi",
          style: TextStyle(fontSize: 12, color: themeProvider.subTextColor),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeProvider themeProvider) {
    switch (_stage) {
      case _Stage.requestingPermission:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: themeProvider.accentColor),
              const SizedBox(height: AppSpacing.lg),
              Text(
                "Tayyorlanmoqda...",
                style: TextStyle(color: themeProvider.subTextColor),
              ),
            ],
          ),
        );

      case _Stage.permissionDenied:
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                IconlyLight.infoSquare,
                size: 56,
                color: themeProvider.subTextColor,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                "Yuklab olish uchun xotiraga yozish ruxsati kerak.\n"
                "Sozlamalardan ruxsat bering va qaytadan urinib ko‘ring.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: themeProvider.subTextColor,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _prepare,
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeProvider.buttonColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text("Qayta urinish"),
              ),
            ],
          ),
        );

      case _Stage.choosingQuality:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title ?? '',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: themeProvider.textColor,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              "Sifatni tanlang",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: themeProvider.textColor,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: ListView.separated(
                itemCount: _qualities.length,
                separatorBuilder:
                    (_, __) => const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final quality = _qualities[index];
                  return Material(
                    color: themeProvider.cardColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      onTap: () => _enqueue(quality),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Row(
                          children: [
                            Icon(
                              IconlyLight.video,
                              color: themeProvider.accentColor,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  quality.label,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: themeProvider.textColor,
                                  ),
                                ),
                                if (quality.resolution != null)
                                  Text(
                                    quality.resolution!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: themeProvider.subTextColor,
                                    ),
                                  ),
                              ],
                            ),
                            const Spacer(),
                            Text(
                              "${(quality.bandwidth / 1000000).toStringAsFixed(1)} Mbit/s",
                              style: TextStyle(
                                fontSize: 13,
                                color: themeProvider.subTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );

      case _Stage.queue:
        return ListenableBuilder(
          listenable: _manager,
          builder: (context, _) {
            final tasks = _manager.tasks.reversed.toList();
            return Column(
              children: [
                _wifiOnlyToggle(themeProvider),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child:
                      tasks.isEmpty
                          ? Center(
                            child: Text(
                              "Navbat bo‘sh",
                              style: TextStyle(
                                color: themeProvider.subTextColor,
                              ),
                            ),
                          )
                          : ListView.separated(
                            itemCount: tasks.length,
                            separatorBuilder:
                                (_, __) =>
                                    const SizedBox(height: AppSpacing.md),
                            itemBuilder:
                                (context, index) => _TaskCard(
                                  task: tasks[index],
                                  themeProvider: themeProvider,
                                  pauseState: _manager.pauseState,
                                  formatBytes: _formatBytes,
                                  onCancel:
                                      () => _manager.cancel(tasks[index].id),
                                  onRetry: () => _manager.retry(tasks[index].id),
                                  onRemove:
                                      () => _manager.remove(tasks[index].id),
                                ),
                          ),
                ),
              ],
            );
          },
        );
    }
  }
}

class _TaskCard extends StatelessWidget {
  final DownloadTask task;
  final ThemeProvider themeProvider;
  final QueuePause pauseState;
  final String Function(int bytes) formatBytes;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  const _TaskCard({
    required this.task,
    required this.themeProvider,
    required this.pauseState,
    required this.formatBytes,
    required this.onCancel,
    required this.onRetry,
    required this.onRemove,
  });

  String get _statusText {
    switch (task.status) {
      case DownloadStatus.queued:
        switch (pauseState) {
          case QueuePause.network:
            return "Tarmoq kutilmoqda";
          case QueuePause.wifi:
            return "Wi-Fi kutilmoqda";
          case QueuePause.none:
            return "Navbatda";
        }
      case DownloadStatus.running:
        switch (task.stage) {
          case DownloadStage.downloading:
            return "Yuklab olinmoqda";
          case DownloadStage.remuxing:
            return "MP4 formatiga o‘tkazilmoqda";
          case DownloadStage.saving:
            return "Xotiraga saqlanmoqda";
        }
      case DownloadStatus.completed:
        return "Yuklab olindi";
      case DownloadStatus.failed:
        return "Xatolik";
      case DownloadStatus.cancelled:
        return "Bekor qilindi";
    }
  }

  Color get _statusColor {
    switch (task.status) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.cancelled:
        return themeProvider.subTextColor;
      case DownloadStatus.queued:
      case DownloadStatus.running:
        return themeProvider.accentColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = task.progress;
    final fraction =
        task.status == DownloadStatus.running &&
                task.stage == DownloadStage.downloading
            ? progress?.fraction
            : (task.status == DownloadStatus.completed ? 1.0 : null);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: themeProvider.cardColor,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: themeProvider.textColor,
                  ),
                ),
              ),
              if (task.qualityLabel != null)
                Container(
                  margin: const EdgeInsets.only(left: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: themeProvider.backgroundColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    task.qualityLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      color: themeProvider.subTextColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Text(
                _statusText,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _statusColor,
                ),
              ),
              const Spacer(),
              if (fraction != null)
                Text(
                  "${(fraction * 100).toStringAsFixed(0)}%",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: themeProvider.textColor,
                  ),
                ),
            ],
          ),
          if (task.status == DownloadStatus.running) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: themeProvider.backgroundColor,
                valueColor: AlwaysStoppedAnimation<Color>(
                  themeProvider.accentColor,
                ),
              ),
            ),
            if (progress != null &&
                task.stage == DownloadStage.downloading) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  progress.totalBytes != null
                      ? "${formatBytes(progress.receivedBytes)} / ${formatBytes(progress.totalBytes!)}"
                      : formatBytes(progress.receivedBytes),
                  "${formatBytes(progress.speedBytesPerSecond.round())}/s",
                  if (progress.totalSegments > 0)
                    "${progress.completedSegments}/${progress.totalSegments} qism",
                ].join("  •  "),
                style: TextStyle(
                  fontSize: 12,
                  color: themeProvider.subTextColor,
                ),
              ),
            ],
          ],
          if (task.status == DownloadStatus.completed &&
              task.savedPath != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SelectableText(
              task.savedPath!,
              style: TextStyle(
                fontSize: 11,
                color: themeProvider.subTextColor,
              ),
            ),
            if (task.warning != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                task.warning!,
                style: const TextStyle(fontSize: 11, color: Colors.orange),
              ),
            ],
          ],
          if (task.error != null &&
              (task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.queued)) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              task.error!,
              style: TextStyle(fontSize: 11, color: themeProvider.subTextColor),
            ),
            if (task.status == DownloadStatus.failed) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                "Qayta urinilsa, yuklangan qismidan davom etadi.",
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: themeProvider.subTextColor,
                ),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (task.isPending)
                TextButton(
                  onPressed: onCancel,
                  child: Text(
                    "Bekor qilish",
                    style: TextStyle(color: themeProvider.subTextColor),
                  ),
                ),
              if (task.status == DownloadStatus.failed ||
                  task.status == DownloadStatus.cancelled)
                TextButton(
                  onPressed: onRetry,
                  child: Text(
                    // Bekor qilinganda yarim fayl o'chiriladi, xatolikda esa
                    // saqlanadi — tugma nomi shuni aks ettiradi.
                    task.status == DownloadStatus.failed
                        ? "Davom ettirish"
                        : "Qayta boshlash",
                    style: TextStyle(color: themeProvider.accentColor),
                  ),
                ),
              if (task.isFinished)
                TextButton(
                  onPressed: onRemove,
                  child: Text(
                    "O‘chirish",
                    style: TextStyle(color: themeProvider.subTextColor),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
