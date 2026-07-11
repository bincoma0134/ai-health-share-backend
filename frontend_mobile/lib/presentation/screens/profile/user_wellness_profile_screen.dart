import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';

class UserWellnessProfileScreen extends StatefulWidget {
  const UserWellnessProfileScreen({super.key});

  @override
  State<UserWellnessProfileScreen> createState() => _UserWellnessProfileScreenState();
}

class _UserWellnessProfileScreenState extends State<UserWellnessProfileScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  Map<String, dynamic>? _wellnessData;
  late AnimationController _pulseController;

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
          child: const ShimmerWrapper(
            child: SizedBox(
              height: 200,
              width: double.infinity,
            ),
          ),
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

    final Color adaptiveColor = _getVitalityColor(score);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F9F6),
      body: RefreshIndicator(
        onRefresh: _fetchWellnessProfile,
        color: const Color(0xFF1A3A35),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.only(top: statusBarPadding + 16, left: 24, right: 24, bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. HEADER
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text(
                    "Hành Trình Wellness",
                    style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                  ),
                  const SizedBox(width: 40), 
                ],
              ),
              const SizedBox(height: 24),

              // 2. VITALITY ORB CONTAINER (TRỌNG TÂM NĂNG LƯỢNG SINH HỌC)
              Center(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: [
                      BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    children: [
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return CustomPaint(
                            painter: _VitalityOrbPainter(
                              progress: _pulseController.value,
                              score: score,
                              themeColor: adaptiveColor,
                            ),
                            child: SizedBox(
                              width: 160,
                              height: 160,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      "$score",
                                      style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 38, fontWeight: FontWeight.w900, letterSpacing: -1),
                                    ),
                                    const Text(
                                      "VITALITY",
                                      style: TextStyle(color: Color(0xFF617D79), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      Text(
                        stateText.toUpperCase(),
                        style: TextStyle(color: adaptiveColor, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          recommendation,
                          style: const TextStyle(color: Color(0xFF617D79), fontSize: 12, height: 1.5, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 3. OVERVIEW CORE METRICS (TỔNG THỜI GIAN ĐẦU TƯ)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricMiniCard(
                      icon: Icons.hourglass_top_rounded,
                      title: "Thời gian đầu tư",
                      value: "$minutes",
                      unit: "phút",
                      iconColor: const Color(0xFF80BF84),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricMiniCard(
                      icon: Icons.calendar_today_rounded,
                      title: "Tổng số buổi hẹn",
                      value: "$sessions",
                      unit: "buổi",
                      iconColor: const Color(0xFF3498DB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // 4. FOCUS AREAS CHIPS
              const Text("LĨNH VỰC TẬP TRUNG", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              focusAreas.isEmpty
                  ? const Text("Chưa có danh mục trị liệu nào được ghi nhận.", style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 13))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: focusAreas.map((area) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A3A35).withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF1A3A35).withOpacity(0.08)),
                          ),
                          child: Text(
                            "$area",
                            style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        );
                      }).toList(),
                    ),
              const SizedBox(height: 28),

              // 5. BREAKDOWN DETAIL LIST (CHI TIẾT PHÂN RÃ HÀNH VI)
              const Text("THỐNG KÊ CHI TIẾT TỪNG LIỆU PHÁP", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              breakdown.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                      child: const Center(child: Text("Hoàn thành các đơn đặt lịch để mở khóa chỉ số chi tiết.", style: TextStyle(color: Color(0xFF617D79), fontSize: 12))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: breakdown.keys.length,
                      itemBuilder: (context, index) {
                        final key = breakdown.keys.elementAt(index);
                        final itemData = breakdown[key] as Map<String, dynamic>;
                        final int itemSessions = itemData['sessions'] ?? 0;
                        final int itemMinutes = itemData['minutes'] ?? 0;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: const Color(0xFFF4F9F6), borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.spa_rounded, color: Color(0xFF1A3A35), size: 20),
                                  ),
                                  const SizedBox(width: 14),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(key, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 4),
                                      Text("$itemSessions buổi điều trị", style: const TextStyle(color: Color(0xFF617D79), fontSize: 12)),
                                    ],
                                  ),
                                ],
                              ),
                              Text(
                                "+$itemMinutes p",
                                style: const TextStyle(color: Color(0xFF80BF84), fontSize: 14, fontWeight: FontWeight.w800),
                              )
                            ],
                          ),
                        );
                      },
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricMiniCard({
    required IconData icon,
    required String title,
    required String value,
    required String unit,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 22),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Row(
            textBaseline: TextBaseline.alphabetic,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            children: [
              Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VitalityOrbPainter extends CustomPainter {
  final double progress;
  final int score;
  final Color themeColor;

  _VitalityOrbPainter({required this.progress, required this.score, required this.themeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double radius = size.width / 2;

    // 1. Vẽ quầng sáng tỏa năng lượng nền (Glow Effect)
    final paintGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          themeColor.withOpacity(0.25),
          themeColor.withOpacity(0.08),
          themeColor.withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.3))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 1.3, paintGlow);

    // 2. Vẽ vòng tròn tiến trình chạy ngầm tinh tế
    final paintTrack = Paint()
      ..color = const Color(0xFFE2ECEB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, radius - 6, paintTrack);

    // 3. Vẽ cung tiến độ dựa trên Vitality Score thực tế
    final paintProgress = Paint()
      ..color = themeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    
    double sweepAngle = (score / 100) * 2 * math.pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 6),
      -math.pi / 2,
      sweepAngle,
      false,
      paintProgress,
    );

    // 4. Các sóng hạt động sinh học chạy ngầm tương thích với nhịp thở động
    final paintWave = Paint()
      ..color = themeColor.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    final int points = 20;
    for (int i = 0; i <= points; i++) {
      double angle = (i * 2 * math.pi) / points;
      double waveOffset = math.sin(angle * 3 + (progress * 2 * math.pi)) * 3.0;
      double r = radius - 18 + waveOffset;
      double x = center.dx + r * math.cos(angle);
      double y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paintWave);
  }

  @override
  bool shouldRepaint(covariant _VitalityOrbPainter oldDelegate) => true;
}