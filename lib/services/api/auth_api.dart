import 'package:shared_preferences/shared_preferences.dart';
import 'package:sms_autofill/sms_autofill.dart';
import 'api_client.dart';
import 'package:riya_play/utils/app_logger.dart';

/// Login, SMS confirmation, session/device management.
class AuthApi {
  static Future<bool> sendPhone(String phone) async {
    const url = "${ApiClient.baseUrl}/v2/user/login";
    String? appSignature = await SmsAutoFill().getAppSignature;
    final deviceName = await ApiClient.getDeviceName();
    final data = {"phone": phone, "phone_hash": appSignature};
    final headers = {"X-Device-Name": deviceName};

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'POST',
      data: data,
      headers: headers,
    );

    if (response is String && response == phone) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', phone);
      return true;
    } else if (response is Map<String, dynamic> &&
        response['success'] == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('phone', phone);
      return true;
    } else {
      return false;
    }
  }

  static Future<Map<String, dynamic>> confirmSms(
    String smsCode, {
    String? tokenId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('phone') ?? '';
    final deviceName = await ApiClient.getDeviceName();

    if (phone.isEmpty) {
      return {"success": false, "message": "Telefon raqami saqlanmagan"};
    }

    final url =
        "${ApiClient.baseUrl}/v2/user/confirm?include=token,files,banned.reason,lastSubscribe,subscribe,tokenId";
    final data = {
      "phone": phone,
      "code": smsCode,
      "device_name": deviceName,
      if (tokenId != null) "token_id": tokenId,
    };
    final headers = {"X-Device-Name": deviceName};

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'POST',
      data: data,
      headers: headers,
    );

    appLogger.d("confirmSms response: $response");

    if (response is List && response.isNotEmpty) {
      // Barcha qurilmalarni qaytarish
      return {"success": false, "devices": response};
    } else if (response is Map<String, dynamic>) {
      if (response.containsKey('token')) {
        final tokenData = response['token'];
        if (tokenData != null && tokenData['token'] != null) {
          await prefs.setString('auth_token', tokenData['token']);
          await prefs.setString('token_id', tokenData['id']?.toString() ?? '');
          return {"success": true};
        }
      }
      return {
        "success": false,
        "message": response['error'] ?? "Token topilmadi",
      };
    }

    return {"success": false, "message": "Noto‘g‘ri javob formati"};
  }

  static Future<bool> kickDevice(String tokenId) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';

    if (authToken.isEmpty) {
      appLogger.d("kickDevice: auth_token topilmadi");
      return false;
    }

    final url = "${ApiClient.baseUrl}/v2/user/kick-device?token_id=$tokenId";

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {"Authorization": "Bearer $authToken"},
    );

    if (response is List) {
      return true;
    } else if (response is Map) {
      return response['success'] != false;
    }

    appLogger.d("kickDevice: Noto‘g‘ri javob formati");
    return false;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    final tokenId = prefs.getString('token_id') ?? '';
    final url = "${ApiClient.baseUrl}/v2/user/kick-device?token_id=$tokenId";

    await ApiClient.sendRequest(
      url: url,
      method: 'DELETE',
      headers: {"Authorization": "Bearer $authToken"},
    );
    await prefs.clear();
  }

  static Future<dynamic> checkQR({required String hash, String? tokenId}) async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString('auth_token') ?? '';
    if (authToken.isEmpty) {
      return {"success": false, "error": "Auth token topilmadi"};
    }

    final deviceName = await ApiClient.getDeviceName();
    final queryParams = {
      "hash": hash,
      if (tokenId != null) "token_id": tokenId,
    };
    final url =
        Uri.parse(
          "${ApiClient.baseUrl}/v2/user/check-qr",
        ).replace(queryParameters: queryParams).toString();

    final response = await ApiClient.sendRequest(
      url: url,
      method: 'POST',
      headers: {
        "Authorization": "Bearer $authToken",
        "X-Device-Name": deviceName,
        "Cache-Control": "no-cache",
      },
      data: {"hash": hash},
    );

    return response;
  }
}
