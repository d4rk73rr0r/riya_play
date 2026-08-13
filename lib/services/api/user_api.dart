import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// User profile and registered-device management.
class UserApi {
  static Future<bool> updateUser({
    required String fullName,
    required String username,
    required int birthDate,
    required int sex,
    required String token,
  }) async {
    const url =
        "${ApiClient.baseUrl}/v2/user/update?include=token,files,banned.reason,lastSubscribe,subscribe,tokenId";
    final deviceName = await ApiClient.getDeviceName();
    final data = {
      "full_name": fullName,
      "username": username,
      "birth_date": birthDate,
      "sex": sex,
    };
    final headers = {
      "X-Device-Name": deviceName,
      "Authorization": "Bearer $token",
    };

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'PUT',
      data: data,
      headers: headers,
    );

    if (response is! Map) return false;
    return response['success'] == true ||
        (!response.containsKey('error') && response.isNotEmpty);
  }

  static Future<Map<String, dynamic>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      throw Exception("Token topilmadi!");
    }

    const url =
        "${ApiClient.baseUrl}/v2/user/get-me?include=token,files,subscribe,lastSubscribe,tokenId,banned.reason";

    final response = await ApiClient.sendRequest(
      url: url,
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": await ApiClient.getDeviceName(),
      },
    );

    if (response['success'] == false) {
      throw Exception(response['error'] ?? "Profil ma'lumotlari yuklanmadi");
    }
    return response;
  }

  static Future<String> getCurrentDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final tokenId = prefs.getString('token_id') ?? '';
    if (tokenId.isEmpty) {
      return '';
    }
    return tokenId;
  }

  static Future<List<dynamic>> getDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return [];
    }

    const url = "${ApiClient.baseUrl}/v2/user/devices";
    final deviceName = await ApiClient.getDeviceName();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'GET',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
        "Cache-Control": "no-cache",
      },
    );

    if (response is List) {
      return response;
    } else if (response['success'] == false) {
      throw Exception(
        response['error'] ?? "Qurilmalar ro'yxatini yuklashda xatolik",
      );
    }
    return [];
  }
}
