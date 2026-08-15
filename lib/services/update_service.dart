import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:riya_play/theme_provider.dart';
import 'package:riya_play/utils/app_logger.dart';

/// In-app updates from GitHub Releases.
///
/// The app is distributed outside Google Play, so nothing updates it on its
/// own. GitHub's `releases/latest` endpoint is the source of truth: it
/// already skips drafts and pre-releases, so a release only reaches users
/// once it is published properly.
class UpdateService {
  /// Release repository. Change these two if the APKs move elsewhere.
  static const String githubUser = "d4rk73rr0r";
  static const String repoName = "rplay-releases";

  static const String releasesUrl =
      "https://api.github.com/repos/$githubUser/$repoName/releases/latest";

  /// GitHub rejects requests without a User-Agent, and the JSON shape is
  /// pinned with an explicit Accept header.
  static const Map<String, String> _headers = {
    'User-Agent': 'riya_play-updater',
    'Accept': 'application/vnd.github+json',
  };

  /// "Keyinroq" bosilgan bo'lsa, shu seansda boshqa so'ralmaydi. Qo'lda
  /// tekshirish bu bayroqni chetlab o'tadi.
  static bool _declinedThisSession = false;

  /// Ikkita oyna birdan ochilib qolmasin (masalan, ishga tushish tekshiruvi
  /// va qo'lda tekshirish bir vaqtda tugasa).
  static bool _dialogOpen = false;

  /// Ilova ochilganda jimgina tekshiradi. Xatolik bo'lsa hech narsa
  /// ko'rsatilmaydi — yangilanish tekshiruvi ilovadan foydalanishga
  /// halaqit bermasligi kerak.
  static Future<void> checkOnStartup(BuildContext context) async {
    if (!Platform.isAndroid || _declinedThisSession || _dialogOpen) return;

    final outcome = await fetchLatest();
    if (!context.mounted) return;
    if (outcome case UpdateAvailable(:final info)) {
      await _showUpdateDialog(context, info);
    } else if (outcome case UpdateCheckFailed(:final message)) {
      appLogger.d('Yangilanishni tekshirish muvaffaqiyatsiz: $message');
    }
  }

  /// Profil ekranidagi "Yangilanishni tekshirish". Ishga tushish
  /// tekshiruvidan farqi: natija har doim ko'rsatiladi — yangilanish yo'q
  /// bo'lsa ham, xato bo'lsa ham.
  static Future<void> checkManually(BuildContext context) async {
    if (!Platform.isAndroid) {
      _showMessage(context, "Yangilanish faqat Android'da mavjud");
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CheckingDialog(),
    );

    final outcome = await fetchLatest();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // Kutish oynasi
    if (!context.mounted) return;

    switch (outcome) {
      case UpdateAvailable(:final info):
        await _showUpdateDialog(context, info);
      case UpdateUpToDate(:final version):
        _showMessage(context, "Ilova eng so'nggi versiyada ($version)");
      case UpdateCheckFailed(:final message):
        _showMessage(context, message);
    }
  }

