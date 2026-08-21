import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/partner_tier_theme.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/services/voucher_api_service.dart';
import '../../../data/services/wallet_api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/partner_tier/partner_avatar_frame.dart';
import '../../widgets/partner_tier/partner_tier_badge.dart';
import '../../widgets/partner_tier/sparkle_overlay.dart';
import 'package:go_router/go_router.dart';

class VipVoucherShopScreen extends StatefulWidget {
  const VipVoucherShopScreen({super.key});

  @override
  State<VipVoucherShopScreen> createState() => _VipVoucherShopScreenState();
}

class _VipVoucherShopScreenState extends State<VipVoucherShopScreen> with TickerProviderStateMixin {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  List<VoucherModel> _vouchers = [];
  List<VoucherModel> _filteredVouchers = [];
  bool _isLoading = true;
  double _pointsBalance = 0.0;
  String _selectedTimeSlot = 'ALL';

  // Carousel Spotlight Banner
  late final PageController _spotlightPageController = PageController(viewportFraction: 0.92);
  Timer? _spotlightTimer;
  int _currentSpotlightIndex = 0;

  final List<String> _timeSlots = [
    'ALL',
    '08:00 - 10:00',
    '10:00 - 12:00',
    '13:00 - 15:00',
    '15:00 - 17:00',
    '18:00 - 20:00',
    '20:00 - 22:00',
  ];

  // 🚀 PHASE 08: Hero Spotlight mang tông màu Cyber Cyan & Imperial Ruby Wellness
  final List<Map<String, dynamic>> _spotlightBanners = [
    {
      "badge": "👑 ĐẶC QUYỀN VIP DIAMOND",
      "title": "ĐẶT LỊCH KHUNG GIỜ VÀNG\nƯU ĐÃI LÊN ĐẾN 50%",
      "desc": "Bảo chứng y tế 5 sao - Trải nghiệm liệu trình chuyên sâu cao cấp.",
      "colors": [const Color(0xFFE63956), const Color(0xFFB81534)], // Imperial Ruby Gradient
      "accent": const Color(0xFFFFD700),
    },
    {
      "badge": "💠 FLASH DEAL PRO",
      "title": "CHĂM SÓC SỨC KHỎE\nCHỈ TỪ 10.000 ĐIỂM",
      "desc": "Mở khóa suất khám ưu tiên tại các cơ sở đối tác uy tín.",
      "colors": [const Color(0xFF00B4D8), const Color(0xFF0077B6)], // Cyber Cyan Gradient
      "accent": const Color(0xFF00E5FF),
    },
    {
      "badge": "✦ ĐẶC QUYỀN BẢO CHỨNG",
      "title": "ĐỔI ĐIỂM MỘT CHẠM\nCHECK-IN KHÔNG CHỜ ĐỢI",
      "desc": "Quét mã QR 6 số tại quầy cơ sở để giải ngân an toàn Escrow.",
      "colors": [const Color(0xFF14302B), const Color(0xFF2E6F65)],
      "accent": const Color(0xFF80BF84),
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
    _startSpotlightTimer();
  }

  void _startSpotlightTimer() {
    _spotlightTimer = Timer.periodic(const Duration(milliseconds: 4000), (timer) {
      if (_spotlightPageController.hasClients && _spotlightPageController.position.hasContentDimensions) {
        int nextPage = _spotlightPageController.page!.round() + 1;
        if (nextPage >= _spotlightBanners.length) nextPage = 0;
        _spotlightPageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _spotlightTimer?.cancel();
    _spotlightPageController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      print('[DEBUG-VIP-SHOP] Bắt đầu đồng bộ danh sách Voucher VIP và Ví điểm từ Server...');
      final vRes = await VoucherApiService.getPublicVipVouchers();
      final wRes = await WalletApiService.getWallet();

      if (mounted) {
        setState(() {
          _vouchers = vRes;
          _pointsBalance = wRes.pointsBalance;
          _isLoading = false;
        });
        _applyFilters();
      }
      print('[DEBUG-VIP-SHOP] Tải thành công: ${_vouchers.length} VIP Vouchers khả dụng. Số dư: $_pointsBalance điểm.');
    } catch (e) {
      print('[DEBUG-VIP-SHOP-EXCEPTION] Lỗi tải dữ liệu Sàn VIP: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context: context, message: 'Không thể kết nối đến máy chủ Sàn VIP.', isSuccess: false);
      }
    }
  }

  void _applyFilters() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredVouchers = _vouchers.where((v) {
        final matchesQuery = query.isEmpty ||
            (v.partnerName?.toLowerCase().contains(query) ?? false) ||
            v.code.toLowerCase().contains(query) ||
            (v.description?.toLowerCase().contains(query) ?? false);

        final matchesSlot = _selectedTimeSlot == 'ALL' || (v.fixedTimeSlot == _selectedTimeSlot);

        return matchesQuery && matchesSlot;
      }).toList();
    });
  }

