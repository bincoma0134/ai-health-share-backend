import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'auth_bottom_sheet.dart';

class GuestProfileView extends StatelessWidget {
  final VoidCallback onSuccess;
  const GuestProfileView({super.key, required this.onSuccess});

  void _showAuth(BuildContext context) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AuthBottomSheet(onSuccess: onSuccess),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Cụm Avatar phát sáng giả lập
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
                border: Border.all(color: Colors.white24),
                boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.3), blurRadius: 50, spreadRadius: 10)],
              ),
              child: const Icon(Icons.account_circle, size: 80, color: Color(0xFF80BF84)),
            ),
            const SizedBox(height: 32),
            
            const Text('Hành trình sức khỏe\ncủa riêng bạn', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, height: 1.2)),
            const SizedBox(height: 12),
            const Text('Đăng nhập để mở khóa không gian lưu trữ cá nhân và nhận tư vấn từ mạng lưới chuyên gia AI Health.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 32),

            // Khối Curiosity Gap (Làm mờ giả lập UI)
            IgnorePointer(
              child: Opacity(
                opacity: 0.5,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month, color: Colors.white54),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 12, width: 150, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6))),
                            const SizedBox(height: 8),
                            Container(height: 8, width: 80, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)) ),
                onPressed: () => context.go('/login'),
                child: const Text('Đăng nhập / Đăng ký ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }
}