import 'package:riya_play/services/error_handler.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Film/series catalog, search, viewing history, genres and categories.
class FilmsApi {
  static Future<List<dynamic>> searchFilms(
    String query,
    int page,
    String category,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return [];
    }

    String url =
        "${ApiClient.baseUrl}/v2/films/search?page=$page&include=files,paid,tags,genres,favorite,holder.logo&_l=uz&_q=${Uri.encodeComponent(query)}&sort=-updated_at";
    if (category.isNotEmpty) url += "&filter[type]=$category";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {"Authorization": "Bearer $authToken"},
    );

    return response['data'] ?? [];
  }

  /// Newest catalog rows, sorted by `updated_at`, for the new-content poller.
  ///
  /// Deliberately **not** authenticated: the poller also runs from the alarm
  /// isolate, where reading `auth_token` would only add a `SharedPreferences`
  /// round trip — this endpoint answers without a token. `_t` defeats the CDN
  /// cache, the same trick [getLatestViewed] uses.
  static Future<List<dynamic>> getLatestPublished({int page = 1}) async {
    final url =
        "${ApiClient.baseUrl}/v2/films/search"
        "?include=files,paid,tags,genres,holder.logo&_l=uz&_f=json"
        "&t=${DateTime.now().millisecondsSinceEpoch}"
        "&sort=-updated_at&page=$page";

    final response = await ApiClient.sendRequest(url: url);

    if (response is! Map || response['success'] == false) return [];
    final data = response['data'];
    return data is List ? data : [];
  }

  static Future<Map<String, dynamic>> getFilmDetails(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final url =
        "${ApiClient.baseUrl}/v2/films/$filmId?include=banner,season_count,episode_count,languages,files,tags,country,paid,actors.files,maker.files,thriller.poster,genres,favorite,lastSeries.track,lastSeries.ads,company,gallery,type,riyaRating";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {"Authorization": "Bearer $authToken"},
    );

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Film ma'lumotlari yuklanmadi");
    }
    return response;
  }

  static Future<List<dynamic>> getSeasons(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final url = "${ApiClient.baseUrl}/v2/films/seasons/$filmId?filter[status]=1";

    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $authToken',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as List<dynamic>;
    } else {
      throw Exception("Failed to load seasons");
    }
  }

  static Future<List<dynamic>> getEpisodes(
    int filmId,
    int seasonId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final url =
        "${ApiClient.baseUrl}/v1/series?filter[film_id]=$filmId&filter[season_id]=$seasonId&filter[status]=1&include=files,track,ads,second,screenshots.file&page=$page&per-page=$perPage&fields=id,name_ru,name_uz,name_en,status,sort,duration,screenshots.id,screenshots.thumbnails,files.thumbnails,is_last_seen";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {"Authorization": "Bearer $authToken"},
    );

    return response['data'] ?? [];
  }

  /// One episode with its `second` block, which carries where this user
  /// stopped watching. Playback position lives on the server, so a film
  /// started on the phone resumes on the TV app and survives a reinstall.
  static Future<Map<String, dynamic>> getEpisodeDetails(int episodeId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) return {};

    final url =
        "${ApiClient.baseUrl}/v1/series/$episodeId"
        "?include=track,ads,files,screenshots.file,second";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
        "Cache-Control": "no-cache",
      },
    );

    if (response is! Map<String, dynamic> || response['success'] == false) {
      return {};
    }
    return response;
  }

  /// Seconds watched, as reported by [getEpisodeDetails]. Zero when the
  /// episode was never started or the call fails — the caller then falls
  /// back to the locally stored position.
  static Future<int> getWatchedSeconds(int episodeId) async {
    try {
      final details = await getEpisodeDetails(episodeId);
      final second = details['second'];
      if (second is Map) return (second['time'] as int?) ?? 0;
      return 0;
    } catch (_) {
      return 0;
    }
  }

  /// First (and for a film, only) episode of [filmId], with its `track` so the
  /// caller also gets a stream URL.
  ///
  /// Films are series rows with a single episode, and the watch-progress
  /// endpoints key on the **episode** id. `film.lastSeries` usually carries
  /// it, but that field is missing from some payloads — then this is the only
  /// way to play the film at all. Do not use it for real series: it always
  /// returns the first episode.
  static Future<Map<String, dynamic>?> getFirstEpisode(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) return null;

    final response = await ApiClient.sendRequest(
      url:
          "${ApiClient.baseUrl}/v1/series"
          "?filter[film_id]=$filmId&per-page=1&include=track",
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
        "Cache-Control": "no-cache",
      },
    );

    if (response is! Map || response['success'] == false) return null;
    final data = response['data'];
    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map<String, dynamic>) return first;
    }
    return null;
  }

  /// Pushes the current playback position back to the server.
  static Future<bool> updateWatchProgress(int episodeId, int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) return false;

    final response = await ApiClient.sendRequest(
      url: "${ApiClient.baseUrl}/v2/films/second/$episodeId",
      method: 'POST',
      data: {"second": seconds},
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
        "Cache-Control": "no-cache",
      },
    );

    // API ba'zan yalang'och `true`, ba'zan {"success": ...} qaytaradi.
    if (response is bool) return response;
    return response is Map && response['success'] != false;
  }

  /// Films the given actor appears in.
  static Future<Map<String, dynamic>> getActorFilms(
    int actorId, {
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';

    final url =
        "${ApiClient.baseUrl}/v2/films/actor/$actorId"
        "?include=files,paid,tags,likesCount,genres,holder.logo"
        "&filter[status]=1&sort=-id&page=$page&per-page=$perPage";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
        "Cache-Control": "no-cache",
      },
    );

    return {'data': response['data'] ?? [], '_meta': response['_meta'] ?? {}};
  }

  static Future<Map<String, dynamic>> checkUrlValidity(String url) async {
    try {
      final response = await http.head(
        Uri.parse(url),
        headers: {"User-Agent": "okhttp/4.9.2"},
      );

      if (response.statusCode == 200 || response.statusCode == 202) {
        return {"isValid": true};
      } else {
        return {
          "isValid": false,
          "error": "URL ishlamayapti, status kod: ${response.statusCode}",
        };
      }
    } catch (e) {
      return {"isValid": false, "error": "Tarmoq xatosi: $e"};
    }
  }

  static Future<List<dynamic>> getBanners() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return [];
    }

    final url =
        "${ApiClient.baseUrl}/v1/banners?_l=uz&sort=-id&include=files,film.company";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {"Authorization": "Bearer $authToken"},
    );

    return response['data'] ?? [];
  }

  static Future<Map<String, dynamic>> getLatestViewed({
    int page = 1,
    int perPage = 20,
    bool isAll = false,
    String fields =
        'name_uz,name_ru,name_en,id,films.id,films.name_uz,films.name_ru,films.publish_time,films.type,films.paid,films.year,films.tags.id,films.tags.title_uz,films.tags.title_en,films.files.thumbnails',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return {'data': [], '_meta': {}};
    }

    final queryParams = {
      'include':
          'series,files,film.paid,film.tags,film.files,film.genres,second,screenshots.file,season',
      'filter[status]': '1',
      // `-id` yozuv qachon yaratilganini bildiradi, oxirgi marta qachon
      // ko'rilganini emas — eski filmni qayta ko'rsangiz ham ro'yxat oxirida
      // qolib ketardi. TV ilovasi ham `-updated_at` ishlatadi.
      'sort': '-updated_at',
      'fields': fields,
      if (isAll) 'is_all': '1',
      if (isAll) 'page': page.toString(),
      if (isAll) 'per_page': perPage.toString(),
      '_t':
          DateTime.now().millisecondsSinceEpoch.toString(), // Dinamik parametr
    };

    final url =
        Uri.parse(
          '${ApiClient.baseUrl}/v2/films/latest-viewed',
        ).replace(queryParameters: queryParams).toString();

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
        "Cache-Control": "no-cache",
      },
    );

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "So‘ngi ko‘rilganlar yuklanmadi");
    }

    return {
      'data': response['data'] ?? [],
      '_meta':
          response['_meta'] ??
          {
            'totalCount': 0,
            'pageCount': 1,
            'currentPage': page,
            'perPage': perPage,
          },
    };
  }

  static Future<bool> removeFromLatestViewed(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/user/last-viewed/$filmId";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
        "Cache-Control": "no-cache",
      },
    );

    return response is Map && response['status'] == 1;
  }

  static Future<bool> clearLatestViewed() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/user/last-viewed";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
        "Cache-Control": "no-cache",
      },
    );

    return response is Map && response['status'] == 1;
  }

  static Future<Map<String, dynamic>> getWatchHistory({int page = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    if (authToken.isEmpty) {
      return {'data': [], 'meta': {}};
    }

    final url =
        "${ApiClient.baseUrl}/v2/user/watch-history?include=files&sort=-updated_at&page=$page";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
        "Cache-Control": "no-cache",
      },
    );

    if (response['success'] == false) {
      throw ApiErrorHandler.fromResponse(response, "Ko'rishlar tarixi yuklanmadi");
    }
    return {'data': response['data'] ?? [], 'meta': response['_meta'] ?? {}};
  }

  static Future<Map<String, dynamic>> getRecommendedFilms({
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    final url =
        "${ApiClient.baseUrl}/v2/films/recommended?include=files,tags,genres,holder.logo&sort=-id&filter[status]=1&page=$page&per-page=$perPage";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return {'data': response['data'] ?? [], 'meta': response['_meta'] ?? {}};
  }

  static Future<List<dynamic>> getGenresPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    final url =
        "${ApiClient.baseUrl}/v1/genres?filter[status]=1&per-page=30&sort=sort&include=photo";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return response['data'] ?? [];
  }

  static Future<List<dynamic>> getAllGenres() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    final url =
        "${ApiClient.baseUrl}/v1/genres?include=photo&sort=sort&filter[status]=1&per-page=50";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return response['data'] ?? [];
  }

  static Future<Map<String, dynamic>> getFilmsByGenre({
    required int genreId,
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    final url =
        "${ApiClient.baseUrl}/v2/films/by-genre/$genreId?filer[films.status]=1&include=files,paid,tags,genres,holder.logo&page=$page&per-page=$perPage&sort=-id";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return {'data': response['data'] ?? [], '_meta': response['_meta'] ?? {}};
  }

  static Future<Map<String, dynamic>> getCategories({
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    if (authToken.isEmpty) {
      return {'data': [], 'meta': {}};
    }

    final url =
        "${ApiClient.baseUrl}/v1/categories?filter[status]=1&include=films.files,films.tags,films.genres,&filter[show_in_home]=1&sort=-id&fields=id,title_uz,films.id,films.name_uz,films.type,films.year,films.tags.title_uz,films.files.thumbnails&page=$page&per-page=$perPage";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return {'data': response['data'] ?? [], 'meta': response['meta'] ?? {}};
  }

  static Future<Map<String, dynamic>> getFilmsByCategory({
    required int categoryId,
    int page = 1,
    int perPage = 20,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    if (authToken.isEmpty) {
      return {'data': [], 'meta': {}};
    }

    final url =
        "${ApiClient.baseUrl}/v2/films/by-category/$categoryId?include=files,tags,genres&per-page=$perPage&sort=-id&page=$page&sort=-updated_at";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return {'data': response['data'] ?? [], 'meta': response['meta'] ?? {}};
  }
}
