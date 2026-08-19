import 'package:dio/dio.dart';
import '../../../core/network/api_client.dart';
import '../models/voucher_model.dart';

class VoucherApiService {
  static final Dio _dio = ApiClient.instance;

  // Lấy danh sách Voucher VIP đang bán trên Sàn
  static Future<List<VoucherModel>> getPublicVipVouchers() async {
    try {
      final res = await _dio.get('/vouchers/vip/public');
      if (res.statusCode == 200 && res.data != null) {
        final List<dynamic> data = res.data['data'] ?? [];
        return data.map((json) => VoucherModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // Mua Voucher bằng Điểm 1 chiều
  static Future<bool> buyVoucherWithPoints(String voucherCode) async {
    try {
      final res = await _dio.post('/vouchers/$voucherCode/buy-with-points');
      return res.statusCode == 200;
    } on DioException catch (e) {
      if (e.response != null && e.response?.data != null) {
        throw Exception(e.response?.data['detail'] ?? 'Lỗi mua voucher');
      }
      throw Exception('Không thể kết nối máy chủ');
    } catch (e) {
      throw Exception('Lỗi không xác định');
    }
  }
}