  // 🚀 PHASE 08: POPUP PREVIEW CHI TIẾT VOUCHER VIP ĐỒNG BỘ THEME CẤP BẬC
  void _showVoucherDetailsModal(VoucherModel voucher) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE63956), Color(0xFFB81534)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE63956).withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 13),
                      SizedBox(width: 4),
                      Text('VIP PASS ĐẶC QUYỀN', style: TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 0.4)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close_rounded, color: Colors.black45, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                voucher.discountType == 'PERCENTAGE' ? 'Giảm ${voucher.discountValue.toInt()}%' : 'Giảm ${_currencyFormat.format(voucher.discountValue)}',
                style: const TextStyle(color: Color(0xFF14302B), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE63956).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'MÃ: [${voucher.code}]',
                  style: const TextStyle(color: Color(0xFFE63956), fontSize: 11.5, fontWeight: FontWeight.w900, fontFamily: 'monospace'),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF6FAF8), 
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2ECE9)),
              ),
              child: Column(
                children: [
                  _buildDetailRow('Cơ sở phát hành', voucher.partnerName ?? 'Cơ sở bảo chứng VIP'),
                  const Divider(color: Color(0xFFEAEFEF), height: 16),
                  _buildDetailRow('Khung giờ áp dụng', voucher.fixedTimeSlot ?? 'N/A', valueColor: const Color(0xFFE63956)),
                  const Divider(color: Color(0xFFEAEFEF), height: 16),
                  _buildDetailRow('Số lượng còn lại', '${voucher.totalQuantity - voucher.usedQuantity}/${voucher.totalQuantity} suất'),
                  const Divider(color: Color(0xFFEAEFEF), height: 16),
                  _buildDetailRow('Giá quy đổi', '${NumberFormat.decimalPattern('vi_VN').format(voucher.pointPrice)} Điểm', valueColor: const Color(0xFFD97706)),
                ],
              ),
            ),
            if (voucher.description != null && voucher.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(voucher.description!, style: const TextStyle(fontSize: 11.5, color: Color(0xFF6B8782), fontStyle: FontStyle.italic, height: 1.35)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF0F4F2),
                      foregroundColor: const Color(0xFF14302B),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (voucher.partnerUsername != null && voucher.partnerUsername!.isNotEmpty) {
                        GoRouter.of(context).push('/public-profile/${voucher.partnerUsername}');
                      }
                    },
                    child: const Text('Xem cơ sở', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE63956), Color(0xFFB81534)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE63956).withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _showCheckoutBottomSheet(voucher);
                      },
                      child: const Text('ĐỔI MÃ NGAY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.4)),
                    ),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color valueColor = Colors.black87}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // --- BOTTOMSHEET THANH TOÁN ĐIỂM ---
  void _showCheckoutBottomSheet(VoucherModel voucher) {
    bool isProcessing = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final double remain = _pointsBalance - voucher.pointPrice;
          
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.lock_rounded, color: Color(0xFF10B981), size: 20),
                    SizedBox(width: 8),
                    Text('Xác nhận đổi Voucher VIP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                  ],
                ),
                const SizedBox(height: 20),
                
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      _buildDetailRow('Mã đặc quyền', voucher.code, valueColor: const Color(0xFF1A3A35)),
                      const Divider(color: Colors.black12, height: 20),
                      _buildDetailRow('Số dư Ví Điểm', '${NumberFormat.decimalPattern('vi_VN').format(_pointsBalance)} Điểm'),
                      const Divider(color: Colors.black12, height: 20),
                      _buildDetailRow('Điểm quy đổi', '-${NumberFormat.decimalPattern('vi_VN').format(voucher.pointPrice)} Điểm', valueColor: Colors.redAccent),
                      const Divider(color: Colors.black12, height: 20),
                      _buildDetailRow('Số dư sau khi đổi', '${NumberFormat.decimalPattern('vi_VN').format(remain)} Điểm', valueColor: remain < 0 ? Colors.red : const Color(0xFF10B981)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: isProcessing ? null : () async {
                      if (remain < 0) {
                        AppToast.show(context: context, message: 'Số dư Điểm không đủ! Vui lòng nạp thêm.', isSuccess: false);
                        return;
                      }
                      
                      setModalState(() => isProcessing = true);
                      try {
                        final success = await VoucherApiService.buyVoucherWithPoints(voucher.code);
                        if (success) {
                          if (context.mounted) Navigator.pop(context);
                          _showSuccessAppleTick(voucher);
                          _loadData();
                        }
                      } catch (e) {
                        if (context.mounted) AppToast.show(context: context, message: e.toString().replaceAll('Exception: ', ''), isSuccess: false);
                      } finally {
                        if (context.mounted) setModalState(() => isProcessing = false);
                      }
                    },
                    child: isProcessing 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Text('XÁC NHẬN THANH TOÁN ĐIỂM', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  // --- ANIMATION APPLE-STYLE TICK ---
  void _showSuccessAppleTick(VoucherModel voucher) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AppleTickAnimationDialog(),
    ).then((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: const Text('🎉 Đổi Mã Thành Công!', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF1A3A35)), textAlign: TextAlign.center),
          content: Text(
            'Voucher [${voucher.code}] đã được lưu vào kho Ưu Đãi của bạn.\nÁp dụng cho khung giờ: ${voucher.fixedTimeSlot}.',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Ở lại sàn', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A3A35),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                // 🚀 DEEP LINK: Trỏ thẳng sang kho ưu đãi cá nhân
                GoRouter.of(context).push('/promo');
              },
              child: const Text('Xem trong Ví', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FA),
      body: CustomScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // 1. FLOATING SEARCH & POINTS BAR
          SliverAppBar(
            floating: true,
            snap: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.only(left: 12, top: 8),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 18),
                ),
              ),
            ),
            title: _buildFloatingSearchBar(),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16, top: 8),
                child: GestureDetector(
                  onTap: () => context.push('/wallet'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A35),
                      borderRadius: BorderRadius.circular(35),
                      boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.stars_rounded, color: Color(0xFFFCD34D), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          NumberFormat.decimalPattern('vi_VN').format(_pointsBalance),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            bottom: const PreferredSize(preferredSize: Size.fromHeight(10), child: SizedBox()),
          ),

          // 2. LIVE TICKER STREAM (Dynamic Island $35px)
          SliverToBoxAdapter(
            child: _buildLiveTickerStream(),
          ),

          // 3. BẢNG VÀNG VIP HUNTERS (Top 3 Vinh Danh)
          SliverToBoxAdapter(
            child: _buildVipHuntersLeaderboard(),
          ),

          // 4. HERO VIP SPOTLIGHT CAROUSEL
          SliverToBoxAdapter(
            child: _buildSpotlightCarousel(),
          ),

          // 5. TIME-SLOT FILTER RIBBON (35px Pill)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _buildTimeSlotRibbon(),
            ),
          ),

          // 6. FLASH DEAL CUỘN NGANG (Khan Hiếm < 5 Lượt)
          if (_vouchers.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildFlashDealHorizontalList(),
            ),

          // 7. DEAL DỄ ĐỔI DƯỚI 20.000 ĐIỂM (Micro-Point Entry)
          SliverToBoxAdapter(
            child: _buildMicroPointDealsList(),
          ),

          // 8. BENTO SPOTLIGHT: ĐỐI TÁC VIP CỦA TUẦN
          SliverToBoxAdapter(
            child: _buildFeaturedPartnerBentoCard(),
          ),

          // 🚀 PHASE 08: BANNER KÊU GỌI NÂNG CẤP ĐỐI TÁC HỘI VIÊN (APPLE WELLNESS STYLE)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2ECE9)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.stars_rounded, color: Color(0xFFE63956), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Bạn là Cơ sở Đối tác?',
                          style: TextStyle(color: Color(0xFF14302B), fontSize: 13, fontWeight: FontWeight.w900),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Nâng cấp Pro/Diamond để phát hành Voucher VIP độc quyền.',
                          style: TextStyle(color: Color(0xFF6B8782), fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF14302B),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => context.push('/partner/membership'),
                    child: const Text('Nâng cấp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ),

          // 9. LƯỚI KHÁM PHÁ TOÀN BỘ VOUCHER VIP (SliverGrid)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(left: 16, top: 20, bottom: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('💎 Toàn Bộ Kho Deal Đặc Quyền', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                  Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text('${_filteredVouchers.length} mã sẵn có', style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),

          _buildVoucherGrid(),

          // Đệm đáy an toàn
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildFloatingSearchBar() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Colors.black45, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (v) => _applyFilters(),
              style: const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Tìm theo cơ sở, mã VIP...',
                hintStyle: TextStyle(color: Colors.black38, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _searchController.clear();
                _applyFilters();
              },
              child: const Icon(Icons.clear_rounded, color: Colors.black38, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildSpotlightCarousel() {
    return SizedBox(
      height: 160,
      child: PageView.builder(
        controller: _spotlightPageController,
        itemCount: _spotlightBanners.length,
        onPageChanged: (idx) => setState(() => _currentSpotlightIndex = idx),
        physics: const BouncingScrollPhysics(),
        itemBuilder: (context, index) {
          final item = _spotlightBanners[index];
          final List<Color> colors = item['colors'] as List<Color>;

          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              boxShadow: [BoxShadow(color: colors[0].withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -15,
                  bottom: -15,
                  child: Icon(Icons.stars_rounded, size: 120, color: Colors.white.withValues(alpha: 0.05)),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Text(item['badge'].toString(), style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 8),
                      Text(item['title'].toString(), style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900, height: 1.2)),
                      const SizedBox(height: 4),
                      Text(item['desc'].toString(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_spotlightBanners.length, (dotIdx) {
                      final isActive = _currentSpotlightIndex == dotIdx;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 2.5),
                        width: isActive ? 14 : 4,
                        height: 4,
                        decoration: BoxDecoration(color: isActive ? Colors.white : Colors.white30, borderRadius: BorderRadius.circular(2)),
                      );
                    }),
                  ),
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTimeSlotRibbon() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.access_time_filled_rounded, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 6),
                  Text(
                    'Khung giờ vàng áp dụng',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1A3A35)),
                  ),
                ],
              ),
              if (_selectedTimeSlot != 'ALL')
                GestureDetector(
                  onTap: () {
                    setState(() => _selectedTimeSlot = 'ALL');
                    _applyFilters();
                  },
                  child: const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text('Đặt lại ✕', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _timeSlots.length,
            itemBuilder: (context, index) {
              final slot = _timeSlots[index];
              final isSelected = _selectedTimeSlot == slot;

              return GestureDetector(
                onTap: () {
                  setState(() => _selectedTimeSlot = slot);
                  _applyFilters();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFF1A3A35) : Colors.white,
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: isSelected ? Colors.transparent : const Color(0xFFE2ECEB), width: 1.2),
                    boxShadow: isSelected ? [BoxShadow(color: const Color(0xFF1A3A35).withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 3))] : null,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 14, color: isSelected ? const Color(0xFFFCD34D) : Colors.black45),
                      const SizedBox(width: 6),
                      Text(
                        slot == 'ALL' ? 'Tất cả giờ' : slot,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFlashDealHorizontalList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 10, bottom: 10),
          child: Row(
            children: [
              Text('⚡ Flash Deal Giờ Vàng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
              SizedBox(width: 8),
              Icon(Icons.bolt_rounded, color: Colors.amber, size: 18),
            ],
          ),
        ),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _vouchers.length,
            itemBuilder: (context, index) {
              final v = _vouchers[index];
              final double ratio = v.totalQuantity > 0 ? (v.usedQuantity / v.totalQuantity) : 0.0;

              return GestureDetector(
                onTap: () => _showVoucherDetailsModal(v),
                child: Container(
                  width: 230,
                  margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(35),
                    border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 3))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                v.discountType == 'PERCENTAGE' ? '-${v.discountValue.toInt()}%' : '-${_currencyFormat.format(v.discountValue)}',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Color(0xFF1A3A35), letterSpacing: -0.5),
                              ),
                              const SizedBox(height: 2),
                              Text(v.partnerName ?? 'Cơ sở', style: const TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: ratio,
                                  backgroundColor: const Color(0xFFF4F7F6),
                                  valueColor: AlwaysStoppedAnimation<Color>(ratio >= 0.8 ? const Color(0xFFFE2C55) : const Color(0xFF10B981)),
                                  minHeight: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 64,
                        height: double.infinity,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFF1A3A35),
                          borderRadius: BorderRadius.horizontal(right: Radius.circular(33)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('${NumberFormat.decimalPattern('vi_VN').format(v.pointPrice / 1000)}k', style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 13, fontWeight: FontWeight.w900)),
                            const Text('ĐIỂM', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVoucherGrid() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator(color: Color(0xFF1A3A35)))),
      );
    }

    if (_filteredVouchers.isEmpty) {
      return const SliverToBoxAdapter(
        child: Center(child: Padding(padding: EdgeInsets.all(40), child: Text('Không tìm thấy Voucher VIP phù hợp.', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)))),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final v = _filteredVouchers[index];
            final double ratio = v.totalQuantity > 0 ? (v.usedQuantity / v.totalQuantity) : 0.0;

            return GestureDetector(
              onTap: () => _showVoucherDetailsModal(v),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🚀 NÂNG CẤP: Header Thẻ Voucher Phối Màu Imperial Ruby Thượng Lưu
                    Container(
                      height: 85,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFE63956), Color(0xFFB81534)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(21)),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -10, 
                            top: -10, 
                            child: Icon(Icons.workspace_premium_rounded, size: 70, color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.2), 
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    'VIP PASS', 
                                    style: TextStyle(color: Colors.white, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                                  ),
                                ),
                                Text(
                                  v.discountType == 'PERCENTAGE' ? '-${v.discountValue.toInt()}%' : '-${_currencyFormat.format(v.discountValue)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        v.partnerName ?? 'VIP Facility', 
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF14302B)), 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const PartnerTierBadge(isPremium: true, premiumTier: 'DIAMOND', isCompact: true),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.access_time_rounded, size: 12, color: Color(0xFF10B981)),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        v.fixedTimeSlot ?? '', 
                                        style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold), 
                                        maxLines: 1, 
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${NumberFormat.decimalPattern('vi_VN').format(v.pointPrice)} Điểm',
                                      style: const TextStyle(color: Color(0xFFD97706), fontSize: 12, fontWeight: FontWeight.w900),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(color: Color(0xFF1A3A35), shape: BoxShape.circle),
                                      child: const Icon(Icons.shopping_bag_rounded, color: Colors.white, size: 12),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    backgroundColor: const Color(0xFFF4F7F6),
                                    valueColor: AlwaysStoppedAnimation<Color>(ratio >= 0.85 ? const Color(0xFFFE2C55) : const Color(0xFF10B981)),
                                    minHeight: 3,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
          childCount: _filteredVouchers.length,
        ),
      ),
    );
  }

  // --- 1. WIDGET LIVE TICKER STREAM (DYNAMIC ISLAND) ---
  Widget _buildLiveTickerStream() {
    final List<String> tickerEvents = [
      '🔥 @hoang_nam vừa đổi mã [VIPOASIS50] cách đây 2 phút',
      '🎉 @minh_thu vừa mở khóa Deal 100k An Sinh Clinic',
      '⚡ Chỉ còn 8 suất [ROYALSKIN30] cho khung giờ 18:00',
      '✨ @quang_huy đã nhận thành công Voucher Yoga Zenith'
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A3A35).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(35),
        border: Border.all(color: const Color(0xFF80BF84).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
            child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tickerEvents[_currentSpotlightIndex % tickerEvents.length],
              style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Text('Live •', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // --- 2. WIDGET BẢNG VÀNG VIP HUNTERS (TOP 3 VINH DANH) ---
  Widget _buildVipHuntersLeaderboard() {
    final topHunters = [
      {"name": "Đặng Mỹ", "tag": "@dangmy", "deals": "18 Deal", "avatar": "https://ui-avatars.com/api/?name=Dang+My&background=1A3A35&color=FCD34D", "rankColor": const Color(0xFFF59E0B), "badge": "👑 TOP 1"},
      {"name": "Thu Hà", "tag": "@thuha", "deals": "14 Deal", "avatar": "https://ui-avatars.com/api/?name=Thu+Ha&background=64748B&color=fff", "rankColor": const Color(0xFF94A3B8), "badge": "🥈 TOP 2"},
      {"name": "Văn Đức", "tag": "@vanduc", "deals": "11 Deal", "avatar": "https://ui-avatars.com/api/?name=Van+Duc&background=B45309&color=fff", "rankColor": const Color(0xFFD97706), "badge": "🥉 TOP 3"},
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECEB)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Color(0xFFD97706), size: 16),
                  SizedBox(width: 6),
                  Text('Bảng Vàng VIP Hunters Tuần', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                child: const Text('Cập nhật 00:00', style: TextStyle(color: Color(0xFFD97706), fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: topHunters.map((hunter) {
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBF9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: (hunter['rankColor'] as Color).withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          CircleAvatar(radius: 16, backgroundImage: NetworkImage(hunter['avatar'] as String)),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: hunter['rankColor'] as Color, borderRadius: BorderRadius.circular(6)),
                              child: Text(hunter['badge'] as String, style: const TextStyle(color: Colors.white, fontSize: 6, fontWeight: FontWeight.w900)),
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(hunter['name'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF1A3A35)), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(hunter['deals'] as String, style: const TextStyle(fontSize: 9, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --- 3. WIDGET DEAL DƯỚI 20K ĐIỂM (MICRO-POINT ENTRY) ---
  Widget _buildMicroPointDealsList() {
    final microDeals = _vouchers.where((v) => v.pointPrice <= 20000).toList();
    if (microDeals.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.monetization_on_rounded, color: Color(0xFF10B981), size: 16),
                  SizedBox(width: 6),
                  Text('Deal Dễ Đổi Dưới 20.000 Điểm', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                ],
              ),
              Text('${microDeals.length} deal', style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: microDeals.length,
            itemBuilder: (context, index) {
              final v = microDeals[index];
              return GestureDetector(
                onTap: () => _showVoucherDetailsModal(v),
                child: Container(
                  width: 200,
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2ECEB)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.stars_rounded, color: Color(0xFF10B981), size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              v.discountType == 'PERCENTAGE' ? 'Giảm ${v.discountValue.toInt()}%' : 'Giảm ${_currencyFormat.format(v.discountValue)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(v.partnerName ?? 'Cơ sở', style: const TextStyle(fontSize: 10, color: Colors.black45), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 4),
                            Text('${NumberFormat.decimalPattern('vi_VN').format(v.pointPrice)} Điểm', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- 4. 🚀 PHASE 08: BENTO SPOTLIGHT ĐỐI TÁC VIP 5 SAO TUẦN NÀY ---
  Widget _buildFeaturedPartnerBentoCard() {
    if (_vouchers.isEmpty) return const SizedBox.shrink();
    final featuredVoucher = _vouchers.first;

    return SparkleOverlay(
      sparkleColor: const Color(0xFFFF80AB),
      particleCount: 4,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF2A0812), Color(0xFF501020), Color(0xFF14302B)], 
            begin: Alignment.topLeft, 
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFFF80AB).withValues(alpha: 0.4), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE63956).withValues(alpha: 0.3), 
              blurRadius: 18, 
              offset: const Offset(0, 6)
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFFCD34D).withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_rounded, color: Color(0xFFFCD34D), size: 14),
                      SizedBox(width: 4),
                      Text('ĐỐI TÁC 5 SAO TUẦN NÀY', style: TextStyle(color: Color(0xFFFCD34D), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
              ],
            ),
            const SizedBox(height: 14),
            Row(
            children: [
              PartnerAvatarFrame(
                avatarUrl: 'https://ui-avatars.com/api/?name=${Uri.encodeComponent(featuredVoucher.partnerName ?? "Partner")}&background=80BF84&color=fff',
                size: 44,
                isPremium: true,
                premiumTier: 'DIAMOND',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            featuredVoucher.partnerName ?? 'Cơ sở chuyên khoa VIP', 
                            style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w900), 
                            maxLines: 1, 
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const PartnerTierBadge(isPremium: true, premiumTier: 'DIAMOND', isCompact: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    const Text('Trải nghiệm y tế chuẩn 5 sao • Đánh giá 4.9★', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Mã VIP Độc Quyền:', style: TextStyle(color: Colors.white60, fontSize: 10)),
                        const SizedBox(height: 2),
                        Text(
                          '[${featuredVoucher.code}] ${featuredVoucher.discountType == "PERCENTAGE" ? "Giảm ${featuredVoucher.discountValue.toInt()}%" : "Giảm ${_currencyFormat.format(featuredVoucher.discountValue)}"}',
                          style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 13, fontWeight: FontWeight.w900),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF80BF84),
                      foregroundColor: const Color(0xFF0F2B26),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _showVoucherDetailsModal(featuredVoucher),
                    child: const Text('Xem Deal', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- ANIMATION APPLE-STYLE TICK ---
class _AppleTickAnimationDialog extends StatefulWidget {
  const _AppleTickAnimationDialog();
  @override
  State<_AppleTickAnimationDialog> createState() => _AppleTickAnimationDialogState();
}

class _AppleTickAnimationDialogState extends State<_AppleTickAnimationDialog> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 8))],
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 70),
          ),
        ),
      ),
    );
  }
}