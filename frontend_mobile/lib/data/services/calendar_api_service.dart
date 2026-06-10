import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/appointment_model.dart';

class CalendarApiService {
  static final Dio _dio = ApiClient.instance;

  // 1. Lấy danh sách lịch hẹn
  static Future<List<AppointmentModel>> fetchAppointments() async {
    try {
      final res = await _dio.get('/appointments/me');
      // 🚀 ĐÃ SỬA: Bọc lót bóc tách mảng động linh hoạt cho cả Map và List để triệt tiêu lỗi lệch cấu trúc dữ liệu
      if (res.statusCode == 200) {
        List<dynamic> data = [];
        if (res.data is Map && res.data['data'] != null) {
          data = res.data['data'];
        } else if (res.data is List) {
          data = res.data;
        }
        // Trả về danh sách Map thô để giao diện tự do tính toán giá gạch ngang linh hoạt
        return data.map((e) => AppointmentModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TẢI LỊCH HẸN: $e');
      return [];
    }
  }

  // Thêm vào cuối class CalendarApiService
  static Future<Map<String, dynamic>?> fetchUserProfile() async {
    try {
      final res = await _dio.get('/user/profile');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['data']['profile'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 2. Hủy lịch (WAITING_PARTNER)
  static Future<bool> cancelAppointment(String appointmentId) async {
    try {
      final res = await _dio.patch('/appointments/$appointmentId/cancel');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // 3. Thanh toán qua PayOS (PENDING_PAYMENT)
  static Future<String?> getPaymentUrl(String appointmentId) async {
    try {
      final res = await _dio.post('/appointments/$appointmentId/pay');
      if (res.statusCode == 200) return res.data['checkout_url'];
      return null;
    } catch (e) {
      return null;
    }
  }

  // 4. Khách xác nhận hoàn thành (SERVED)
  static Future<bool> confirmCompletion(String appointmentId) async {
    try {
      final res = await _dio.patch('/appointments/$appointmentId/user-confirm');
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}


