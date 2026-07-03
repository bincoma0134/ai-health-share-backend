import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/partner_map_model.dart';

class MapApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<List<PartnerMapModel>> fetchMapPartners() async {
    try {
      final response = await _dio.get('/map/partners');
      if (response.statusCode == 200 && response.data != null) {
        // Đồng bộ hóa với Swagger: FastAPI trả về mảng trực tiếp hoặc data object trực tiếp
        final dynamic rawData = response.data;
        final List<dynamic> dataList = (rawData is Map && rawData.containsKey('data')) 
            ? rawData['data'] 
            : (rawData is List ? rawData : []);
        return dataList.map((json) => PartnerMapModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TẢI DỮ LIỆU BẢN ĐỒ: $e');
      return [];
    }
  }
}