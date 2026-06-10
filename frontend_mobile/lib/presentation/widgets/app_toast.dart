import 'dart:ui';
import 'package:flutter/material.dart';

class AppToast {
  static void show({
    required BuildContext context,
    required String message,
    bool isSuccess = true,
    Duration duration = const Duration(seconds: 3),
  }) {
    // 1. Khởi tạo một thực thể Overlay trong RAM hệ thống
    final overlayState = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _ToastWidget(
        message: message,
        isSuccess: isSuccess,
        duration: duration,
        onDismiss: () {
          overlayEntry.remove();
        },
      ),
    );

    // 2. Chèn thông báo lơ lửng đè lên tất cả các Widget hiện tại
    overlayState.insert(overlayEntry);
  }
}

// --- KHỐI ANIMATION CHUYỂN ĐỘNG THẢ TRÊN XUỐNG ---
class _ToastWidget extends StatefulWidget {
  final String message;
  final bool isSuccess;
  final Duration duration;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.isSuccess,
    required this.duration,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 550), // Tốc độ thả xuống
      reverseDuration: const Duration(milliseconds: 400), // Tốc độ rụt lên
      vsync: this,
    );

    // Cấu hình trục Y dịch chuyển từ ngoài màn hình (-1.5) xuống vùng hiển thị an toàn
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.fastOutSlowIn, // Hiệu ứng quán tính phanh mềm mượt giống iOS
    ));

    _controller.forward();

    // Tự động rụt thông báo lên và giải phóng bộ nhớ khi hết thời gian chờ
    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Lấy khoảng lẹm tai thỏ (StatusBar) của thiết bị để căn chỉnh khoảng cách
    final double topPadding = MediaQuery.paddingOf(context).top;

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24), // Bo góc sâu viên thuốc cực kỳ sang trọng
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), // Kính mờ Glassmorphism xuyên thấu nền
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.isSuccess 
                      ? const Color(0xFF80BF84).withOpacity(0.85) // Màu xanh SM mờ
                      : const Color(0xFFFE2C55).withOpacity(0.85), // Màu đỏ cảnh báo mờ
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withOpacity(0.25), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: Icon(
                        widget.isSuccess ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                        color: widget.isSuccess ? const Color(0xFF4C8D50) : const Color(0xFFFE2C55),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}