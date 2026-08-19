import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/services/wallet_api_service.dart';
import '../../../core/network/api_client.dart';
import '../widgets/auth_guard.dart';
import '../widgets/guest_profile_view.dart';
import '../widgets/app_toast.dart';
import 'package:go_router/go_router.dart';
import 'profile/user_wellness_profile_screen.dart';
import 'dart:async'; // Thêm Timer cho Polling QR
import 'promo/vip_voucher_shop_screen.dart'; // Bổ sung điều hướng VIP Shop
import 'package:flutter/services.dart';

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
                              backgroundColor: const Color(0xFF80BF84), 
                              foregroundColor: Colors.white, 
                              elevation: 0,
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
                            child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('XÁC NHẬN RÚT TIỀN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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
  double _pointsBalance = 0.0; // Thêm số dư ví điểm
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
        _pointsBalance = walletRes.pointsBalance; // Đồng bộ điểm nạp
      }
      
      // Auto-Routing: Thử nạp lịch sử rút tiền theo từng phân hệ Role (Dò tìm)
      dynamic historyRes;
      try {
        historyRes = await ApiClient.instance.get('/user/withdrawals');
      } catch (_) {
        try {
          historyRes = await ApiClient.instance.get('/partner/withdrawals');
        } catch (_) {
          try { historyRes = await ApiClient.instance.get('/creator/withdrawals'); } catch (_) {}
        }
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
                      // THẺ SỐ DƯ PREMIUM (Pearl White & Soft Emerald - Phong cách Oasis Spa)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: const Color(0xFFE2ECEB), width: 1.5),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8), 
                                      decoration: const BoxDecoration(color: Color(0xFFF4F9F6), shape: BoxShape.circle), 
                                      child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF80BF84), size: 16)
                                    ),
                                    const SizedBox(width: 12),
                                    const Text("SỐ DƯ KHẢ DỤNG", style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                                  ],
                                ),
                                const Icon(Icons.verified_user_rounded, color: Color(0xFF80BF84), size: 20),
                              ],
                            ),
                            const SizedBox(height: 28),
                            Text(_currencyFormat.format(_balance), style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1)),
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity, height: 52,
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF80BF84), 
                                  foregroundColor: Colors.white, 
                                  elevation: 0, 
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                ),
                                onPressed: () => WalletScreen.showPremiumWithdrawalSheet(context, onSuccess: _loadWalletData),
                                child: const Text("YÊU CẦU RÚT TIỀN", style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5, fontSize: 14)),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // THẺ VÍ ĐIỂM NẠP (1 CHIỀU) ĐỂ MUA VOUCHER VIP
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A3A35), // Tone màu tối (Dark Mode Card) phân biệt với Ví Bảo Chứng
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8), 
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), 
                                      child: const Icon(Icons.stars_rounded, color: Color(0xFFE2ECEB), size: 16)
                                    ),
                                    const SizedBox(width: 12),
                                    const Text("VÍ ĐIỂM NẠP", style: TextStyle(color: Color(0xFFE2ECEB), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                  child: const Text("Chỉ mua Voucher", style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(NumberFormat.decimalPattern('vi_VN').format(_pointsBalance), style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1)),
                                const Padding(
                                  padding: EdgeInsets.only(bottom: 6, left: 4),
                                  child: Text(" điểm", style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                                )
                              ],
                            ),
                            const SizedBox(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.1), 
                                        foregroundColor: Colors.white, 
                                        elevation: 0, 
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                      ),
                                      onPressed: () {
                                        Navigator.push(context, MaterialPageRoute(builder: (_) => const VipVoucherShopScreen()));
                                      },
                                      child: const Text("SĂN MÃ VIP", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 14)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SizedBox(
                                    height: 52,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFE2ECEB), 
                                        foregroundColor: const Color(0xFF1A3A35), 
                                        elevation: 0, 
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                                      ),
                                      onPressed: () => _showTopupBottomSheet(context),
                                      child: const Text("NẠP ĐIỂM", style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 14)),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      // WIDGET TIÊU DÙNG THÔNG MINH (SHORTCUT GAMIFICATION - PREMIUM LIGHT)
                      if (_rewardStatus != null && !(_rewardStatus!['has_claimed'] ?? false))
                        GestureDetector(
                          onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const UserWellnessProfileScreen()));
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF4F9F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.4)),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.08), blurRadius: 15, offset: const Offset(0, 6))
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.2), blurRadius: 8)]),
                                  child: const Icon(Icons.diamond_rounded, color: Color(0xFF80BF84), size: 20),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        "Tiến độ hoàn tiền 500k",
                                        style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                                      ),
                                      const SizedBox(height: 8),
                                      Stack(
                                        children: [
                                          Container(
                                            height: 8, width: double.infinity,
                                            decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)),
                                          ),
                                          FractionallySizedBox(
                                            widthFactor: ((_rewardStatus!['total_spent'] ?? 0) / (_rewardStatus!['target_amount'] ?? 5000000)).clamp(0.0, 1.0),
                                            child: Container(
                                              height: 8,
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF48C9B0)]),
                                                borderRadius: BorderRadius.circular(10),
                                                boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.4), blurRadius: 6)],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const Icon(Icons.chevron_right_rounded, color: Color(0xFF80BF84), size: 24),
                              ],
                            ),
                          ),
                        ),
                      
                      const SizedBox(height: 36),
                      
                      const Text("Lịch sử giao dịch", style: TextStyle(color: Color(0xFF111827), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                      const SizedBox(height: 16),
                      
                      if (_history.isEmpty)
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(40),
                          decoration: BoxDecoration(
                            color: Colors.white, 
                            borderRadius: BorderRadius.circular(24), 
                            boxShadow: [BoxShadow(color: const Color(0xFF111827).withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8))]
                          ),
                          child: const Column(
                            children: [
                              Icon(Icons.receipt_long_rounded, size: 48, color: Color(0xFFE5E7EB)),
                              SizedBox(height: 16),
                              Text("Chưa có giao dịch rút tiền nào", style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        )
                      else
                        ..._history.map((item) {
                          final status = item['status'] ?? 'PENDING';
                          
                          // Tone màu mềm mại sang trọng (Soft UI)
                          Color statusColor = const Color(0xFFF59E0B); // Amber/Gold cho Pending
                          Color bgColor = const Color(0xFFFEF3C7);
                          IconData statusIcon = Icons.schedule_rounded;
                          String statusText = "Chờ duyệt";
                          
                          if (status == 'APPROVED') { 
                            statusColor = const Color(0xFF10B981); // Emerald cho Success
                            bgColor = const Color(0xFFD1FAE5);
                            statusIcon = Icons.check_circle_rounded; 
                            statusText = "Thành công"; 
                          } else if (status == 'REJECTED') { 
                            statusColor = const Color(0xFFEF4444); // Red cho Rejected
                            bgColor = const Color(0xFFFEE2E2);
                            statusIcon = Icons.cancel_rounded; 
                            statusText = "Từ chối"; 
                          }

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12), 
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white, 
                              borderRadius: BorderRadius.circular(24), 
                              boxShadow: [BoxShadow(color: const Color(0xFF111827).withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))]
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12), 
                                  decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle), 
                                  child: Icon(Icons.account_balance_rounded, color: statusColor, size: 20)
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text("Rút tiền về ngân hàng", style: TextStyle(color: Color(0xFF111827), fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(statusIcon, size: 14, color: statusColor),
                                          const SizedBox(width: 4),
                                          Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w700)),
                                          const Text(" • ", style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 12)),
                                          Text(item['created_at']?.toString().split('T')[0] ?? '', style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text("-${_currencyFormat.format(double.tryParse(item['amount'].toString()) ?? 0)}", style: const TextStyle(color: Color(0xFF111827), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
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

  // --- LOGIC LUỒNG NẠP ĐIỂM ---

  void _showTopupBottomSheet(BuildContext context) {
    final amountCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.5,
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
                      const Text('Nạp Ví Điểm', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
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
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: const Color(0xFF1A3A35).withOpacity(0.05), borderRadius: BorderRadius.circular(12)),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded, color: Color(0xFF1A3A35), size: 16),
                              SizedBox(width: 8),
                              Expanded(child: Text('Tỷ lệ quy đổi: 1,000đ = 1,000 Điểm. Số tiền nạp phải là bội số của 5.000đ.', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        WalletScreen._buildSheetField(amountCtrl, 'Số tiền nạp (Ví dụ: 10000, 50000)', Icons.monetization_on_rounded, isNumber: true),
                        const SizedBox(height: 12),
                        // 🚀 UX NÂNG CẤP: Gợi ý các mốc nạp nhanh bằng Chip
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [10000, 20000, 50000, 100000, 500000].map((val) => GestureDetector(
                            onTap: () => amountCtrl.text = val.toString(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8)),
                              child: Text(_currencyFormat.format(val), style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.w800)),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity, height: 52,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A3A35), 
                              foregroundColor: Colors.white, 
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: isSubmitting ? null : () async {
                              final amount = double.tryParse(amountCtrl.text) ?? 0;
                              if (amount < 10000) { AppToast.show(context: context, message: 'Tối thiểu 10,000đ', isSuccess: false); return; }
                              // 🚀 BỌC THÉP VALIDATION: Chặn cứng bội số 5000 ngay tại Frontend trước khi gọi API
                              if (amount % 5000 != 0) { AppToast.show(context: context, message: 'Số tiền phải là bội số của 5,000đ', isSuccess: false); return; }

                              setModalState(() => isSubmitting = true);
                              try {
                                // Sử dụng Service đã được đóng gói gọn gàng
                                final res = await WalletApiService.topupPoints(amount);
                                if (res != null && res.statusCode == 200 && res.data['status'] == 'success') {
                                  Navigator.pop(context); // Đóng form nhập tiền
                                  final inAppData = res.data['in_app_data'];
                                  if (inAppData != null && inAppData['qr_code'] != null) {
                                    _showQrTopupDialog(inAppData, amount);
                                  } else {
                                    AppToast.show(context: context, message: 'Lỗi khởi tạo QR PayOS.', isSuccess: false);
                                  }
                                } else {
                                  AppToast.show(context: context, message: 'Lỗi tạo giao dịch.', isSuccess: false);
                                }
                              } catch (e) {
                                AppToast.show(context: context, message: 'Lỗi kết nối máy chủ.', isSuccess: false);
                              } finally {
                                if (context.mounted) setModalState(() => isSubmitting = false);
                              }
                            },
                            child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('TẠO MÃ THANH TOÁN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
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

  void _showQrTopupDialog(Map<String, dynamic> inAppData, double amountVnd) {
    bool isChecking = false;
    Timer? pollingTimer;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (qrContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            
            // Polling ngầm để xác thực giao dịch PayOS
            pollingTimer ??= Timer.periodic(const Duration(seconds: 3), (timer) async {
              if (!mounted || isChecking) return;
              try {
                // Sử dụng hàm webhook nội bộ hoặc giả lập check order (Giả sử sử dụng logic chung như Lịch hẹn)
                final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
                if (res.statusCode == 200 && res.data['status'] == 'success') {
                  timer.cancel();
                  if (Navigator.canPop(qrContext)) Navigator.pop(qrContext);
                  if (mounted) AppToast.show(context: context, message: '🎉 Nạp điểm hoàn tất tự động!', isSuccess: true);
                  _loadWalletData();
                }
              } catch (_) {}
            });

            return WillPopScope(
              onWillPop: () async {
                pollingTimer?.cancel();
                return true;
              },
              child: Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              backgroundColor: Colors.white,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: const BoxDecoration(color: Color(0xFF1A3A35), shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 8),
                                const Text('NẠP ĐIỂM PAYOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black38, letterSpacing: 1.2)),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 22, color: Colors.black38),
                              onPressed: () { pollingTimer?.cancel(); Navigator.pop(qrContext); },
                              padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Column(
                            children: [
                              // 🚀 THUẬT TOÁN ĐỔI ĐIỂM: 1000 VND = 1000 Điểm (Khớp Backend 1:1)
                              Text('${NumberFormat.decimalPattern('vi_VN').format(inAppData['points_to_receive'] ?? amountVnd)} Điểm', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                              const SizedBox(height: 2),
                              Text('Số tiền nạp: ${_currencyFormat.format(amountVnd)}', style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 16, offset: const Offset(0, 8))],
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(inAppData['qr_code'] ?? '')}',
                              width: 190, height: 190, fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // 🚀 UX NÂNG CẤP: Bổ sung khối Copy Banking Details giống Lịch Hẹn
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(20)),
                          child: Column(
                            children: [
                              _buildCopyableRow('Ngân hàng nhận', 'PayOS (Vietinbank)', isMono: false),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Colors.black12)),
                              _buildCopyableRow('Số tài khoản', inAppData['account_number']?.toString() ?? '', isMono: true),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Colors.black12)),
                              _buildCopyableRow('Số tiền chuyển', _currencyFormat.format((inAppData['amount'] ?? amountVnd).toDouble()), customValueColor: const Color(0xFF1A3A35)),
                              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: Colors.black12)),
                              _buildCopyableRow('Nội dung bắt buộc', inAppData['description']?.toString() ?? '', customValueColor: const Color(0xFF80BF84)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFF59E0B))),
                            const SizedBox(width: 8),
                            Text('Đang chờ thanh toán tự động...', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade700)),
                          ],
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity, height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isChecking ? null : () async {
                              setState(() => isChecking = true);
                              try {
                                final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
                                if (res.statusCode == 200 && res.data['status'] == 'success') {
                                  pollingTimer?.cancel();
                                  Navigator.pop(qrContext);
                                  if (mounted) AppToast.show(context: context, message: '🎉 Nạp điểm thành công!', isSuccess: true);
                                  _loadWalletData();
                                } else {
                                  if (mounted) AppToast.show(context: context, message: '⏳ Chưa ghi nhận dòng tiền.', isSuccess: false);
                                  setState(() => isChecking = false);
                                }
                              } catch (e) {
                                if (mounted) AppToast.show(context: context, message: '❌ Lỗi đường truyền.', isSuccess: false);
                                setState(() => isChecking = false);
                              }
                            },
                            child: isChecking 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('TÔI ĐÃ CHUYỂN KHOẢN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),);
          },
        );
      },
    );
  }

  // 🚀 HÀM BỔ TRỢ: Xây dựng dòng Copyable chuẩn UX
  Widget _buildCopyableRow(String title, String value, {bool isMono = false, Color? customValueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500)),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              // Sử dụng bộ Clipboard chuẩn của Flutter để tương tác với Native OS
              Clipboard.setData(ClipboardData(text: value));
              AppToast.show(context: context, message: '🎉 Đã sao chép: $value', isSuccess: true);
            },
            child: Container(
              color: Colors.transparent,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: customValueColor ?? Colors.black87,
                        fontFamily: isMono ? 'monospace' : null,
                        fontFeatures: isMono ? const [FontFeature.tabularFigures()] : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy_rounded, size: 12, color: Colors.black26),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}