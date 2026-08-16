import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pointycastle/export.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:riya_play/utils/app_logger.dart';

/// Snapshot of an in-progress download. [fraction] is 0..1, or null while
/// the total size/segment count isn't known yet.
class DownloadProgress {
  final int receivedBytes;
  final int? totalBytes;
  final double speedBytesPerSecond;
  final int completedSegments;
  final int totalSegments;

  const DownloadProgress({
    required this.receivedBytes,
    this.totalBytes,
    required this.speedBytesPerSecond,
    this.completedSegments = 0,
    this.totalSegments = 0,
  });

  double? get fraction {
    if (totalSegments > 0) return completedSegments / totalSegments;
    if (totalBytes != null && totalBytes! > 0) {
      return receivedBytes / totalBytes!;
    }
    return null;
  }
}

/// Coarse phase of a download, for driving UI/notification text.
enum DownloadStage { downloading, remuxing, saving }

class DownloadResult {
  /// Public location the finished video was moved to.
  final String path;

  /// Trailing segments the source advertised but never served. Non-zero
  /// means the video is slightly shorter than the catalogue claims.
  final int skippedSegments;

  const DownloadResult(this.path, {this.skippedSegments = 0});
}

class DownloadCancelledException implements Exception {}

/// The server answered, but with an error status.
///
/// Kept separate from connection failures on purpose: a 404 on a segment is
/// not "the internet dropped", and retrying it every 15 seconds forever —
/// which is what a network-classified failure does — never succeeds and
/// tells the user the wrong thing.
class HttpStatusException implements Exception {
  final int statusCode;
  final String url;

  const HttpStatusException(this.statusCode, this.url);

  /// 5xx, timeouts and rate limits are worth another attempt; 4xx means the
  /// request itself is wrong or the content is gone.
  bool get isTransient =>
      statusCode >= 500 || statusCode == 408 || statusCode == 429;

  @override
  String toString() => 'HTTP $statusCode';
}

/// Thrown before any bytes are fetched when the device can't fit the result.
/// Failing up front beats filling the disk and dying at 95%.
class InsufficientStorageException implements Exception {
  final int requiredBytes;
  final int freeBytes;
  const InsufficientStorageException(this.requiredBytes, this.freeBytes);

  static String _mb(int bytes) => '${(bytes / (1024 * 1024)).round()} MB';

  @override
  String toString() =>
      "Xotirada joy yetarli emas: taxminan ${_mb(requiredBytes)} kerak, "
      "${_mb(freeBytes)} bo‘sh.";
}

/// One `#EXT-X-STREAM-INF` variant from a master playlist.
class VideoQuality {
  /// Familiar tier name ("1080p", "720p"). Widescreen films are letterboxed
  /// to non-standard heights — a 2.35:1 movie encodes 1080p as 1778x1000 —
  /// so the raw height would read as a confusing "1000p"; this rounds to the
  /// tier users actually recognise, with [resolution] carrying the exact size.
  final String label;

  /// "1778x1000", or null when the playlist omits RESOLUTION.
  final String? resolution;
  final int bandwidth;
  final String playlistUrl;

  const VideoQuality({
    required this.label,
    required this.bandwidth,
    required this.playlistUrl,
    this.resolution,
  });

  static String labelForHeight(int height) {
    if (height >= 1800) return '4K';
    if (height >= 1300) return '1440p';
    if (height >= 900) return '1080p';
    if (height >= 650) return '720p';
    if (height >= 440) return '480p';
    if (height >= 300) return '360p';
    return '240p';
  }
}

/// A single fetchable piece of an HLS media playlist: a media segment, or
/// the `#EXT-X-MAP` initialisation segment that fMP4 streams start with.
class _HlsSegment {
  final String url;

  /// AES-128 key in force for this segment, or null when unencrypted. Keys
  /// are per-segment because a playlist may rotate them mid-stream.
  final Uint8List? key;
  final Uint8List? iv;

  /// Set when the playlist addresses this piece with `#EXT-X-BYTERANGE`,
  /// i.e. many segments share one URL and differ only by offset.
  final int? rangeStart;
  final int? rangeLength;

  const _HlsSegment({
    required this.url,
    this.key,
    this.iv,
    this.rangeStart,
    this.rangeLength,
  });
}

class _HlsPlaylist {
  final List<_HlsSegment> segments;

  /// True when `#EXT-X-MAP` was present: the stream is fragmented MP4, not
  /// MPEG-TS, which changes how it must be remuxed.
  final bool isFragmentedMp4;
  final double totalDurationSeconds;

  const _HlsPlaylist({
    required this.segments,
    required this.isFragmentedMp4,
    required this.totalDurationSeconds,
  });
}

/// Wall-clock split of one HLS download, so a slow transfer can be blamed
/// on the right thing. Reported once at the end via [appLogger].
///
/// `fetch` is time blocked on the network; the rest is work this app does on
/// the Dart isolate after the bytes arrive. Comparing `networkBytes/fetch`
/// against `networkBytes/total` shows how much of the achievable link speed
/// the pipeline actually delivers.
class _DownloadProfile {
  double fetchMs = 0;
  double cryptoMs = 0;
  double writeMs = 0;
  double persistMs = 0;
  int networkBytes = 0;

  final Stopwatch total = Stopwatch()..start();

  static String _mbps(int bytes, double ms) {
    if (ms <= 0) return '—';
    return '${(bytes / (1024 * 1024) / (ms / 1000)).toStringAsFixed(2)} MB/s';
  }

