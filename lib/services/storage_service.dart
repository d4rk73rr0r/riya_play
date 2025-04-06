import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  Future<void> saveTokenId(String tokenId) async {
    await _storage.write(key: 'token_id', value: tokenId);
  }

  Future<String?> getTokenId() async {
    return await _storage.read(key: 'token_id');
  }

  Future<void> savePhone(String phone) async {
    await _storage.write(key: 'phone', value: phone);
  }

  Future<String?> getPhone() async {
    return await _storage.read(key: 'phone');
  }

  Future<void> clear() async {
    await _storage.deleteAll();
  }
}
