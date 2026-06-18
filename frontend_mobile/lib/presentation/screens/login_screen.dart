import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:dio/dio.dart'; // THÊM ĐỂ BẮT LỖI API
import '../../data/services/secure_storage_service.dart';
import '../../data/services/user_api_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isLogin = true;
  bool isLoading = false;
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final PageController _pageController = PageController(initialPage: 0);

  // Mã màu chuẩn Wellness & Healing theo kiến trúc mới
  final Color primaryGreen = const Color(0xFF4A8B6F);
  final Color backgroundLight = const Color(0xFFF4F9F5);

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _userCtrl.dispose();
    _nameCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // --- LOGIC BACKEND KHÔNG ĐỔI ---
  Future<void> _handleEmailAuth() async {
    setState(() => isLoading = true);
    try {
      if (isLogin) {
        final res = await UserApiService.loginEmail(_emailCtrl.text.trim(), _passCtrl.text);
        if (res != null && res['access_token'] != null) {
          await SecureStorageService.saveToken(res['access_token']);
          await SecureStorageService.saveRole(res['user']['role'] ?? 'USER');
          
          final fullName = res['user']['full_name'] ?? 'bạn';
          final role = res['user']['role'] ?? 'USER';
          await SecureStorageService.saveName(fullName);

          // ĐỒNG BỘ RAM: Ép nạp lại dữ liệu mới nhất từ Storage (bỏ qua cờ khóa _isInitialized)
          await AuthNotifier.instance.refresh();

          if (mounted) {
            // Toast 1: Thông báo đăng nhập thành công
            AppToast.show(context: context, message: 'Đăng nhập thành công', isSuccess: true, duration: const Duration(seconds: 2));
            
            // Giữ lại context của hệ thống để gọi Toast 2 sau khi đã chuyển trang
            final overlayContext = context;
            
            // Toast 2: Lời chào cá nhân hóa (delay 1.5s để nối tiếp mượt mà)
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (overlayContext.mounted) {
                AppToast.show(
                  context: overlayContext, 
                  message: 'Chào mừng $fullName trở lại hệ thống! Chúc bạn một ngày an lành và thư thái.', 
                  isSuccess: true, 
                  duration: const Duration(seconds: 4)
                );
              }
            });

            // Điều hướng đồng nhất về Trang chủ theo yêu cầu tinh chỉnh luồng
            context.go('/');
          }
        } else {
          if (mounted) AppToast.show(context: context, message: 'Tài khoản hoặc mật khẩu không chính xác', isSuccess: false);
        }
      } else {
        final res = await UserApiService.registerEmail(_emailCtrl.text.trim(), _passCtrl.text, _userCtrl.text.trim(), _nameCtrl.text.trim());
        if (res != null) {
          if (mounted) AppToast.show(context: context, message: 'Đăng ký thành công! Đang chuyển hướng...', isSuccess: true);
          await Future.delayed(const Duration(seconds: 1));
          setState(() => isLogin = true);
        } else {
          if (mounted) AppToast.show(context: context, message: 'Đăng ký thất bại. Email hoặc Username có thể đã tồn tại.', isSuccess: false);
        }
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleSocialAuth(String provider) async {
    setState(() => isLoading = true);
    try {
      String? idToken;
      
      // 1. Kích hoạt luồng SDK Native
      if (provider == 'Google') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => isLoading = false);
          return; // Người dùng ấn hủy
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
        idToken = await userCred.user?.getIdToken();
      } 
      else if (provider == 'Facebook') {
        final LoginResult result = await FacebookAuth.instance.login(
          permissions: ['public_profile', 'email'],
        );
        if (result.status == LoginStatus.success) {
          final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
          final UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
          idToken = await userCred.user?.getIdToken();
        } else {
          setState(() => isLoading = false);
          return; // Canceled hoặc Failed
        }
      }

      // 2. Gửi ID Token thật của Firebase lên Backend của chúng ta
      if (idToken != null) {
        final res = await UserApiService.loginFirebase(idToken);
        
        if (res != null && res['access_token'] != null) {
          final fullName = res['user']['full_name'] ?? 'bạn';
          final role = res['user']['role'] ?? 'USER';
          
          await SecureStorageService.saveToken(res['access_token']);
          await SecureStorageService.saveRole(role);
          await SecureStorageService.saveName(fullName);

          // ĐỒNG BỘ RAM: Ép nạp lại dữ liệu mới nhất từ Storage (bỏ qua cờ khóa _isInitialized)
          await AuthNotifier.instance.refresh();

          if (mounted) {
            AppToast.show(context: context, message: 'Đăng nhập thành công', isSuccess: true, duration: const Duration(seconds: 2));
            
            final overlayContext = context;
            Future.delayed(const Duration(milliseconds: 1500), () {
              if (overlayContext.mounted) {
                AppToast.show(context: overlayContext, message: 'Chào mừng $fullName trở lại hệ thống!', isSuccess: true);
              }
            });

            context.go('/');
          }
        } else {
          if (mounted) AppToast.show(context: context, message: 'Chứng thực thất bại từ máy chủ hệ thống.', isSuccess: false);
        }
      }
    } on DioException catch (e) {
      // Phơi bày lỗi thật từ Backend
      final String errorMessage = e.response?.data['detail'] ?? 'Lỗi từ máy chủ: ${e.message}';
      if (mounted) AppToast.show(context: context, message: errorMessage, isSuccess: false);
    } catch (e) {
      // Lỗi hệ thống khác
      if (mounted) AppToast.show(context: context, message: 'Lỗi ngoại lệ: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- GIAO DIỆN 1: WELCOME SCREEN ---
  Widget _buildWelcomeView() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [backgroundLight, const Color(0xFFE2EFE7)],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.eco_rounded, color: primaryGreen, size: 64),
              ),
              const SizedBox(height: 24),
              Text(
                'Bắt đầu\nHành trình tĩnh tại',
                style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: primaryGreen, height: 1.2),
              ),
              const SizedBox(height: 16),
              Text(
                'Khám phá không gian sức khỏe và chia sẻ giá trị sống đích thực cùng mạng lưới chuyên gia AI Health.',
                style: TextStyle(fontSize: 15, color: primaryGreen.withOpacity(0.8), height: 1.5, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryGreen,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  elevation: 0,
                ),
                onPressed: () => _pageController.nextPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
                child: const Text('Bắt đầu ngay', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => context.go('/'),
                  child: Text('Bỏ qua & Khám phá', style: TextStyle(color: primaryGreen.withOpacity(0.6), fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- GIAO DIỆN 2: FORM ĐĂNG NHẬP (GLASSMORPHISM) ---
  Widget _buildAuthForm() {
    return Container(
      color: backgroundLight,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                alignment: Alignment.centerLeft,
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryGreen.withOpacity(0.8)),
                onPressed: () => _pageController.previousPage(duration: const Duration(milliseconds: 500), curve: Curves.easeInOut),
              ),
              const SizedBox(height: 24),
              // Hiệu ứng mờ dần chuyển đổi Text nhẹ nhàng
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: Text(
                  isLogin ? 'Chào mừng\ntrở lại!' : 'Tạo tài khoản\nmới',
                  key: ValueKey<bool>(isLogin),
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: primaryGreen, height: 1.2, letterSpacing: -0.5),
                ),
              ),
              const SizedBox(height: 32),
              
              // Thẻ Panel Form bo góc sâu, đổ bóng cực nhẹ
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(color: primaryGreen.withOpacity(0.04), blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 12))
                  ]
                ),
                child: Column(
                  children: [
                    // Cấu trúc AnimatedSize giúp form tự động đẩy lên/xuống mượt mà không bị giật
                    AnimatedSize(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.fastOutSlowIn,
                      alignment: Alignment.topCenter,
                      child: Column(
                        children: [
                          if (!isLogin) ...[
                            _buildTextField(controller: _nameCtrl, label: 'Họ và tên', icon: Icons.person_outline_rounded),
                            const SizedBox(height: 16),
                            _buildTextField(controller: _userCtrl, label: 'Username', icon: Icons.alternate_email_rounded),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                    _buildTextField(controller: _emailCtrl, label: 'Email', icon: Icons.email_outlined, isEmail: true),
                    const SizedBox(height: 16),
                    _buildTextField(controller: _passCtrl, label: 'Mật khẩu', icon: Icons.lock_outline_rounded, isPassword: true),
                    
                    // CTA Quên Mật Khẩu
                    if (isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => AppToast.show(context: context, message: 'Tính năng Quên mật khẩu đang cập nhật...', isSuccess: true),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
                          child: Text('Quên mật khẩu?', style: TextStyle(color: primaryGreen.withOpacity(0.7), fontWeight: FontWeight.w600)),
                        ),
                      )
                    else
                      const SizedBox(height: 24),

                    SizedBox(height: isLogin ? 12 : 0),

                    isLoading 
                      ? CircularProgressIndicator(color: primaryGreen) 
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 4,
                            shadowColor: primaryGreen.withOpacity(0.4),
                          ),
                          onPressed: _handleEmailAuth,
                          child: Text(isLogin ? 'Đăng nhập' : 'Đăng ký', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory), // Bỏ hiệu ứng loang lổ khi chạm
                  onPressed: () => setState(() => isLogin = !isLogin),
                  child: RichText(
                    text: TextSpan(
                      text: isLogin ? 'Chưa có tài khoản? ' : 'Đã có tài khoản? ',
                      style: const TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w500),
                      children: [
                        TextSpan(
                          text: isLogin ? 'Đăng ký ngay' : 'Đăng nhập',
                          style: TextStyle(color: primaryGreen, fontWeight: FontWeight.w800),
                        )
                      ]
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1.5)),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Hoặc tiếp tục với', style: TextStyle(color: Colors.black45, fontSize: 13, fontWeight: FontWeight.w600))),
                  Expanded(child: Divider(color: Colors.grey.shade200, thickness: 1.5)),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSocialButton(Icons.g_mobiledata_rounded, () => _handleSocialAuth('Google'), size: 44),
                  const SizedBox(width: 20),
                  _buildSocialButton(Icons.facebook_rounded, () => _handleSocialAuth('Facebook'), color: const Color(0xFF1877F2)),
                ],
              ),
              const SizedBox(height: 32), // Không gian đệm chống tràn bàn phím
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool isPassword = false, bool isEmail = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.black.withOpacity(0.4), fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: primaryGreen.withOpacity(0.6), size: 22),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 0.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 0.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryGreen.withOpacity(0.5), width: 1.0)),
      ),
    );
  }

  Widget _buildSocialButton(IconData icon, VoidCallback onTap, {Color? color, double size = 28}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200, width: 0.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: Icon(icon, size: size, color: color ?? Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundLight,
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(), // Chặn vuốt ngang tự do để bắt buộc dùng nút CTA
        children: [
          _buildWelcomeView(),
          _buildAuthForm(),
        ],
      ),
    );
  }
}