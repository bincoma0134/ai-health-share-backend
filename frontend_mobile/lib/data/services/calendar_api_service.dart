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
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is Map<String, dynamic>) {
          return res.data['profile'] ?? res.data['data']?['profile'] ?? res.data;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 2. Hủy lịch (WAITING_PARTNER) - Trả về trạng thái xử lý logic chuẩn xác
  static Future<bool> cancelAppointment(String appointmentId) async {
    try {
      // Đồng bộ truyền thêm lý do hủy mặc định lên hệ thống Backend tương tự bản Website
      final res = await _dio.patch(
        '/appointments/$appointmentId/cancel',
        data: {'rejection_reason': 'Người dùng chủ động hủy bỏ yêu cầu'},
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('❌ LỖI HỦY LỊCH HẸN: $e');
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

  // 4. Khách xác nhận hoàn thành (SERVED) - Vá triệt để lỗi 422 nhờ bổ sung Request Body AppointmentConfirm
  static Future<bool> confirmCompletion(String appointmentId) async {
    try {
      final res = await _dio.patch(
        '/appointments/$appointmentId/user-confirm',
        data: {
          'is_satisfied': true,
          'feedback': 'Xác nhận hài lòng qua ứng dụng Flutter Mobile Client'
        },
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('❌ LỖI XÁC NHẬN GIẢI NGÂN APPOINTMENT: $e');
      return false;
    }
  }

  // 🚀 BỔ SUNG: Lấy thông tin xem trước hóa đơn kế toán (Preview Billing)
  static Future<Map<String, dynamic>?> fetchPaymentPreview(String appointmentId) async {
    try {
      final res = await _dio.get('/appointments/$appointmentId/preview');
      if (res.statusCode == 200 && res.data != null) {
        return res.data['data'] is Map<String, dynamic> ? res.data['data'] : res.data;
      }
      return null;
    } catch (e) {
      debugPrint('❌ LỖI PREVIEW HÓA ĐƠN: $e');
      return null;
    }
  }

  // 🚀 BỔ SUNG: Đối tác xác thực mã 6 số của khách hàng tại quầy (Check-in)
  static Future<Map<String, dynamic>?> partnerCheckIn(String appointmentId, String code) async {
    try {
      final res = await _dio.patch(
        '/appointments/$appointmentId/check-in',
        data: {'check_in_code': code, 'partner_notes': 'Xác nhận qua Flutter Mobile'},
      );
      if (res.statusCode == 200 && res.data != null) {
        return res.data;
      }
      return null;
    } catch (e) {
      debugPrint('❌ LỖI ĐỐI TÁC CHECK-IN: $e');
      return null;
    }
  }
}