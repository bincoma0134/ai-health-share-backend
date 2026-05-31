import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'user_api_service.dart';

class CreatorApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<Map<String, dynamic>?> fetchStats() async {
    try {
      final res = await _dio.get('/creator/stats');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<Map<String, dynamic>?> fetchContent() async {
    try {
      final res = await _dio.get('/creator/content');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> createVideo(Map<String, dynamic> payload, File videoFile) async {
    try {
      String? videoUrl = await UserApiService.uploadMedia(videoFile, 'tiktok_feeds/videos');
      if (videoUrl == null) return false;
      
      payload['video_url'] = videoUrl;
      final res = await _dio.post('/tiktok/feeds', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> createPost(String content, File? imageFile) async {
    try {
      String? imageUrl;
      if (imageFile != null) {
        imageUrl = await UserApiService.uploadMedia(imageFile, 'community_posts/images');
        if (imageUrl == null) return false;
      }
      final res = await _dio.post('/community/posts', data: {
        'content': content,
        'image_url': imageUrl
      });
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}