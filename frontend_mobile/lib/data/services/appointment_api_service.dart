import '../../../core/network/api_client.dart';

class AppointmentApiService {
  
  // 🚀 ĐỒNG BỘ LUỒNG TẠO LỊCH HẸN KHỚP BACKEND (DỨT ĐIỂM LỖI 404)
  static Future<bool> createAppointmentRequest(Map<String, dynamic> payload) async {
    try {
      final res = await ApiClient.instance.post('/appointments/request', data: payload);
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  // Luồng lấy ví voucher cá nhân (Dùng endpoint /vouchers/me chuẩn hóa)
  static Future<List<dynamic>> getMyVoucherWallet() async {
    try {
      final response = await ApiClient.instance.get('/vouchers/me');
      if (response.statusCode == 200) {
        if (response.data is List) {
          return response.data;
        } else if (response.data is Map) {
          return response.data['data'] ?? response.data['vouchers'] ?? response.data['items'] ?? [];
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}