import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:riya_play/services/storage_service.dart';

class ApiService {
  static const String baseUrl = "https://finalapi.riyaplay.uz";
  static const String salomTvBaseUrl = "https://spectator-api.salomtv.uz";

  final Dio _dio;
  final StorageService _storage;

  ApiService(this._storage)
    : _dio = Dio(
        BaseOptions(
          baseUrl: baseUrl,
          headers: {
            "Accept": "application/json",
            "User-Agent": "okhttp/4.9.2",
            "Content-Type": "application/json",
          },
        ),
      ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          debugPrint("Dio xatosi: ${error.message}");
          handler.next(error);
        },
      ),
    );
  }

  Future<bool> sendPhone(String phone) async {
    const url = "$baseUrl/v2/user/login";
    final data = {
      "phone": phone,
      "phone_hash":
          "app_signature_placeholder", // SmsAutoFill hozircha o'chirildi
    };
    final headers = {"X-Device-Name": "Android SM-N975F"};

    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );
      debugPrint("API javobi (sendPhone): ${response.data}");
      if (response.data is String && response.data == phone) {
        await _storage.savePhone(phone);
        return true;
      }
      return response.data['success'] == true;
    } catch (e) {
      debugPrint("Xatolik (sendPhone): $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> confirmSms(
    String smsCode, {
    String? tokenId,
  }) async {
    final phone = await _storage.getPhone() ?? '';
    if (phone.isEmpty) {
      return {"success": false, "message": "Telefon raqami saqlanmagan"};
    }

    final url =
        "$baseUrl/v2/user/confirm?include=token,files,banned.reason,lastSubscribe,subscribe,tokenId";
    final data = {
      "phone": phone,
      "code": smsCode,
      "device_name": "Android SM-N975F",
      if (tokenId != null) "token_id": tokenId,
    };
    final headers = {"X-Device-Name": "Android SM-N975F"};

    try {
      final response = await _dio.post(
        url,
        data: data,
        options: Options(headers: headers),
      );
      debugPrint("API javobi (confirmSms): ${response.data}");

      if (response.data is List && (response.data as List).isNotEmpty) {
        return {"success": false, "devices": response.data};
      } else if (response.data is Map<String, dynamic>) {
        final tokenData = response.data['token'];
        if (tokenData != null && tokenData['token'] != null) {
          await _storage.saveToken(tokenData['token']);
          await _storage.saveTokenId(tokenData['id']?.toString() ?? '');
          debugPrint("Token saqlandi: ${tokenData['token']}");
          return {"success": true};
        }
        return {
          "success": false,
          "message": response.data['error'] ?? "Token topilmadi",
        };
      }
      return {"success": false, "message": "Noto‘g‘ri javob formati"};
    } catch (e) {
      debugPrint("Xatolik (confirmSms): $e");
      return {"success": false, "message": e.toString()};
    }
  }

  Future<bool> updateUser({
    required String fullName,
    required String username,
    required int birthDate,
    required int sex,
  }) async {
    const url =
        "$baseUrl/v2/user/update?include=token,files,banned.reason,lastSubscribe,subscribe,tokenId";
    final data = {
      "full_name": fullName,
      "username": username,
      "birth_date": birthDate,
      "sex": sex,
    };
    final headers = {"X-Device-Name": "Android SM-N975F"};

    try {
      final response = await _dio.put(
        url,
        data: data,
        options: Options(headers: headers),
      );
      debugPrint("API javobi (updateUser): ${response.data}");
      return response.statusCode == 200 || response.data['success'] == true;
    } catch (e) {
      debugPrint("Xatolik (updateUser): $e");
      return false;
    }
  }

  Future<List<dynamic>> searchFilms(
    String query,
    int page,
    String category,
  ) async {
    String url =
        "/v2/films/search?page=$page&include=files,paid,tags,genres,holder.logo&_l=uz&_q=${Uri.encodeComponent(query)}&sort=-updated_at";
    if (category.isNotEmpty) url += "&filter[type]=$category";

    try {
      final response = await _dio.get(url);
      debugPrint("searchFilms API javobi: ${response.data}");
      return response.data['data'] ?? [];
    } catch (e) {
      debugPrint("Xatolik (searchFilms): $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getFilmDetails(int filmId) async {
    final url =
        "/v2/films/$filmId?include=banner,season_count,episode_count,languages,files,tags,country,paid,actors.files,maker.files,thriller.poster,genres,favorite,lastSeries.track,lastSeries.ads,company,gallery,type,riyaRating";

    try {
      final response = await _dio.get(url);
      debugPrint("getFilmDetails API javobi: ${response.data}");
      if (response.data['success'] == false) {
        throw Exception(
          response.data['error'] ?? "Film ma'lumotlari yuklanmadi",
        );
      }
      return response.data;
    } catch (e) {
      debugPrint("Xatolik (getFilmDetails): $e");
      throw Exception(e.toString());
    }
  }

  Future<List<dynamic>> getSeasons(int filmId) async {
    final url = "/v2/films/seasons/$filmId?filter[status]=1";

    try {
      final response = await _dio.get(url);
      return response.data as List<dynamic>;
    } catch (e) {
      debugPrint("Xatolik (getSeasons): $e");
      throw Exception("Failed to load seasons: $e");
    }
  }

  Future<List<dynamic>> getEpisodes(
    int filmId,
    int seasonId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final url =
        "/v1/series?filter[film_id]=$filmId&filter[season_id]=$seasonId&filter[status]=1&include=files,track,ads,second,screenshots.file&page=$page&per-page=$perPage";

    try {
      final response = await _dio.get(url);
      return response.data['data'] ?? [];
    } catch (e) {
      debugPrint("Xatolik (getEpisodes): $e");
      return [];
    }
  }

  Future<void> logout() async {
    final tokenId = await _storage.getTokenId() ?? '';
    final url = "/v2/user/kick-device?token_id=$tokenId";

    try {
      await _dio.delete(url);
      await _storage.clear();
    } catch (e) {
      debugPrint("Xatolik (logout): $e");
    }
  }

  Future<Map<String, dynamic>> checkUrlValidity(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(headers: {"User-Agent": "okhttp/4.9.2"}),
      );
      debugPrint(
        "checkUrlValidity: URL $url uchun status kod: ${response.statusCode}",
      );
      return {
        "isValid": response.statusCode == 200 || response.statusCode == 202,
      };
    } catch (e) {
      debugPrint("checkUrlValidity xatosi: $e");
      return {"isValid": false, "error": "Tarmoq xatosi: $e"};
    }
  }

  Future<List<dynamic>> getBanners() async {
    const url = "/v1/banners?_l=uz&sort=-id&include=files,film.company";

    try {
      final response = await _dio.get(url);
      debugPrint("getBanners API javobi: ${response.data}");
      return response.data['data'] ?? [];
    } catch (e) {
      debugPrint("Xatolik (getBanners): $e");
      return [];
    }
  }

  Future<List<dynamic>> getLatestViewed() async {
    const url =
        "/v2/films/latest-viewed?include=series,files,film.paid,film.tags,film.files,film.genres,second,screenshots.file,season&filter[status]=1&sort=-id&fields=name_uz,name_ru,name_en,id,films.id,films.name_uz,films.name_ru,films.publish_time,films.type,films.paid,films.year,films.tags.id,films.tags.title_uz,films.tags.title_en,films.files.thumbnails";

    try {
      final response = await _dio.get(
        url,
        options: Options(headers: {"X-Device-Name": "Android SM-N975F"}),
      );
      debugPrint("getLatestViewed API javobi: ${response.data}");
      if (response.data['success'] == false) {
        throw Exception(
          response.data['error'] ?? "So‘ngi ko‘rilganlar yuklanmadi",
        );
      }
      return response.data['data'] ?? [];
    } catch (e) {
      debugPrint("Xatolik (getLatestViewed): $e");
      return [];
    }
  }

  Future<List<dynamic>> getTVCategories() async {
    const url = "$salomTvBaseUrl/v1/tv/category?page=1&limit=100&lang=uz";

    try {
      final response = await _dio.get(url);
      debugPrint("getTVCategories API javobi: ${response.data}");
      if (response.data['success'] == false) {
        throw Exception(response.data['error'] ?? "Kategoriyalar yuklanmadi");
      }
      return response.data['categories'] as List<dynamic>;
    } catch (e) {
      debugPrint("Xatolik (getTVCategories): $e");
      return [];
    }
  }

  Future<Map<String, dynamic>> getTVChannels({
    int page = 1,
    int limit = 24,
    bool status = true,
    String? categoryId,
  }) async {
    String url =
        "$salomTvBaseUrl/v1/tv/channel?page=$page&limit=$limit&status=$status&lang=uz";
    if (categoryId != null && categoryId.isNotEmpty) {
      url += "&category=$categoryId";
    }

    try {
      final response = await _dio.get(url);
      debugPrint("getTVChannels API javobi: ${response.data}");
      if (response.data['success'] == false) {
        throw Exception(response.data['error'] ?? "Kanallar yuklanmadi");
      }
      return response.data;
    } catch (e) {
      debugPrint("Xatolik (getTVChannels): $e");
      throw Exception(e.toString());
    }
  }
}
