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
        headers: {'Content-Type': 'application/json'},
      ));
      _instance!.interceptors.add(AuthInterceptor());
    }
    return _instance!;
  }
}