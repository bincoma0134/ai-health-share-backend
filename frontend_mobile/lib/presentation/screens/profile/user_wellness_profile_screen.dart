import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter; // Import bắt buộc cho Glassmorphism
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';
import 'package:intl/intl.dart'; // Đảm bảo format số tiền
import '../wallet_screen.dart'; // Dynamic import cục bộ



class UserWellnessProfileScreen extends StatefulWidget {
  const UserWellnessProfileScreen({super.key});

  @override
  State<UserWellnessProfileScreen> createState() => _UserWellnessProfileScreenState();
}

class _UserWellnessProfileScreenState extends State<UserWellnessProfileScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  bool _isSubmittingMood = false;
  Map<String, dynamic>? _wellnessData;
  late AnimationController _pulseController;
  final PageController _pageController = PageController(); // 🚀 Khởi tạo biến điều hướng Trang

  // 🚀 Logic gửi dữ liệu Nhật ký vi mô (Micro-Mood) xuống Database
  Future<void> _submitMood(String moodState, String bodyFocus) async {
    if (_isSubmittingMood) return;
    setState(() => _isSubmittingMood = true);
    try {
      final res = await ApiClient.instance.post('/user/wellness/logs', data: {
        'mood_state': moodState,
        'body_focus': bodyFocus,
      });
      if (res.statusCode == 200) {
        AppToast.show(context: context, message: 'Đã ghi nhận thể trạng! Hệ thống đang phân tích...', isSuccess: true);
      }
    } catch (e) {
      AppToast.show(context: context, message: 'Chưa thể ghi nhận lúc này', isSuccess: false);
    } finally {
      setState(() => _isSubmittingMood = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _fetchWellnessProfile();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pageController.dispose(); // Giải phóng bộ nhớ
    super.dispose();
  }

  Future<void> _fetchWellnessProfile() async {
    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.get('/user/wellness/profile');
      if (res.statusCode == 200 && res.data != null) {
        setState(() {
          _wellnessData = res.data['data'];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        AppToast.show(context: context, message: 'Không thể tải dữ liệu hành trình', isSuccess: false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      AppToast.show(context: context, message: 'Lỗi kết nối máy chủ hành trình', isSuccess: false);
    }
  }

  Color _getVitalityColor(int score) {
    if (score <= 20) return const Color(0xFFE67E22); // Cam kích hoạt
    if (score <= 50) return const Color(0xFF3498DB); // Xanh dương hồi phục
    if (score <= 80) return const Color(0xFF2ECC71); // Xanh lá cân bằng
    return const Color(0xFFFF7A8A); // Hồng cánh sen tối ưu Premium
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarPadding = MediaQuery.paddingOf(context).top;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4F9F6),
        body: Padding(
          padding: EdgeInsets.only(top: statusBarPadding + 20, left: 24, right: 24),
          child: const ShimmerWrapper(child: SizedBox(height: 200, width: double.infinity)),
        ),
      );
    }

    final data = _wellnessData ?? {};
    final int score = data['vitality_score'] ?? 0;
    final int minutes = data['total_wellness_minutes'] ?? 0;
    final int sessions = data['total_sessions'] ?? 0;
    final String stateText = data['state_text'] ?? 'Chưa có dữ liệu';
    final String recommendation = data['recommendation'] ?? 'Hãy bắt đầu hành trình của bạn.';
    final List<dynamic> focusAreas = data['focus_areas'] ?? [];
    final Map<String, dynamic> breakdown = data['metrics_breakdown'] ?? {};
    final String milestoneBadge = data['milestone_badge'] ?? 'Tập Sự Sức Khỏe';
    final int decayPoints = data['decay_points_lost'] ?? 0;

    final Color adaptiveColor = _getVitalityColor(score);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F6),
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Ép người dùng dùng nút để tăng tính tương tác đích
        children: [
          // GỌI GIAO DIỆN TRANG 1 VỪA ĐƯỢC VẼ
          _buildPage1Dashboard(statusBarPadding, score, minutes, sessions, stateText, recommendation, milestoneBadge, decayPoints, focusAreas, adaptiveColor),
          
          // TRANG 2: TRẠM PHÂN TÍCH CHUYÊN SÂU
          _buildPage2Insights(statusBarPadding, breakdown, score, adaptiveColor, recommendation),
        ],
      ),
    );
  }

  // =========================================================================
  // 📱 TRANG 1: DASHBOARD TỔNG QUAN (CHUẨN PIXEL PERFECT THEO UI MẪU XANH DƯƠNG)
  // =========================================================================
  Widget _buildPage1Dashboard(double statusBarPadding, int score, int minutes, int sessions, String stateText, String recommendation, String milestoneBadge, int decayPoints, List<dynamic> focusAreas, Color adaptiveColor) {
    
    // 1. Logic thời gian cho Lời chào & Câu chúc
    final hour = DateTime.now().hour;
    String greeting = "";
    String quote = "";
    
    if (hour >= 5 && hour < 11) {
      greeting = "Chào buổi sáng";
      quote = "Bắt đầu ngày mới đầy năng lượng ✨";
    } else if (hour >= 11 && hour < 13) {
      greeting = "Nghỉ trưa nhé";
      quote = "Nạp lại năng lượng cho buổi chiều ☀️";
    } else if (hour >= 13 && hour < 18) {
      greeting = "Chào buổi chiều";
      quote = "Sắp hoàn thành mục tiêu hôm nay rồi 🚀";
    } else if (hour >= 18 && hour < 22) {
      greeting = "Buổi tối an lành";
      quote = "Dành thời gian thư giãn bản thân 🌙";
    } else {
      greeting = "Ngủ ngon nhé";
      quote = "Cơ thể cần nghỉ ngơi để phục hồi 💤";
    }

    // 2. Logic rút gọn Nhãn (Tối đa 2 từ) cho Grid Card
    String shortStatus = score <= 20 ? "Cạn kiệt" : (score <= 50 ? "Hồi phục" : (score <= 80 ? "Cân bằng" : "Tối ưu"));
    String shortBadge = minutes < 200 ? "Tập sự" : (minutes < 500 ? "Tiến bộ" : (minutes < 1000 ? "Thành thạo" : "Hoàn thiện"));

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF80BF84), Color(0xFF1A3A35)], // Nâng cấp sang Gradient Wellness Green Premium
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: RefreshIndicator(
        onRefresh: _fetchWellnessProfile,
        color: const Color(0xFF80BF84),
        backgroundColor: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // --- PHẦN HEADER (NỀN XANH CHUYỂN MÀU) ---
                      Padding(
                        padding: EdgeInsets.only(top: statusBarPadding + 16, left: 24, right: 24),
                        child: Column(
                          children: [
                            // Thanh điều hướng trên cùng (Nút Back, Lời chào, và Nút Phân tích Premium)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF4B5563), size: 20),
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                ),
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text("🌟", style: TextStyle(fontSize: 20)),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        child: Text(
                                          greeting,
                                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                                          maxLines: 1, overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Nút Phân tích tích hợp hiệu ứng Shimmer/Pulse Premium để thu hút Click
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return GestureDetector(
                                      onTap: () => _pageController.animateToPage(1, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.15 + (_pulseController.value * 0.05)),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.3 + (_pulseController.value * 0.5)),
                                            width: 1.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.white.withOpacity(0.2 * _pulseController.value),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            )
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 16),
                                            SizedBox(width: 4),
                                            Text(
                                              "Phân tích",
                                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 28),

                            // 🚀 DỜI THẺ SMART CONSUMER LÊN ĐẦU, KÍCH THÍCH NGƯỜI DÙNG NGAY KHI VÀO MÀN HÌNH
                            _buildSmartConsumerCard(),
                            
                            const SizedBox(height: 36),
                          ],
                        ),
                      ),

                      // --- PHẦN NỘI DUNG CHÍNH (THẺ NỀN TRẮNG PHỦ BO GÓC TRÒN LỚN ĐÁY) ---
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40, left: 24, right: 24, bottom: 40),
                            child: Column(
                              children: [
                                // 1. VÒNG CUNG PROGRESS KHỔNG LỒ (Hiệu ứng Ripple sóng nước tỏa ra nhịp điệu)
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    return Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          // Bóng tĩnh cố định để giữ độ sâu
                                          BoxShadow(
                                            color: const Color(0xFF80BF84).withOpacity(0.15),
                                            blurRadius: 40,
                                            spreadRadius: 10,
                                          ),
                                          // Bóng động nhịp điệu (Ripple Effect) tỏa ra và mờ dần
                                          BoxShadow(
                                            color: const Color(0xFF80BF84).withOpacity(0.25 * (1 - _pulseController.value)),
                                            blurRadius: 60 * _pulseController.value,
                                            spreadRadius: 35 * _pulseController.value,
                                          ),
                                        ],
                                      ),
                                      child: child,
                                    );
                                  },
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 220, height: 220,
                                        child: CircularProgressIndicator(
                                          value: 1.0,
                                          strokeWidth: 20,
                                          valueColor: const AlwaysStoppedAnimation(Color(0xFFE2ECEB)), // Nền xám xanh nhạt chuẩn Wellness
                                        ),
                                      ),
                                      SizedBox(
                                        width: 220, height: 220,
                                        child: CircularProgressIndicator(
                                          value: score / 100,
                                          strokeWidth: 20,
                                          strokeCap: StrokeCap.round,
                                          valueColor: const AlwaysStoppedAnimation(Color(0xFF1A3A35)), // Xanh lá đậm Premium nổi bật
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            "$score%",
                                            style: const TextStyle(color: Color(0xFF111827), fontSize: 56, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -2),
                                          ),
                                          const SizedBox(height: 8),
                                          const Text(
                                            "Chất lượng",
                                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 40),

                                // 2. METRICS ROW (Tổng thời gian & Mục tiêu xếp đối xứng - Thu nhỏ thanh lịch hơn)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    Column(
                                      children: [
                                        const Text("Tổng thời gian", style: TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text("${minutes ~/ 60}h ${minutes % 60}m", style: const TextStyle(color: Color(0xFF111827), fontSize: 20, fontWeight: FontWeight.w800)),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Column(
                                      children: [
                                        const Text("Mục tiêu", style: TextStyle(color: Color(0xFF80BF84), fontSize: 12, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 6),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.baseline,
                                          textBaseline: TextBaseline.alphabetic,
                                          children: [
                                            Text("$sessions", style: const TextStyle(color: Color(0xFF111827), fontSize: 20, fontWeight: FontWeight.w800)),
                                            const SizedBox(width: 4),
                                            const Text("buổi", style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w700)),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 40),

                                // 3. LƯỚI KHỐI BENTO 2x2 CÁC CHỈ SỐ BỔ TRỢ (Áp dụng bộ Nhãn 2 chữ siêu ngắn)
                                Row(
                                  children: [
                                    Expanded(child: _buildInfoGridCard(Icons.query_stats_rounded, "Trạng thái", shortStatus)),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildInfoGridCard(Icons.pie_chart_rounded, "Tập trung", "${focusAreas.length} vùng")),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(child: _buildInfoGridCard(Icons.trending_down_rounded, "Suy giảm", "-$decayPoints")),
                                    const SizedBox(width: 16),
                                    Expanded(child: _buildInfoGridCard(Icons.workspace_premium_rounded, "Huy hiệu", shortBadge)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 🚀 BIẾN STATE QUẢN LÝ SMART CONSUMER (Khai báo ngầm cục bộ trong build process)
  Map<String, dynamic>? _rewardStatus;
  bool _isFetchingReward = false;
  bool _isClaimingReward = false;

  Future<void> _fetchRewardStatus() async {
    if (_isFetchingReward) return;
    _isFetchingReward = true;
    try {
      final res = await ApiClient.instance.get('/user/wellness/reward-status');
      if (res.statusCode == 200 && mounted) {
        setState(() => _rewardStatus = res.data['data']);
      }
    } catch (_) {}
    _isFetchingReward = false;
  }

  Future<void> _handleClaimReward() async {
    if (_isClaimingReward) return;
    setState(() => _isClaimingReward = true);
    try {
      final res = await ApiClient.instance.post('/user/wellness/claim-reward');
      if (res.statusCode == 200 && mounted) {
        AppToast.show(context: context, message: '🎉 Đã nhận thưởng 500.000đ vào Ví!', isSuccess: true);
        await _fetchRewardStatus(); // Tải lại để chuyển nút sang Rút tiền
      } else {
        AppToast.show(context: context, message: 'Thất bại hoặc bạn đã nhận thưởng rồi.', isSuccess: false);
      }
    } catch (_) {
      AppToast.show(context: context, message: 'Lỗi đường truyền', isSuccess: false);
    }
    if (mounted) setState(() => _isClaimingReward = false);
  }

  // 🚀 KHỐI HIỂN THỊ SMART CONSUMER CARD (Phong cách Pearl Oasis - Trắng ngọc trai & Xanh ngọc bích)
  Widget _buildSmartConsumerCard() {
    if (_rewardStatus == null) {
      _fetchRewardStatus();
      return const ShimmerWrapper(child: SizedBox(height: 160, width: double.infinity));
    }

    final double totalSpent = (_rewardStatus!['total_spent'] ?? 0).toDouble();
    final bool hasClaimed = _rewardStatus!['has_claimed'] ?? false;
    final bool isEligible = _rewardStatus!['is_eligible'] ?? false;
    final double target = (_rewardStatus!['target_amount'] ?? 5000000).toDouble();
    
    // Tính toán giới hạn thanh Progress không vượt quá 1.0 (100%)
    double progressPercent = (totalSpent / target).clamp(0.0, 1.0);
    
    final formatCurrency = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0);

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isEligible && !hasClaimed 
                  ? const Color(0xFF80BF84) 
                  : const Color(0xFFE2ECEB), 
              width: isEligible && !hasClaimed ? 2.0 : 1.5
            ),
            boxShadow: [
              if (isEligible && !hasClaimed)
                BoxShadow(
                  color: const Color(0xFF80BF84).withOpacity(0.3 * _pulseController.value), 
                  blurRadius: 30, spreadRadius: 4, offset: const Offset(0, 10)
                )
              else
                BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF4F9F6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.diamond_rounded, color: Color(0xFF80BF84), size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Đặc Quyền Hội Viên",
                      style: TextStyle(
                        color: Color(0xFF1A3A35),
                        fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isEligible && !hasClaimed 
                          ? const Color(0xFF80BF84).withOpacity(0.15 + (_pulseController.value * 0.1)) 
                          : const Color(0xFFF4F9F6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isEligible && !hasClaimed ? const Color(0xFF80BF84).withOpacity(0.5) : Colors.transparent)
                    ),
                    child: const Text(
                      "Thưởng 500k",
                      style: TextStyle(
                        color: Color(0xFF2A5951), 
                        fontSize: 11, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              
              if (!hasClaimed) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Tiến độ chi tiêu", style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w600)),
                    Text("${formatCurrency.format(totalSpent)} / ${formatCurrency.format(target)}", style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 10),
                Stack(
                  children: [
                    Container(
                      height: 14, width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2ECEB), 
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: progressPercent,
                      child: Container(
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF48C9B0)]), 
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            if (isEligible)
                              BoxShadow(
                                color: const Color(0xFF80BF84).withOpacity(0.4 + (_pulseController.value * 0.3)), 
                                blurRadius: 10
                              )
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!isEligible)
                  Text(
                    "💡 Chỉ còn ${formatCurrency.format(target - totalSpent)} nữa để mở khóa phần thưởng!",
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                const SizedBox(height: 20),
                
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEligible ? const Color(0xFF80BF84) : const Color(0xFFF4F7F6), // Xanh khi đủ, Xám nhạt khi bị khóa
                      foregroundColor: isEligible ? Colors.white : const Color(0xFF94A3B8), 
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: isEligible ? _handleClaimReward : null,
                    child: _isClaimingReward 
                        ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: isEligible ? Colors.white : const Color(0xFF94A3B8), strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (!isEligible) ...[
                                const Icon(Icons.lock_rounded, size: 16),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isEligible ? "✨ NHẬN THƯỞNG 500.000Đ ✨" : "NHẬN THƯỞNG",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                              ),
                            ],
                          ),
                  ),
                ),
              ] else ...[
                // TRẠNG THÁI ĐÃ NHẬN THƯỞNG
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9F6), 
                    borderRadius: BorderRadius.circular(16), 
                    border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.3))
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF80BF84), size: 28),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Tuyệt vời! Bạn đã mở khóa mốc thưởng và nhận 500.000đ vào Ví.", 
                          style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.bold)
                        )
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35), 
                      foregroundColor: Colors.white, 
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: () {
                      WalletScreen.showPremiumWithdrawalSheet(context, onSuccess: () {
                        _fetchRewardStatus();
                      });
                    },
                    child: const Text("RÚT TIỀN VỀ NGÂN HÀNG", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ],
          ),
        );
      }
    );
  }

  // Widget hỗ trợ vẽ 4 Grid Card Premium (Bo góc lớn, Đổ bóng mờ mịn)
  Widget _buildInfoGridCard(IconData icon, String label, String value) {
    // Dynamic phân màu nhẹ dựa trên nội dung card để mắt không bị nhàm chán
    bool isHighlight = label == "Trạng thái" || label == "Tập trung";
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: isHighlight ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC), // F0FDF4: Xanh lá siêu nhạt | F8FAFC: Xám siêu nhạt
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF111827).withOpacity(0.03),
            blurRadius: 24,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isHighlight ? const Color(0xFF1A3A35) : const Color(0xFF617D79), // Xanh đậm và Xanh xám Wellness
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Color(0xFF111827), fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 📱 TRANG 2: TRẠM PHÂN TÍCH CHUYÊN SÂU (INSIGHTS & LOGS - CHUẨN OVERVIEW IMAGE)
  // =========================================================================
  Widget _buildPage2Insights(double statusBarPadding, Map<String, dynamic> breakdown, int score, Color adaptiveColor, String recommendation) {
    // Thuật toán rút trích dữ liệu cho Bento Grid
    int maxSessions = 1; // Khóa chia 0
    int topSession = 0;
    String topCategory = "Trị liệu";
    int totalMinutes = 0;
    
    breakdown.forEach((key, value) {
      final s = value['sessions'] ?? 0;
      final m = value['minutes'] ?? 0;
      totalMinutes += m as int;
      if (s > maxSessions) maxSessions = s;
      if (s > topSession) {
        topSession = s;
        topCategory = key;
      }
    });

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.only(top: statusBarPadding + 16, left: 24, right: 24, bottom: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER (Overview Style - Chữ béo đen & Avatar góc phải)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => _pageController.animateToPage(0, duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF111827), size: 18),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Text("Phân tích", style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Color(0xFF111827), letterSpacing: -0.5)),
                ],
              ),
              Container(
                width: 38, height: 38, // Thu nhỏ kích thước cho thanh lịch hơn
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  image: DecorationImage(
                    image: NetworkImage(
                      _wellnessData?['profile']?['avatar_url'] ?? "https://ui-avatars.com/api/?name=${_wellnessData?['profile']?['full_name'] ?? 'U'}&background=80BF84&color=fff&size=128"
                    ), 
                    fit: BoxFit.cover
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 4))],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 2. MAIN CARD (Tái cấu trúc phẳng hoàn toàn từ đầu - Giải phóng kích thước hình tròn)
          Container(
            height: 150, 
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF80BF84), Color(0xFF1A3A35)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.25), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Hình tròn tiến độ độc lập với Stroke mềm mại và phẳng hoàn toàn (Đã xóa bỏ hiệu ứng loang màu và bóng đổ)
                Container(
                  width: 116,
                  height: 116,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 1. Quỹ đạo nền mờ
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: 1.0,
                          strokeWidth: 8.0, 
                          valueColor: AlwaysStoppedAnimation(Colors.white.withOpacity(0.15)),
                        ),
                      ),
                      // 2. Cung tiến trình chính
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: score / 100,
                          strokeWidth: 8.0,
                          strokeCap: StrokeCap.round,
                          valueColor: AlwaysStoppedAnimation(adaptiveColor), 
                        ),
                      ),
                      // 3. Chỉ số % ở giữa
                      Text(
                        "$score%",
                        style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Khối thông tin bên phải tự động chiếm trọn diện tích còn lại, không gây ràng buộc lên hình tròn
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (_wellnessData?['state_text'] ?? "Chưa có dữ liệu").replaceAll("Cân bằng sinh học", "Cân bằng"), 
                        style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text("⏱️", style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              "Thời gian: ${totalMinutes ~/ 60}h ${totalMinutes % 60}m",
                              style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w500, letterSpacing: -0.2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 3. MOOD SECTION (Sleek & Neo-Glow Style - Phẳng mượt, tối giản)
          const Text("Cơ thể bạn cảm thấy thế nào?", style: TextStyle(color: Color(0xFF111827), fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          // Đập bỏ khối hộp Container thô cứng, trải phẳng trực tiếp các nút lên màn hình (White-space cực đại)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMoodItem("Mệt mỏi", Icons.battery_alert_rounded, const Color(0xFFF59E0B), "TIRED", "GENERAL"),
                _buildMoodItem("Đau mỏi", Icons.healing_rounded, const Color(0xFF3B82F6), "STIFF", "NECK_SHOULDER"),
                _buildMoodItem("Căng thẳng", Icons.psychology_rounded, const Color(0xFF8B5CF6), "STRESSED", "HEAD"),
                _buildMoodItem("Năng lượng", Icons.bolt_rounded, const Color(0xFF10B981), "ENERGETIC", "GENERAL"),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // 4. BENTO GRID (Kéo dài lưới chạm đáy, tạo không gian thoáng đãng cho Giáo sư X và Đầu tư)
          SizedBox(
            height: 380, // Tăng chiều cao để kéo dãn các hộp Expanded xuống gần chạm đáy
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // COLUMN 1 (Cột Trái)
                Expanded(
                  child: Column(
                    children: [
                      // Card 1.1: Trị liệu (Nâng cấp Premium Glow Bar)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))],
                          border: Border.all(color: Colors.white, width: 2), // Glass border nhẹ
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text("", style: TextStyle(fontSize: 14)),
                                Expanded(child: Text(topCategory, style: const TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text("$topSession buổi trị liệu", style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 14),
                            Stack(
                              children: [
                                Container(height: 8, decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8))),
                                FractionallySizedBox(
                                  widthFactor: (topSession / maxSessions).clamp(0.1, 1.0),
                                  child: Container(
                                    height: 8, 
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [adaptiveColor.withOpacity(0.6), adaptiveColor]),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [BoxShadow(color: adaptiveColor.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))], // Glow bóng tỏa
                                    )
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Card 1.2: Giáo sư X (Animated Wave)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Trạng thái", style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900)),
                              SizedBox(
                                height: 16, width: double.infinity, 
                                child: AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) {
                                    final double continuousRotation = _pulseController.status == AnimationStatus.forward
                                        ? _pulseController.value
                                        : 2.0 - _pulseController.value;
                                    return CustomPaint(painter: _WavePainter(color: adaptiveColor, phase: continuousRotation)); // Chuyển động liên tục
                                  },
                                ),
                              ),
                              Text(
                                recommendation,
                                style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600, height: 1.5),
                                maxLines: 5, overflow: TextOverflow.fade,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // COLUMN 2 (Cột Phải)
                Expanded(
                  child: Column(
                    children: [
                      // Card 2.1: Đầu tư (Liquid / Bọt khí cuộn trào)
                      Expanded(
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text("Thời gian", style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900)),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Container(
                                    width: 76, 
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: const Color(0xFFE5E7EB).withOpacity(0.5), width: 2), // Viền kính bể chứa
                                    ),
                                    alignment: Alignment.bottomCenter,
                                    child: FractionallySizedBox(
                                      heightFactor: (totalMinutes / 500).clamp(0.2, 1.0),
                                      widthFactor: 1.0,
                                      child: AnimatedBuilder(
                                        animation: _pulseController,
                                        builder: (context, child) {
                                          final double liquidShift = math.sin(_pulseController.value * math.pi * 2) * 0.1; // Cảm giác sóng sánh lên xuống nhẹ
                                          
                                          return Container(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [adaptiveColor.withOpacity(0.6), adaptiveColor], 
                                                begin: Alignment(0, -1.0 + liquidShift), 
                                                end: Alignment(0, 1.0 - liquidShift)
                                              ),
                                              borderRadius: BorderRadius.circular(14),
                                              boxShadow: [BoxShadow(color: adaptiveColor.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, -2))], // Ánh sáng hắt lên mặt nước
                                            ),
                                            alignment: Alignment.center,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text("$totalMinutes", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, shadows: [Shadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))])), // Text nổi trên chất lỏng
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Card 2.2: Tập trung (Premium Focus Bars)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 12))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Tập trung", style: TextStyle(color: Color(0xFF111827), fontSize: 13, fontWeight: FontWeight.w900)),
                            const SizedBox(height: 6),
                            Text("${breakdown.keys.length} lĩnh vực", style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(4, (index) {
                                bool isFilled = index < breakdown.keys.length;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  width: 16, height: 24, // Mở rộng block cho vững chãi
                                  decoration: BoxDecoration(
                                    gradient: isFilled ? LinearGradient(colors: [adaptiveColor.withOpacity(0.6), adaptiveColor], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
                                    color: isFilled ? null : const Color(0xFFF3F4F6),
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: isFilled ? [BoxShadow(color: adaptiveColor.withOpacity(0.3), blurRadius: 6, offset: const Offset(0, 2))] : null,
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ♻️ WIDGET NHẬT KÝ VI MÔ (PREMIUM NEO-GLOW INTERACTION)
  // =========================================================================
  Widget _buildMoodItem(String label, IconData iconData, Color themeColor, String moodState, String bodyFocus) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _submitMood(moodState, bodyFocus),
        borderRadius: BorderRadius.circular(24),
        splashColor: themeColor.withOpacity(0.2),
        highlightColor: themeColor.withOpacity(0.1),
        child: Container(
          width: 72, // Mở rộng nhẹ vùng chạm (Hitbox) thân thiện ngón tay
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: themeColor.withOpacity(0.08), // Nền sáng nhẹ mờ (Glow circle background)
                  shape: BoxShape.circle,
                ),
                child: Icon(iconData, color: themeColor, size: 28),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(color: Color(0xFF4B5563), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// 🎨 CUSTOM PAINTER: ĐỒ THỊ NHỊP TIM ĐỘNG (ANIMATED WAVE PAINTER)
// =========================================================================
class _WavePainter extends CustomPainter {
  final Color color;
  final double phase; // Thêm tham số tịnh tiến pha để tạo dòng chảy liên tục
  _WavePainter({required this.color, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    path.moveTo(0, size.height / 2);
    
    // Sử dụng thuật toán Sine Wave quét qua chiều dài trục X kết hợp tịnh tiến pha (phase)
    for (double i = 0; i <= size.width; i++) {
      // Điều chế biên độ (Amplitude) dựa vào điểm giữa để tạo cảm giác nhịp tim đập mạch ở tâm
      final double amplitude = math.sin(i / size.width * math.pi) * (size.height / 2); 
      path.lineTo(
        i, 
        size.height / 2 + math.sin((i / size.width * 3 * math.pi) + (phase * 2 * math.pi)) * amplitude,
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter oldDelegate) => oldDelegate.phase != phase;
}

// =========================================================================
// 🎨 CUSTOM PAINTER: VÒNG CUNG SINH LỰC 270 ĐỘ (ARC GAUGE PREMIUM)
// =========================================================================
class _VitalityArcPainter extends CustomPainter {
  final double progress;
  final int score;
  final Color themeColor;

  _VitalityArcPainter({required this.progress, required this.score, required this.themeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    // Góc bắt đầu là 135 độ (Góc dưới bên trái), Quét 270 độ sang góc dưới bên phải
    final double startAngle = math.pi * 0.75; 
    final double sweepAngle = math.pi * 1.5;

    // 1. Vẽ Track nền mờ (Background Arc) - Đưa bán kính sát biên biên (radius - 4) và làm thanh mảnh nét vẽ
    final paintTrack = Paint()
      ..color = const Color(0xFFE2ECEB).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      startAngle,
      sweepAngle,
      false,
      paintTrack,
    );

    // 2. Vẽ cung tiến trình thực tế (Gradient lấp lánh) - Giải phóng hoàn toàn không gian vẽ bung rộng ra sát biên
    final double currentSweep = (score / 100) * sweepAngle;
    final paintProgress = Paint()
      ..shader = SweepGradient(
        startAngle: startAngle,
        endAngle: startAngle + sweepAngle,
        colors: [themeColor.withOpacity(0.5), themeColor],
        stops: const [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius - 4))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 4),
      startAngle,
      currentSweep,
      false,
      paintProgress,
    );

    // 3. Hiệu ứng hạt Pulse chạy ngầm trên quỹ đạo mới đã nới rộng
    final double pulseAngle = startAngle + (progress * sweepAngle);
    final paintPulse = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final double px = center.dx + (radius - 4) * math.cos(pulseAngle);
    final double py = center.dy + (radius - 4) * math.sin(pulseAngle);
    canvas.drawCircle(Offset(px, py), 4, paintPulse);
  }

  @override
  bool shouldRepaint(covariant _VitalityArcPainter oldDelegate) => true;
}