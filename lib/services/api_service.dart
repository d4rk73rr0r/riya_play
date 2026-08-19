import 'api/api_client.dart';
import 'api/auth_api.dart';
import 'api/user_api.dart';
import 'api/films_api.dart';
import 'api/favorites_api.dart';

/// Facade over the domain-specific `*Api` classes in `lib/services/api/`,
/// kept so every existing `ApiService.xxx(...)` call site across the app
/// keeps working unchanged while the implementation lives in focused files
/// (auth, user, films, favorites) instead of one 800-line class.
class ApiService {
  static const String baseUrl = ApiClient.baseUrl;
  static const Map<String, String> defaultHeaders = ApiClient.defaultHeaders;

  static Future<String> getCurrentDeviceName() => ApiClient.getDeviceName();

  static Future<dynamic> sendRequest({
    required String url,
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, String>? headers,
  }) => ApiClient.sendRequest(
    url: url,
    method: method,
    data: data,
    headers: headers,
  );

  // Auth
  static Future<bool> sendPhone(String phone) => AuthApi.sendPhone(phone);

  static Future<Map<String, dynamic>> confirmSms(
    String smsCode, {
    String? tokenId,
  }) => AuthApi.confirmSms(smsCode, tokenId: tokenId);

  static Future<bool> kickDevice(String tokenId) =>
      AuthApi.kickDevice(tokenId);

  static Future<void> logout() => AuthApi.logout();

  static Future<dynamic> checkQR({required String hash, String? tokenId}) =>
      AuthApi.checkQR(hash: hash, tokenId: tokenId);

  // User
  static Future<bool> updateUser({
    required String fullName,
    required String username,
    required int birthDate,
    required int sex,
    required String token,
  }) => UserApi.updateUser(
    fullName: fullName,
    username: username,
    birthDate: birthDate,
    sex: sex,
    token: token,
  );

  static Future<Map<String, dynamic>> getUserProfile() =>
      UserApi.getUserProfile();

  static Future<String> getCurrentDeviceId() => UserApi.getCurrentDeviceId();

  static Future<List<dynamic>> getDevices() => UserApi.getDevices();

  // Films / catalog
  static Future<List<dynamic>> searchFilms(
    String query,
    int page,
    String category,
  ) => FilmsApi.searchFilms(query, page, category);

  static Future<Map<String, dynamic>> getFilmDetails(int filmId) =>
      FilmsApi.getFilmDetails(filmId);

  static Future<List<dynamic>> getSeasons(int filmId) =>
      FilmsApi.getSeasons(filmId);

  static Future<List<dynamic>> getEpisodes(
    int filmId,
    int seasonId, {
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getEpisodes(filmId, seasonId, page: page, perPage: perPage);

  static Future<Map<String, dynamic>> checkUrlValidity(String url) =>
      FilmsApi.checkUrlValidity(url);

  static Future<Map<String, dynamic>> getEpisodeDetails(int episodeId) =>
      FilmsApi.getEpisodeDetails(episodeId);

  static Future<Map<String, dynamic>?> getFirstEpisode(int filmId) =>
      FilmsApi.getFirstEpisode(filmId);

  static Future<int> getWatchedSeconds(int episodeId) =>
      FilmsApi.getWatchedSeconds(episodeId);

  static Future<bool> updateWatchProgress(int episodeId, int seconds) =>
      FilmsApi.updateWatchProgress(episodeId, seconds);

  static Future<Map<String, dynamic>> getActorFilms(
    int actorId, {
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getActorFilms(actorId, page: page, perPage: perPage);

  static Future<List<dynamic>> getBanners() => FilmsApi.getBanners();

  static Future<List<dynamic>> getLatestPublished({int page = 1}) =>
      FilmsApi.getLatestPublished(page: page);

  static Future<Map<String, dynamic>> getLatestViewed({
    int page = 1,
    int perPage = 20,
    bool isAll = false,
    String fields =
        'name_uz,name_ru,name_en,id,films.id,films.name_uz,films.name_ru,films.publish_time,films.type,films.paid,films.year,films.tags.id,films.tags.title_uz,films.tags.title_en,films.files.thumbnails',
  }) => FilmsApi.getLatestViewed(
    page: page,
    perPage: perPage,
    isAll: isAll,
    fields: fields,
  );

  static Future<bool> removeFromLatestViewed(int filmId) =>
      FilmsApi.removeFromLatestViewed(filmId);

  static Future<bool> clearLatestViewed() => FilmsApi.clearLatestViewed();

  static Future<Map<String, dynamic>> getWatchHistory({int page = 1}) =>
      FilmsApi.getWatchHistory(page: page);

  static Future<Map<String, dynamic>> getRecommendedFilms({
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getRecommendedFilms(page: page, perPage: perPage);

  static Future<List<dynamic>> getGenresPreview() =>
      FilmsApi.getGenresPreview();

  static Future<List<dynamic>> getAllGenres() => FilmsApi.getAllGenres();

  static Future<Map<String, dynamic>> getFilmsByGenre({
    required int genreId,
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getFilmsByGenre(genreId: genreId, page: page, perPage: perPage);

  static Future<Map<String, dynamic>> getCategories({
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getCategories(page: page, perPage: perPage);

  static Future<Map<String, dynamic>> getFilmsByCategory({
    required int categoryId,
    int page = 1,
    int perPage = 20,
  }) => FilmsApi.getFilmsByCategory(
    categoryId: categoryId,
    page: page,
    perPage: perPage,
  );

  // Favorites
  static Future<bool> addToFavorite(int filmId) =>
      FavoritesApi.addToFavorite(filmId);

  static Future<bool> removeFromFavorite(int filmId) =>
      FavoritesApi.removeFromFavorite(filmId);

  static Future<List<dynamic>> getFavorites({int page = 1}) =>
      FavoritesApi.getFavorites(page: page);

  static Future<bool> clearAllFavorites() => FavoritesApi.clearAllFavorites();
}
