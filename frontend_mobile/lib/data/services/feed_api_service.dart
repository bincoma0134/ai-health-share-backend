import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/video_model.dart';

class FeedApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<List<VideoModel>> fetchFeeds() async {
    try {
      debugPrint('Đang gọi API lấy Video...');
      final response = await _dio.get('/tiktok/feeds');

      if (response.statusCode == 200) {
        // Cấu trúc từ Swagger của cậu: {"status": "success", "data": [...]}
        if (response.data is Map<String, dynamic> && response.data['status'] == 'success') {
          final List<dynamic> dataList = response.data['data'];
          
          debugPrint('Đã tải thành công ${dataList.length} video.');
          return dataList.map((json) => VideoModel.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI NẠP VIDEO: $e');
      return [];
    }
  }
}