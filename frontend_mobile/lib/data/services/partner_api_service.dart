import 'dart:io';
import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import 'user_api_service.dart';

class PartnerApiService {
  static final Dio _dio = ApiClient.instance;

  // --- QUẢN LÝ DỊCH VỤ ---
  static Future<List<dynamic>> fetchMyServices() async {
    try {
      final res = await _dio.get('/partner/my-services');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> createService(Map<String, dynamic> payload, File? mediaFile, String mediaType) async {
    try {
      if (mediaFile != null) {
        String folder = mediaType == 'video' ? 'services/videos' : 'services/images';
        String? mediaUrl = await UserApiService.uploadMedia(mediaFile, folder);
        if (mediaUrl == null) return false;
        
        if (mediaType == 'video') payload['video_url'] = mediaUrl;
        else payload['image_url'] = mediaUrl;
      }

      final res = await _dio.post('/services', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> updateService(String id, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.patch('/partner/my-services/$id', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteService(String id) async {
    try {
      final res = await _dio.delete('/partner/my-services/$id');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // --- QUẢN LÝ STUDIO VIDEO ---
  static Future<List<dynamic>> fetchMyVideos() async {
    try {
      final res = await _dio.get('/partner/my-tiktok-feeds');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
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

  static Future<bool> updateVideo(String id, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.patch('/partner/my-tiktok-feeds/$id', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteVideo(String id) async {
    try {
      final res = await _dio.delete('/partner/my-tiktok-feeds/$id');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // ==========================================
  // QUẢN LÝ ĐƠN HÀNG VÀ LỊCH HẸN (DASHBOARD)
  // ==========================================
  static Future<List<dynamic>> fetchBookings() async {
    try {
      final res = await _dio.get('/partner/bookings');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchAppointments() async {
    try {
      final res = await _dio.get('/appointments/me');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<List<dynamic>> fetchWithdrawals() async {
    try {
      final res = await _dio.get('/partner/withdrawals');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }


  static Future<bool> requestWithdrawal(Map<String, dynamic> payload) async {
    try {
      final res = await _dio.post('/partner/withdraw', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> completeBooking(String bookingId) async {
    try {
      final res = await _dio.patch('/bookings/$bookingId/complete');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> checkInAppointment(String appointmentId, String code) async {
    try {
      final res = await _dio.patch('/appointments/$appointmentId/check-in', data: {
        'check_in_code': code,
        'partner_notes': 'Check-in từ Mobile App'
      });
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> respondAppointment(String appointmentId, Map<String, dynamic> payload) async {
    try {
      final res = await _dio.patch('/appointments/$appointmentId/respond', data: payload);
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<List<dynamic>> fetchVouchers() async {
    try {
      final res = await _dio.get('/partner/vouchers');
      if (res.statusCode == 200) return res.data['data'] ?? [];
      return [];
    } catch (e) {
      return [];
    }
  }

  static Future<bool> createVoucher(Map<String, dynamic> payload) async {
    try {
      final res = await _dio.post('/vouchers', data: payload);
      return res.statusCode == 200;
    } on DioException catch (e) {
      // Đọc và phân tách chi tiết lỗi 422 hoặc 400 từ Backend
      if (e.response != null && e.response?.data != null) {
        final detail = e.response?.data['detail'];
        if (detail is String) throw Exception(detail);
        if (detail is List && detail.isNotEmpty) throw Exception(detail[0]['msg'] ?? 'Dữ liệu không hợp lệ (422)');
        throw Exception('Lỗi từ máy chủ');
      }
      throw Exception('Không thể kết nối đến máy chủ');
    } catch (e) {
      throw Exception('Đã xảy ra lỗi không xác định');
    }
  }
}