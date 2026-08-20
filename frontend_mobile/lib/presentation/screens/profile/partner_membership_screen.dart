import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/partner_membership_model.dart';
import '../../../data/services/partner_api_service.dart';
import '../../widgets/app_toast.dart';

class PartnerMembershipScreen extends StatefulWidget {
  const PartnerMembershipScreen({super.key});

  @override
  State<PartnerMembershipScreen> createState() => _PartnerMembershipScreenState();
}

class _PartnerMembershipScreenState extends State<PartnerMembershipScreen> {
  final List<PartnerMembershipPlan> _plans = PartnerMembershipPlan.defaultPlans;
  int _selectedPlanIndex = 1; // Mặc định focus vào VIP Diamond (Best Value)
  int _selectedDurationMonths = 1;
  bool _isLoading = false;

  final PageController _pageController = PageController(viewportFraction: 0.88, initialPage: 1);

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _formatCurrency(double amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0).format(amount);
  }

  PartnerMembershipPlan get _currentPlan => _plans[_selectedPlanIndex];

  MembershipPricingOption get _currentPricing {
    return _currentPlan.pricingOptions.firstWhere(
      (opt) => opt.durationMonths == _selectedDurationMonths,
      orElse: () => _currentPlan.pricingOptions.first,
    );
  }

  Future<void> _handleSubscribe() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final tierStr = _currentPlan.tier == MembershipTier.diamond ? 'DIAMOND' : 'PRO';
    print('[DEBUG-MEMBERSHIP-SCREEN] Khởi tạo mua gói: $tierStr | $_selectedDurationMonths tháng');

    try {
      final res = await PartnerApiService.subscribePremium(
        planTier: tierStr,
        durationMonths: _selectedDurationMonths,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        if (res != null && res['in_app_data'] != null) {
          _showPayOSModal(res['in_app_data']);
        } else {
          AppToast.show(context: context, message: 'Không thể khởi tạo cổng thanh toán PayOS', isSuccess: false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context: context, message: e.toString().replaceAll('Exception: ', ''), isSuccess: false);
      }
    }
  }

  void _showPayOSModal(Map<String, dynamic> inAppData) {
    final int orderCode = inAppData['order_code'] ?? 0;
    final double amount = (inAppData['amount'] as num?)?.toDouble() ?? 0.0;
    final String accNum = inAppData['account_number'] ?? '';
    final String accName = inAppData['account_name'] ?? 'VN SHARE PAYOS';
    final String desc = inAppData['description'] ?? 'Goi VIP';
    final String? qrData = inAppData['qr_code'];

    Timer? pollingTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      isDismissible: false,
      builder: (ctx) {
        // Kích hoạt Polling kiểm tra trạng thái thanh toán ngầm mỗi 3 giây
        pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
          try {
            final checkRes = await ApiClient.instance.get(
              '/appointments/payment/verify',
              queryParameters: {'orderCode': orderCode},
            );
            if (checkRes.statusCode == 200 && checkRes.data['status'] == 'success') {
              timer.cancel();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                AppToast.show(
                  context: context,
                  message: '🎉 Chúc mừng! Gói hội viên của bạn đã được kích hoạt thành công.',
                  isSuccess: true,
                  duration: const Duration(seconds: 4),
                );
                Navigator.pop(context, true); // Quay về Profile và kích hoạt Refresh
              }
            }
          } catch (err) {
            print('[DEBUG-POLLING-SUB-ERR] $err');
          }
        });

        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 48, height: 5, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Thanh Toán VietQR PayOS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A3A35))),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF617D79)),
                      onPressed: () {
                        pollingTimer?.cancel();
                        Navigator.pop(ctx);
                      },
                    )
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0F4F3)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FBF9),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE2ECEB)),
                        ),
                        child: Column(
                          children: [
                            if (qrData != null && qrData.isNotEmpty)
                              QrImageView(
                                data: qrData,
                                version: QrVersions.auto,
                                size: 200.0,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1A3A35)),
                                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1A3A35)),
                              )
                            else
                              const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                            const SizedBox(height: 12),
                            const Text('Quét mã qua bất kỳ App Ngân hàng (MB, VCB, Tech...)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF617D79), fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildPayDetailRow('Số tiền thanh toán', _formatCurrency(amount), isHighlight: true),
                      _buildPayDetailRow('Chủ tài khoản', accName),
                      _buildPayDetailRow('Số tài khoản', accNum),
                      _buildPayDetailRow('Nội dung chuyển khoản', desc, isHighlight: true),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue)),
                            SizedBox(width: 12),
                            Expanded(child: Text('Đang tự động kiểm tra giao dịch... Hệ thống sẽ tự kích hoạt ngay khi nhận được tiền.', style: TextStyle(fontSize: 11.5, color: Color(0xFF1565C0), fontWeight: FontWeight.w600))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) => pollingTimer?.cancel());
  }

  Widget _buildPayDetailRow(String label, String value, {bool isHighlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF617D79), fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(fontSize: 13.5, color: isHighlight ? const Color(0xFFE63946) : const Color(0xFF1A3A35), fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A), // Dark Luxury Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Đặc Quyền Hội Viên',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Background Glow Orbs
          Positioned(
            top: -60,
            right: -60,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPlan.accentColor.withValues(alpha: 0.25),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Text(
                        'Nâng Tầm Thương Hiệu',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Mở khóa công cụ AI 10.000 ký tự, định vị Top 1 và tối đa hóa doanh thu cho cơ sở của bạn.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Carousel Plan Cards
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _plans.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _selectedPlanIndex = idx;
                        // Reset về chu kỳ 1 tháng nếu gói mới không hỗ trợ chu kỳ hiện tại
                        if (!_plans[idx].pricingOptions.any((opt) => opt.durationMonths == _selectedDurationMonths)) {
                          _selectedDurationMonths = 1;
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final plan = _plans[index];
                      final bool isSelected = _selectedPlanIndex == index;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 300),
                        scale: isSelected ? 1.0 : 0.94,
                        child: _buildPlanCard(plan, isSelected),
                      );
                    },
                  ),
                ),

                // Chu kỳ thanh toán (Duration Selector)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    children: _currentPlan.pricingOptions.map((opt) {
                      final bool isOptSelected = opt.durationMonths == _selectedDurationMonths;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDurationMonths = opt.durationMonths),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: isOptSelected ? _currentPlan.accentColor : Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isOptSelected ? Colors.transparent : Colors.white.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  opt.label,
                                  style: TextStyle(
                                    color: isOptSelected ? Colors.black : Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (opt.discountBadge != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    opt.discountBadge!,
                                    style: TextStyle(
                                      color: isOptSelected ? const Color(0xFFB91C1C) : _currentPlan.accentColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Bottom Action Button
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, bottom: 20, top: 4),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _currentPlan.gradientColors,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _currentPlan.accentColor.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      onPressed: _isLoading ? null : _handleSubscribe,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  'KÍCH HOẠT ${_currentPlan.title.toUpperCase()} • ${_formatCurrency(_currentPricing.priceVnd)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanCard(PartnerMembershipPlan plan, bool isSelected) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: plan.gradientColors,
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isSelected ? plan.accentColor : Colors.white.withValues(alpha: 0.15),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: isSelected
            ? [BoxShadow(color: plan.accentColor.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: plan.accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: plan.accentColor, width: 0.8),
                ),
                child: Text(
                  plan.badgeText,
                  style: TextStyle(color: plan.accentColor, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                ),
              ),
              Icon(plan.icon, color: plan.accentColor, size: 28),
            ],
          ),
          const SizedBox(height: 16),
          Text(plan.title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(plan.subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: plan.benefits.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_rounded, color: plan.accentColor, size: 16),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }
}