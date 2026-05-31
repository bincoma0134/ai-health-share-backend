import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/partner_map_model.dart';

class MapApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<List<PartnerMapModel>> fetchMapPartners() async {
    try {
      final response = await _dio.get('/map/partners');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> data = response.data['data'];
        return data.map((json) => PartnerMapModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TẢI DỮ LIỆU BẢN ĐỒ: $e');
      return [];
    }
  }
}