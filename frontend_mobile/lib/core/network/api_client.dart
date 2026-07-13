import 'package:dio/dio.dart';
import 'auth_interceptor.dart';

class ApiClient {
  static Dio? _instance;

  static Dio get instance {
    if (_instance == null) {
      _instance = Dio(BaseOptions(
        baseUrl: 'https://ai-health-share-backend.onrender.com', 
        connectTimeout: const Duration(milliseconds: 30000), 
        receiveTimeout: const Duration(milliseconds: 30000),
        sendTimeout: const Duration(milliseconds: 300000),
      ));
      _instance!.interceptors.add(AuthInterceptor());
    }
    return _instance!;
  }

  // 🚀 HARD RESET SESSION: Xóa sạch instance cũ để ép chu kỳ sau tạo mới hoàn toàn
  static void clearSession() {
    if (_instance != null) {
      _instance!.options.headers.clear();
      _instance = null;
    }
  }
}