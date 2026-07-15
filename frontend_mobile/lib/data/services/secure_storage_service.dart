import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage();
  
  // Các key này khớp với tư duy lưu trữ của bản Web cũ
  static const String _tokenKey = 'ai_health_token';
  static const String _roleKey = 'ai_health_role';
  static const String _nameKey = 'ai_health_name';
  static const String _refreshTokenKey = 'ai_health_refresh_token';
  static const String _fcmTokenKey = 'fcm_device_token';

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

  // --- REFRESH TOKEN ---
  static Future<void> saveRefreshToken(String token) async => await _storage.write(key: _refreshTokenKey, value: token);
  static Future<String?> getRefreshToken() async => await _storage.read(key: _refreshTokenKey);

  // --- FCM DEVICE TOKEN ---
  static Future<void> saveFcmToken(String token) async => await _storage.write(key: _fcmTokenKey, value: token);
  static Future<String?> getFcmToken() async => await _storage.read(key: _fcmTokenKey);

  // --- XÓA PHIÊN KHI LOGOUT / 401 ---
  static Future<void> clearSession() async {
    // Chỉ xóa các phiên làm việc bảo mật
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _roleKey);
    await _storage.delete(key: _nameKey);
    await _storage.delete(key: _refreshTokenKey);
    // GIỮ LẠI fcm_device_token để nhận thông báo đẩy kể cả khi chưa đăng nhập
  }
}