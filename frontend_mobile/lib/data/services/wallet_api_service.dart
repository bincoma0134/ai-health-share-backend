import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../models/wallet_model.dart';

class WalletApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<WalletModel> getWallet() async {
    final res = await _dio.get('/partner/wallet');
    return WalletModel.fromJson(res.data);
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