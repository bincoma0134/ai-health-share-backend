import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/partner_membership_model.dart';
import '../../../data/services/partner_api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';

class PartnerMembershipScreen extends StatefulWidget {
  const PartnerMembershipScreen({super.key});

  @override
  State<PartnerMembershipScreen> createState() => _PartnerMembershipScreenState();
}

class _PartnerMembershipScreenState extends State<PartnerMembershipScreen> {
  final List<PartnerMembershipPlan> _plans = PartnerMembershipPlan.defaultPlans;
  int _selectedPlanIndex = 1; // Mặc định focus vào VIP Diamond
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
                Navigator.pop(context, true);
              }
            }
          } catch (err) {
            print('[DEBUG-POLLING-SUB-ERR] $err');
          }
        });

        return Container(
          height: MediaQuery.of(context).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Color(0xFFFBFDFD),
            borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 44, height: 5, decoration: BoxDecoration(color: const Color(0xFFD1E3E0), borderRadius: BorderRadius.circular(10))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Thanh Toán VietQR', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: Color(0xFF14302B), letterSpacing: -0.4)),
                        SizedBox(height: 2),
                        Text('Bảo chứng bởi cổng PayOS', style: TextStyle(fontSize: 12, color: Color(0xFF6B8782), fontWeight: FontWeight.w500)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Color(0xFF6B8782), size: 22),
                      onPressed: () {
                        pollingTimer?.cancel();
                        Navigator.pop(ctx);
                      },
                    )
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE8F2F0)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(color: const Color(0xFFE2ECE9)),
                          boxShadow: [
                            BoxShadow(color: const Color(0xFF14302B).withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          children: [
                            if (qrData != null && qrData.isNotEmpty)
                              QrImageView(
                                data: qrData,
                                version: QrVersions.auto,
                                size: 200.0,
                                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF14302B)),
                                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF14302B)),
                              )
                            else
                              const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(color: Color(0xFF2E6F65)))),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(color: const Color(0xFFF0F7F5), borderRadius: BorderRadius.circular(12)),
                              child: const Text('Hỗ trợ tất cả ứng dụng Ngân hàng & Ví điện tử', style: TextStyle(fontSize: 11.5, color: Color(0xFF42635D), fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE8F2F0)),
                        ),
                        child: Column(
                          children: [
                            _buildPayDetailRow('Số tiền thanh toán', _formatCurrency(amount), isHighlight: true),
                            const Divider(height: 12, color: Color(0xFFF4F9F8)),
                            _buildPayDetailRow('Chủ tài khoản', accName),
                            const Divider(height: 12, color: Color(0xFFF4F9F8)),
                            _buildPayDetailRow('Số tài khoản', accNum),
                            const Divider(height: 12, color: Color(0xFFF4F9F8)),
                            _buildPayDetailRow('Nội dung chuyển khoản', desc, isHighlight: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F4F1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2E6F65))),
                            SizedBox(width: 12),
                            Expanded(child: Text('Đang tự động đối soát... Gói sẽ kích hoạt ngay khi chuyển khoản thành công.', style: TextStyle(fontSize: 12, color: Color(0xFF1E4D45), fontWeight: FontWeight.w600, height: 1.3))),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF6B8782), fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(fontSize: 13.5, color: isHighlight ? const Color(0xFFE63956) : const Color(0xFF14302B), fontWeight: FontWeight.w800)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAF8), // Apple Light Wellness Background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF14302B), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Đặc Quyền Đối Tác',
          style: TextStyle(color: Color(0xFF14302B), fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Soft Ambient Glow Orbs
          Positioned(
            top: -40,
            right: -40,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPlan.accentColor.withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            top: 200,
            left: -60,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF80BF84).withValues(alpha: 0.1),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      Text(
                        'Nâng Tầm Không Gian Sống',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF14302B), fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Mở khóa định vị Top 1 bản đồ, trợ lý AI học sâu và tối ưu hóa doanh thu bảo chứng.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF6B8782), fontSize: 13, height: 1.45, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Carousel Plan Cards
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _plans.length,
                    onPageChanged: (idx) {
                      setState(() {
                        _selectedPlanIndex = idx;
                        if (!_plans[idx].pricingOptions.any((opt) => opt.durationMonths == _selectedDurationMonths)) {
                          _selectedDurationMonths = 1;
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final plan = _plans[index];
                      final bool isSelected = _selectedPlanIndex == index;
                      return AnimatedScale(
                        duration: const Duration(milliseconds: 280),
                        scale: isSelected ? 1.0 : 0.94,
                        child: _buildAppleStylePlanCard(plan, isSelected),
                      );
                    },
                  ),
                ),

                // iOS-Style Segmented Duration Selector
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7EFEA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: _currentPlan.pricingOptions.map((opt) {
                      final bool isOptSelected = opt.durationMonths == _selectedDurationMonths;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _selectedDurationMonths = opt.durationMonths),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: isOptSelected ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: isOptSelected
                                  ? [BoxShadow(color: const Color(0xFF14302B).withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))]
                                  : [],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  opt.label,
                                  style: TextStyle(
                                    color: isOptSelected ? const Color(0xFF14302B) : const Color(0xFF6B8782),
                                    fontSize: 13,
                                    fontWeight: isOptSelected ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                ),
                                if (opt.discountBadge != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    opt.discountBadge!,
                                    style: TextStyle(
                                      color: isOptSelected ? const Color(0xFFE63956) : const Color(0xFF8A9F9B),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
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

                // 🚀 NÂNG CẤP BỌC THÉP: Đồng bộ màu Cyber Cyan cho Pro & Chống Overflow tuyệt đối
                Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 20, top: 4),
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _currentPlan.tier == MembershipTier.diamond
                            ? const [Color(0xFFE63956), Color(0xFFB81534)] // Imperial Ruby Gradient
                            : const [Color(0xFF00B4D8), Color(0xFF0077B6)], // Cyber Cyan Gradient đồng bộ với Pro Card
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: (_currentPlan.tier == MembershipTier.diamond
                                  ? const Color(0xFFE63956)
                                  : const Color(0xFF00B4D8))
                              .withValues(alpha: 0.38),
                          blurRadius: 20,
                          spreadRadius: 1,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                      ),
                      onPressed: _isLoading ? null : _handleSubscribe,
                      child: _isLoading
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.25),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 16),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'KÍCH HOẠT ${_currentPlan.title.toUpperCase()} • ${_formatCurrency(_currentPricing.priceVnd)}',
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
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

  Widget _buildAppleStylePlanCard(PartnerMembershipPlan plan, bool isSelected) {
    final bool isDiamond = plan.tier == MembershipTier.diamond;

    Widget cardContent = Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: isDiamond ? const Color(0xFFFFF9FA) : const Color(0xFFFFFFFF),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: isSelected ? plan.accentColor.withValues(alpha: 0.7) : const Color(0xFFE2ECE9),
          width: isSelected ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isSelected
                ? plan.accentColor.withValues(alpha: 0.14)
                : const Color(0xFF14302B).withValues(alpha: 0.04),
            blurRadius: isSelected ? 24 : 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Badge & Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: plan.accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: plan.accentColor.withValues(alpha: 0.35), width: 0.8),
                ),
                child: Text(
                  plan.badgeText,
                  style: TextStyle(
                    color: plan.accentColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: plan.accentColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(plan.icon, color: plan.accentColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            plan.title,
            style: const TextStyle(color: Color(0xFF14302B), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5),
          ),
          const SizedBox(height: 3),
          Text(
            plan.subtitle,
            style: const TextStyle(color: Color(0xFF6B8782), fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 14),

          // 🚀 TẤM LÓT FROSTED GLASSMORHPISM ĐỆM BÊN DƯỚI DANH SÁCH QUYỀN LỢI
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.75),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDiamond ? const Color(0xFFFFE3E8) : const Color(0xFFE2EFEA),
                  width: 1.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF14302B).withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  children: plan.benefits.map((b) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: plan.accentColor.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_rounded, color: plan.accentColor, size: 11),
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            b,
                            style: const TextStyle(
                              color: Color(0xFF2C4944),
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // 🚀 ÁP DỤNG SHIMMER CHO THẺ VIP DIAMOND ĐỂ THỂ HIỆN SỰ ĐẲNG CẤP VƯƠNG GIẢ
    if (isDiamond && isSelected) {
      return ShimmerWrapper(child: cardContent);
    }

    return cardContent;
  }
}