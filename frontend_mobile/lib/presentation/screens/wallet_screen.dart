import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/services/wallet_api_service.dart';
import '../../../core/network/api_client.dart';
import '../widgets/auth_guard.dart';
import '../widgets/guest_profile_view.dart';
import '../widgets/app_toast.dart';
import 'package:go_router/go_router.dart';
import 'profile/user_wellness_profile_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();

  // Đóng gói BottomSheet rút tiền thành hàm Static public để Wellness Profile có thể tái sử dụng dễ dàng
  static void showPremiumWithdrawalSheet(BuildContext context, {required VoidCallback onSuccess}) {
    final amountCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final accountNumCtrl = TextEditingController();
    final accountNameCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(color: Color(0xFFF4F7F6), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(top: 12, bottom: 20), decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(10)))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Rút tiền về Ngân hàng', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2ECEB))), child: IconButton(icon: const Icon(Icons.close_rounded, color: Color(0xFF617D79), size: 20), onPressed: () => Navigator.pop(context))),
                    ],
                  ),
                ),
                Container(height: 1, width: double.infinity, margin: const EdgeInsets.only(top: 16, bottom: 24), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, const Color(0xFFE2ECEB).withOpacity(0.5), Colors.transparent]))),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSheetField(amountCtrl, 'Số tiền muốn rút (Tối thiểu 50,000đ)', Icons.monetization_on_rounded, isNumber: true),
                        const SizedBox(height: 16),
                        _buildSheetField(bankNameCtrl, 'Tên Ngân hàng (VD: Vietcombank)', Icons.account_balance_rounded),
                        const SizedBox(height: 16),
                        _buildSheetField(accountNumCtrl, 'Số tài khoản', Icons.numbers_rounded, isNumber: true),
                        const SizedBox(height: 16),
                        _buildSheetField(accountNameCtrl, 'Tên chủ tài khoản (Không dấu)', Icons.person_rounded),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity, height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A3A35), foregroundColor: Colors.white, elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: isSubmitting ? null : () async {
                              final amount = double.tryParse(amountCtrl.text) ?? 0;
                              if (amount < 50000) { AppToast.show(context: context, message: 'Số tiền rút tối thiểu là 50,000đ', isSuccess: false); return; }
                              if (bankNameCtrl.text.isEmpty || accountNumCtrl.text.isEmpty || accountNameCtrl.text.isEmpty) {
                                AppToast.show(context: context, message: 'Vui lòng điền đủ thông tin ngân hàng!', isSuccess: false); return;
                              }

                              setModalState(() => isSubmitting = true);
                              try {
                                // 🚀 AUTO-ROUTING THÔNG MINH: Đẩy thẳng vào API dùng chung mới cho User/Creator/Partner
                                final res = await ApiClient.instance.post('/user/withdraw', data: {
                                  "amount": amount, "bank_name": bankNameCtrl.text, "account_number": accountNumCtrl.text, "account_name": accountNameCtrl.text
                                });
                                if (res.statusCode == 200) {
                                  Navigator.pop(context);
                                  onSuccess();
                                  AppToast.show(context: context, message: 'Yêu cầu rút tiền đang được Kiểm duyệt viên xử lý', isSuccess: true);
                                } else {
                                  AppToast.show(context: context, message: 'Thất bại: Số dư không đủ hoặc lỗi hệ thống.', isSuccess: false);
                                }
                              } catch (e) {
                                // Fallback tự chữa cháy nếu User là Partner thì API /user/withdraw sẽ báo 403, tự động chuyển về /partner/withdraw
                                try {
                                  final resPartner = await ApiClient.instance.post('/partner/withdraw', data: {
                                    "amount": amount, "bank_name": bankNameCtrl.text, "account_number": accountNumCtrl.text, "account_name": accountNameCtrl.text
                                  });
                                  if (resPartner.statusCode == 200) {
                                    Navigator.pop(context);
                                    onSuccess();
                                    AppToast.show(context: context, message: 'Yêu cầu rút tiền đang được Kiểm duyệt viên xử lý', isSuccess: true);
                                    return;
                                  }
                                } catch (_) {}
                                AppToast.show(context: context, message: 'Lỗi đường truyền hệ thống.', isSuccess: false);
                              } finally {
                                if (context.mounted) setModalState(() => isSubmitting = false);
                              }
                            },
                            child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('XÁC NHẬN RÚT TIỀN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
      )
    );
  }

  static Widget _buildSheetField(TextEditingController ctrl, String label, IconData icon, {bool isNumber = false}) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2ECEB)), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))]),
      child: TextField(
        controller: ctrl, keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label, labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 13),
          prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 20),
          border: InputBorder.none, contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }
}

