import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/secure_storage_service.dart';
import '../../data/services/user_api_service.dart';
import '../widgets/app_toast.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _breathingController;
  late Animation<double> _breathingAnimation;
  late AnimationController _rippleController;

  @override
  void initState() {
    super.initState();

    // 1. Bộ điều khiển nhịp thở sinh học (Breathing effect) chậm rãi, thư giãn
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _breathingAnimation = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _breathingController, curve: Curves.easeInOutSine),
    );

    // 2. Bộ điều khiển gợn sóng lan tỏa (Bio-ripples) chạy lặp mềm mại dưới nền
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat();

    // 3. Kích hoạt luồng chờ tải dữ liệu ngầm hệ thống trước khi chuyển trang
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 1. Giảm thời gian chờ cứng xuống 1.5s để nhường thời gian cho việc gọi API xác thực
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    
    final token = await SecureStorageService.getToken();
    
    if (token != null && token.isNotEmpty) {
      // 2. BẮT BUỘC: Gọi API để xác minh phiên làm việc thực tế trên Server
      final userProfileResponse = await UserApiService.fetchPrivateProfile();
      
      // Chú ý: Backend trả về {"profile": {...}, "stats": {...}} nên phải trích xuất đúng nhánh 'profile'
      if (userProfileResponse != null && userProfileResponse['profile'] != null) {
        final profileData = userProfileResponse['profile'];
        
        // Phiên hợp lệ -> Lấy thông tin cập nhật nhất từ Server
        final fullName = profileData['full_name'] ?? await SecureStorageService.getName() ?? 'bạn';
        final role = profileData['role'] ?? await SecureStorageService.getRole() ?? 'USER';
        
        // Đồng bộ lại Storage lỡ có thay đổi từ nền tảng Website
        await SecureStorageService.saveName(fullName);
        await SecureStorageService.saveRole(role);
        
        if (mounted) {
          AppToast.show(
            context: context, 
            message: 'Chào mừng $fullName trở lại hệ thống! Chúc bạn một ngày an lành và thư thái.', 
            isSuccess: true,
            duration: const Duration(seconds: 4)
          );
          
          // Điều hướng đồng nhất về Trang chủ theo yêu cầu tinh chỉnh luồng
        context.go('/');
        }
      } else {
        // Phiên KHÔNG hợp lệ (Hết hạn JWT, tài khoản bị xóa/khóa, hoặc lỗi mạng) -> Xóa rác và đẩy ra cổng
        await SecureStorageService.clearSession();
        if (mounted) context.go('/login');
      }
    } else {
      if (mounted) context.go('/login'); // Chưa đăng nhập -> Ra cổng
    }
  }

  @override
  void dispose() {
    _breathingController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF4A8B6F); // Xanh lục thảo mộc Wellness
    const backgroundLight = Color(0xFFF4F9F5); // Trắng ngọc trai thanh khiết dịu mát

    return Scaffold(
      backgroundColor: backgroundLight,
      body: Stack(
        children: [
          // LỚP 1: GỢN SÓNG LAN TỎA SINH HỌC CHẠY NGẦM (BIO-RIPPLES)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _rippleController,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: List.generate(2, (index) {
                    final progress = (_rippleController.value + (index * 0.5)) % 1.0;
                    return Container(
                      width: 140 + (progress * 280),
                      height: 140 + (progress * 280),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: primaryGreen.withOpacity((1 - progress) * 0.15),
                          width: 1.2,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          // LỚP 2: TÂM ĐIỂM - BIỂU TƯỢNG CHIẾC LÁ THIỀN ĐỊNH CO GIÃN THEO NHỊP THỞ
          Center(
            child: ScaleTransition(
              scale: _breathingAnimation,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: primaryGreen.withOpacity(0.08),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(
                    Icons.eco_rounded, // Biểu tượng chiếc lá nguyên bản, thanh khiết
                    color: primaryGreen,
                    size: 64,
                  ),
                ),
              ),
            ),
          ),

          // LỚP 3: THÔNG TIN NHẬN DIỆN THƯƠNG HIỆU VN SHARE
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'VN Share',
                  style: TextStyle(
                    color: primaryGreen,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 8.0, // Tạo khoảng trống thoáng đãng sang trọng
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Hành trình Sống Khỏe & Sẻ chia',
                  style: TextStyle(
                    color: primaryGreen.withOpacity(0.5),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 48),
                // Thanh tiến trình siêu mảnh tinh tế đồng điệu không gian Spa
                SizedBox(
                  width: 40,
                  height: 1.5,
                  child: LinearProgressIndicator(
                    backgroundColor: primaryGreen.withOpacity(0.08),
                    color: primaryGreen.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}