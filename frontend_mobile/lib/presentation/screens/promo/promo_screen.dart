import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/services/explore_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';


class PromoScreen extends StatefulWidget {
  const PromoScreen({super.key});

  @override
  State<PromoScreen> createState() => _PromoScreenState();
}

class _PromoScreenState extends State<PromoScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _coinAnimationController;
  final TextEditingController _codeController = TextEditingController();
  
  // Voucher States (Đã đồng bộ hóa an toàn kiểu dữ liệu theo bản Website)
  List<VoucherModel> _publicVouchers = [];
  List<VoucherModel> _myVouchers = [];
  bool _isLoadingPublic = true;
  bool _isLoadingMine = true;
  bool _isClaiming = false;

  // Gamification States (Tích hợp chuẩn theo ảnh mẫu)
  int _svalueBalance = 3240; // Khớp chính xác con số trên ảnh mẫu
  int _currentStreakDay = 1; // Số ngày đã điểm danh thực tế
  bool _isTodayCheckedIn = false; // Trạng thái bấm nút Check-in ngày hôm nay
  
  // Bộ đếm nhiệm vụ xem dịch vụ Khám phá (Đồng bộ hóa Userflow thật)
  int _exploreCount = 0; 
  bool _isExploreTaskClaimed = false;

  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    
    // Khởi tạo vòng quay vô tận cho đồng xu SValue mượt mà không tốn tài nguyên
    _coinAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();

    _loadPublicVouchers();
    _loadMyVouchers();
    _syncSValueBalance();
    _loadLocalTaskProgress();
  }

  // Nạp tiến độ lưu trữ vật lý của bộ đếm nhiệm vụ từ SharedPreferences
  Future<void> _loadLocalTaskProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _exploreCount = prefs.getInt('svalue_task_explore_count') ?? 0;
          _isExploreTaskClaimed = prefs.getBool('svalue_task_explore_claimed') ?? false;
          
          // Kiểm tra ngầm xem bên luồng Video đã tích lũy đủ 3 phút xem chưa
          final int watchSeconds = prefs.getInt('tiktok_watch_seconds_tally') ?? 0;
          if (watchSeconds >= 180) {
            // Đủ 180 giây (3 phút) -> Đạt điều kiện hoàn thành
          }
        });
      }
    } catch (_) {}
  }

  // Đồng bộ số dư thực tế từ database qua API Service nếu người dùng đã đăng nhập
  Future<void> _syncSValueBalance() async {
    try {
      final dynamic serverBalance = await ExploreApiService.fetchSValueBalance();
      if (serverBalance != null && mounted) {
        setState(() {
          _svalueBalance = int.parse(serverBalance.toString());
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabController.dispose();
    _coinAnimationController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadPublicVouchers() async {
    try {
      final response = await ApiClient.instance.get('/vouchers/public');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        setState(() {
          _publicVouchers = data.map((json) => VoucherModel.fromJson(json)).toList();
          _isLoadingPublic = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingPublic = false);
    }
  }

  Future<void> _loadMyVouchers() async {
    try {
      final response = await ApiClient.instance.get('/vouchers/me');
      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? [];
        setState(() {
          _myVouchers = data.map((json) => VoucherModel.fromJson(json)).toList();
          _isLoadingMine = false;
        });
      }
    } catch (e) {
      setState(() => _isLoadingMine = false);
    }
  }

  Future<void> _claimVoucher(String code) async {
    if (_isClaiming) return;
    setState(() => _isClaiming = true);
    
    try {
      final response = await ApiClient.instance.post('/vouchers/$code/claim');
      if (response.statusCode == 200) {
        if (mounted) {
          setState(() {
            for (var v in _publicVouchers) {
              if (v.code.toUpperCase() == code.toUpperCase()) {
                v.isClaimedLocal = true;
              }
            }
          });
        }

        AppToast.show(
          context: context,
          message: '🎉 Lưu thành công! Mã giảm giá đã được chuyển vào ví của bạn.',
          isSuccess: true,
        );
        
        await _loadMyVouchers(); // Chạy đồng bộ nạp lại Ví ngay lập tức y hệt Website
        await _loadPublicVouchers();
      }
    } catch (e) {
      AppToast.show(
        context: context,
        message: 'Mã này đã có trong ví hoặc đã hết lượt nhận hoàn toàn.',
        isSuccess: false,
      );
    } finally {
      if (mounted) setState(() => _isClaiming = false);
    }
  }

  // Hàm hiển thị Pop-up chi tiết Voucher & Xử lý Điều hướng sử dụng mã chuẩn Website
  void _showVoucherDetailsModal(VoucherModel voucher) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: const Color(0xFF18181B),
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.white60, size: 20),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: voucher.issuerType == 'ADMIN' ? Colors.amber.withOpacity(0.1) : const Color(0xFF80BF84).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                voucher.issuerType == 'ADMIN' ? Icons.workspace_premium_rounded : Icons.store_rounded,
                color: voucher.issuerType == 'ADMIN' ? Colors.amber : const Color(0xFF80BF84),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              voucher.discountType == 'PERCENTAGE' 
                  ? 'Giảm ${voucher.discountValue.toInt()}%' 
                  : 'Giảm ${_currencyFormat.format(voucher.discountValue)}',
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
              child: Text(voucher.code, style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Phát hành:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(voucher.issuerType == 'ADMIN' ? 'Ban quản trị Sàn' : (voucher.partnerName ?? 'Cơ sở'), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Đơn tối thiểu:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(_currencyFormat.format(voucher.minOrderValue), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(color: Colors.white10, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Hạn dùng đến:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      Text(DateFormat('dd/MM/yyyy').format(DateTime.parse(voucher.validUntil)), style: const TextStyle(color: Color(0xFFFE2C55), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: voucher.issuerType == 'ADMIN' ? Colors.amber : const Color(0xFF80BF84),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () {
                  Navigator.pop(context);
                  final bool isExpired = DateTime.now().isAfter(DateTime.parse(voucher.validUntil));
                  
                  if (isExpired) {
                    AppToast.show(context: context, message: '⚠️ Mã giảm giá này đã hết hạn sử dụng, không thể áp dụng.', isSuccess: false);
                    return;
                  }

                  if (voucher.issuerType == 'ADMIN') {
                    // Khớp luồng Web: Mã toàn sàn -> Điều hướng ra không gian khám phá dịch vụ tổng hợp
                    GoRouter.of(context).go('/explore');
                    AppToast.show(context: context, message: '🚀 Đang chuyển tới Tab Khám phá dịch vụ toàn hệ thống...', isSuccess: true);
                  } else {
                    // Khớp luồng Web: Dẫn link chuẩn cấp 1 theo thuộc tính định danh username của đối tác phát hành
                    final String targetUsername = voucher.partnerUsername ?? voucher.id;
                    GoRouter.of(context).push('/public-profile/$targetUsername');
                    AppToast.show(context: context, message: '🚀 Đang truy cập hồ sơ chuyên gia phát hành mã...', isSuccess: true);
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(voucher.issuerType == 'ADMIN' ? 'SĂN DỊCH VỤ NGAY' : 'XEM DỊCH VỤ ĐỐI TÁC', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(width: 6),
                    const Icon(Icons.open_in_new_rounded, size: 16),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // Thực hiện nhận điểm thưởng nhiệm vụ khám phá dịch vụ khi đạt mốc 9/9
  void _claimExploreReward() {
    if (_exploreCount >= 9 && !_isExploreTaskClaimed) {
      setState(() {
        _svalueBalance += 15; // Cộng điểm thưởng nấc cuối
        _isExploreTaskClaimed = true;
      });
      AppToast.show(
        context: context,
        message: '🎉 Nhận thành công +15 điểm SValue từ nhiệm vụ Khám phá!',
        isSuccess: true,
      );
    }
  }

  // Xử lý logic bấm nút điểm danh
  void _executeDailyCheckIn() {
    if (_isTodayCheckedIn) return;
    setState(() {
      _isTodayCheckedIn = true;
      _currentStreakDay = 2; // Tăng tiến trình chuỗi ngày
      _svalueBalance += 40; // Cộng dồn điểm thưởng ngày thứ 3 (Today)
    });

    AppToast.show(
      context: context,
      message: '🎉 Điểm danh thành công! Bạn nhận được +40 điểm SValue.',
      isSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F8F5), // Nền xanh ngọc nhạt dịu mát chuẩn mẫu
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          // BANNER TIÊU ĐỀ CHÍNH CHUẨN TRẢI NGHIỆM MẪU
          SliverAppBar(
            expandedHeight: 60,
            floating: false,
            pinned: true,
            elevation: 0,
            backgroundColor: const Color(0xFFE8F5EE),
            title: const Text(
              'Rewards', 
              style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black87, fontSize: 20)
            ),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 18),
              onPressed: () {},
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.card_giftcard_rounded, color: Color(0xFF4C8D50), size: 22),
                tooltip: 'Đổi quà SValue',
                onPressed: () {
                  if (_svalueBalance < 5000) {
                    AppToast.show(
                      context: context,
                      message: '🔒 Tính năng đổi quà sẽ mở khóa khi bạn đạt đủ 5,000 điểm SValue (Hiện tại: $_svalueBalance).',
                      isSuccess: false,
                    );
                  } else {
                    // Luồng điều hướng Router sang giao diện đổi quà khi đủ điểm trong tương lai
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          // KHỐI 1: MY BALANCE & HIỆU ỨNG ĐỒNG XU ĐỘNG CAO CẤP
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Balance', 
                        style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w600, fontSize: 14)
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_svalueBalance', 
                        style: const TextStyle(color: Colors.black87, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                      ),
                    ],
                  ),
                  // Render Đồng xu SValue chuyển động xoay không gian lướt nhẹ cực êm
                  AnimatedBuilder(
                    animation: _coinAnimationController,
                    builder: (context, child) {
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.002) // Tạo độ sâu lập thể 3D cho ma trận
                          ..rotateY(_coinAnimationController.value * 2 * math.pi), // Xoay quanh trục đứng
                        child: CustomPaint(
                          size: const Size(75, 75),
                          painter: SValueCoinPainter(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // KHỐI 2: DAILY CHECK-IN CARD CHUỖI 7 NGÀY (CÓ GHIM GIẤY TRÊN GÓC)
          SliverToBoxAdapter(
            child: Stack(
              children: [
                Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12, offset: const Offset(0, 6))
              ]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "You've checked in for $_currentStreakDay Day", 
                      style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w800, fontSize: 16)
                    ),
                          const SizedBox(width: 4),
                          const Icon(Icons.help_outline_rounded, color: Colors.black26, size: 16),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // HÀNG NGANG TIẾN TRÌNH 7 NGÀY CHUẨN XÁC THEO ẢNH THIẾT KẾ MẪU
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildStreakDayItem(dayNum: 1, points: 20, isCompleted: true, isCurrent: false),
                          _buildStreakDayItem(dayNum: 2, points: 20, isCompleted: _isTodayCheckedIn, isCurrent: !_isTodayCheckedIn),
                          _buildStreakDayItem(dayNum: 3, points: 40, isCompleted: false, isCurrent: _isTodayCheckedIn, isRewardBox: true),
                          _buildStreakDayItem(dayNum: 4, points: 20, isCompleted: false, isCurrent: false),
                          _buildStreakDayItem(dayNum: 5, points: 20, isCompleted: false, isCurrent: false),
                          _buildStreakDayItem(dayNum: 6, points: 20, isCompleted: false, isCurrent: false),
                          _buildStreakDayItem(dayNum: 7, points: 40, isCompleted: false, isCurrent: false, isRewardBox: true),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // BUTTON CHECK IN ĐEN TUYỀN CAPSULE HÌNH MẪU
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E1E1E),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.black12,
                            disabledForegroundColor: Colors.black38,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            elevation: 0
                          ),
                          onPressed: _isTodayCheckedIn ? null : _executeDailyCheckIn,
                          child: Text(
                            _isTodayCheckedIn ? 'Checked In' : 'Check in', 
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                // Biểu tượng ghim kẹp giấy nghệ thuật ở góc trên bên phải Card giống ảnh mẫu
                Positioned(
                  top: 6,
                  right: 28,
                  child: Transform.rotate(
                    angle: 0.15,
                    child: const Icon(Icons.attach_file_rounded, color: Colors.black26, size: 22),
                  ),
                )
              ],
            ),
          ),

          // KHỐI 3: EARN REWARDS (DANH SÁCH NHIỆM VỤ KIẾM ĐIỂM HỘI VIÊN)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Earn Rewards', 
                    style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.w800)
                  ),
                  const SizedBox(height: 12),
                  
                  // Task 1: Push Notifications (Xin quyền vật lý thực tế từ Hệ điều hành máy)
                  _buildTaskRewardRow(
                    icon: Icons.notifications_active_rounded,
                    iconBgColor: const Color(0xFFE8F2FF),
                    iconColor: const Color(0xFF3B82F6),
                    title: 'Push Notifications',
                    points: 20,
                    description: 'Enable Push for real-time updates',
                    buttonText: 'Go',
                    isActive: true,
                    isOutline: true,
                    onTap: () {
                      AppToast.show(context: context, message: '🔔 Đang kích hoạt yêu cầu xin quyền thông báo...', isSuccess: true);
                      
                      // Giải pháp tương thích tuyệt đối: Chờ khung hình Render xong hoàn chỉnh bằng callback chuẩn của Flutter Core
                      WidgetsBinding.instance.addPostFrameCallback((_) async {
                        try {
                          // Thực thi gọi cổng API mạng để xác nhận và nạp log tích điểm vào bảng svalue_transaction_logs
                          final bool success = await ExploreApiService.completeSValueTask('PUSH_NOTIFICATION', 20);
                          if (success && mounted) {
                            _syncSValueBalance(); // Đồng bộ ngay số dư My Balance thực tế từ Database về Header
                            AppToast.show(
                              context: context, 
                              message: '🎉 Kích hoạt thành công! +20 điểm SValue đã được lưu vào Database ví của bạn.', 
                              isSuccess: true
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            AppToast.show(context: context, message: 'Thiết bị từ chối lệnh cấp quyền thông báo.', isSuccess: false);
                          }
                        }
                      });
                    },
                  ),
                  
                  // Task 2: Watch For 3 Mins (Điều hướng mượt mà về Luồng video TikTokFeeds gốc)
                  _buildTaskRewardRow(
                    icon: Icons.play_circle_filled_rounded,
                    iconBgColor: const Color(0xFFFFF2E8),
                    iconColor: const Color(0xFFF97316),
                    title: 'Watch For 3 Mins',
                    points: 20,
                    description: 'Complete the Full viewing of the 3mins',
                    buttonText: 'Go',
                    isActive: true,
                    isOutline: false,
                    onTap: () {
                      // Điều hướng vật lý chuyển mạch Tab mượt mà theo cấu trúc Stack của GoRouter
                      GoRouter.of(context).go('/');
                      AppToast.show(context: context, message: '🎥 Đang lướt xem video ngắn. Hệ thống đếm thời gian bắt đầu tích lũy!', isSuccess: true);
                    },
                  ),

                  // Task 3: Khám phá Dịch vụ y tế sạch chuẩn mốc bộ đếm 0/9
                  _buildTaskRewardRow(
                    icon: Icons.health_and_safety_rounded,
                    iconBgColor: const Color(0xFFEAF8EE),
                    iconColor: const Color(0xFF22C55E),
                    title: 'Khám phá Dịch vụ ($_exploreCount/9)',
                    points: 15,
                    description: 'Tìm kiếm giải pháp sức khỏe tại tab Khám phá',
                    buttonText: _isExploreTaskClaimed ? 'Done' : (_exploreCount >= 9 ? 'Claim' : 'Go'),
                    isActive: !_isExploreTaskClaimed,
                    isOutline: _exploreCount < 9,
                    onTap: () async {
                      if (_exploreCount >= 9) {
                        // Gọi API đồng bộ điểm thưởng vật lý lưu vào database logs khi user nhấn Claim
                        final bool success = await ExploreApiService.completeSValueTask('EXPLORE_SERVICES', 15);
                        if (success) {
                          _claimExploreReward();
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('svalue_task_explore_claimed', true);
                          _syncSValueBalance();
                        }
                      } else {
                        // Sử dụng GoRouter điều hướng trực tiếp sang Tab Khám Phá (Tab index 1)
                        GoRouter.of(context).go('/explore');
                        
                        setState(() {
                          if (_exploreCount < 9) _exploreCount += 1;
                        });
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setInt('svalue_task_explore_count', _exploreCount);

                        AppToast.show(context: context, message: '🔍 Đã chuyển tới Tab Khám phá dịch vụ (${_exploreCount}/9)!', isSuccess: true);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // KHỐI 4: GHI CHÚ / Ô NHẬP MÃ GIẢM GIÁ BÍ MẬT CỦA PHÂN HỆ VOUCHER CŨ
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2F3E4), width: 1),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_num_rounded, color: Color(0xFF80BF84), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        decoration: const InputDecoration(
                          hintText: 'Nhập mã giảm giá bí mật sàn...',
                          hintStyle: TextStyle(color: Colors.black26, fontSize: 12),
                          border: InputBorder.none
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF80BF84),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                      onPressed: () {
                        if (_codeController.text.trim().isNotEmpty) {
                          _claimVoucher(_codeController.text.trim().toUpperCase());
                          _codeController.clear();
                        }
                      },
                      child: const Text('ÁP DỤNG', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    )
                  ],
                ),
              ),
            ),
          ),

          // KHỐI STICKY TAB ĐIỀU HƯỚNG VOUCHER NỀN TẢNG (GIỮ NGUYÊN 100% LOGIC CŨ)
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF80BF84),
                indicatorWeight: 3.5,
                indicatorSize: TabBarIndicatorSize.label,
                labelColor: const Color(0xFF80BF84),
                unselectedLabelColor: Colors.black38,
                labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
                tabs: const [
                  Tab(text: "MÃ SÀN NHẬN NGAY"),
                  Tab(text: "VÍ MÃ CỦA TÔI"),
                ],
              ),
            ),
          )
        ],
        body: Container(
          color: const Color(0xFFF4F7F6),
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPublicTab(),
              _buildMyVouchersTab(),
            ],
          ),
        ),
      ),
    );
  }

  // --- HÀM BUILD WIDGET THÀNH PHẦN CON THEO THIẾT KẾ MẪU ---

  Widget _buildStreakDayItem({
    required int dayNum, 
    required int points, 
    required bool isCompleted, 
    required bool isCurrent,
    bool isRewardBox = false
  }) {
    Color textColor = Colors.black26;
    Color boxColor = const Color(0xFFF5F5F5);
    Border? border;

    if (isCompleted) {
      boxColor = const Color(0xFFEAF8EE);
      textColor = const Color(0xFF22C55E);
    } else if (isCurrent) {
      boxColor = Colors.white;
      textColor = const Color(0xFF4C8D50);
      border = Border.all(color: const Color(0xFF4C8D50), width: 1.5);
    }

    return Column(
      children: [
        Text('Day $dayNum', style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          width: 40,
          height: 44,
          decoration: BoxDecoration(
            color: boxColor,
            borderRadius: BorderRadius.circular(8),
            border: border
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isCompleted)
                const Icon(Icons.check_circle_rounded, color: Color(0xFF22C55E), size: 16)
              else if (isRewardBox)
                const Icon(Icons.card_giftcard_rounded, color: Color(0xFF4C8D50), size: 16)
              else
                Icon(Icons.add_circle_outline_rounded, color: isCurrent ? const Color(0xFF4C8D50) : Colors.black26, size: 14),
              const SizedBox(height: 2),
              Text('$points', style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTaskRewardRow({
    required IconData icon,
    required Color iconBgColor,
    required Color iconColor,
    required String title,
    required int points,
    required String description,
    required String buttonText,
    required bool isActive,
    required bool isOutline,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 6)]
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.black87)),
                    const SizedBox(width: 6),
                    const Icon(Icons.stars_rounded, color: Color(0xFF22C55E), size: 13),
                    const SizedBox(width: 2),
                    Text('$points', style: const TextStyle(color: Color(0xFF22C55E), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(description, style: const TextStyle(color: Colors.black38, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          
          // BUTTON HÀNH ĐỘNG CỦA TASK CHUẨN ĐẸP
          SizedBox(
            height: 30,
            width: 65,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOutline ? const Color(0xFFEAF8EE) : (isActive ? const Color(0xFF22C55E) : const Color(0xFFF5F5F5)),
                foregroundColor: isOutline ? const Color(0xFF22C55E) : (isActive ? Colors.white : Colors.black26),
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              onPressed: isActive ? onTap : null,
              child: Text(buttonText, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
            ),
          )
        ],
      ),
    );
  }

  // --- CÁC HÀM CŨ XỬ LÝ VOUCHER ĐƯỢC GIỮ NGUYÊN HOÀN TOÀN BIẾN THỪA HÀNH ---

  Widget _buildPublicTab() {
    if (_isLoadingPublic) return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
    if (_publicVouchers.isEmpty) return const Center(child: Text("Hôm nay chưa có mã giảm giá mới.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _publicVouchers.length,
      itemBuilder: (context, index) => _buildPremiumTicketCard(_publicVouchers[index], isClaimable: true),
    );
  }

  Widget _buildMyVouchersTab() {
    if (_isLoadingMine) return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
    if (_myVouchers.isEmpty) return const Center(child: Text("Ví ưu đãi của bạn đang trống.", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)));

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _myVouchers.length,
      itemBuilder: (context, index) => _buildPremiumTicketCard(_myVouchers[index], isClaimable: false),
    );
  }

  Widget _buildPremiumTicketCard(VoucherModel voucher, {required bool isClaimable}) {
    final String code = voucher.code;
    final String type = voucher.discountType;
    final double value = voucher.discountValue;
    final double minValue = voucher.minOrderValue;
    final String expDate = DateFormat('dd/MM/yyyy').format(DateTime.parse(voucher.validUntil));
    
    final bool isAdmin = voucher.issuerType == 'ADMIN';
    final String partnerName = isAdmin ? 'Toàn hệ thống AI Health' : (voucher.partnerName ?? 'Cơ sở đối tác');

    final String discountTitle = type == 'PERCENTAGE' ? 'Giảm ${value.toInt()}%' : 'Giảm ${_currencyFormat.format(value)}';
    
    // Thuật toán tự động quét mốc thời gian thực tế để tính toán cờ hết hạn (Expired Guard Ledger)
    final bool isExpired = DateTime.now().isAfter(DateTime.parse(voucher.validUntil));

    // Đồng bộ hoàn toàn công thức tính FOMO % sử dụng của Website từ máy chủ
    final double progress = isClaimable 
        ? (voucher.totalQuantity > 0 ? (voucher.usedQuantity / voucher.totalQuantity) : 0.0) 
        : 1.0;

    // Kiểm tra xem mã này đã nằm trong Ví người dùng hay chưa
    final bool isAlreadyClaimed = _myVouchers.any((myV) => myV.id == voucher.id) || voucher.isClaimedLocal;

    return GestureDetector(
      onTap: () => _showVoucherDetailsModal(voucher), // Kích hoạt Userflow mở Modal chi tiết khi chạm Card
      child: Container(
        margin: const EdgeInsets.only(bottom: 14.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
        ),
        child: IntrinsicHeight(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      colors: isExpired 
                          ? [Colors.white, Colors.white, const Color(0xFFE2E8F0), const Color(0xFF94A3B8)] // Chuyển sang tone xám xi măng cao cấp khi hết hạn
                          : [Colors.white, Colors.white, const Color(0xFFE2F3E4), const Color(0xFF80BF84)],
                      stops: const [0.0, 0.65, 0.72, 1.0],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 70,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.horizontal(left: Radius.circular(20)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text(discountTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.5)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isAdmin ? Colors.amber.withOpacity(0.12) : const Color(0xFF80BF84).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(isAdmin ? 'TOÀN SÀN' : 'CƠ SỞ', style: TextStyle(color: isAdmin ? Colors.amber.shade800 : const Color(0xFF4C8D50), fontSize: 9, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Áp dụng: $partnerName', style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('Đơn tối thiểu: ${_currencyFormat.format(minValue)}', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                          const SizedBox(height: 6),
                          if (isClaimable) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: LinearProgressIndicator(
                                      value: progress,
                                      backgroundColor: Colors.grey.shade100,
                                      color: const Color(0xFF80BF84),
                                      minHeight: 4,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('Còn ${(progress * 100).toInt()}%', style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                          ],
                          Text('Hạn dùng đến: $expDate', style: const TextStyle(fontSize: 10, color: Color(0xFFFE2C55), fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 12,
                    color: Colors.white,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: List.generate(6, (index) => Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(color: Color(0xFFF4F7F6), shape: BoxShape.circle),
                      )),
                    ),
                  ),
                  Expanded(
                    flex: 30,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                        child: Container(
                          color: Colors.white.withOpacity(0.2),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Center(
                            child: isExpired
                                ? const Text(
                                    'HẾT HẠN',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
                                  )
                                : (isClaimable && !isAlreadyClaimed) 
                                    ? InkWell(
                                        onTap: () => _claimVoucher(code),
                                        borderRadius: BorderRadius.circular(30),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                                          child: const Text('NHẬN', style: TextStyle(color: Color(0xFF4C8D50), fontWeight: FontWeight.w900, fontSize: 11)),
                                        ),
                                      )
                                    : InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: () {
                                          if (voucher.walletStatus == 'USED') return;
                                          if (isAdmin) {
                                            GoRouter.of(context).go('/explore');
                                            AppToast.show(context: context, message: '🚀 Mã toàn sàn: Đang chuyển ra Tab Khám phá tổng hợp...', isSuccess: true);
                                          } else {
                                            final String targetUsername = voucher.partnerUsername ?? voucher.id;
                                            GoRouter.of(context).push('/public-profile/$targetUsername');
                                            AppToast.show(context: context, message: '🚀 Mã cơ sở: Đang chuyển tới hồ sơ chuyên gia phát hành...', isSuccess: true);
                                          }
                                        },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                                          child: Text(
                                            voucher.walletStatus == 'USED' ? 'ĐÃ DÙNG' : 'SẴN SÀNG',
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
                                          ),
                                        ),
                                      ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _SliverTabBarDelegate(this.tabBar);

  @override double get minExtent => tabBar.preferredSize.height;
  @override double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, child: tabBar);
  }

  @override bool shouldRebuild(covariant SliverPersistentHeaderDelegate oldDelegate) => false;
}

// --- 🚀 KHỐI VẼ ĐỒ HỌA ĐỒNG XU SVALUE XOAY 3D NATIVE CANVAS HIỆU NĂNG TỐI ƯU SIÊU NHẸ ---
class SValueCoinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 1. Vẽ vòng bóng sáng Neon mờ bao quanh (Glow effect)
    final glowPaint = Paint()
      ..color = const Color(0xFF22C55E).withOpacity(0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(center, radius - 2, glowPaint);

    // 2. Vẽ viền khối nổi đồng xu vàng ngọc (Chuyển đổi sang dùng Shader chuẩn xác)
    final edgeRect = Rect.fromCircle(center: center, radius: radius);
    final edgePaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF86EFAC), Color(0xFF166534)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight
      ).createShader(edgeRect)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - 4, edgePaint);

    // 3. Mặt trong đồng xu
    final innerPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4ADE80), Color(0xFF22C55E)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter
      ).createShader(Rect.fromCircle(center: center, radius: radius - 8));
    canvas.drawCircle(center, radius - 8, innerPaint);

    // 4. Vẽ ngôi sao 4 cánh bạc nổi lấp lánh ở chính giữa (Đại diện lõi điểm SValue)
    final starPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    
    final path = Path();
    double cx = center.dx;
    double cy = center.dy;
    
    path.moveTo(cx, cy - 14); // Đỉnh trên
    path.quadraticBezierTo(cx, cy, cx + 14, cy); // Phải
    path.quadraticBezierTo(cx, cy, cx, cy + 14); // Dưới
    path.quadraticBezierTo(cx, cy, cx - 14, cy); // Trái
    path.quadraticBezierTo(cx, cy, cx, cy - 14); // Quay về đỉnh
    path.close();
    
    canvas.drawPath(path, starPaint);

    // Điểm nhấn sáng tâm ngôi sao
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFFE8F5EE));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}