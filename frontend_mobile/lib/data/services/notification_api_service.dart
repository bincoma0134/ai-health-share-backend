import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';

class NotificationApiService {
  static final Dio _dio = ApiClient.instance;

  // Cập nhật FCM Token lên Server
  static Future<bool> updateFcmToken(String token) async {
    try {
      final res = await _dio.post('/notifications/token', data: {'token': token});
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // Lấy danh sách thông báo từ Server
  static Future<List<dynamic>> fetchNotifications({int limit = 50}) async {
    try {
      final res = await _dio.get('/notifications', queryParameters: {'limit': limit});
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return List<dynamic>.from(res.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Đồng bộ trạng thái đã đọc của một thông báo
  static Future<bool> markAsRead(String notificationId) async {
    try {
      final res = await _dio.patch('/notifications/$notificationId/read');
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // Đồng bộ trạng thái đã đọc toàn bộ
  static Future<bool> markAllAsRead() async {
    try {
      final res = await _dio.patch('/notifications/read-all');
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // 🚀 XÁC NHẬN MÁY ĐÃ NHẬN (ACK)
  static Future<bool> sendAck(String notificationId) async {
    try {
      final res = await _dio.patch('/notifications/$notificationId/ack');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 🚀 VOUCHER DROP: Lưu voucher rơi vào ví
  static Future<bool> claimVoucher(String code) async {
    try {
      final res = await _dio.post('/vouchers/$code/claim');
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // 🚀 VOUCHER DROP: Tải danh sách public voucher để lọc
  static Future<List<dynamic>> fetchPublicVouchers() async {
    try {
      final res = await _dio.get('/vouchers/public');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return List<dynamic>.from(res.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
  
  // 🚀 VOUCHER DROP: Tải danh sách my voucher để lọc chéo
  static Future<List<dynamic>> fetchMyVouchers() async {
    try {
      final res = await _dio.get('/vouchers/me');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return List<dynamic>.from(res.data['data'] ?? []);
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}