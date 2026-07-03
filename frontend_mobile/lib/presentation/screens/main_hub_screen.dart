import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_theme.dart';
import '../widgets/liquid_glass/liquid_glass_panel.dart';
import '../widgets/auth_guard.dart';
import '../widgets/notification_notifier.dart';

class MainHubScreen extends StatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainHubScreen({super.key, required this.navigationShell});

  @override
  State<MainHubScreen> createState() => _MainHubScreenState();
}

class _MainHubScreenState extends State<MainHubScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  bool _isPageLoading = false;

  @override
  void initState() {
    super.initState();
    // Bộ điều khiển luồng sáng quét qua các khối skeleton liên tục
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void _onTap(BuildContext context, int index) {
    void performNav() {
      if (index != widget.navigationShell.currentIndex) {
        // 🚀 THUẬT TOÁN INDEXEDSTACK: Chuyển tab tức thì (Zero-latency)
        widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        );
      } else {
        widget.navigationShell.goBranch(
          index,
          initialLocation: true,
        );
      }
    }

    // Chặn điều hướng trực tiếp bằng AuthGuard đối với Tab AI Trợ lý (Index 2)
    if (index == 2) {
      AuthGuard.run(context, action: performNav);
    } else {
      performNav();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: _isPageLoading ? _buildSkeletonLayout() : widget.navigationShell,
          ),
        ],
      ),
      bottomNavigationBar: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16
          ),
          child: SizedBox(
            height: 90,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 1. THANH NỀN KÍNH TRONG SUỐT ĐƯỢC TỐI ƯU BỞI LIQUID GLASS FOUNDATION
                LiquidGlassPanel(
                  child: Container(
                  height: 70,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.zinc950.withOpacity(0.03),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Nhóm 2 tab trái: Chuyển đổi sang bộ Icon bo tròn mềm mại và bổ sung Label tương ứng
                      Expanded(child: _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Trang chủ', context)),
                      Expanded(child: _buildNavItem(1, Icons.explore_rounded, Icons.explore_outlined, 'Khám phá', context)),
                      
                      // Khoảng trống trung tâm cho nút AI (Index 2)
                      const SizedBox(width: 55), 
                      
                      // Nhóm 2 tab phải: Đồng bộ nhãn Cá nhân khớp với Profile User mới
                      Expanded(child: _buildNavItem(3, Icons.map_rounded, Icons.map_outlined, 'Bản đồ', context)),
                      Expanded(child: _buildNavItem(4, Icons.person_rounded, Icons.person_outline, 'Cá nhân', context)),
                    ],
                  ),
                ),
              ),
              
              
              // 2. NÚT AI TRỢ LÝ NỔI CHẤT LIỆU ĐẶC SẮC CHỈNH SỬA BIỂU TƯỢNG CHIẾC LÁ
                Positioned(
                  top: 0,
                  child: _buildAiButton(2, context),
                ),
              ],
            ),
          ),
        ),
      );
    }

  // --- THIẾT KẾ BỘ KHUNG XƯƠNG (SKELETON LAYOUT SYSTEM) TRỪU TƯỢNG ---
  Widget _buildSkeletonLayout() {
    return Container(
      color: const Color(0xFFFAFAFA), // Đồng điệu nền sáng zinc50 của AppTheme hoặc nền ngọc trai
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          // Khung xương Header (Avatar + Tên mờ)
          Row(
            children: [
              _buildShimmerBox(width: 50, height: 50, borderRadius: 25),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildShimmerBox(width: 140, height: 16),
                  const SizedBox(height: 8),
                  _buildShimmerBox(width: 90, height: 12),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          // Khung xương Banner chính (Card lớn nội dung)
          _buildShimmerBox(width: double.infinity, height: 180, borderRadius: 16),
          const SizedBox(height: 32),
          // Khung xương Tiêu đề mục phụ
          _buildShimmerBox(width: 150, height: 20),
          const SizedBox(height: 16),
          // Danh sách khung xương xếp lớp bên dưới
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: 3,
              physics: const NeverScrollableScrollPhysics(),
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  key: ValueKey<int>(index),
                  child: Row(
                    children: [
                      _buildShimmerBox(width: 55, height: 55, borderRadius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildShimmerBox(width: double.infinity, height: 14),
                            const SizedBox(height: 8),
                            _buildShimmerBox(width: 160, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET CON TRỢ LÝ: Tạo hiệu ứng quét dải sáng Shimmer thuần Flutter ---
  Widget _buildShimmerBox({required double width, required double height, double borderRadius = 8}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFFE4E4E7), // zinc200 làm nền khối xương sáng
                Color(0xFFF4F4F5), // zinc100 làm vệt sáng quét qua trung tâm
                Color(0xFFE4E4E7), // zinc200 kết thúc vệt sáng
              ],
              stops: const [0.1, 0.5, 0.9],
              begin: Alignment(-1.0 + (_shimmerController.value * 2.0), -0.3),
              end: Alignment(1.0 + (_shimmerController.value * 2.0), 0.3),
            ),
          ),
        );
      },
    );
  }

  // --- WIDGET CON: Phân bổ trục dọc phẳng tích hợp lớp nền lót mỏng sinh học Premium chống mờ thị giác ---
  Widget _buildNavItem(int index, IconData activeIcon, IconData icon, String label, BuildContext context) {
    final isActive = widget.navigationShell.currentIndex == index;
    return GestureDetector(
      onTap: () => _onTap(context, index),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: double.infinity,
        alignment: Alignment.center,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutQuad,
          // Khóa cứng kích thước đối xứng tuyệt đối (chiều rộng 76px, chiều cao 54px) giúp triệt tiêu lỗi kén to kén nhỏ
          width: 76,
          height: 54,
          alignment: Alignment.center, // Ép trục dọc Column vào tâm khối lót cố định
          decoration: BoxDecoration(
            // Lót vệt sáng Mint mờ nhẹ tương thích cao với nền Liquid Glass mờ
            color: isActive ? const Color(0xFF10B981).withOpacity(0.08) : Colors.transparent,
            // Đồng bộ hoàn hảo với thông số bo tròn tuyệt đối (35px) của thanh điều hướng Liquid Glass bên ngoài
            borderRadius: BorderRadius.circular(35), 
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ColorFiltered(
                colorFilter: isActive 
                    ? const ColorFilter.matrix([
                        1.2, 0,   0,   0,   0,
                        0,   1.2, 0,   0,   0,
                        0,   0,   1.2, 0,   0,
                        0,   0,   0,   1,   0,
                      ])
                    : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                  child: Icon(
                    isActive ? activeIcon : icon, 
                    key: ValueKey<bool>(isActive),
                    color: isActive ? const Color(0xFF10B981) : AppTheme.zinc400, 
                    size: 26, // Cân đối lại kích cỡ thấu kính Icon lồng trong khối lót
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                  color: isActive ? const Color(0xFF10B981) : AppTheme.zinc400,
                  letterSpacing: -0.1,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET CON: Nút AI nổi bật ---
  Widget _buildAiButton(int index, BuildContext context) {
    final isActive = widget.navigationShell.currentIndex == index;
    return GestureDetector(
      onTap: () => _onTap(context, index),
      child: Container(
        width: 65,
        height: 65,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.5),
          border: Border.all(color: Colors.white.withOpacity(0.8)),
          boxShadow: isActive ? [
            BoxShadow(color: const Color(0xFF10B981).withOpacity(0.4), blurRadius: 20, spreadRadius: 2)
          ] : [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF34D399), Color(0xFF059669)], // Đồng bộ nhận diện thương hiệu Xanh Ngọc bích
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: Color(0xFF10B981).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))
            ],
          ),
          child: const Icon(
            Icons.eco, 
            color: Colors.white, 
            size: 30
          ),
        ),
      ),
    );
  }
}