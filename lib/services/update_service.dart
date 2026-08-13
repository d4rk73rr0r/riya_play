import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:ota_update/ota_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riya_play/utils/app_logger.dart';

/// In-app updates from GitHub Releases.
///
/// Only useful when the APK is distributed outside Google Play — Play
/// handles its own updates and forbids this flow. Ported from the TV build,
/// which ships the same way.
class UpdateService {
  /// Release repository. Change these two if the APKs move elsewhere.
  static const String githubUser = "d4rk73rr0r";
  static const String repoName = "riyaplay-releases";

  static const String _releaseUrl =
      "https://api.github.com/repos/$githubUser/$repoName/releases/latest";

  /// Asks GitHub for the latest release and, if it is newer than what is
  /// installed, offers it. Any failure is swallowed: a missing update check
  /// must never block someone from using the app.
  static Future<void> checkUpdate(BuildContext context) async {
    if (!Platform.isAndroid) return;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http
          .get(Uri.parse(_releaseUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tag = data['tag_name'] as String? ?? '';
      // "v1.2.3" -> "1.2.3"
      final latestVersion = tag.replaceAll(RegExp(r'[^0-9.]'), '');
      if (latestVersion.isEmpty) return;

      if (!_isNewer(currentVersion, latestVersion)) return;

      final apkUrl = await _pickApk(data['assets'] as List<dynamic>? ?? []);
      if (apkUrl == null || !context.mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(version: latestVersion, url: apkUrl),
      );
    } catch (e) {
      appLogger.d('Yangilanishni tekshirishda xato: $e');
    }
  }

  /// Prefers an ABI-specific APK so the download stays small, and falls back
  /// to a universal one when the release isn't split per architecture.
  static Future<String?> _pickApk(List<dynamic> assets) async {
    var abis = <String>[];
    try {
      abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
    } catch (_) {
      // ABI aniqlanmasa, universal faylga tushamiz.
    }

    for (final abi in abis) {
      for (final asset in assets) {
        final name = (asset['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk') && name.contains(abi.toLowerCase())) {
          return asset['browser_download_url'] as String?;
        }
      }
    }

    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk') &&
          !name.contains('arm') &&
          !name.contains('x86')) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  static bool _isNewer(String current, String latest) {
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (var i = 0; i < 3; i++) {
      final cv = i < c.length ? c[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (lv > cv) return true;
      if (lv < cv) return false;
    }
    return false;
  }
}

class _UpdateDialog extends StatefulWidget {
  final String version;
  final String url;

  const _UpdateDialog({required this.version, required this.url});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = 0;
  bool _isDownloading = false;
  bool _hasError = false;
  String _status = '';

  void _startUpdate() {
    setState(() {
      _isDownloading = true;
      _hasError = false;
      _status = 'Yuklanmoqda... 0%';
    });

    try {
      OtaUpdate()
          .execute(widget.url, destinationFilename: 'riyaplay_update.apk')
          .listen((event) {
            if (!mounted) return;
            setState(() {
              switch (event.status) {
                case OtaStatus.DOWNLOADING:
                  final percent = double.tryParse(event.value ?? '0') ?? 0;
                  _progress = percent / 100;
                  _status = 'Yuklanmoqda... ${percent.toInt()}%';
                case OtaStatus.INSTALLING:
                  _progress = 1;
                  _status = 'O‘rnatilmoqda...';
                case OtaStatus.PERMISSION_NOT_GRANTED_ERROR:
                  _status =
                      'Ruxsat berilmadi. Sozlamalardan "Noma‘lum manbalar"ga '
                      'ruxsat bering.';
                  _isDownloading = false;
                  _hasError = true;
                default:
                  _status = 'Xatolik: ${event.value ?? 'noma‘lum'}';
                  _isDownloading = false;
                  _hasError = true;
              }
            });
          });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'Xatolik: $e';
        _isDownloading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Yangilanish mavjud'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Yangi versiya: ${widget.version}'),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _status,
              style: TextStyle(
                fontSize: 12,
                color: _hasError ? Colors.red : null,
              ),
            ),
          ],
          if (_isDownloading) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _progress == 0 ? null : _progress),
          ],
        ],
      ),
      actions: [
        if (!_isDownloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Keyinroq'),
          ),
        if (!_isDownloading)
          ElevatedButton(
            onPressed: _startUpdate,
            child: Text(_hasError ? 'Qayta urinish' : 'Yangilash'),
          ),
      ],
    );
  }
}
