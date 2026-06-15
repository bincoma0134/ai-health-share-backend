import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/services/secure_storage_service.dart';
import '../../presentation/widgets/auth_guard.dart';

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Danh sách các public endpoint không được tự ý chèn token hệ thống
    final publicEndpoints = ['/auth/login', '/auth/register', '/auth/firebase'];
    
    final isPublic = publicEndpoints.any((path) => options.path.contains(path));
    
    if (!isPublic) {
      // Đọc token trực tiếp từ RAM (AuthNotifier) để tăng tốc độ
      final token = AuthNotifier.instance.token;
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Đồng bộ xử lý dọn dẹp phiên khi Backend trả về mã lỗi 401 Unauthorized
    if (err.response?.statusCode == 401) {
      debugPrint('Token hết hạn hoặc không hợp lệ. Kích hoạt logout toàn cục...');
      await AuthNotifier.instance.logout();
    }
    super.onError(err, handler);
  }
}