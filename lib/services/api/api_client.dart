import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';

/// Shared HTTP plumbing used by every domain-specific `*Api` class
/// (base URL, default headers, the request wrapper, and device naming).
class ApiClient {
  static const String baseUrl = "https://finalapi.riyaplay.uz";
  static const Map<String, String> defaultHeaders = {
    "Accept": "application/json",
    "User-Agent": "okhttp/4.9.2",
    "Content-Type": "application/json",
  };

  static Future<dynamic> sendRequest({
    required String url,
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) async {
    try {
      final response =
          method == 'POST'
              ? await http.post(
                Uri.parse(url),
                headers: {...defaultHeaders, ...?headers},
                body: jsonEncode(data),
              )
              : method == 'DELETE'
              ? await http.delete(
                Uri.parse(url),
                headers: {...defaultHeaders, ...?headers},
              )
              : method == 'PUT'
              ? await http.put(
                Uri.parse(url),
                headers: {...defaultHeaders, ...?headers},
                body: jsonEncode(data),
              )
              : await http.get(
                Uri.parse(url),
                headers: {...defaultHeaders, ...?headers},
              );

      final decodedBody = utf8.decode(response.bodyBytes);
      if (response.statusCode == 200 || response.statusCode == 202) {
        final decodedJson = jsonDecode(decodedBody);
        return decodedJson;
      } else {
        return {
          "success": false,
          "statusCode": response.statusCode,
          "error": "Xatolik: ${response.statusCode}",
        };
      }
    } catch (e) {
      return {"success": false, "error": "Tarmoq xatosi: $e"};
    }
  }

  static Future<String> getDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return "${androidInfo.brand} ${androidInfo.model}";
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      return iosInfo.utsname.machine;
    }
    return "Unknown Device";
  }
}
