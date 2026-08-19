import 'package:riya_play/services/error_handler.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:riya_play/utils/app_logger.dart';

class TVApiService {
  static const Map<String, String> baseUrls = {
    "SalomTV": "https://spectator-api.salomtv.uz",
    "SpecUZ": "https://api.spec.uzd.udevs.io",
    "BizTV": "https://api.biztv.media",
  };

  static const Map<String, String> defaultHeaders = {
    "Accept": "application/json",
    "User-Agent": "okhttp/4.9.2",
    "Content-Type": "application/json",
  };

  static const Map<String, String> specUzHeaders = {
    "User-Agent": "Dart/3.4 (dart:io)",
    "Accept-Encoding": "gzip, deflate, br",
    "key": "false",
    "platform": "7e9217c5-a6b4-490a-9e90-dad564f39361",
    "Connection": "keep-alive",
  };

  static const Map<String, String> bizTvHeaders = {
    "Platform": "Mobile:android",
    "User-Agent":
        "Mozilla/5.0 (Linux; Android 9; SM-N975F Build/PI; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/133.0.6943.137 Mobile Safari/537.36",
    "Cache-Control": "no-cache",
    "Accept-Encoding": "gzip, deflate, br",
    "Connection": "keep-alive",
  };

  static Future<dynamic> _sendRequest({
    required String url,
    required String source,
    Map<String, String>? headers,
  }) async {
    try {
      final combinedHeaders =
          source == "SpecUZ"
              ? {...defaultHeaders, ...specUzHeaders, ...?headers}
              : source == "BizTV"
              ? {...defaultHeaders, ...bizTvHeaders, ...?headers}
              : {...defaultHeaders, ...?headers};

      final response = await http.get(Uri.parse(url), headers: combinedHeaders);

      appLogger.d("So'rov URL: $url");
      appLogger.d("Javob kodi: ${response.statusCode}");
      appLogger.d("Javob tanasi: ${utf8.decode(response.bodyBytes)}");

      if (response.statusCode == 200 || response.statusCode == 202) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        return {"success": false, "error": "Xatolik: ${response.statusCode}"};
      }
    } catch (e) {
      appLogger.d("Tarmoq xatosi: $e");
      return {"success": false, "error": "Tarmoq xatosi: $e"};
    }
  }

  static Future<List<dynamic>> getTVCategories(String source) async {
    if (source == "BizTV") {
      return []; // BizTV has no categories
    }

    final baseUrl = baseUrls[source]!;
    final url =
        source == "SalomTV"
            ? "$baseUrl/v1/tv/category?page=1&limit=100&lang=uz"
            : "$baseUrl/v1/tv/category?limit=50&page=1&search=&status=true";

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kategoriyalar yuklanmadi");
    }

    return response['categories'] as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getTVChannels({
    required String source,
    int page = 1,
    int limit = 24,
    bool status = true,
    String? categoryId,
    bool fetchAll = false, // Yangi parametr: barcha kanallarni olish uchun
  }) async {
    final baseUrl = baseUrls[source]!;
    String url;

    if (source == "BizTV") {
      if (fetchAll) {
        // Barcha kanallarni olish uchun sahifalarni iteratsiya qilamiz
        List<dynamic> allChannels = [];
        int currentPage = 1;
        const int perPage = 100; // BizTV uchun maksimal limit

        while (true) {
          url =
              "$baseUrl/api/v2/channels?per_page=$perPage&page=$currentPage&_l=uz&append=promotion,canWatch&include=file";
          final response = await _sendRequest(url: url, source: source);

          if (response['success'] == false) {
            throw ApiErrorHandler.fromResponse(response, "Kanallar yuklanmadi");
          }

          final channels =
              response["data"]
                  .map(
                    (channel) => {
                      "id": channel["id"].toString(),
                      "title_uz": channel["name"],
                      "image": channel["file"]["url"],
                      "url":
                          channel["url_1080"] ??
                          channel["url_720"] ??
                          channel["url_480"],
                    },
                  )
                  .toList();

          allChannels.addAll(channels);

          // Agar olingan kanallar soni perPage'dan kam bo'lsa, bu oxirgi sahifa
          if (channels.length < perPage) {
            break;
          }

          currentPage++;
        }

        return {"tv_channels": allChannels};
      } else {
        // Faqat bitta sahifani olish
        url =
            "$baseUrl/api/v2/channels?per_page=$limit&page=$page&_l=uz&append=promotion,canWatch&include=file";
      }
    } else if (source == "SalomTV") {
      url =
          "$baseUrl/v1/tv/channel?page=$page&limit=$limit&status=$status&lang=uz";
      if (categoryId != null && categoryId.isNotEmpty) {
        url += "&category=$categoryId";
      }
    } else {
      url =
          "$baseUrl/v1/tv/channel?search=&limit=$limit&page=$page&status=$status";
      if (categoryId != null && categoryId.isNotEmpty) {
        url += "&category=$categoryId";
      } else {
        url += "&category=";
      }
    }

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kanallar yuklanmadi");
    }

    if (source == "BizTV") {
      return {
        "tv_channels":
            response["data"]
                .map(
                  (channel) => {
                    "id": channel["id"].toString(),
                    "title_uz": channel["name"],
                    "image": channel["file"]["url"],
                    "url":
                        channel["url_1080"] ??
                        channel["url_720"] ??
                        channel["url_480"],
                  },
                )
                .toList(),
      };
    }

    return response;
  }

  static Future<Map<String, dynamic>> getChannelDetails({
    required String source,
    required String channelId,
  }) async {
    if (source != "SpecUZ") {
      return {"success": false, "error": "Faqat SpecUZ uchun ishlaydi"};
    }

    final baseUrl = baseUrls[source]!;
    final url = "$baseUrl/v1/tv/channel/$channelId";

    final response = await _sendRequest(url: url, source: source);

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Kanal detallari yuklanmadi");
    }

    return response;
  }
}
