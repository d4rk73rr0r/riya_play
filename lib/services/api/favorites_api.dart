import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Favorite-films list management.
class FavoritesApi {
  static Future<bool> addToFavorite(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/films/add-favorite?id=$filmId";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'POST',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return response is Map && response['id'] != null;
  }

  static Future<bool> removeFromFavorite(int filmId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/films/un-favorite?id=$filmId";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return response is bool && response == true;
  }

  static Future<List<dynamic>> getFavorites({int page = 1}) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return [];
    }

    final url =
        "${ApiClient.baseUrl}/v2/films/favorite?include=files,paid,tags,genres,holder.logo&sort=-id&page=$page";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
      },
    );

    return response['data'] ?? [];
  }

  static Future<bool> clearAllFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/films/favorite";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
      },
    );

    return response is bool && response == true;
  }
}
