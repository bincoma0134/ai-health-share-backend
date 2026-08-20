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
    try {
      print('[DEBUG-SPLASH] Khởi chạy luồng khởi động nhanh ứng dụng...');

      // 1. Chạy song song: Đọc Token cục bộ & Hiển thị tối thiểu 600ms thương hiệu (Không chờ tuần tự)
      final results = await Future.wait([
        SecureStorageService.getToken(),
        Future.delayed(const Duration(milliseconds: 600)),
      ]);

      if (!mounted) return;
      final token = results[0] as String?;

      // Nếu không có Token -> Chuyển ngay đến màn hình Đăng nhập
      if (token == null || token.isEmpty) {
        print('[DEBUG-SPLASH] Không tìm thấy Token cục bộ -> Điều hướng /login');
        if (mounted) context.go('/login');
        return;
      }

      print('[DEBUG-SPLASH] Tìm thấy Token cục bộ. Bắt đầu đồng bộ hồ sơ...');

      // 2. Gọi xác thực phiên Server nhưng có cơ chế phòng vệ mạng (Timeout 2.5s)
      Map<String, dynamic>? userProfileResponse;
      try {
        userProfileResponse = await UserApiService.fetchPrivateProfile()
            .timeout(const Duration(milliseconds: 2500));
      } catch (e) {
        print('[DEBUG-SPLASH-WARN] API Profile timeout hoặc lỗi mạng: $e');
        userProfileResponse = null;
      }

      if (!mounted) return;

      // 3. Xử lý dữ liệu Profile & Điều hướng
      if (userProfileResponse != null && userProfileResponse['profile'] != null) {
        final profileData = userProfileResponse['profile'];
        final fullName = profileData['full_name'] ?? 'bạn';
        final role = profileData['role'] ?? 'USER';

        // Đồng bộ ngầm không chặn luồng điều hướng (Fire-and-forget)
        SecureStorageService.saveName(fullName);
        SecureStorageService.saveRole(role);

        AppToast.show(
          context: context,
          message: 'Chào mừng $fullName trở lại hệ thống!',
          isSuccess: true,
          duration: const Duration(seconds: 3),
        );
        print('[DEBUG-SPLASH-SUCCESS] Xác thực Server thành công -> Điều hướng /');
        context.go('/');
      } else {
        // 🚀 BỌC THÉP LOCAL-FIRST: Nếu API trễ do mạng/cold start nhưng Token còn nguyên vẹn,
        // TUYỆT ĐỐI KHÔNG clearSession mà cho phép User vào thẳng trang chủ
        print('[DEBUG-SPLASH-LOCAL-FIRST] Cho phép sử dụng phiên đăng nhập cục bộ -> Điều hướng /');
        final savedName = await SecureStorageService.getName() ?? 'bạn';
        
        AppToast.show(
          context: context,
          message: 'Chào mừng $savedName trở lại hệ thống!',
          isSuccess: true,
          duration: const Duration(seconds: 3),
        );
        context.go('/');
      }
    } catch (e) {
      print('[DEBUG-SPLASH-EXCEPTION] Lỗi ngoại lệ trong quá trình khởi động: $e');
      // Khi gặp lỗi nghiêm trọng không thể phục hồi mới điều hướng về login
      if (mounted) context.go('/login');
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
                          color: primaryGreen.withValues(alpha: (1 - progress) * 0.15),
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
                      color: primaryGreen.withValues(alpha: 0.08),
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
                    color: primaryGreen.withValues(alpha: 0.5),
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
                    backgroundColor: primaryGreen.withValues(alpha: 0.08),
                    color: primaryGreen.withValues(alpha: 0.35),
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