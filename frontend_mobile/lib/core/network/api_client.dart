import 'package:dio/dio.dart';
import 'auth_interceptor.dart';

class ApiClient {
  static Dio get instance {
    final dio = Dio(BaseOptions(
      // Trỏ trực tiếp về localhost vì đã mở luồng adb reverse tcp:8000 tcp:8000
      baseUrl: 'http://127.0.0.1:8000', 
      connectTimeout: const Duration(milliseconds: 10000), 
      receiveTimeout: const Duration(milliseconds: 10000),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(AuthInterceptor());
    return dio;
  }
}