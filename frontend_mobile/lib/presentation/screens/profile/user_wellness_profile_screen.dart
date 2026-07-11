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
  bool _isSubmittingMood = false;
  Map<String, dynamic>? _wellnessData;
  late AnimationController _pulseController;

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
    
    // 🚀 Bắt luồng logic mới từ Backend
    final String milestoneBadge = data['milestone_badge'] ?? 'Tập Sự Sức Khỏe';
    final int decayPoints = data['decay_points_lost'] ?? 0;

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
              // 1. HEADER & MILESTONE BADGE
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      "Hành Trình Wellness",
                      style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 48), 
                ],
              ),
              const SizedBox(height: 12),
              
              // 🌟 MILESTONE BADGE (Huy hiệu cao cấp)
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [const Color(0xFF80BF84).withOpacity(0.2), const Color(0xFF3498DB).withOpacity(0.2)]),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified_rounded, color: Color(0xFF3498DB), size: 16),
                      const SizedBox(width: 6),
                      Text(
                        milestoneBadge.toUpperCase(),
                        style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
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
                                      style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 42, fontWeight: FontWeight.w900, letterSpacing: -1.5),
                                    ),
                                    const Text(
                                      "VITALITY",
                                      style: TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      
                      // ⚠️ CẢNH BÁO SUY GIẢM SINH LỰC (DECAY LOGIC)
                      if (decayPoints > 0) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE74C3C).withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE74C3C).withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.trending_down_rounded, color: Color(0xFFE74C3C), size: 16),
                              const SizedBox(width: 8),
                              Text(
                                "Trừ $decayPoints điểm sinh lý do bỏ bê",
                                style: const TextStyle(color: Color(0xFFE74C3C), fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 24),
                      Text(
                        stateText.toUpperCase(),
                        style: TextStyle(color: adaptiveColor, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          recommendation,
                          style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // 3. MICRO-MOOD TRACKER (NHẬT KÝ VI MÔ ĐIỀU HƯỚNG TÂM LÝ)
              const Text("CƠ THỂ BẠN HÔM NAY THẾ NÀO?", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMoodButton("Năng lượng", "⚡", "ENERGETIC", "FULL_BODY"),
                  _buildMoodButton("Thư giãn", "😌", "RELAXED", "MIND"),
                  _buildMoodButton("Căng thẳng", "😫", "STRESSED", "HEAD"),
                  _buildMoodButton("Đau nhức", "🤕", "TIRED", "NECK_SHOULDER"),
                ],
              ),
              const SizedBox(height: 32),

              // 4. OVERVIEW CORE METRICS
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
                      title: "Số phiên trị liệu",
                      value: "$sessions",
                      unit: "buổi",
                      iconColor: const Color(0xFF3498DB),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // 5. BREAKDOWN VISUAL CHART (BIỂU ĐỒ THANH NGANG THAY CHO LIST VIEW)
              const Text("BIỂU ĐỒ PHÂN BỔ TRỊ LIỆU", style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 16),
              breakdown.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
                      child: const Center(child: Text("Hoàn thành đơn đặt lịch để vẽ biểu đồ.", style: TextStyle(color: Color(0xFF617D79), fontSize: 13))),
                    )
                  : Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 6))],
                      ),
                      child: Column(
                        children: breakdown.entries.map((entry) {
                          final String key = entry.key;
                          final int itemSessions = entry.value['sessions'] ?? 0;
                          final double percentage = sessions > 0 ? (itemSessions / sessions) : 0;
                          
                          Color barColor = const Color(0xFF80BF84);
                          if (key == 'THERAPY') barColor = const Color(0xFFE67E22);
                          if (key == 'BEAUTY') barColor = const Color(0xFFFF7A8A);
                          if (key == 'MIND') barColor = const Color(0xFF9B59B6);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(key, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
                                    Text("$itemSessions buổi (${(percentage * 100).toStringAsFixed(0)}%)", style: const TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Stack(
                                  children: [
                                    Container(
                                      height: 10,
                                      width: double.infinity,
                                      decoration: BoxDecoration(color: const Color(0xFFF4F9F6), borderRadius: BorderRadius.circular(6)),
                                    ),
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 1200),
                                      curve: Curves.easeOutCubic,
                                      height: 10,
                                      width: MediaQuery.of(context).size.width * 0.75 * percentage, 
                                      decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(6)),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // WIDGET NÚT GHI NHẬN CẢM XÚC GÂY NGHIỆN (MICRO-MOOD TRACKER)
  Widget _buildMoodButton(String label, String emoji, String moodState, String bodyFocus) {
    return GestureDetector(
      onTap: () => _submitMood(moodState, bodyFocus),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 6))],
              border: Border.all(color: const Color(0xFFE2ECEB), width: 1.5),
            ),
            child: Text(emoji, style: const TextStyle(fontSize: 26)),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w700)),
        ],
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