  /// So'nggi relizni o'qiydi va joriy versiya bilan solishtiradi.
  ///
  /// Hech qachon `throw` qilmaydi — barcha nosozliklar [UpdateCheckFailed]
  /// sifatida, foydalanuvchiga ko'rsatsa bo'ladigan xabar bilan qaytadi.
  static Future<UpdateCheckOutcome> fetchLatest() async {
    final String currentName;
    try {
      currentName = (await PackageInfo.fromPlatform()).version;
    } catch (e) {
      return UpdateCheckFailed("Ilova versiyasini aniqlab bo'lmadi: $e");
    }
    // Debug qurilmada versionName "1.0.1-debug" bo'ladi — raqamli qismi
    // olinadi.
    final current = AppVersion.parse(currentName);
    if (current == null) {
      return UpdateCheckFailed("Ilova versiyasi noto'g'ri: $currentName");
    }

    http.Response response;
    try {
      response = await http
          .get(Uri.parse(releasesUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      return const UpdateCheckFailed("Internetga ulanib bo'lmadi");
    } on TimeoutException {
      return const UpdateCheckFailed("GitHub javob bermadi, qayta urinib ko'ring");
    } catch (e) {
      return UpdateCheckFailed("Tarmoq xatosi: $e");
    }

    if (response.statusCode == 404) {
      return const UpdateCheckFailed("Reliz topilmadi");
    }
    if (response.statusCode == 403 &&
        response.headers['x-ratelimit-remaining'] == '0') {
      return const UpdateCheckFailed(
        "GitHub so'rovlar chegarasiga yetildi, birozdan keyin urinib ko'ring",
      );
    }
    if (response.statusCode != 200) {
      return UpdateCheckFailed(
        "GitHub xatosi (${response.statusCode})",
      );
    }

    final Map<String, dynamic> data;
    try {
      final decoded = json.decode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckFailed("Reliz ma'lumoti noto'g'ri");
      }
      data = decoded;
    } catch (e) {
      return const UpdateCheckFailed("Reliz ma'lumotini o'qib bo'lmadi");
    }

    final tag = (data['tag_name'] as String? ?? '').trim();
    final latest = AppVersion.parse(tag);
    if (latest == null) {
      return UpdateCheckFailed("Reliz versiyasi noto'g'ri: ${tag.isEmpty ? '—' : tag}");
    }

    // Joriy versiya yangiroq bo'lishi ham mumkin (masalan, qo'lda yig'ilgan
    // build) — bunda ham "eng so'nggi versiyadasiz" deymiz.
    if (latest.compareTo(current) <= 0) {
      return UpdateUpToDate(currentName);
    }

    final assets = data['assets'];
    final apk = await _pickApk(assets is List ? assets : const []);
    if (apk == null) {
      return const UpdateCheckFailed("Relizda APK fayli topilmadi");
    }

    return UpdateAvailable(
      UpdateInfo(
        version: latest.toString(),
        tagName: tag,
        notes: (data['body'] as String? ?? '').trim(),
        apkUrl: apk.url,
        apkBytes: apk.size,
      ),
    );
  }

  /// Qurilma arxitekturasiga mos APK afzal ko'riladi (yuklama kichikroq
  /// bo'ladi), topilmasa universal fayl olinadi.
  static Future<_ApkAsset?> _pickApk(List<dynamic> assets) async {
    final apks = <_ApkAsset>[];
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = (asset['name'] as String? ?? '');
      final url = asset['browser_download_url'] as String? ?? '';
      if (!name.toLowerCase().endsWith('.apk') || url.isEmpty) continue;
      apks.add(
        _ApkAsset(
          name: name,
          url: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    if (apks.isEmpty) return null;

    var abis = <String>[];
    try {
      abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      // ABI aniqlanmasa, universal faylga tushamiz.
    }

    for (final abi in abis) {
      final match = _firstWhereOrNull(
        apks,
        (a) => a.name.toLowerCase().contains(abi.toLowerCase()),
      );
      if (match != null) return match;
    }

    final universal = _firstWhereOrNull(
      apks,
      (a) => a.name.toLowerCase().contains('universal'),
    );
    if (universal != null) return universal;

    // ABI belgisi umuman yo'q fayl — odatda bitta umumiy APK.
    final plain = _firstWhereOrNull(apks, (a) {
      final n = a.name.toLowerCase();
      return !n.contains('arm') && !n.contains('x86');
    });
    return plain ?? apks.first;
  }

  static _ApkAsset? _firstWhereOrNull(
    List<_ApkAsset> items,
    bool Function(_ApkAsset) test,
  ) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  static Future<void> _showUpdateDialog(
    BuildContext context,
    UpdateInfo info,
  ) async {
    if (_dialogOpen) return;
    _dialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(info: info),
      );
    } finally {
      _dialogOpen = false;
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Reliz haqida pleerga/oynaga kerak bo'ladigan ma'lumot.
class UpdateInfo {
  final String version;
  final String tagName;
  final String notes;
  final String apkUrl;
  final int apkBytes;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.apkUrl,
    required this.apkBytes,
  });

  String get readableSize {
    if (apkBytes <= 0) return '';
    final mb = apkBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

sealed class UpdateCheckOutcome {
  const UpdateCheckOutcome();
}

class UpdateAvailable extends UpdateCheckOutcome {
  final UpdateInfo info;
  const UpdateAvailable(this.info);
}

class UpdateUpToDate extends UpdateCheckOutcome {
  final String version;
  const UpdateUpToDate(this.version);
}

class UpdateCheckFailed extends UpdateCheckOutcome {
  final String message;
  const UpdateCheckFailed(this.message);
}

class _ApkAsset {
  final String name;
  final String url;
  final int size;

  const _ApkAsset({required this.name, required this.url, required this.size});
}

/// Nuqta bilan ajratilgan versiya raqami, ixtiyoriy build raqami bilan
/// ("v1.2.3", "1.2.3", "1.2.3+7", "1.0.1-debug").
///
/// Satr sifatida solishtirish yaramaydi: "1.10.0" < "1.9.0" bo'lib chiqadi.
class AppVersion implements Comparable<AppVersion> {
  final List<int> parts;
  final int build;

  const AppVersion(this.parts, this.build);

  static AppVersion? parse(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // "v1.2.3+7-debug" -> core "1.2.3", build "7"
    final match = RegExp(r'(\d+(?:\.\d+)*)(?:\+(\d+))?').firstMatch(text);
    if (match == null) return null;

    final parts =
        match
            .group(1)!
            .split('.')
            .map((e) => int.tryParse(e) ?? 0)
            .toList(growable: false);
    if (parts.isEmpty) return null;

    return AppVersion(parts, int.tryParse(match.group(2) ?? '') ?? 0);
  }

  @override
  int compareTo(AppVersion other) {
    final length = parts.length > other.parts.length
        ? parts.length
        : other.parts.length;
    for (var i = 0; i < length; i++) {
      final a = i < parts.length ? parts[i] : 0;
      final b = i < other.parts.length ? other.parts[i] : 0;
      if (a != b) return a.compareTo(b);
    }
    return build.compareTo(other.build);
  }

  @override
  String toString() =>
      build > 0 ? '${parts.join('.')}+$build' : parts.join('.');
}

class _CheckingDialog extends StatelessWidget {
  const _CheckingDialog();

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    return AlertDialog(
      backgroundColor: themeProvider.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      content: Row(
        children: [
          CircularProgressIndicator(color: themeProvider.accentColor),
          const SizedBox(width: 20),
          const Expanded(child: Text('Yangilanish tekshirilmoqda...')),
        ],
      ),
    );
  }
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  StreamSubscription<OtaEvent>? _subscription;
  double _progress = 0;
  bool _isWorking = false;
  bool _hasError = false;
  String _status = '';

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _startUpdate() {
    setState(() {
      _isWorking = true;
      _hasError = false;
      _progress = 0;
      _status = 'Yuklanmoqda... 0%';
    });

    try {
      _subscription = OtaUpdate()
          .execute(
            widget.info.apkUrl,
            destinationFilename: 'riyaplay_update.apk',
          )
          .listen(_onEvent, onError: _onStreamError);
    } catch (e) {
      _fail('Yangilashni boshlab bo‘lmadi: $e');
    }
  }

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        final percent = double.tryParse(event.value ?? '0') ?? 0;
        setState(() {
          _progress = percent / 100;
          _status = 'Yuklanmoqda... ${percent.toInt()}%';
        });
      case OtaStatus.INSTALLING:
        setState(() {
          _progress = 1;
          _status = 'O‘rnatish oynasi ochildi';
        });
      case OtaStatus.INSTALLATION_DONE:
        setState(() => _status = 'O‘rnatildi');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        _fail(
          'Ruxsat berilmadi. Sozlamalardan ushbu ilovaga "Noma‘lum '
          'ilovalarni o‘rnatish" ruxsatini bering.',
        );
      case OtaStatus.ALREADY_RUNNING_ERROR:
        _fail('Yuklash allaqachon boshlangan');
      case OtaStatus.DOWNLOAD_ERROR:
        _fail('Yuklab olishda xato: ${event.value ?? 'noma‘lum'}');
      case OtaStatus.CHECKSUM_ERROR:
        _fail('Fayl buzilgan, qaytadan yuklang');
      case OtaStatus.INSTALLATION_ERROR:
        _fail('O‘rnatib bo‘lmadi: ${event.value ?? 'noma‘lum'}');
      case OtaStatus.CANCELED:
        _fail('Yuklash bekor qilindi');
      case OtaStatus.INTERNAL_ERROR:
        _fail('Xatolik: ${event.value ?? 'noma‘lum'}');
    }
  }

  void _onStreamError(Object error) {
    if (!mounted) return;
    _fail('Xatolik: $error');
  }

  void _fail(String message) {
    appLogger.d('OTA: $message');
    if (!mounted) return;
    setState(() {
      _status = message;
      _isWorking = false;
      _hasError = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final info = widget.info;

    return PopScope(
      // Yuklash ketayotganda tasodifan yopilib qolmasin.
      canPop: !_isWorking,
      child: AlertDialog(
        backgroundColor: themeProvider.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Yangi versiya mavjud'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.readableSize.isEmpty
                  ? 'Versiya ${info.version}'
                  : 'Versiya ${info.version} · ${info.readableSize}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: themeProvider.accentColor,
              ),
            ),
            if (info.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: SingleChildScrollView(
                  child: Text(
                    info.notes,
                    style: TextStyle(
                      fontSize: 13,
                      color: themeProvider.subTextColor,
                    ),
                  ),
                ),
              ),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 12,
                  color: _hasError ? Colors.redAccent : themeProvider.subTextColor,
                ),
              ),
            ],
            if (_isWorking) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _progress == 0 ? null : _progress,
                color: themeProvider.accentColor,
              ),
            ],
          ],
        ),
        actions: [
          if (!_isWorking)
            TextButton(
              onPressed: () {
                UpdateService._declinedThisSession = true;
                Navigator.pop(context);
              },
              child: const Text('Keyinroq'),
            ),
          if (!_isWorking)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: _startUpdate,
              child: Text(_hasError ? 'Qayta urinish' : 'Yangilash'),
            ),
        ],
      ),
    );
  }
}
