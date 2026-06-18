import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_bottom_sheet.dart';

class GuestProfileView extends StatelessWidget {
  final VoidCallback onSuccess;
  const GuestProfileView({super.key, required this.onSuccess});

  void _showAuth(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.4), // Sương mù dịu nhẹ
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return Stack(
          children: [
            // Hiệu ứng mờ nền chuẩn Apple
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: const SizedBox.expand(),
            ),
            Center(
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(32),
                  child: AuthBottomSheet(onSuccess: onSuccess),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)
            ),
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF8FAF9), Color(0xFFE8F2ED)],
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Khung cảnh tĩnh lặng - Oasis of Wellness
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF4A8B6F).withOpacity(0.08),
                  border: Border.all(color: const Color(0xFF4A8B6F).withOpacity(0.15), width: 0.5),
                  boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.1), blurRadius: 40, spreadRadius: 5)],
                ),
                child: const Icon(Icons.spa_rounded, size: 48, color: Color(0xFF4A8B6F)),
              ),
              const SizedBox(height: 32),
              
              const Text('Chào bạn, tâm thế mới', 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: Color(0xFF2C3E35), height: 1.4, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              const Text('Không gian lưu giữ hành trình phục hồi\nvà trị liệu của riêng bạn.', 
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: Color(0xFF5A6E63), height: 1.6, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 48),

              // Thẻ thông tin Khung kính cao cấp tương phản tốt
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF4A8B6F).withOpacity(0.1), width: 0.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 20, offset: const Offset(0, 8))
                  ]
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A8B6F).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4A8B6F), size: 20),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(height: 10, width: 120, decoration: BoxDecoration(color: const Color(0xFF2C3E35).withOpacity(0.2), borderRadius: BorderRadius.circular(5))),
                          const SizedBox(height: 10),
                          Container(height: 6, width: 70, decoration: BoxDecoration(color: const Color(0xFF5A6E63).withOpacity(0.15), borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                    )
                  ],
                ),
              ),
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2C3E35), 
                    foregroundColor: Colors.white, 
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)) 
                  ),
                  onPressed: () => context.go('/login'),
                  child: const Text('Mở Cửa Không Gian', style: TextStyle(fontWeight: FontWeight.w400, fontSize: 16, letterSpacing: 0.3)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _showAuth(context),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF4A8B6F)),
                child: const Text('Trải nghiệm đăng nhập nhanh', style: TextStyle(fontWeight: FontWeight.w300)),
              )
            ],
          ),
        ),
      ),
    );
  }
}