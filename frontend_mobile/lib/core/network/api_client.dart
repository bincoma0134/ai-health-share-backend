import 'package:dio/dio.dart';
import 'auth_interceptor.dart';

class ApiClient {
  static Dio get instance {
    final dio = Dio(BaseOptions(
      // ĐỒNG BỘ RELEASE: Trỏ trực tiếp về Server Deploy thực tế của hệ thống để Tester bên ngoài load được dữ liệu
      baseUrl: 'https://ai-health-share-backend.onrender.com', 
      connectTimeout: const Duration(milliseconds: 10000), 
      receiveTimeout: const Duration(milliseconds: 10000),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(AuthInterceptor());
    return dio;
  }
}