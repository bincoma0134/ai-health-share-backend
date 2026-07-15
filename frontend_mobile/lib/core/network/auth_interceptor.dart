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
    // Xử lý khi Backend trả về mã lỗi 401 Unauthorized
    if (err.response?.statusCode == 401) {
      final refreshToken = await SecureStorageService.getRefreshToken();
      
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          debugPrint('Token hết hạn. Đang tiến hành refresh ngầm...');
          // Tạo một Dio instance mới để tránh vòng lặp Interceptor
          final dio = Dio(BaseOptions(baseUrl: err.requestOptions.baseUrl));
          
          final refreshResponse = await dio.post(
            '/auth/refresh', // API endpoint xử lý cấp lại token bên Backend
            data: {'refresh_token': refreshToken},
          );

          if (refreshResponse.statusCode == 200) {
            final newAccessToken = refreshResponse.data['access_token'];
            final newRefreshToken = refreshResponse.data['refresh_token'];
            
            // Lưu token mới xuống Local
            await SecureStorageService.saveToken(newAccessToken);
            if (newRefreshToken != null) {
              await SecureStorageService.saveRefreshToken(newRefreshToken);
            }

            // Gọi lại request ban đầu bị lỗi (401) bằng token mới vừa lấy
            final options = err.requestOptions;
            options.headers['Authorization'] = 'Bearer $newAccessToken';
            
            final retryResponse = await dio.fetch(options);
            return handler.resolve(retryResponse);
          }
        } catch (e) {
          debugPrint('Refresh token thất bại hoặc hết hạn.');
        }
      }

      debugPrint('Không thể cứu vãn phiên. Kích hoạt logout toàn cục...');
      await AuthNotifier.instance.logout();
    }
    super.onError(err, handler);
  }
}