  static String _share(double part, double whole) {
    if (whole <= 0) return '0%';
    return '${(part / whole * 100).toStringAsFixed(0)}%';
  }

  void report() {
    total.stop();
    final totalMs = total.elapsedMicroseconds / 1000;
    final otherMs = totalMs - fetchMs - cryptoMs - writeMs - persistMs;
    appLogger.d(
      'Yuklash profili: jami ${(totalMs / 1000).toStringAsFixed(1)}s, '
      '${(networkBytes / (1024 * 1024)).toStringAsFixed(1)} MB\n'
      '  tarmoq  ${(fetchMs / 1000).toStringAsFixed(1)}s '
      '(${_share(fetchMs, totalMs)}) -> ${_mbps(networkBytes, fetchMs)}\n'
      '  deshifr ${(cryptoMs / 1000).toStringAsFixed(1)}s '
      '(${_share(cryptoMs, totalMs)}) -> ${_mbps(networkBytes, cryptoMs)}\n'
      '  yozish  ${(writeMs / 1000).toStringAsFixed(1)}s '
      '(${_share(writeMs, totalMs)})\n'
      '  saqlash ${(persistMs / 1000).toStringAsFixed(1)}s '
      '(${_share(persistMs, totalMs)})\n'
      '  qolgan  ${(otherMs / 1000).toStringAsFixed(1)}s '
      '(${_share(otherMs, totalMs)})\n'
      '  haqiqiy tezlik ${_mbps(networkBytes, totalMs)}',
    );
  }
}

/// Where a previously interrupted download got to, so it can pick up
/// instead of re-fetching everything.
class _ResumeState {
  final int bytes;
  final int completedSegments;
  final int totalSegments;

  const _ResumeState({
    required this.bytes,
    required this.completedSegments,
    required this.totalSegments,
  });

  Map<String, dynamic> toJson() => {
    'bytes': bytes,
    'completed': completedSegments,
    'total': totalSegments,
  };

