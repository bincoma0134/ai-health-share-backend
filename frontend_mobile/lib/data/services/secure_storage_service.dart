import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  
  // Các key này khớp với tư duy lưu trữ của bản Web cũ
  static const String _tokenKey = 'ai_health_token';
  static const String _roleKey = 'ai_health_role';
  static const String _nameKey = 'ai_health_name';

  // --- TOKEN ---
  static Future<void> saveToken(String token) async => await _storage.write(key: _tokenKey, value: token);
  static Future<String?> getToken() async => await _storage.read(key: _tokenKey);

  // --- ROLE (USER / PARTNER) ---
  static Future<void> saveRole(String role) async => await _storage.write(key: _roleKey, value: role.trim().toUpperCase());
  static Future<String?> getRole() async {
    final role = await _storage.read(key: _roleKey);
    return role?.trim().toUpperCase();
  }

  // --- TÊN HIỂN THỊ (FULL NAME) ---
  static Future<void> saveName(String name) async => await _storage.write(key: _nameKey, value: name);
  static Future<String?> getName() async => await _storage.read(key: _nameKey);

  // --- XÓA PHIÊN KHI LOGOUT / 401 ---
  static Future<void> clearSession() async => await _storage.deleteAll();
}