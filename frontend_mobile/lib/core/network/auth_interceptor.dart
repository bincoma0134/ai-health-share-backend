import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/foundation.dart';

class AuthInterceptor extends Interceptor {
  final _storage = const FlutterSecureStorage();
  // Đồng bộ tên key với localStorage của bản Web
  static const String tokenKey = 'ai-health-token'; 

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: tokenKey);
    
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Tái hiện logic xóa token khi lỗi từ AuthContext.tsx
    if (err.response?.statusCode == 401) {
      debugPrint('Token hết hạn hoặc không hợp lệ. Đang xóa phiên...');
      await _storage.delete(key: tokenKey);
      // Hệ thống sẽ không tự động nhảy trang để tránh gắt luồng xem Video của Khách
    }
    super.onError(err, handler);
  }
}