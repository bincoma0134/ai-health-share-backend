import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'user_api_service.dart';

class AdminApiService {
  static final Dio _dio = ApiClient.instance;

  // 1. Lấy chỉ số hệ thống (Stats)
  static Future<Map<String, dynamic>?> fetchStats() async {
    try {
      final res = await _dio.get('/admin/profile-stats');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  // 2. Lấy nội dung (Videos & Posts)
  static Future<Map<String, dynamic>?> fetchContent() async {
    try {
      final res = await _dio.get('/admin/my-content');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  // 3. Đăng Bài Cộng đồng
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

  // 4. Đăng Video (Auto-Approved)
  static Future<bool> createVideo(String title, String content, String price, File videoFile) async {
    try {
      String? videoUrl = await UserApiService.uploadMedia(videoFile, 'tiktok_feeds/videos');
      if (videoUrl == null) return false;
      
      final res = await _dio.post('/tiktok/feeds', data: {
        'title': title,
        'content': content,
        'price': double.tryParse(price) ?? 0,
        'video_url': videoUrl
      });
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  // 5. Thống kê Dashboard Tổng
  static Future<Map<String, dynamic>?> fetchDashboardStats() async {
    try {
      final res = await _dio.get('/admin/dashboard-stats');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  // 6. Danh sách lệnh Rút tiền
  static Future<List<dynamic>> fetchWithdrawals() async {
    try {
      final res = await _dio.get('/admin/withdrawals');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  // 7. Xử lý lệnh Rút tiền (Duyệt/Từ chối)
  static Future<bool> processWithdrawal(String wId, String status, String adminNote) async {
    try {
      final res = await _dio.patch('/admin/withdrawals/$wId', data: {
        'status': status,
        'admin_note': adminNote,
      });
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 8. Quản lý Mạng lưới Đối tác
  static Future<List<dynamic>> fetchPartners() async {
    try {
      final res = await _dio.get('/admin/partners');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  // 9. Lấy Thống kê Kiểm duyệt (Cho Moderator)
  static Future<Map<String, dynamic>?> fetchModerationStats() async {
    try {
      final res = await _dio.get('/moderation/stats');
      if (res.statusCode == 200) return res.data['data'];
      return null;
    } catch (e) {
      return null;
    }
  }

  // 10. Lấy Hàng đợi chờ duyệt
  static Future<List<dynamic>> fetchModerationQueue() async {
    try {
      final res = await _dio.get('/moderation/queue');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  // 11. Lấy Lịch sử đã duyệt
  static Future<List<dynamic>> fetchModerationHistory() async {
    try {
      final res = await _dio.get('/moderation/history');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  // 12. Gửi Lệnh Phê duyệt / Từ chối
  static Future<bool> moderateItem(String itemType, String itemId, String action, String note) async {
    try {
      final res = await _dio.patch('/moderation/action/$itemType/$itemId', data: {
        'action': action,
        'note': note
      });
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}


