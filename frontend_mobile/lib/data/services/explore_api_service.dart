import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/service_model.dart';

class ExploreApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<List<ServiceModel>> fetchServices() async {
    try {
      // Gọi qua ApiClient để tận dụng đường ống LAN adb reverse
      final response = await _dio.get('/services');
      
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> data = response.data['data'];
        return data.map((json) => ServiceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TẢI DỊCH VỤ KHÁM PHÁ: $e');
      return [];
    }
  }
}