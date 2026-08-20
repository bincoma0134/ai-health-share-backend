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
  bool _obscurePassword = true; // 🚀 NÂNG CẤP UX: Quản lý trạng thái Ẩn/Hiện mật khẩu
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

  // --- LOGIC AUTH VỚI CLIENT-SIDE VALIDATION & FOCUS UNFOCUS ---
  Future<void> _handleEmailAuth() async {
    if (isLoading) return;
    FocusScope.of(context).unfocus(); // 🚀 Ẩn bàn phím ngay lập tức chống giật khung hình

    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    // 🚀 BẢO VỆ CLIENT-SIDE: Kiểm tra dữ liệu rỗng và độ dài trong 0ms
    if (email.isEmpty) {
      AppToast.show(context: context, message: 'Vui lòng nhập địa chỉ Email!', isSuccess: false);
      return;
    }
    if (pass.isEmpty) {
      AppToast.show(context: context, message: 'Vui lòng nhập Mật khẩu!', isSuccess: false);
      return;
    }
    if (!isLogin) {
      if (_nameCtrl.text.trim().isEmpty) {
        AppToast.show(context: context, message: 'Vui lòng nhập Họ và tên!', isSuccess: false);
        return;
      }
      if (_userCtrl.text.trim().isEmpty) {
        AppToast.show(context: context, message: 'Vui lòng nhập Username định danh!', isSuccess: false);
        return;
      }
      if (pass.length < 6) {
        AppToast.show(context: context, message: 'Mật khẩu phải có tối thiểu 6 ký tự!', isSuccess: false);
        return;
      }
    }

    setState(() => isLoading = true);
    print('[DEBUG-AUTH] Bắt đầu xác thực Email Auth: Mode=${isLogin ? "LOGIN" : "REGISTER"} | Email=$email');

    try {
      if (isLogin) {
        final res = await UserApiService.loginEmail(email, pass);
        if (res != null && res['access_token'] != null) {
          final fullName = res['user']['full_name'] ?? 'bạn';
          final role = res['user']['role'] ?? 'USER';

          // 🚀 TĂNG TỐC ĐĂNG NHẬP: Ghi đĩa KeyStore/Keychain song song (Giảm 66% thời gian I/O)
          await Future.wait([
            SecureStorageService.saveToken(res['access_token']),
            SecureStorageService.saveRole(role),
            SecureStorageService.saveName(fullName),
          ]);

          // ĐỒNG BỘ RAM: Ép nạp lại dữ liệu mới nhất từ Storage
          await AuthNotifier.instance.refresh();

          if (mounted) {
            print('[DEBUG-AUTH-SUCCESS] Đăng nhập thành công -> Điều hướng /');
            AppToast.show(
              context: context, 
              message: 'Chào mừng $fullName trở lại hệ thống!', 
              isSuccess: true, 
              duration: const Duration(seconds: 3)
            );
            context.go('/');
          }
        } else {
          print('[DEBUG-AUTH-FAIL] Không nhận được Access Token hợp lệ từ máy chủ');
          if (mounted) AppToast.show(context: context, message: 'Tài khoản hoặc mật khẩu không chính xác.', isSuccess: false);
        }
      } else {
        final res = await UserApiService.registerEmail(email, pass, _userCtrl.text.trim(), _nameCtrl.text.trim());
        if (res != null) {
          print('[DEBUG-AUTH-REGISTER-SUCCESS] Đăng ký thành công -> Chuyển sang form Đăng nhập');
          if (mounted) AppToast.show(context: context, message: '🎉 Đăng ký thành công! Hãy đăng nhập ngay.', isSuccess: true);
          setState(() => isLogin = true);
        } else {
          print('[DEBUG-AUTH-REGISTER-FAIL] Đăng ký thất bại: Trùng Email/Username');
          if (mounted) AppToast.show(context: context, message: 'Đăng ký thất bại. Email hoặc Username có thể đã tồn tại.', isSuccess: false);
        }
      }
    } on DioException catch (e) {
      // 🚀 BẮT LỖI THÔNG MINH TỪ BACKEND: Phân biệt rõ "Tài khoản không tồn tại" và "Sai mật khẩu"
      final String errorMessage = e.response?.data is Map 
          ? (e.response?.data['detail'] ?? 'Lỗi xác thực từ máy chủ.') 
          : 'Lỗi kết nối máy chủ xác thực.';
      print('[DEBUG-AUTH-DIO-ERROR] Mã lỗi ${e.response?.statusCode}: $errorMessage');
      if (mounted) AppToast.show(context: context, message: errorMessage, isSuccess: false);
    } catch (e) {
      print('[DEBUG-AUTH-EXCEPTION] Lỗi ngoại lệ khi xác thực Email: $e');
      if (mounted) AppToast.show(context: context, message: 'Lỗi kết nối máy chủ xác thực.', isSuccess: false);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _handleSocialAuth(String provider) async {
    if (isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() => isLoading = true);
    print('[DEBUG-SOCIAL-AUTH] Bắt đầu xác thực qua mạng xã hội: $provider');

    try {
      String? idToken;
      
      // 1. Kích hoạt luồng SDK Native
      if (provider == 'Google') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          print('[DEBUG-SOCIAL-AUTH] Người dùng đã hủy đăng nhập Google');
          setState(() => isLoading = false);
          return;
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
          print('[DEBUG-SOCIAL-AUTH] Facebook login cancelled or failed: ${result.message}');
          setState(() => isLoading = false);
          return;
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

          await AuthNotifier.instance.refresh();

          if (mounted) {
            print('[DEBUG-SOCIAL-AUTH-SUCCESS] Đăng nhập $provider thành công -> Điều hướng /');
            AppToast.show(
              context: context, 
              message: 'Chào mừng $fullName trở lại hệ thống!', 
              isSuccess: true, 
              duration: const Duration(seconds: 3)
            );
            context.go('/');
          }
        } else {
          print('[DEBUG-SOCIAL-AUTH-FAIL] Backend từ chối Token Firebase');
          if (mounted) AppToast.show(context: context, message: 'Chứng thực thất bại từ máy chủ hệ thống.', isSuccess: false);
        }
      }
    } on DioException catch (e) {
      final String errorMessage = e.response?.data['detail'] ?? 'Lỗi từ máy chủ: ${e.message}';
      print('[DEBUG-SOCIAL-AUTH-DIO-ERROR] $errorMessage');
      if (mounted) AppToast.show(context: context, message: errorMessage, isSuccess: false);
    } catch (e) {
      print('[DEBUG-SOCIAL-AUTH-EXCEPTION] Lỗi ngoại lệ: $e');
      if (mounted) AppToast.show(context: context, message: 'Đăng nhập mạng xã hội không thành công.', isSuccess: false);
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
                  color: Colors.white.withValues(alpha: 0.6),
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
                'Khám phá không gian sức khỏe và chia sẻ giá trị sống đích thực cùng mạng lưới chuyên gia VN SHARE.',
                style: TextStyle(fontSize: 15, color: primaryGreen.withValues(alpha: 0.8), height: 1.5, fontWeight: FontWeight.w500),
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
                  child: Text('Bỏ qua & Khám phá', style: TextStyle(color: primaryGreen.withValues(alpha: 0.6), fontSize: 15, fontWeight: FontWeight.w600)),
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
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: primaryGreen.withValues(alpha: 0.8)),
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
                    BoxShadow(color: primaryGreen.withValues(alpha: 0.04), blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 12))
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
                    _buildTextField(
                      controller: _passCtrl, 
                      label: 'Mật khẩu', 
                      icon: Icons.lock_outline_rounded, 
                      isPassword: true,
                      obscureText: _obscurePassword,
                      onToggleVisibility: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    
                    // CTA Quên Mật Khẩu
                    if (isLogin)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => AppToast.show(context: context, message: 'Tính năng Quên mật khẩu đang cập nhật...', isSuccess: true),
                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), minimumSize: Size.zero),
                          child: Text('Quên mật khẩu?', style: TextStyle(color: primaryGreen.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                        ),
                      )
                    else
                      const SizedBox(height: 24),

                    SizedBox(height: isLogin ? 12 : 0),

                    isLoading 
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: CircularProgressIndicator(color: primaryGreen),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 56),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            elevation: 4,
                            shadowColor: primaryGreen.withValues(alpha: 0.4),
                          ),
                          onPressed: isLoading ? null : _handleEmailAuth,
                          child: Text(isLogin ? 'Đăng nhập' : 'Đăng ký', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: TextButton(
                  style: TextButton.styleFrom(splashFactory: NoSplash.splashFactory),
                  onPressed: isLoading ? null : () => setState(() => isLogin = !isLogin),
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
                  _buildGoogleBrandButton(onTap: isLoading ? null : () => _handleSocialAuth('Google')),
                  const SizedBox(width: 20),
                  _buildSocialButton(Icons.facebook_rounded, isLoading ? () {} : () => _handleSocialAuth('Facebook'), color: const Color(0xFF1877F2)),
                ],
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller, 
    required String label, 
    required IconData icon, 
    bool isPassword = false, 
    bool isEmail = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword ? obscureText : false,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black87, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.4), fontWeight: FontWeight.w500),
        prefixIcon: Icon(icon, color: primaryGreen.withValues(alpha: 0.6), size: 22),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: Colors.black38,
                  size: 20,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 0.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Colors.grey.shade200, width: 0.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: primaryGreen.withValues(alpha: 0.5), width: 1.0)),
      ),
    );
  }

  // 🚀 BIỂU TƯỢNG GOOGLE CHUẨN THƯƠNG HIỆU (BRAND ICON)
  Widget _buildGoogleBrandButton({VoidCallback? onTap}) {
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
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: Color(0xFFEA4335),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'G',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  fontFamily: 'sans-serif',
                ),
              ),
            ),
          ),
        ),
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
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))
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