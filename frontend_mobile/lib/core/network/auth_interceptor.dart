import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:frontend_mobile/core/network/api_client.dart';
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

  // Biến tĩnh dùng chung để chia sẻ tiến trình refresh giữa các request song song (chống race condition)
  static Future<String?>? _refreshFuture;

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    // 🛡️ CHẶN ĐỆ QUY: Nếu lỗi 401 xảy ra tại chính API refresh token, không cố cứu vãn nữa để tránh loop vô hạn
    if (err.requestOptions.path.contains('/auth/refresh')) {
      debugPrint('Refresh token thất bại ở mức mạng. Kích hoạt logout...');
      _refreshFuture = null;
      await AuthNotifier.instance.logout();
      return super.onError(err, handler);
    }

    // Xử lý khi Backend trả về mã lỗi 401 Unauthorized
    if (err.response?.statusCode == 401) {
      final refreshToken = await SecureStorageService.getRefreshToken();
      
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          // 🛡️ LOCKING MECHANISM: Bảo vệ tài nguyên song song bằng khóa chia sẻ thời gian thực
          _refreshFuture ??= () async {
            try {
              debugPrint('Token hết hạn. Đang tiến hành refresh ngầm...');
              final dio = Dio(BaseOptions(
                baseUrl: err.requestOptions.baseUrl,
                headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
              ));
              
              final refreshResponse = await dio.post(
                '/auth/refresh',
                data: {'refresh_token': refreshToken},
              );

              if (refreshResponse.statusCode == 200) {
                final newAccessToken = refreshResponse.data['access_token'];
                final newRefreshToken = refreshResponse.data['refresh_token'];
                
                // Lưu token mới xuống bộ nhớ cục bộ an toàn
                await SecureStorageService.saveToken(newAccessToken);
                if (newRefreshToken != null) {
                  await SecureStorageService.saveRefreshToken(newRefreshToken);
                }

                // 🛡️ CẬP NHẬT AN TOÀN TRÁNH CRASH: Cập nhật trạng thái RAM đồng bộ
                try {
                  await AuthNotifier.instance.updateToken(newAccessToken);
                } catch (notifierError) {
                  debugPrint('Lưu ý: Không thể gán trực tiếp AuthNotifier, hãy kiểm tra Setter hoặc định nghĩa hàm updateToken');
                }

                return newAccessToken as String?;
              }
              return null;
            } catch (e) {
              debugPrint('Lỗi phát sinh trong tiến trình refresh ngầm: $e');
              return null;
            } finally {
              // 🛡️ GIẢI PHÓNG ĐÚNG CHỖ: Chỉ cho phép dọn dẹp biến khóa sau khi toàn bộ tiến trình refresh hoàn tất
              _refreshFuture = null;
            }
          }();

          final String? freshToken = await _refreshFuture;

          if (freshToken != null && freshToken.isNotEmpty) {
            // Tái thiết lập token mới vào cấu hình Header của yêu cầu gốc
            final options = err.requestOptions;
            options.headers['Authorization'] = 'Bearer $freshToken';
            
            // 🚀 BỌC THÉP RETRY: Tạo Dio instance cô lập độc lập hoàn toàn để gửi lại request gốc,
            // tránh tuyệt đối việc đi qua chính AuthInterceptor này một lần nữa gây đệ quy chéo
            final dioRetry = Dio(BaseOptions(
              baseUrl: err.requestOptions.baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ));
            
            try {
              final retryResponse = await dioRetry.fetch(options);
              return handler.resolve(retryResponse);
            } on DioException catch (retryErr) {
              // Nếu quá trình gọi lại thất bại do lỗi mạng thông thường, chuyển tiếp lỗi đó lên UI xử lý thay vì tự ý logout
              return handler.next(retryErr);
            } catch (retryErr) {
              return handler.reject(DioException(
                requestOptions: options,
                error: retryErr,
              ));
            }
          }
        } catch (e) {
          debugPrint('Hệ thống bọc thép: Tiến trình refresh token ngầm thất bại.');
          _refreshFuture = null;
        }
      }

      // Chỉ kích hoạt Logout khi thực sự không thể lấy được Access Token mới (do Refresh Token hết hạn hoặc sai lệch)
      debugPrint('Không thể cứu vãn phiên do Refresh Token hết hạn hoặc không tồn tại. Kích hoạt logout toàn cục...');
      await AuthNotifier.instance.logout();
    }
    super.onError(err, handler);
  }
}