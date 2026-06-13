import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../data/services/secure_storage_service.dart';

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // Gọi hàm trung tâm để lấy đúng từ khóa 'ai_health_token' đã lưu lúc Đăng nhập
    final token = await SecureStorageService.getToken();
    
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    super.onRequest(options, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // Đồng bộ xử lý dọn dẹp phiên khi Backend trả về mã lỗi 401 Unauthorized
    if (err.response?.statusCode == 401) {
      debugPrint('Token hết hạn hoặc không hợp lệ. Đang xóa phiên...');
      await SecureStorageService.clearSession();
    }
    super.onError(err, handler);
  }
}