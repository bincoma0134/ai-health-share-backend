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
                      // ==================== THẺ 1: VÍ BẢO CHỨNG (FINANCIAL ESCROW CARD) ====================
                      Container(
                        width: double.infinity,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.35), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF80BF84).withOpacity(0.12),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Icon chìm đại diện cho dòng tiền bảo chứng & an toàn tài chính
                            Positioned(
                              right: -15,
                              bottom: -20,
                              child: Icon(
                                Icons.verified_user_rounded,
                                size: 140,
                                color: const Color(0xFF80BF84).withOpacity(0.05),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(24),
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
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF80BF84).withOpacity(0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF10B981), size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            "VÍ BẢO CHỨNG",
                                            style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF80BF84).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.lock_outline_rounded, color: Color(0xFF1A3A35), size: 11),
                                            SizedBox(width: 4),
                                            Text(
                                              "Tiền khả dụng",
                                              style: TextStyle(color: Color(0xFF1A3A35), fontSize: 10, fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _currencyFormat.format(_balance),
                                    style: const TextStyle(
                                      color: Color(0xFF1A3A35),
                                      fontSize: 34,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Doanh thu dịch vụ & hoa hồng có thể rút về ngân hàng",
                                    style: TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 24),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF80BF84),
                                        foregroundColor: Colors.white,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                      icon: const Icon(Icons.north_east_rounded, size: 16),
                                      label: const Text(
                                        "YÊU CẦU RÚT TIỀN",
                                        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5, fontSize: 13),
                                      ),
                                      onPressed: () => WalletScreen.showPremiumWithdrawalSheet(context, onSuccess: _loadWalletData),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ==================== THẺ 2: VÍ ĐIỂM NẠP (DEEP EMERALD PRIVILEGE CARD) ====================
                      Container(
                        width: double.infinity,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0F2B26), Color(0xFF1A3A35)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.3), width: 1.2),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0F2B26).withOpacity(0.35),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Icon chìm đại diện cho đặc quyền săn Voucher VIP
                            Positioned(
                              right: -10,
                              bottom: -20,
                              child: Icon(
                                Icons.stars_rounded,
                                size: 140,
                                color: Colors.white.withOpacity(0.04),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(24),
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
                                            decoration: BoxDecoration(
                                              color: Colors.white.withOpacity(0.12),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.diamond_rounded, color: Color(0xFFFCD34D), size: 16),
                                          ),
                                          const SizedBox(width: 10),
                                          const Text(
                                            "VÍ ĐIỂM NẠP",
                                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                                          ),
                                        ],
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.bolt_rounded, color: Color(0xFFFCD34D), size: 11),
                                            SizedBox(width: 4),
                                            Text(
                                              "Đổi Voucher VIP",
                                              style: TextStyle(color: Color(0xFFFCD34D), fontSize: 10, fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.baseline,
                                    textBaseline: TextBaseline.alphabetic,
                                    children: [
                                      Text(
                                        NumberFormat.decimalPattern('vi_VN').format(_pointsBalance),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: -1,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Text(
                                        "điểm",
                                        style: TextStyle(color: Color(0xFF80BF84), fontSize: 16, fontWeight: FontWeight.w800),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "Tỷ lệ 1.000đ = 1.000 điểm • Tiêu dùng săn ưu đãi đặc quyền",
                                    style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 24),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: SizedBox(
                                          height: 48,
                                          child: OutlinedButton.icon(
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: Colors.white,
                                              side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            ),
                                            icon: const Icon(Icons.local_offer_rounded, size: 15, color: Color(0xFFFCD34D)),
                                            label: const Text(
                                              "SĂN MÃ VIP",
                                              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5, fontSize: 12),
                                            ),
                                            onPressed: () {
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => const VipVoucherShopScreen()));
                                            },
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SizedBox(
                                          height: 48,
                                          child: ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: const Color(0xFF80BF84),
                                              foregroundColor: const Color(0xFF0F2B26),
                                              elevation: 0,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                            ),
                                            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF0F2B26)),
                                            label: const Text(
                                              "NẠP ĐIỂM",
                                              style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 12),
                                            ),
                                            onPressed: () => _showTopupBottomSheet(context),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
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
                      
                      // 🚀 UX NÂNG CẤP: Ghi rõ ngữ nghĩa phân tách dòng tiền nạp điểm & rút tiền
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Lịch sử rút tiền", style: TextStyle(color: Color(0xFF111827), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)),
                            child: const Text("Ví bảo chứng", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
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
    int? selectedPreset;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final currentInputVal = double.tryParse(amountCtrl.text) ?? 0;
          final calculatedPoints = currentInputVal.toInt();

          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F7F6), 
              borderRadius: BorderRadius.vertical(top: Radius.circular(32))
            ),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(top: 12, bottom: 16), decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(10)))),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Nạp Ví Điểm', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        Container(decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFFE2ECEB))), child: IconButton(icon: const Icon(Icons.close_rounded, color: Color(0xFF617D79), size: 18), onPressed: () => Navigator.pop(context))),
                      ],
                    ),
                  ),
                  Container(height: 1, width: double.infinity, margin: const EdgeInsets.only(top: 14, bottom: 18), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, const Color(0xFFE2ECEB).withOpacity(0.5), Colors.transparent]))),
                  Padding(
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
                              Expanded(child: Text('Tỷ lệ quy đổi: 1,000đ = 1,000 Điểm. Bội số 5.000đ.', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // 🚀 UX NÂNG CẤP: Ô nhập có lắng nghe thay đổi thời gian thực
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2ECEB)), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4))]),
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold),
                            onChanged: (val) {
                              setModalState(() {
                                selectedPreset = int.tryParse(val);
                              });
                            },
                            decoration: const InputDecoration(
                              labelText: 'Số tiền nạp (VNĐ)',
                              labelStyle: TextStyle(color: Color(0xFF617D79), fontSize: 13),
                              prefixIcon: Icon(Icons.monetization_on_rounded, color: Color(0xFF94A3B8), size: 20),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        
                        // 🚀 UX NÂNG CẤP: Hiển thị số điểm nhận tương ứng ngay lập tức
                        if (calculatedPoints > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8, left: 4),
                            child: Text(
                              '✨ Bạn sẽ nhận được: ${NumberFormat.decimalPattern('vi_VN').format(calculatedPoints)} điểm',
                              style: const TextStyle(color: Color(0xFF80BF84), fontSize: 12, fontWeight: FontWeight.w800),
                            ),
                          ),

                        const SizedBox(height: 14),
                        
                        // 🚀 UX NÂNG CẤP: Gợi ý các mốc nạp nhanh có Active Highlight
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [10000, 20000, 50000, 100000, 500000].map((val) {
                            final isSelected = selectedPreset == val;
                            return GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  selectedPreset = val;
                                  amountCtrl.text = val.toString();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? const Color(0xFF1A3A35) : const Color(0xFFE2ECEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: isSelected ? const Color(0xFF1A3A35) : Colors.transparent),
                                ),
                                child: Text(
                                  _currencyFormat.format(val),
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : const Color(0xFF1A3A35),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity, height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1A3A35), 
                              foregroundColor: Colors.white, 
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: isSubmitting ? null : () async {
                              final amount = double.tryParse(amountCtrl.text) ?? 0;
                              if (amount < 10000) { 
                                AppToast.show(context: context, message: 'Tối thiểu 10,000đ', isSuccess: false); 
                                return; 
                              }
                              if (amount % 5000 != 0) { 
                                AppToast.show(context: context, message: 'Số tiền phải là bội số của 5,000đ', isSuccess: false); 
                                return; 
                              }

                              setModalState(() => isSubmitting = true);
                              try {
                                final res = await WalletApiService.topupPoints(amount);
                                if (res != null && res.statusCode == 200 && res.data['status'] == 'success') {
                                  if (context.mounted) Navigator.pop(context);
                                  final inAppData = res.data['in_app_data'];
                                  if (inAppData != null && inAppData['qr_code'] != null) {
                                    _showQrTopupDialog(inAppData, amount);
                                  } else {
                                    print('[DEBUG-TOPUP-ERROR] In-app payload PayOS thiếu qr_code: $inAppData');
                                    if (context.mounted) AppToast.show(context: context, message: 'Lỗi khởi tạo QR PayOS.', isSuccess: false);
                                  }
                                } else {
                                  print('[DEBUG-TOPUP-ERROR] API trả về không thành công: ${res?.data}');
                                  if (context.mounted) AppToast.show(context: context, message: 'Lỗi tạo giao dịch.', isSuccess: false);
                                }
                              } catch (e) {
                                print('[DEBUG-TOPUP-EXCEPTION] Ngoại lệ khi tạo giao dịch nạp: $e');
                                if (context.mounted) AppToast.show(context: context, message: 'Lỗi kết nối máy chủ.', isSuccess: false);
                              } finally {
                                if (context.mounted) setModalState(() => isSubmitting = false);
                              }
                            },
                            child: isSubmitting 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                                : const Text('TẠO MÃ THANH TOÁN', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      )
    );
  }

  void _showQrTopupDialog(Map<String, dynamic> inAppData, double amountVnd) {
    bool isChecking = false;
    Timer? pollingTimer;

    // Khởi tạo Polling Timer một lần duy nhất ngoài builder của dialog để tránh leak
    pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || isChecking) return;
      try {
        final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
        if (res.statusCode == 200 && res.data['status'] == 'success') {
          timer.cancel();
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
          if (mounted) AppToast.show(context: context, message: '🎉 Nạp điểm hoàn tất tự động!', isSuccess: true);
          _loadWalletData();
        }
      } catch (e) {
        print('[DEBUG-POLLING-EXCEPTION] Lỗi polling PayOS verify: $e');
      }
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (qrContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return PopScope(
              canPop: true,
              onPopInvoked: (didPop) {
                if (didPop) {
                  pollingTimer?.cancel();
                  print('[DEBUG-TOPUP] Hủy Timer Polling khi đóng Dialog');
                }
              },
              child: Dialog(
                insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                backgroundColor: Colors.white,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF1A3A35), shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  const Text('NẠP ĐIỂM PAYOS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.black38, letterSpacing: 1.2)),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black38),
                                onPressed: () { 
                                  pollingTimer?.cancel(); 
                                  Navigator.pop(qrContext); 
                                },
                                padding: EdgeInsets.zero, 
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Column(
                              children: [
                                Text('${NumberFormat.decimalPattern('vi_VN').format(inAppData['points_to_receive'] ?? amountVnd)} Điểm', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                                const SizedBox(height: 2),
                                Text('Số tiền: ${_currencyFormat.format(amountVnd)}', style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 4))],
                              ),
                              child: Image.network(
                                'https://api.qrserver.com/v1/create-qr-code/?size=200x200&data=${Uri.encodeComponent(inAppData['qr_code'] ?? '')}',
                                width: 150, 
                                height: 150, 
                                fit: BoxFit.contain,
                                errorBuilder: (ctx, err, stack) => const SizedBox(
                                  width: 150, height: 150,
                                  child: Center(child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 40)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          
                          // Khối thông tin chuyển khoản nhỏ gọn, chống tràn
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(16)),
                            child: Column(
                              children: [
                                _buildCopyableRow('Ngân hàng', 'PayOS (Vietinbank)'),
                                const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, color: Colors.black12)),
                                _buildCopyableRow('Số tài khoản', inAppData['account_number']?.toString() ?? '', isMono: true),
                                const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Divider(height: 1, color: Colors.black12)),
                                _buildCopyableRow('Nội dung', inAppData['description']?.toString() ?? '', customValueColor: const Color(0xFF80BF84), isMono: true),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(width: 8, height: 8, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFF59E0B))),
                              const SizedBox(width: 6),
                              Text('Chờ quét tự động...', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity, height: 44,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: isChecking ? null : () async {
                                setState(() => isChecking = true);
                                try {
                                  final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
                                  if (res.statusCode == 200 && res.data['status'] == 'success') {
                                    pollingTimer?.cancel();
                                    if (context.mounted) Navigator.pop(qrContext);
                                    if (mounted) AppToast.show(context: context, message: '🎉 Nạp điểm thành công!', isSuccess: true);
                                    _loadWalletData();
                                  } else {
                                    if (mounted) AppToast.show(context: context, message: '⏳ Chưa ghi nhận thanh toán.', isSuccess: false);
                                    setState(() => isChecking = false);
                                  }
                                } catch (e) {
                                  print('[DEBUG-MANUAL-VERIFY-ERROR] Lỗi nút xác nhận thủ công: $e');
                                  if (mounted) AppToast.show(context: context, message: '❌ Lỗi kết nối.', isSuccess: false);
                                  setState(() => isChecking = false);
                                }
                              },
                              child: isChecking 
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text('TÔI ĐÃ CHUYỂN KHOẢN', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      pollingTimer?.cancel();
      print('[DEBUG-TOPUP] Timer Polling đã được dọn dẹp sau khi Dialog đóng');
    });
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