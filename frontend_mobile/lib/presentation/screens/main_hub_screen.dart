import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainHubScreen extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const MainHubScreen({super.key, required this.navigationShell});

  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, 
      body: navigationShell,
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          left: 16, // Trả lại lề chuẩn 16px vì giao diện đã thoáng hơn
          right: 16, 
          bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 16
        ),
        child: SizedBox(
          height: 90,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              // 1. THANH NỀN KÍNH SIÊU MỜ (GLASSMORPHISM PILL)
              ClipRRect(
                borderRadius: BorderRadius.circular(35),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(35),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Nhóm 3 tab trái (Bỏ qua nhãn label để UI tối giản)
                        Expanded(child: _buildNavItem(0, Icons.home_filled, Icons.home_outlined, context)),
                        Expanded(child: _buildNavItem(1, Icons.explore, Icons.explore_outlined, context)),
                        Expanded(child: _buildNavItem(2, Icons.local_offer, Icons.local_offer_outlined, context)),
                        
                        // Khoảng trống trung tâm cho nút AI
                        const SizedBox(width: 55), 
                        
                        // Nhóm 3 tab phải
                        Expanded(child: _buildNavItem(4, Icons.map, Icons.map_outlined, context)),
                        Expanded(child: _buildNavItem(5, Icons.calendar_month, Icons.calendar_today_outlined, context)),
                        Expanded(child: _buildNavItem(6, Icons.person, Icons.person_outline, context)),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 2. NÚT AI TRỢ LÝ NỔI (CRYSTAL FLOAT BUTTON) - Index số 3
              Positioned(
                top: 0,
                child: _buildAiButton(3, context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET CON: Nút chức năng thường (Đã tối giản, loại bỏ Text) ---
  Widget _buildNavItem(int index, IconData activeIcon, IconData icon, BuildContext context) {
    final isActive = navigationShell.currentIndex == index;
    return GestureDetector(
      onTap: () => _onTap(context, index),
      behavior: HitTestBehavior.opaque, // Bắt sự kiện chạm trên toàn bộ vùng Expanded
      child: Container(
        height: double.infinity, // Kéo dãn vùng chạm lấp đầy chiều cao thanh Nav
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
          child: Icon(
            isActive ? activeIcon : icon, 
            key: ValueKey<bool>(isActive),
            color: isActive ? const Color(0xFF80BF84) : Colors.white70, 
            size: 28, // Phóng to Icon để bù lại không gian của chữ
          ),
        ),
      ),
    );
  }

  // --- WIDGET CON: Nút AI nổi bật ---
  Widget _buildAiButton(int index, BuildContext context) {
    final isActive = navigationShell.currentIndex == index;
    return GestureDetector(
      onTap: () => _onTap(context, index),
      child: Container(
        width: 65,
        height: 65,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.1),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
          boxShadow: isActive ? [
            BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.5), blurRadius: 20, spreadRadius: 2)
          ] : [],
        ),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF80BF84), Color(0xFF5e9662)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
            ],
          ),
          child: Icon(
            Icons.auto_awesome, 
            color: isActive ? Colors.white : Colors.black87, 
            size: 30
          ),
        ),
      ),
    );
  }
}