  static _ResumeState? fromJson(String raw) {
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return _ResumeState(
        bytes: map['bytes'] as int? ?? 0,
        completedSegments: map['completed'] as int? ?? 0,
        totalSegments: map['total'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Downloads a video (direct file or HLS `.m3u8` stream) and publishes it
/// into the shared Movies/RiyaPlay folder, so it's findable from the
/// Gallery and any file manager rather than buried in app-private storage.
class DownloadService {
  static const _channel = MethodChannel('uz.mrlg.riyaplay/media_store');

  /// Matches what [FilmsApi.checkUrlValidity] sends. Some CDN edges answer
  /// 403 to Dart's default agent while serving the same URL to the player,
  /// so every request here identifies itself the same way.
  static const Map<String, String> _requestHeaders = {
    'User-Agent': 'okhttp/4.9.2',
  };

  /// The transfer itself writes to app-private storage and the finished file
  /// is handed to MediaStore, neither of which needs a runtime permission on
  /// Android 10+. Only API <= 28 still requires legacy
  /// WRITE_EXTERNAL_STORAGE — and on API 33+ requesting it always returns
  /// denied (it no longer exists), which would block downloads that are in
  /// fact allowed.
  static Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final androidInfo = await DeviceInfoPlugin().androidInfo;

    // Foreground xizmati bildirishnomasi ko'rinishi uchun. Rad etilsa ham
    // xizmat ishlayveradi (Doze'dan himoya saqlanadi), shunchaki
    // foydalanuvchi jarayonni ko'rmaydi — shuning uchun bloklamaymiz.
    if (androidInfo.version.sdkInt >= 33) {
      final notify = await Permission.notification.status;
      if (notify.isDenied) await Permission.notification.request();
    }

    if (androidInfo.version.sdkInt >= 29) return true;

    final status = await Permission.storage.status;
    if (status.isGranted || status.isLimited) return true;
    final result = await Permission.storage.request();
    return result.isGranted || result.isLimited;
  }

  static String _sanitizeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'video' : cleaned;
  }

  static String _resolveUrl(String baseUrl, String maybeRelative) {
    if (maybeRelative.startsWith('http://') ||
        maybeRelative.startsWith('https://')) {
      return maybeRelative;
    }
    return Uri.parse(baseUrl).resolve(maybeRelative).toString();
  }

  /// Stable per-video key for resume bookkeeping. The query string is
  /// dropped because stream URLs carry expiring tokens — the same episode
  /// comes back under a different token on the next attempt, and keying on
  /// that would lose the partial file every time.
  static String _resumeKey(String url, String safeName) {
    final cleaned = url.split('?').first;
    // FNV-1a: short, stable, and no crypto dependency needed for a cache key.
    var hash = 0xcbf29ce484222325;
    for (final unit in utf8.encode('$safeName|$cleaned')) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return 'dl_resume_${hash.toRadixString(16)}';
  }

  /// Upper bound on how many segment bodies may be in flight at once.
  /// Segments are held whole in memory while a batch is gathered, so the
  /// cap is expressed in bytes rather than count: ten 50 MB 4K segments
  /// would be half a gigabyte of heap and an OOM kill on most devices.
  static const int _maxInFlightBytes = 64 * 1024 * 1024;

  /// O'lchangan qiymatlar: 10 ta ulanish 5.55 MB/s, 24 tasi 7.23 MB/s berdi.
  /// 48 ta birinchi urinishda beqaror bo'lib ilovani qayta ishga tushirgan
  /// edi, lekin o'shanda boshqa xotira xatolari ham bor edi (Bug 17 —
  /// `safeDispose` ExoPlayer'ni oqizardi). Ular tuzatilgandan keyin 48
  /// loyiha egasining qaroriga ko'ra qaytarildi.
  ///
  /// DIQQAT: 48 qayta o'lchanmagan. `_maxInFlightBytes` (64 MB) baribir
  /// ushlab turadi, ammo agar yuklab olish paytida ilova yana qayta ishga
  /// tushsa — birinchi shubha shu qiymatga.
  ///
  /// Boshlang'ich qiymat maksimaldan oshmasligi shart, aks holda faqat
  /// birinchi guruh keng bo'lib, qolganlari `_adaptConcurrency` tomonidan
  /// qisiladi.
  static const int _maxSegmentConcurrency = 48;
  static const int _minSegmentConcurrency = 2;

  /// Starting batch size, before any segment has been measured.
  static const int _initialSegmentConcurrency = _maxSegmentConcurrency;

  /// 5 urinish ~6 soniyaga cho'ziladi — mobil tarmoq almashinuvi kabi
  /// qisqa uzilishlarni o'tkazib yuborish uchun yetarli.
  static const int _maxAttempts = 5;

  /// Some media playlists advertise a final segment the CDN never serves —
  /// a real case in this catalogue, where one episode's `segment244.ts`
  /// returns 404 on every attempt. Failing the whole download over the last
  /// dozen seconds throws away hundreds of megabytes and leaves the episode
  /// permanently un-downloadable, so a 404 on the very tail is tolerated.
  /// The caller is told, and anything beyond the tail still fails properly.
  static const int _maxSkippableTailSegments = 2;

  /// Fetches [url], retrying transient network failures with exponential
  /// backoff. A dropped connection mid-download used to abort the whole
  /// file ("Connection closed while receiving data"), throwing away
  /// everything already fetched.
  static Future<Uint8List> _fetchWithRetry(
    http.Client client,
    String url,
    bool Function() isCancelled, {
    int? rangeStart,
    int? rangeLength,
  }) async {
    final headers = <String, String>{..._requestHeaders};
    if (rangeLength != null) {
      final start = rangeStart ?? 0;
      headers['Range'] = 'bytes=$start-${start + rangeLength - 1}';
    }

    for (var attempt = 1; ; attempt++) {
      if (isCancelled()) throw DownloadCancelledException();
      try {
        final response = await client
            .get(Uri.parse(url), headers: headers)
            .timeout(const Duration(seconds: 60));
        if (response.statusCode >= 400) {
          throw HttpStatusException(response.statusCode, url);
        }
        return response.bodyBytes;
      } catch (e) {
        if (e is DownloadCancelledException) rethrow;
        // 4xx'ni takrorlash befoyda — javob o'zgarmaydi, shuning uchun
        // 5 marta kutib o'tirmasdan darhol xabar beramiz.
        if (e is HttpStatusException && !e.isTransient) rethrow;
        if (attempt >= _maxAttempts) rethrow;
        appLogger.d('Segment qayta urinilmoqda ($attempt): $e');
        await Future.delayed(
          Duration(milliseconds: 400 * (1 << (attempt - 1))),
        );
      }
    }
  }

  /// Fetches one segment, returning null when it is a tail segment the
  /// source doesn't actually have. Only permanent (4xx) statuses are
  /// skipped — a dropped connection still fails, so a flaky network can
  /// never silently punch holes in the file.
  static Future<Uint8List?> _fetchSegment(
    http.Client client,
    _HlsSegment segment,
    bool Function() isCancelled, {
    required bool skippable,
  }) async {
    try {
      return await _fetchWithRetry(
        client,
        segment.url,
        isCancelled,
        rangeStart: segment.rangeStart,
        rangeLength: segment.rangeLength,
      );
    } on HttpStatusException catch (e) {
      if (skippable && !e.isTransient) {
        appLogger.d('Oxirgi segment manbada yo‘q (HTTP ${e.statusCode})');
        return null;
      }
      rethrow;
    }
  }

  /// Foreground xizmatini boshqarish. Xatolarni yutamiz — bildirishnoma
  /// ko'rsatilmasligi yuklashning o'zini to'xtatishga sabab bo'lmasligi kerak.
  static Future<void> _serviceCall(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod(method, args);
    } catch (e) {
      appLogger.d('Foreground xizmati ($method) xatosi: $e');
    }
  }

  /// The queue owns the service lifecycle now: it stays up across the whole
  /// run rather than being torn down and restarted between items, which
  /// would drop the Doze exemption in the gap.
  static Future<void> startForegroundService(String title, String status) =>
      _serviceCall('startDownloadService', {'title': title, 'status': status});

  static Future<void> updateForegroundService(
    String title,
    String status,
    int progress,
  ) => _serviceCall('updateDownloadService', {
    'title': title,
    'status': status,
    'progress': progress,
  });

  static Future<void> stopForegroundService() =>
      _serviceCall('stopDownloadService');

  /// Free space on the volume holding app-private storage, or null when the
  /// platform can't tell us (in which case the pre-flight check is skipped
  /// rather than guessed at).
  static Future<int?> _freeBytes() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<int>('getFreeBytes');
    } catch (e) {
      appLogger.d('Bo‘sh joyni aniqlab bo‘lmadi: $e');
      return null;
    }
  }

  /// Peak disk use is roughly twice the finished file: the download and the
  /// remuxed MP4 coexist while FFmpeg runs, and later the temp file and its
  /// MediaStore copy coexist while it is published. Those two peaks don't
  /// overlap, so 2x plus a small margin is the real requirement.
  static const double _peakDiskMultiplier = 2.0;
  static const int _diskMarginBytes = 64 * 1024 * 1024;

  static Future<void> _ensureSpaceFor(int estimatedBytes) async {
    if (estimatedBytes <= 0) return;
    final free = await _freeBytes();
    // Manfiy qiymat — platforma aniqlay olmadi; taxmin qilgandan ko'ra
    // tekshiruvni o'tkazib yuborgan ma'qul.
    if (free == null || free < 0) return;
    final required =
        (estimatedBytes * _peakDiskMultiplier).round() + _diskMarginBytes;
    if (free < required) {
      throw InsufficientStorageException(required, free);
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final clean = hex.toLowerCase().startsWith('0x') ? hex.substring(2) : hex;
    final bytes = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  /// Media sequence number as the 16-byte big-endian IV that HLS uses when
  /// `#EXT-X-KEY` doesn't carry an explicit one.
  static Uint8List _sequenceIv(int sequence) {
    final iv = Uint8List(16);
    var value = sequence;
    for (var i = 15; i >= 0 && value > 0; i--) {
      iv[i] = value & 0xFF;
      value >>= 8;
    }
    return iv;
  }

  /// AES-128-CBC with PKCS7 padding — the only method HLS defines for
  /// `METHOD=AES-128`. Each segment is encrypted (and padded) on its own.
  static Uint8List _decryptSegment(
    Uint8List key,
    Uint8List iv,
    Uint8List data,
  ) {
    if (data.isEmpty || data.length % 16 != 0) {
      throw Exception("Shifrlangan segment hajmi noto‘g‘ri: ${data.length}");
    }
    final cipher = CBCBlockCipher(AESEngine())
      ..init(false, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(data.length);
    var offset = 0;
    while (offset < data.length) {
      offset += cipher.processBlock(data, offset, out, offset);
    }
    final padLength = out[out.length - 1];
    if (padLength < 1 || padLength > 16 || padLength > out.length) {
      return out; // To‘ldirish kutilganidek emas — borini qaytaramiz.
    }
    return Uint8List.sublistView(out, 0, out.length - padLength);
  }

  /// Reads one quoted or bare attribute out of an `#EXT-X-…` tag line.
  static String? _attribute(String line, String name) {
    final quoted = RegExp('$name="([^"]*)"').firstMatch(line);
    if (quoted != null) return quoted.group(1);
    return RegExp('$name=([^,]*)').firstMatch(line)?.group(1)?.trim();
  }

  /// Variants offered by an HLS master playlist, best quality first.
  ///
  /// Returns an empty list when [videoUrl] isn't HLS, or points straight at
  /// a media playlist with no variants to choose between — in that case
  /// there's nothing to ask the user about.
  static Future<List<VideoQuality>> fetchQualities(String videoUrl) async {
    if (!videoUrl.contains('.m3u8')) return const [];

    final client = http.Client();
    try {
      final body = utf8.decode(
        await _fetchWithRetry(client, videoUrl, () => false),
      );
      final variants = _parseMasterPlaylist(videoUrl, body);
      // Yagona variantda tanlaydigan narsa yo'q — dialogni ko'rsatmaymiz.
      return variants.length > 1 ? variants : const [];
    } catch (_) {
      return const []; // Sifatlarni o'qib bo'lmasa, avtomatik tanlashga qaytamiz.
    } finally {
      client.close();
    }
  }

  static List<VideoQuality> _parseMasterPlaylist(String url, String body) {
    final lines = body.split('\n');
    final qualities = <VideoQuality>[];

    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      if (i + 1 >= lines.length) continue;
      final next = lines[i + 1].trim();
      if (next.isEmpty || next.startsWith('#')) continue;

      final bandwidth =
          int.tryParse(
            RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '',
          ) ??
          0;
      final match = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(lines[i]);
      final height = int.tryParse(match?.group(2) ?? '');
      final label =
          height != null
              ? VideoQuality.labelForHeight(height)
              : '${(bandwidth / 1000000).toStringAsFixed(1)} Mbit/s';

      qualities.add(
        VideoQuality(
          label: label,
          resolution:
              match != null ? '${match.group(1)}x${match.group(2)}' : null,
          bandwidth: bandwidth,
          playlistUrl: _resolveUrl(url, next),
        ),
      );
    }

    // Eng yuqori sifat birinchi. Bitta variant ham qaytariladi: yuklovchiga
    // media playlist manzili kerak, tanlov taklif qilinmasa ham.
    qualities.sort((a, b) => b.bandwidth.compareTo(a.bandwidth));
    return qualities;
  }

  static Future<DownloadResult> download({
    required String videoUrl,
    required String title,

    /// Set when the user picked a variant, so the master playlist's
    /// automatic "highest bandwidth" choice is bypassed.
    String? mediaPlaylistUrl,

    /// Tier name ("720p") to look for in the master playlist when
    /// [mediaPlaylistUrl] wasn't resolved up front — how a batched season
    /// download expresses "this quality for every episode".
    String? preferredQualityLabel,

    /// Bits per second of the chosen variant, used to size the disk-space
    /// pre-flight check. Null simply skips that check.
    int? bandwidthHint,
    required void Function(DownloadProgress progress) onProgress,
    required void Function(DownloadStage stage) onStage,
    required bool Function() isCancelled,
  }) async {
    final safeName = _sanitizeFileName(title);
    final isHls = videoUrl.contains('.m3u8');

    final tempDir = await getApplicationDocumentsDirectory();
    // A `.part` suffix keeps an interrupted transfer distinguishable from a
    // finished file, so the next attempt knows it may resume into it.
    final partFile = File('${tempDir.path}/$safeName.dl.part');
    final resumeKey = _resumeKey(mediaPlaylistUrl ?? videoUrl, safeName);

    onStage(DownloadStage.downloading);

    final String downloadedExtension;
    var skippedSegments = 0;
    if (isHls) {
      final outcome = await _downloadHls(
        videoUrl,
        partFile,
        onProgress,
        isCancelled,
        selectedPlaylistUrl: mediaPlaylistUrl,
        preferredQualityLabel: preferredQualityLabel,
        bandwidthHint: bandwidthHint,
        resumeKey: resumeKey,
      );
      downloadedExtension = outcome.extension;
      skippedSegments = outcome.skipped;
    } else {
      final raw = videoUrl.split('?').first.split('.').last;
      downloadedExtension = raw.length <= 4 ? raw : 'mp4';
      await _downloadDirect(
        videoUrl,
        partFile,
        onProgress,
        isCancelled,
        resumeKey: resumeKey,
      );
    }

    return _finish(
      title: title,
      safeName: safeName,
      tempDir: tempDir,
      partFile: partFile,
      extension: downloadedExtension,
      isHls: isHls,
      resumeKey: resumeKey,
      onStage: onStage,
      skippedSegments: skippedSegments,
    );
  }

  /// Remuxes when needed and publishes the result, then clears the resume
  /// bookkeeping. Kept separate from the transfer so a failure here can't be
  /// mistaken for a network failure that should be resumed.
  static Future<DownloadResult> _finish({
    required String title,
    required String safeName,
    required Directory tempDir,
    required File partFile,
    required String extension,
    required bool isHls,
    required String resumeKey,
    required void Function(DownloadStage stage) onStage,
    int skippedSegments = 0,
  }) async {
    var sourceFile = partFile;
    var publicFileName = '$safeName.$extension';

    // HLS segmentlari MPEG-TS yoki fMP4 bo'ladi; ikkalasini ham MP4
    // konteyneriga o'tkazamiz.
    if (isHls) {
      onStage(DownloadStage.remuxing);
      final mp4File = File('${tempDir.path}/$safeName.mp4');
      final remuxed = await _remuxToMp4(
        partFile,
        mp4File,
        isMpegTs: extension == 'ts',
      );
      if (remuxed) {
        sourceFile = mp4File;
        publicFileName = '$safeName.mp4';
        if (await partFile.exists()) await partFile.delete();
      }
      // Remuxing muvaffaqiyatsiz bo'lsa, xom faylni saqlaymiz — u ham
      // o'ynatiladi, shunchaki mosligi kamroq.
    }

    onStage(DownloadStage.saving);
    try {
      final publicPath = await _channel.invokeMethod<String>('saveToMovies', {
        'sourcePath': sourceFile.path,
        'fileName': publicFileName,
      });
      await _clearResume(resumeKey);
      return DownloadResult(
        publicPath ?? sourceFile.path,
        skippedSegments: skippedSegments,
      );
    } catch (_) {
      if (await sourceFile.exists()) await sourceFile.delete();
      await _clearResume(resumeKey);
      rethrow;
    }
  }

  /// Rewraps the downloaded stream into MP4 without re-encoding (`-c copy`),
  /// so it stays fast and lossless. Returns false if FFmpeg failed, leaving
  /// the caller to fall back to publishing the raw file.
  static Future<bool> _remuxToMp4(
    File source,
    File target, {
    required bool isMpegTs,
  }) async {
    if (await target.exists()) await target.delete();
    // -bsf:a aac_adtstoasc: TS'dagi ADTS audio ramkalarini MP4 kutadigan
    // formatga o'tkazadi. fMP4 manbada ADTS bo'lmaydi va bu filtr xato
    // beradi, shuning uchun faqat TS uchun qo'llaymiz.
    final audioFilter = isMpegTs ? '-bsf:a aac_adtstoasc ' : '';
    final session = await FFmpegKit.execute(
      '-y -i "${source.path}" -c copy $audioFilter'
      '-movflags +faststart "${target.path}"',
    );
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) return true;

    appLogger.e("Remux xatosi: ${await session.getFailStackTrace()}");
    if (await target.exists()) await target.delete();
    return false;
  }

  static Future<_ResumeState?> _readResume(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null ? null : _ResumeState.fromJson(raw);
  }

  static Future<void> _writeResume(String key, _ResumeState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, json.encode(state.toJson()));
  }

  static Future<void> _clearResume(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  /// Drops the partial file and its bookkeeping. Called when the user
  /// cancels outright, as opposed to a failure we intend to resume from.
  static Future<void> discardPartial(String videoUrl, String title) async {
    final safeName = _sanitizeFileName(title);
    final tempDir = await getApplicationDocumentsDirectory();
    final partFile = File('${tempDir.path}/$safeName.dl.part');
    if (await partFile.exists()) await partFile.delete();
    await _clearResume(_resumeKey(videoUrl, safeName));
  }

  static Future<void> _downloadDirect(
    String url,
    File target,
    void Function(DownloadProgress) onProgress,
    bool Function() isCancelled, {
    required String resumeKey,
  }) async {
    final client = http.Client();
    try {
      // Bo'sh joyni oldindan tekshiramiz: HEAD so'rovi hajmni beradi.
      int? knownTotal;
      try {
        final head = await client
            .head(Uri.parse(url), headers: _requestHeaders)
            .timeout(const Duration(seconds: 20));
        knownTotal = int.tryParse(head.headers['content-length'] ?? '');
      } catch (_) {
        // Hajm noma'lum — tekshiruvsiz davom etamiz.
      }
      if (knownTotal != null) await _ensureSpaceFor(knownTotal);

      final resume = await _readResume(resumeKey);
      var alreadyHave = 0;
      if (resume != null && await target.exists()) {
        final onDisk = await target.length();
        alreadyHave = math.min(resume.bytes, onDisk);
      }

      final request = http.Request('GET', Uri.parse(url))
        ..headers.addAll(_requestHeaders);
      if (alreadyHave > 0) request.headers['Range'] = 'bytes=$alreadyHave-';

      final response = await client.send(request);
      // 206 bo'lsa davom ettiramiz; server Range'ni e'tiborsiz qoldirib 200
      // qaytarsa, boshidan yozishdan boshqa iloj yo'q.
      final resuming = response.statusCode == 206 && alreadyHave > 0;
      if (!resuming) alreadyHave = 0;

      final total =
          response.contentLength == null
              ? knownTotal
              : response.contentLength! + alreadyHave;

      // RandomAccessFile ishlatiladi, IOSink emas: IOSink xatolari asinxron
      // yuzaga chiqadi, ya'ni yozish muvaffaqiyatsiz bo'lsa ham sikl davom
      // etib, progress yolg'on ko'rsatishi mumkin edi.
      final raf = await target.open(
        mode: resuming ? FileMode.append : FileMode.write,
      );
      try {
        if (resuming) {
          // truncate yozish pozitsiyasini ko'chirmaydi — uni qo'lda
          // qo'ymasak, fayl oxirida bo'sh joy qolib ketadi.
          await raf.truncate(alreadyHave);
          await raf.setPosition(alreadyHave);
        }
        var received = alreadyHave;
        var lastReported = received;
        var lastPersisted = received;
        final stopwatch = Stopwatch()..start();

        await for (final chunk in response.stream) {
          if (isCancelled()) throw DownloadCancelledException();
          await raf.writeFrom(chunk);
          received += chunk.length;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs > 300) {
            final speed = (received - lastReported) / (elapsedMs / 1000);
            onProgress(
              DownloadProgress(
                receivedBytes: received,
                totalBytes: total,
                speedBytesPerSecond: speed,
              ),
            );
            lastReported = received;
            stopwatch.reset();
          }
          // Har 8 MB'da holatni yozamiz — ilova o'ldirilsa ham shu nuqtadan
          // davom etiladi, lekin SharedPreferences'ni ham ko'p bezovta
          // qilmaymiz.
          if (received - lastPersisted > 8 * 1024 * 1024) {
            await raf.flush();
            await _writeResume(
              resumeKey,
              _ResumeState(
                bytes: received,
                completedSegments: 0,
                totalSegments: 0,
              ),
            );
            lastPersisted = received;
          }
        }
        onProgress(
          DownloadProgress(
            receivedBytes: received,
            totalBytes: total,
            speedBytesPerSecond: 0,
          ),
        );
      } finally {
        await raf.close();
      }
    } finally {
      client.close();
    }
  }

  /// Downloads every segment of an HLS stream into [target]. Returns the
  /// extension the raw file should carry (`ts` or `m4s`), which decides how
  /// it is remuxed afterwards, plus how many tail segments the source failed
  /// to provide.
  static Future<({String extension, int skipped})> _downloadHls(
    String masterUrl,
    File target,
    void Function(DownloadProgress) onProgress,
    bool Function() isCancelled, {
    String? selectedPlaylistUrl,
    String? preferredQualityLabel,
    int? bandwidthHint,
    required String resumeKey,
  }) async {
    final client = http.Client();
    try {
      var mediaPlaylistUrl = selectedPlaylistUrl ?? masterUrl;
      var bandwidth = bandwidthHint ?? 0;

      // Aniq manzil berilmagan bo'lsa, master playlistdan tanlaymiz:
      // so'ralgan sifat bo'lsa o'sha, aks holda eng yuqorisi.
      if (selectedPlaylistUrl == null) {
        final masterBody = utf8.decode(
          await _fetchWithRetry(client, masterUrl, isCancelled),
        );
        final variants = _parseMasterPlaylist(masterUrl, masterBody);
        if (variants.isNotEmpty) {
          final chosen = _pickVariant(variants, preferredQualityLabel);
          mediaPlaylistUrl = chosen.playlistUrl;
          bandwidth = chosen.bandwidth;
        }
      }

      final mediaBody = utf8.decode(
        await _fetchWithRetry(client, mediaPlaylistUrl, isCancelled),
      );
      final playlist = await _parseMediaPlaylist(
        client,
        mediaPlaylistUrl,
        mediaBody,
        isCancelled,
      );
      if (playlist.segments.isEmpty) {
        throw Exception("Video segmentlari topilmadi");
      }

      if (bandwidth > 0 && playlist.totalDurationSeconds > 0) {
        await _ensureSpaceFor(
          (playlist.totalDurationSeconds * bandwidth / 8).round(),
        );
      }

      // Segment soni mos kelsa, oldingi urinish qoldirgan joydan davom
      // etamiz. Mos kelmasa oqim o'zgargan — boshidan yuklaymiz.
      var startIndex = 0;
      var received = 0;
      final resume = await _readResume(resumeKey);
      if (resume != null &&
          resume.totalSegments == playlist.segments.length &&
          resume.completedSegments > 0 &&
          await target.exists() &&
          await target.length() >= resume.bytes) {
        startIndex = resume.completedSegments;
        received = resume.bytes;
        appLogger.d(
          'Yuklash davom ettirilmoqda: $startIndex/${playlist.segments.length}',
        );
      }

      // Faqat ro'yxat oxiridagi segmentlar o'tkazib yuborilishi mumkin.
      final tailStart = playlist.segments.length - _maxSkippableTailSegments;
      var skipped = 0;
      final profile = _DownloadProfile();

      final raf = await target.open(
        mode: startIndex > 0 ? FileMode.append : FileMode.write,
      );
      try {
        // Yarim yozilgan segment qolgan bo'lishi mumkin — oxirgi tasdiqlangan
        // chegaraga qirqamiz va pozitsiyani ham o'sha yerga qo'yamiz.
        if (startIndex > 0) {
          await raf.truncate(received);
          await raf.setPosition(received);
        }

        var lastReported = received;
        var concurrency = _initialSegmentConcurrency;
        final stopwatch = Stopwatch()..start();

        onProgress(
          DownloadProgress(
            receivedBytes: received,
            speedBytesPerSecond: 0,
            completedSegments: startIndex,
            totalSegments: playlist.segments.length,
          ),
        );

        var index = startIndex;
        while (index < playlist.segments.length) {
          if (isCancelled()) throw DownloadCancelledException();
          final batchStart = index;
          final end = math.min(
            batchStart + concurrency,
            playlist.segments.length,
          );

          // Segmentlar guruh-guruh parallel yuklanadi, lekin faylga qat'iy
          // tartibda yoziladi — aks holda video buzilgan bo'lardi.
          final fetchWatch = Stopwatch()..start();
          final batch = await Future.wait([
            for (var i = batchStart; i < end; i++)
              _fetchSegment(
                client,
                playlist.segments[i],
                isCancelled,
                skippable: i >= tailStart,
              ),
          ]);
          fetchWatch.stop();
          profile.fetchMs += fetchWatch.elapsedMicroseconds / 1000;

          var batchBytes = 0;
          for (var i = batchStart; i < end; i++) {
            final segment = playlist.segments[i];
            var bytes = batch[i - batchStart];
            if (bytes == null) {
              skipped++;
              continue;
            }
            batchBytes += bytes.length;
            if (segment.key != null) {
              final cryptoWatch = Stopwatch()..start();
              bytes = _decryptSegment(segment.key!, segment.iv!, bytes);
              cryptoWatch.stop();
              profile.cryptoMs += cryptoWatch.elapsedMicroseconds / 1000;
            }
            final writeWatch = Stopwatch()..start();
            await raf.writeFrom(bytes);
            writeWatch.stop();
            profile.writeMs += writeWatch.elapsedMicroseconds / 1000;
            received += bytes.length;
          }
          index = end;
          profile.networkBytes += batchBytes;

          // Keyingi guruh hajmini o'lchangan segment kattaligiga moslaymiz,
          // shunda 4K oqim ham xotiraga sig'adi.
          concurrency = _adaptConcurrency(batchBytes, end - batchStart);

          final persistWatch = Stopwatch()..start();
          await raf.flush();
          await _writeResume(
            resumeKey,
            _ResumeState(
              bytes: received,
              completedSegments: index,
              totalSegments: playlist.segments.length,
            ),
          );
          persistWatch.stop();
          profile.persistMs += persistWatch.elapsedMicroseconds / 1000;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          final speed =
              elapsedMs > 0
                  ? (received - lastReported) / (elapsedMs / 1000)
                  : 0.0;
          onProgress(
            DownloadProgress(
              receivedBytes: received,
              speedBytesPerSecond: speed,
              completedSegments: index,
              totalSegments: playlist.segments.length,
            ),
          );
          if (elapsedMs > 300) {
            lastReported = received;
            stopwatch.reset();
          }
        }
      } finally {
        await raf.close();
        // Profil — faqat tuzatish (debug) uchun mo'ljallangan o'lchov.
        // Release'da matn ham qurilmaydi, log ham yozilmaydi.
        if (kDebugMode) profile.report();
      }

      return (
        extension: playlist.isFragmentedMp4 ? 'm4s' : 'ts',
        skipped: skipped,
      );
    } finally {
      client.close();
    }
  }

  /// Chooses which variant to fetch. [variants] is highest-bandwidth first.
  ///
  /// A season queued at "720p" may contain episodes that were never encoded
  /// at 720p, so an exact-label miss falls back to the closest tier at or
  /// below the request rather than silently jumping to the largest file.
  static VideoQuality _pickVariant(
    List<VideoQuality> variants,
    String? preferredLabel,
  ) {
    if (preferredLabel == null) return variants.first;

    for (final variant in variants) {
      if (variant.label == preferredLabel) return variant;
    }

    final wantedRank = _qualityRank(preferredLabel);
    if (wantedRank != null) {
      for (final variant in variants) {
        final rank = _qualityRank(variant.label);
        if (rank != null && rank <= wantedRank) return variant;
      }
    }
    // Hammasi so'ralganidan past sifatli — eng yaqini oxirgisi.
    return variants.last;
  }

  static const List<String> _qualityOrder = [
    '240p',
    '360p',
    '480p',
    '720p',
    '1080p',
    '1440p',
    '4K',
  ];

  static int? _qualityRank(String label) {
    final index = _qualityOrder.indexOf(label);
    return index < 0 ? null : index;
  }

  /// Picks the next batch size so roughly [_maxInFlightBytes] is buffered.
  static int _adaptConcurrency(int lastBatchBytes, int lastBatchCount) {
    if (lastBatchCount <= 0 || lastBatchBytes <= 0) {
      return _initialSegmentConcurrency;
    }
    final average = lastBatchBytes / lastBatchCount;
    final fits = (_maxInFlightBytes / average).floor();
    return fits.clamp(_minSegmentConcurrency, _maxSegmentConcurrency);
  }

  /// Walks a media playlist in order, so tags that only affect what follows
  /// them (`#EXT-X-KEY`, `#EXT-X-BYTERANGE`) are applied to the right
  /// segments. The previous single-pass scan kept only the last key it saw,
  /// which silently corrupted every stream that rotates keys.
  static Future<_HlsPlaylist> _parseMediaPlaylist(
    http.Client client,
    String playlistUrl,
    String body,
    bool Function() isCancelled,
  ) async {
    final segments = <_HlsSegment>[];
    final keyCache = <String, Uint8List>{};
    final rangeCursor = <String, int>{};

    Uint8List? activeKey;
    Uint8List? activeIv; // null => segment ketma-ketlik raqami IV bo'ladi
    var mediaSequence = 0;
    var mediaIndex = 0;
    var totalDuration = 0.0;
    var isFragmentedMp4 = false;

    int? pendingRangeLength;
    int? pendingRangeStart;

    (int?, int?) takeRange(String url) {
      if (pendingRangeLength == null) return (null, null);
      final length = pendingRangeLength!;
      final start = pendingRangeStart ?? rangeCursor[url] ?? 0;
      rangeCursor[url] = start + length;
      pendingRangeLength = null;
      pendingRangeStart = null;
      return (start, length);
    }

    void setPendingRange(String value) {
      final parts = value.split('@');
      pendingRangeLength = int.tryParse(parts.first.trim());
      pendingRangeStart =
          parts.length > 1 ? int.tryParse(parts[1].trim()) : null;
    }

    for (final raw in body.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-MEDIA-SEQUENCE:')) {
        mediaSequence = int.tryParse(line.split(':').last.trim()) ?? 0;
      } else if (line.startsWith('#EXTINF:')) {
        totalDuration +=
            double.tryParse(line.substring(8).split(',').first.trim()) ?? 0;
      } else if (line.startsWith('#EXT-X-BYTERANGE:')) {
        setPendingRange(line.substring('#EXT-X-BYTERANGE:'.length));
      } else if (line.startsWith('#EXT-X-KEY:')) {
        final method = _attribute(line, 'METHOD');
        if (method == null || method == 'NONE') {
          activeKey = null;
          activeIv = null;
          continue;
        }
        if (method != 'AES-128') {
          throw Exception("Qo‘llab-quvvatlanmaydigan shifrlash: $method");
        }
        final keyUri = _attribute(line, 'URI');
        if (keyUri == null) {
          throw Exception("Shifrlash kaliti manzili topilmadi");
        }
        final resolved = _resolveUrl(playlistUrl, keyUri);
        activeKey =
            keyCache[resolved] ??= await _fetchWithRetry(
              client,
              resolved,
              isCancelled,
            );
        final ivHex = _attribute(line, 'IV');
        activeIv = ivHex != null ? _hexToBytes(ivHex) : null;
      } else if (line.startsWith('#EXT-X-MAP:')) {
        // fMP4 oqimi: init segmentisiz fayl umuman ochilmaydi.
        isFragmentedMp4 = true;
        final mapUri = _attribute(line, 'URI');
        if (mapUri == null) continue;
        final url = _resolveUrl(playlistUrl, mapUri);
        final mapRange = _attribute(line, 'BYTERANGE');
        if (mapRange != null) setPendingRange(mapRange);
        final (start, length) = takeRange(url);
        segments.add(
          _HlsSegment(
            url: url,
            key: activeKey,
            iv: activeKey == null ? null : (activeIv ?? _sequenceIv(0)),
            rangeStart: start,
            rangeLength: length,
          ),
        );
      } else if (!line.startsWith('#')) {
        final url = _resolveUrl(playlistUrl, line);
        final (start, length) = takeRange(url);
        segments.add(
          _HlsSegment(
            url: url,
            key: activeKey,
            iv:
                activeKey == null
                    ? null
                    : (activeIv ?? _sequenceIv(mediaSequence + mediaIndex)),
            rangeStart: start,
            rangeLength: length,
          ),
        );
        mediaIndex++;
      }
    }

    return _HlsPlaylist(
      segments: segments,
      isFragmentedMp4: isFragmentedMp4,
      totalDurationSeconds: totalDuration,
    );
  }
}
