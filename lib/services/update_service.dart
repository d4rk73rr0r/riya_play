import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// API'ning anonim chegarasi — bitta IP uchun soatiga 60 so'rov. Mobil
  /// operatorlar minglab abonentni bitta tashqi IP ortida ushlaydi, shuning
  /// uchun chegara tez tugaydi. Atom lentasi oddiy sayt sifatida beriladi va
  /// bu chegaraga kirmaydi — 403 kelganda shunga tushamiz.
  static const String atomUrl =
      "https://github.com/$githubUser/$repoName/releases.atom";

  /// Flutter `--split-per-abi` bilan yig'ilgan fayl nomlari. Atom lentasida
  /// asset ro'yxati yo'q, shuning uchun havola shu qolipdan tuziladi va
  /// mavjudligi HEAD so'rovi bilan tekshiriladi.
  static String _splitApkUrl(String tag, String abi) =>
      "https://github.com/$githubUser/$repoName/releases/download/$tag/app-$abi-release.apk";

  /// Ishga tushishdagi tekshiruv shu oraliqdan tez-tez so'ramaydi. Bu ham
  /// chegarani tejaydi: ilova kuniga o'n marta ochilsa ham GitHub'ga bir
  /// necha marta murojaat qilinadi.
  static const Duration _startupCheckInterval = Duration(hours: 6);
  static const String _lastCheckKey = 'ota_last_check_at';

  /// Foydalanuvchi o'rnatishga yuborgan oxirgi reliz tegi. Agar reliz ichidagi
  /// APK'ning `versionName` i teg bilan mos kelmasa (masalan, `pubspec.yaml`
  /// yangilanmasdan yig'ilgan bo'lsa), o'rnatishdan keyin ham ilova o'zini
  /// eski versiya deb biladi va har safar yana "yangilanish bor" deb turadi.
  /// Shu tegni eslab qolib, avtomatik so'rashni to'xtatamiz — qo'lda
  /// tekshirish baribir ko'rsatadi.
  static const String _installedTagKey = 'ota_installed_tag';

  /// GitHub rejects requests without a User-Agent, and the JSON shape is
  /// pinned with an explicit Accept header.
  static const Map<String, String> _headers = {
    'User-Agent': 'riya_play-updater',
    'Accept': 'application/vnd.github+json',
  };

  /// Yuklab olingan APK nomi — plagin uni `files/ota_update/` ichiga yozadi.
  static const String _apkFileName = 'riyaplay_update.apk';

  /// Qurilma bilan aloqa: o'rnatish ruxsatini tekshirish va sozlamalar
  /// ekranini ochish. Yuklab olishlar uchun allaqachon ochilgan kanal.
  static const MethodChannel _nativeChannel = MethodChannel(
    'uz.mrlg.riyaplay/media_store',
  );

  /// Ilova APK o'rnatishni boshlay oladimi.
  ///
  /// Manifestdagi `REQUEST_INSTALL_PACKAGES` yetarli emas: API 26 dan boshlab
  /// foydalanuvchi shu ilova uchun "Noma'lum ilovalarni o'rnatish"ni alohida
  /// yoqishi kerak va uni istalgan vaqtda o'chirib ham qo'yishi mumkin.
  static Future<bool> canInstallPackages() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _nativeChannel.invokeMethod<bool>('canInstallPackages') ??
          false;
    } catch (e) {
      appLogger.d('O‘rnatish ruxsatini tekshirib bo‘lmadi: $e');
      return false;
    }
  }

  /// Shu ilova uchun "Noma'lum ilovalarni o'rnatish" ekranini ochadi.
  static Future<void> openInstallPermissionSettings() async {
    try {
      await _nativeChannel.invokeMethod<void>('openInstallPermissionSettings');
    } catch (e) {
      appLogger.d('Sozlamalar ekranini ochib bo‘lmadi: $e');
    }
  }

  /// O'rnatishga uzatilgan eski APK'ni o'chiradi.
  ///
  /// Fayl ~45 MB va ilovaning ichki xotirasida yotadi. O'rnatish boshlangan
  /// zahoti o'chirib bo'lmaydi — tizim o'rnatuvchisi uni o'sha paytda o'qiydi
  /// — shuning uchun keyingi ishga tushishda tozalanadi.
  static Future<void> _cleanupDownloadedApk() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final apk = File('${dir.path}/ota_update/$_apkFileName');
      if (await apk.exists()) {
        await apk.delete();
        appLogger.d('Eski yangilanish APK fayli o‘chirildi');
      }
    } catch (e) {
      appLogger.d('APK faylini o‘chirib bo‘lmadi: $e');
    }
  }

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
    if (!await _startupIntervalElapsed()) return;

    final outcome = await fetchLatest();
    await _rememberCheckTime();
    if (!context.mounted) return;
    if (outcome case UpdateAvailable(:final info)) {
      if (await _alreadyInstalled(info.tagName)) {
        appLogger.d(
          'Yangilanish so\'ralmadi: ${info.tagName} allaqachon o\'rnatilgan '
          '(reliz ichidagi versiya teg bilan mos emas)',
        );
        await _cleanupDownloadedApk();
        return;
      }
      if (!context.mounted) return;
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
    await _rememberCheckTime();
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
      return const UpdateCheckFailed(
        "GitHub javob bermadi, qayta urinib ko'ring",
      );
    } catch (e) {
      return UpdateCheckFailed("Tarmoq xatosi: $e");
    }

    if (response.statusCode == 404) {
      return const UpdateCheckFailed("Reliz topilmadi");
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      // Chegara — API o'rniga atom lentasidan o'qiymiz.
      appLogger.d(
        'GitHub API chegarasi (${response.statusCode}), atom lentasi',
      );
      return _fetchFromAtom(current, currentName);
    }
    if (response.statusCode != 200) {
      return UpdateCheckFailed("GitHub xatosi (${response.statusCode})");
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
      return UpdateCheckFailed(
        "Reliz versiyasi noto'g'ri: ${tag.isEmpty ? '—' : tag}",
      );
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
        notes: _plainText(data['body'] as String? ?? ''),
        apkUrl: apk.url,
        apkBytes: apk.size,
        sha256: apk.sha256,
      ),
    );
  }

  /// API chegarasi tugaganda ishlatiladigan zaxira yo'l.
  ///
  /// `releases.atom` oddiy sayt manzili — u yerda so'rov chegarasi yo'q,
  /// lekin asset ro'yxati ham yo'q: faqat teg va reliz izohi bor. Shuning
  /// uchun APK havolasi `--split-per-abi` qolipidan tuzilib, HEAD so'rovi
  /// bilan tekshiriladi.
  static Future<UpdateCheckOutcome> _fetchFromAtom(
    AppVersion current,
    String currentName,
  ) async {
    http.Response response;
    try {
      response = await http
          .get(
            Uri.parse(atomUrl),
            headers: const {'User-Agent': 'riya_play-updater'},
          )
          .timeout(const Duration(seconds: 15));
    } on SocketException {
      return const UpdateCheckFailed("Internetga ulanib bo'lmadi");
    } on TimeoutException {
      return const UpdateCheckFailed(
        "GitHub javob bermadi, qayta urinib ko'ring",
      );
    } catch (e) {
      return UpdateCheckFailed("Tarmoq xatosi: $e");
    }

    if (response.statusCode != 200) {
      return const UpdateCheckFailed(
        "GitHub so'rovlar chegarasiga yetildi, birozdan keyin urinib ko'ring",
      );
    }

    final body = utf8.decode(response.bodyBytes);
    final tag =
        RegExp(r'releases/tag/([^"<]+)').firstMatch(body)?.group(1)?.trim() ??
        '';
    final latest = AppVersion.parse(tag);
    if (latest == null) {
      return const UpdateCheckFailed("Reliz ma'lumotini o'qib bo'lmadi");
    }
    if (latest.compareTo(current) <= 0) {
      return UpdateUpToDate(currentName);
    }

    final apk = await _findSplitApk(tag);
    if (apk == null) {
      return const UpdateCheckFailed("Relizda APK fayli topilmadi");
    }

    return UpdateAvailable(
      UpdateInfo(
        version: latest.toString(),
        tagName: tag,
        notes: _plainTextFromAtom(body),
        apkUrl: apk.url,
        apkBytes: apk.size,
      ),
    );
  }

  /// Qurilma ABI'lari bo'yicha `app-<abi>-release.apk` havolasini sinab
  /// ko'radi. HEAD 200 qaytargan birinchisi olinadi.
  static Future<_ApkAsset?> _findSplitApk(String tag) async {
    var abis = <String>[];
    try {
      abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      abis = const ['arm64-v8a', 'armeabi-v7a'];
    }

    for (final abi in abis) {
      final url = _splitApkUrl(tag, abi);
      try {
        final head = await http
            .head(
              Uri.parse(url),
              headers: const {'User-Agent': 'riya_play-updater'},
            )
            .timeout(const Duration(seconds: 10));
        if (head.statusCode == 200) {
          return _ApkAsset(
            name: 'app-$abi-release.apk',
            url: url,
            size: int.tryParse(head.headers['content-length'] ?? '') ?? 0,
          );
        }
      } catch (_) {
        // Keyingi ABI bilan urinib ko'ramiz.
      }
    }
    return null;
  }

  /// Atom lentasidagi birinchi yozuvning HTML izohini oddiy matnga aylantirib
  /// beradi — dialogda teglar ko'rinib qolmasin.
  static String _plainTextFromAtom(String body) {
    final content =
        RegExp(
          r'<content[^>]*>([\s\S]*?)</content>',
        ).firstMatch(body)?.group(1) ??
        '';
    return _plainText(content);
  }

  /// Reliz izohidan HTML teglarini olib tashlaydi.
  ///
  /// GitHub API `body` maydonini qanday yozilgan bo'lsa shunday qaytaradi —
  /// reliz izohiga `<p>...</p>` yozilsa, teglar dialogda ko'rinib qolardi.
  ///
  /// Avval HTML belgilari ochiladi, keyin teglar olib tashlanadi. Tartib
  /// muhim: atom lentasida teglar `&lt;p&gt;` ko'rinishida keladi, shuning
  /// uchun teskari tartibda ular ochilib, ekranda ko'rinib qolardi.
  static String _plainText(String raw) {
    final unescaped = raw
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&amp;', '&');
    return unescaped
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Ishga tushishdagi tekshiruv oralig'i o'tdimi.
  static Future<bool> _startupIntervalElapsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_lastCheckKey);
      if (last == null) return true;
      final elapsed = DateTime.now().millisecondsSinceEpoch - last;
      return elapsed >= _startupCheckInterval.inMilliseconds;
    } catch (_) {
      return true;
    }
  }

  /// Shu teg uchun o'rnatish allaqachon boshlanganmi.
  static Future<bool> _alreadyInstalled(String tag) async {
    if (tag.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_installedTagKey) == tag;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _rememberInstalledTag(String tag) async {
    if (tag.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_installedTagKey, tag);
    } catch (_) {}
  }

  static Future<void> _rememberCheckTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Vaqtni saqlay olmasak, keyingi ochilishda yana tekshiriladi — zarari
      // yo'q.
    }
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
      // GitHub `digest` ni `sha256:<hex>` shaklida beradi; `ota_update` esa
      // faqat hex kutadi. Maydon eski relizlarda yo'q bo'lishi mumkin.
      final digest = asset['digest'] as String? ?? '';
      final sha256 =
          digest.startsWith('sha256:') ? digest.substring(7).trim() : null;
      apks.add(
        _ApkAsset(
          name: name,
          url: url,
          size: (asset['size'] as num?)?.toInt() ?? 0,
          sha256: (sha256 != null && sha256.isNotEmpty) ? sha256 : null,
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Reliz haqida pleerga/oynaga kerak bo'ladigan ma'lumot.
class UpdateInfo {
  final String version;
  final String tagName;
  final String notes;
  final String apkUrl;
  final int apkBytes;

  /// Yuklab olingandan keyin `ota_update` tekshiradigan SHA-256.
  ///
  /// Faqat GitHub API yo'lida mavjud: reliz asset'i `digest` maydonini olib
  /// keladi. Atom zaxira yo'lida `null`, ya'ni tekshiruvsiz o'rnatiladi —
  /// bu avvalgi xatti-harakat, shuning uchun regressiya emas.
  final String? sha256;

  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.notes,
    required this.apkUrl,
    required this.apkBytes,
    this.sha256,
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

  /// GitHub asset'ining SHA-256 yig'indisi, `sha256:` prefiksisiz.
  ///
  /// Atom zaxira yo'lida `null` bo'ladi — u yerda asset ro'yxati umuman yo'q.
  final String? sha256;

  const _ApkAsset({
    required this.name,
    required this.url,
    required this.size,
    this.sha256,
  });
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

    final parts = match
        .group(1)!
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList(growable: false);
    if (parts.isEmpty) return null;

    return AppVersion(parts, int.tryParse(match.group(2) ?? '') ?? 0);
  }

  @override
  int compareTo(AppVersion other) {
    final length =
        parts.length > other.parts.length ? parts.length : other.parts.length;
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

class _UpdateDialogState extends State<_UpdateDialog>
    with WidgetsBindingObserver {
  StreamSubscription<OtaEvent>? _subscription;
  double _progress = 0;
  bool _isWorking = false;
  bool _hasError = false;
  String _status = '';

  /// Foydalanuvchi sozlamalar ekraniga yuborildi va qaytishini kutyapmiz.
  bool _awaitingPermission = false;

  /// O'rnatish ruxsati yo'q — tugma "Ruxsat berish"ga aylanadi.
  bool _needsPermission = false;

  /// Tizim o'rnatgichi ochildi. `ota_update` bu nuqtadan keyin hech qanday
  /// hodisa yubormaydi: foydalanuvchi "Отмена" bossa ham stream jim qoladi.
  /// Shu sababli dialog o'zi yopiladigan holatga o'tishi kerak.
  bool _installerLaunched = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    super.dispose();
  }

  /// Sozlamalardan qaytgach ruxsat yoqilganini tekshiramiz.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_awaitingPermission) return;
    _awaitingPermission = false;
    _resumeAfterSettings();
  }

  Future<void> _resumeAfterSettings() async {
    final granted = await UpdateService.canInstallPackages();
    if (!mounted) return;
    if (granted) {
      setState(() {
        _needsPermission = false;
        _hasError = false;
        _status = '';
      });
      _download();
    } else {
      setState(() {
        _needsPermission = true;
        _hasError = true;
        _status =
            'Ruxsat hali berilmagan. "Ruxsat berish"ni bosib, ushbu ilova '
            'uchun "Noma‘lum ilovalarni o‘rnatish"ni yoqing.';
      });
    }
  }

  /// "Yangilash" bosilganda: avval o'rnatish ruxsati, keyin yuklab olish.
  ///
  /// Ruxsatni yuklab olishdan OLDIN so'raymiz — 45 MB ni yuklab olib,
  /// oxirida "ruxsat yo'q" deyish foydalanuvchining trafigini behuda sarflaydi.
  Future<void> _startUpdate() async {
    setState(() {
      _hasError = false;
      _status = 'Tekshirilmoqda...';
    });

    final granted = await UpdateService.canInstallPackages();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _needsPermission = true;
        _status =
            'Yangilanishni o‘rnatish uchun ushbu ilovaga "Noma‘lum '
            'ilovalarni o‘rnatish" ruxsatini berish kerak.';
      });
      return;
    }

    _download();
  }

  /// Sozlamalar ekranini ochadi; qaytgandan keyin [didChangeAppLifecycleState]
  /// ruxsatni qayta tekshiradi va yuklab olishni o'zi davom ettiradi.
  Future<void> _requestPermission() async {
    setState(() {
      _hasError = false;
      _status = 'Sozlamalar ochilmoqda...';
    });
    _awaitingPermission = true;
    await UpdateService.openInstallPermissionSettings();
  }

  void _download() {
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
            destinationFilename: UpdateService._apkFileName,
            // Yig'indi bo'lmasa uzatilmaydi: `ota_update` ni bo'sh satr bilan
            // chaqirish har doim CHECKSUM_ERROR beradi.
            sha256checksum: widget.info.sha256,
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
        UpdateService._rememberInstalledTag(widget.info.tagName);
        setState(() {
          _progress = 1;
          _isWorking = false;
          _installerLaunched = true;
          _status = 'O‘rnatish oynasi ochildi';
        });
      case OtaStatus.INSTALLATION_DONE:
        setState(() => _status = 'O‘rnatildi');
      case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
        // Ruxsat yuklab olish davomida o'chirib qo'yilgan bo'lishi mumkin.
        setState(() => _needsPermission = true);
        _fail(
          'Ruxsat berilmadi. "Ruxsat berish"ni bosib, ushbu ilova uchun '
          '"Noma‘lum ilovalarni o‘rnatish"ni yoqing.',
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
              _ReleaseNotes(
                notes: info.notes,
                color: themeProvider.subTextColor,
              ),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                _status,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      _hasError ? Colors.redAccent : themeProvider.subTextColor,
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
          // O'rnatgich ochilgach yagona mantiqiy amal — dialogni yopish.
          // Qayta yuklab olish 45 MB trafikni behuda sarflaydi.
          if (_installerLaunched)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Yopish'),
            ),
          if (!_isWorking && !_installerLaunched)
            TextButton(
              onPressed: () {
                UpdateService._declinedThisSession = true;
                Navigator.pop(context);
              },
              child: const Text('Keyinroq'),
            ),
          if (!_isWorking && !_installerLaunched)
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeProvider.accentColor,
                foregroundColor: Colors.white,
              ),
              onPressed: _needsPermission ? _requestPermission : _startUpdate,
              child: Text(
                _needsPermission
                    ? 'Ruxsat berish'
                    : (_hasError ? 'Qayta urinish' : 'Yangilash'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Reliz izohi. Matn baland bo'lsa 160 px lik oynada aylantiriladi.
///
/// Aylantirish ilgari ham ishlagan, lekin buni ko'rsatadigan hech narsa yo'q
/// edi: matn oxirgi qatorda kesilgandek ko'rinardi. Shuning uchun doimiy
/// ko'rinadigan `Scrollbar` va pastki qorayish qo'shildi — ikkalasi ham
/// pastda yana matn borligini bildiradi va oxiriga yetganda yo'qoladi.
class _ReleaseNotes extends StatefulWidget {
  final String notes;
  final Color color;

  const _ReleaseNotes({required this.notes, required this.color});

  @override
  State<_ReleaseNotes> createState() => _ReleaseNotesState();
}

class _ReleaseNotesState extends State<_ReleaseNotes> {
  static const double _maxHeight = 160;
  static const double _fadeHeight = 28;

  final ScrollController _controller = ScrollController();
  bool _hasMoreBelow = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncFade());
  }

  void _syncFade() {
    if (!_controller.hasClients) return;
    final more = _controller.position.extentAfter > 4;
    if (more != _hasMoreBelow && mounted) {
      setState(() => _hasMoreBelow = more);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFade);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _maxHeight),
      child: Stack(
        children: [
          Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _controller,
              // Scrollbar matn ustiga tushmasin.
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                widget.notes,
                style: TextStyle(fontSize: 13, color: widget.color),
              ),
            ),
          ),
          if (_hasMoreBelow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  height: _fadeHeight,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.0),
                        // Dialog sirti qoramtir shisha, shuning uchun
                        // qorayish unga qo'shilib ketadi.
                        Colors.black.withOpacity(0.65),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
