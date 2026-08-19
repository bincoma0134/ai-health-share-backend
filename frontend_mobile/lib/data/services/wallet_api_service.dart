import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../models/wallet_model.dart';

class WalletApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<WalletModel> getWallet() async {
    // 🚀 NÂNG CẤP TƯƠNG THÍCH CHÉO: Lấy tổng hợp tiền từ ví và điểm từ Profile
    try {
      double pBalance = 0.0;
      double wBalance = 0.0;
      double wPending = 0.0;
      
      // 1. Quét ví đối tác (Lấy tiền)
      try {
        final resWallet = await _dio.get('/partner/wallet');
        wBalance = (resWallet.data['balance'] ?? 0).toDouble();
        wPending = (resWallet.data['pending_amount'] ?? 0).toDouble();
      } catch (_) {}

      // 2. Quét profile (Lấy ví điểm 1 chiều)
      try {
        final resProfile = await _dio.get('/user/profile');
        if (resProfile.data != null && resProfile.data['data'] != null && resProfile.data['data']['profile'] != null) {
          pBalance = (resProfile.data['data']['profile']['points_balance'] ?? 0).toDouble();
        }
      } catch (_) {}

      return WalletModel(balance: wBalance, pendingAmount: wPending, pointsBalance: pBalance);
    } catch (e) {
      return WalletModel(balance: 0.0, pendingAmount: 0.0, pointsBalance: 0.0);
    }
  }

  // 🚀 TÍCH HỢP PHASE 2: Endpoint sinh link thanh toán nạp điểm
  static Future<Response?> topupPoints(double amountVnd) async {
    try {
      return await _dio.post('/user/points/topup', data: {"amount_vnd": amountVnd});
    } catch (e) {
      return null;
    }
  }

  static Future<bool> requestWithdrawal(double amount, String bank, String account) async {
    try {
      await _dio.post('/partner/withdrawals', data: {
        "amount": amount,
        "bank_name": bank,
        "bank_account_number": account
      });
      return true;
    } catch (e) { return false; }
  }
}