class _WalletScreenState extends State<WalletScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  bool _isLoading = true;
  double _balance = 0.0;
  List<dynamic> _history = [];
  Map<String, dynamic>? _rewardStatus;

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    setState(() => _isLoading = true);
    try {
      final walletRes = await WalletApiService.getWallet();
      if (walletRes != null) {
        _balance = walletRes.balance;
      }
      
      // Auto-Routing: Thử nạp lịch sử rút tiền theo từng phân hệ Role (Dò tìm)
      dynamic historyRes;
      try {
        historyRes = await ApiClient.instance.get('/partner/withdrawals');
      } catch (_) {
        try { historyRes = await ApiClient.instance.get('/creator/withdrawals'); } catch (_) {}
      }
      
      if (historyRes != null && historyRes.statusCode == 200) {
        _history = historyRes.data['data'] ?? [];
      }
      
      try {
        final rewardRes = await ApiClient.instance.get('/user/wellness/reward-status');
        if (rewardRes.statusCode == 200) {
          _rewardStatus = rewardRes.data['data'];
        }
      } catch (_) {}
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => Scaffold(
        backgroundColor: const Color(0xFFF4F7F6),
        appBar: AppBar(title: const Text("Ví Bảo Chứng", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.bold)), backgroundColor: Colors.transparent, elevation: 0, centerTitle: true),
        body: GuestProfileView(onSuccess: () { AuthNotifier.instance.refresh(); _loadWalletData(); }),
      ),
      builder: (context, token, userId) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
          appBar: AppBar(
            backgroundColor: Colors.transparent, elevation: 0, centerTitle: true,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20), onPressed: () => context.pop()),
            title: const Text("Ví Bảo Chứng", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.bold)),
          ),
          body: _isLoading 
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)))
            : RefreshIndicator(
                onRefresh: _loadWalletData,
                color: const Color(0xFF80BF84),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // THẺ SỐ DƯ PREMIUM (Glassmorphism Gradient)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2A5951)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 24, offset: const Offset(0, 12))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 16)),
                                    const SizedBox(width: 10),
                                    Text("SỐ DƯ KHẢ DỤNG", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                                  ],
                                ),
                                const Icon(Icons.shield_rounded, color: Color(0xFF80BF84), size: 20),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Text(_currencyFormat.format(_balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity, height: 48,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                                onPressed: () => WalletScreen.showPremiumWithdrawalSheet(context, onSuccess: _loadWalletData),
                                child: const Text("YÊU CẦU RÚT TIỀN", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // WIDGET TIÊU DÙNG THÔNG MINH (SHORTCUT GAMIFICATION)
                      if (_rewardStatus != null && !(_rewardStatus!['has_claimed'] ?? false))
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserWellnessProfileScreen()));
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.5)),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1A3A35).withOpacity(0.05),
                                  blurRadius: 10, offset: const Offset(0, 4),
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                const Text("💎", style: TextStyle(fontSize: 18)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Tiến độ nhận thưởng 500k",
                                        style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 4),
                                      Stack(
                                        children: [
                                          Container(
                                            height: 6, width: double.infinity,
                                            decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: ((_rewardStatus!['total_spent'] ?? 0) / (_rewardStatus!['target_amount'] ?? 5000000)).clamp(0.0, 1.0),
                                            child: Container(
                                              height: 6,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF48C9B0)]),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFF80BF84), size: 14),
                              ],
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 32),
                      
                      const Text("Lịch sử giao dịch", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      
                      if (_history.isEmpty)
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(32),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2ECEB))),
                          child: const Column(
                            children: [
                              Icon(Icons.history_rounded, size: 48, color: Color(0xFFE2ECEB)),
                              SizedBox(height: 12),
                              Text("Chưa có giao dịch rút tiền nào", style: TextStyle(color: Color(0xFF617D79), fontWeight: FontWeight.w600)),
                            ],
                          ),
                        )
                      else
                        ..._history.map((item) {
                          final status = item['status'] ?? 'PENDING';
                          Color statusColor = Colors.amber.shade700;
                          IconData statusIcon = Icons.access_time_filled_rounded;
                          String statusText = "Chờ duyệt";
                          
                          if (status == 'APPROVED') { statusColor = const Color(0xFF80BF84); statusIcon = Icons.check_circle_rounded; statusText = "Thành công"; }
                          else if (status == 'REJECTED') { statusColor = Colors.redAccent; statusIcon = Icons.cancel_rounded; statusText = "Từ chối"; }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2ECEB))),
                            child: Row(
                              children: [
                                Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF4F7F6), shape: BoxShape.circle), child: Icon(Icons.arrow_upward_rounded, color: statusColor, size: 20)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text("Rút tiền về ngân hàng", style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Icon(statusIcon, size: 12, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                          const Text(" • ", style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 11)),
                                          Text(item['created_at']?.toString().split('T')[0] ?? '', style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text("-${_currencyFormat.format(double.tryParse(item['amount'].toString()) ?? 0)}", style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w900)),
                              ],
                            ),
                          );
                        }).toList(),
                    ],
                  ),
                ),
              ),
        );
      },
    );
  }
}