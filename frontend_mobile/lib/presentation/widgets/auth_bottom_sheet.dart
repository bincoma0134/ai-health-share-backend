import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../../core/network/api_client.dart';
import '../../data/services/user_api_service.dart';
import '../../data/services/secure_storage_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/auth_guard.dart';

class AuthBottomSheet extends StatefulWidget {
  final VoidCallback onSuccess;
  const AuthBottomSheet({super.key, required this.onSuccess});

  @override
  State<AuthBottomSheet> createState() => _AuthBottomSheetState();
}

class _AuthBottomSheetState extends State<AuthBottomSheet> {
  bool _isLoginMode = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  
  final _storage = const FlutterSecureStorage();

  Future<void> _submitAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        // LUỒNG ĐĂNG NHẬP
        final res = await ApiClient.instance.post('/auth/login', data: {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        });
        
        if (res.statusCode == 200) {
          await _storage.write(key: 'ai-health-token', value: res.data['access_token']);
          
          // Kích hoạt đồng bộ state toàn cục
          await AuthNotifier.instance.refresh();
          
          if (mounted) {
            AppToast.show(context: context, message: 'Đăng nhập thành công', isSuccess: true);
            widget.onSuccess(); 
            Navigator.pop(context); 
          }
        }
      } else {
        // LUỒNG ĐĂNG KÝ
        final res = await ApiClient.instance.post('/auth/register', data: {
          'email': _emailController.text.trim(),
          'username': _usernameController.text.trim(),
          'full_name': _fullNameController.text.trim(),
          'password': _passwordController.text,
          'role': 'USER' 
        });
        
        if (res.statusCode == 200) {
          setState(() {
            _isLoginMode = true;
            _passwordController.clear();
          });
          if (mounted) {
            AppToast.show(context: context, message: 'Đăng ký thành công! Vui lòng đăng nhập.', isSuccess: true);
          }
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? 'Lỗi kết nối máy chủ. Vui lòng thử lại!';
      if (mounted) {
        AppToast.show(context: context, message: msg, isSuccess: false);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context: context, message: 'Có lỗi xảy ra: $e', isSuccess: false);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // WIDGET W1: KHUNG NHẬP LIỆU CHUẨN APPLE-LEVEL (MINIMALIST COMPACT)
  Widget _buildGlassInput({
    required TextEditingController controller, 
    required String hint, 
    required IconData icon, 
    bool isPassword = false
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), // Giảm khoảng cách giữa các ô nhập liệu
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 2))
        ]
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: const TextStyle(color: Color(0xFF2C3E35), fontSize: 14, fontWeight: FontWeight.w400), // Thu nhỏ chữ
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontWeight: FontWeight.w300),
          prefixIcon: Icon(icon, color: const Color(0xFF4A8B6F).withOpacity(0.6), size: 20), // Thu nhỏ Icon
          suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.grey.shade400, size: 18),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ) 
            : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), // Thu gọn padding trong
        ),
      ),
    );
  }

  Future<void> _handleSocialAuth(String provider) async {
    setState(() => _isLoading = true);
    try {
      String? idToken;
      
      if (provider == 'Google') {
        final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }
        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
        idToken = await userCred.user?.getIdToken();
      } else if (provider == 'Facebook') {
        final LoginResult result = await FacebookAuth.instance.login(
          permissions: ['public_profile', 'email'],
        );
        if (result.status == LoginStatus.success) {
          final OAuthCredential credential = FacebookAuthProvider.credential(result.accessToken!.tokenString);
          final UserCredential userCred = await FirebaseAuth.instance.signInWithCredential(credential);
          idToken = await userCred.user?.getIdToken();
        } else {
          setState(() => _isLoading = false);
          return;
        }
      }

      if (idToken != null) {
        final res = await UserApiService.loginFirebase(idToken);
        if (res != null && res['access_token'] != null) {
          await SecureStorageService.saveToken(res['access_token']);
          await SecureStorageService.saveRole(res['user']['role'] ?? 'USER');
          
          final fullName = res['user']['full_name'] ?? 'bạn';
          await SecureStorageService.saveName(fullName);
          
          await AuthNotifier.instance.refresh();

          if (mounted) {
            AppToast.show(context: context, message: 'Chào mừng $fullName trở lại!', isSuccess: true);
            widget.onSuccess();
            Navigator.pop(context);
          }
        } else {
          if (mounted) AppToast.show(context: context, message: 'Chứng thực thất bại từ máy chủ hệ thống.', isSuccess: false);
        }
      }
    } catch (e) {
      if (mounted) AppToast.show(context: context, message: 'Lỗi đăng nhập $provider: $e', isSuccess: false);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // WIDGET W2: NÚT ĐĂNG NHẬP MẠNG XÃ HỘI (COMPACT HƠN NỮA)
  Widget _buildSocialBtn(Widget iconWidget, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 52, height: 52, // Thu nhỏ kích cỡ nút
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 1.0),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
          ]
        ),
        child: Center(child: iconWidget),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent, // Bắt buộc để Backdrop hoạt động đúng
      resizeToAvoidBottomInset: true, // Tự động đẩy Modal lên khi bàn phím xuất hiện
      body: SafeArea( // BẢO VỆ TUYỆT ĐỐI: Ép Modal luôn nằm gọn trong vùng an toàn, không bị Navigation Bar che khuất
        top: true,
        bottom: true,
        child: Center( // Căn giữa tuyệt đối trong không gian an toàn
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), 
              constraints: const BoxConstraints(maxWidth: 380), 
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), 
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 24), // Padding đồng nhất, ép chặt nội dung
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F6).withOpacity(0.95), 
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 40, offset: const Offset(0, 10))
                    ]
                  ),
                  child: Column( // Bỏ SingleChildScrollView ở đây để tránh dãn Modal
                    mainAxisSize: MainAxisSize.min, // Ép khung chữ nhật sát theo đúng chiều cao nội dung
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // HEADER: Biểu tượng Spa/Wellness
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                      ),
                      child: const Icon(Icons.spa_rounded, size: 28, color: Color(0xFF6B8E7B)), // Thu nhỏ Icon
                    ),
                    const SizedBox(height: 16), // Giảm spacing
                    
                    // TIÊU ĐỀ: Ấm áp, thư giãn
                    Text(
                      _isLoginMode ? 'Chào mừng bạn' : 'Bắt đầu hành trình', 
                      style: const TextStyle(color: Color(0xFF2C3E35), fontSize: 22, fontWeight: FontWeight.w400, letterSpacing: 0.5) // Giảm size chữ
                    ),
                    const SizedBox(height: 8), // Giảm spacing
                    
                    // SUBTITLE: Giá trị hội viên
                    Text(
                      _isLoginMode 
                        ? 'Tiếp tục hành trình chăm sóc bản thân, quản lý lịch hẹn và nhận các ưu đãi.' 
                        : 'Tham gia không gian trị liệu, lưu giữ lịch sử và tích lũy điểm thưởng SValue.', 
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF6B8E7B), fontSize: 13, fontWeight: FontWeight.w300, height: 1.5) // Giảm size và line-height
                    ),
                    const SizedBox(height: 24), // Giảm spacing rất lớn từ 36 -> 24
                    
                    // TẦNG 1: FORM ĐĂNG NHẬP EMAIL
                    _buildGlassInput(controller: _emailController, hint: 'Địa chỉ Email', icon: Icons.mail_outline_rounded),
                    
                    if (!_isLoginMode) ...[
                      _buildGlassInput(controller: _usernameController, hint: 'Tên người dùng', icon: Icons.alternate_email_rounded),
                      _buildGlassInput(controller: _fullNameController, hint: 'Họ và tên', icon: Icons.badge_outlined),
                    ],
                    
                    _buildGlassInput(controller: _passwordController, hint: 'Mật khẩu bảo mật', icon: Icons.lock_outline_rounded, isPassword: true),
                    
                    if (_isLoginMode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 16), // Bỏ top padding, giảm bottom padding từ 24 -> 16
                          child: TextButton(
                            onPressed: () => AppToast.show(context: context, message: 'Tính năng Quên mật khẩu đang cập nhật...', isSuccess: true),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                              minimumSize: Size.zero,
                              foregroundColor: const Color(0xFF6B8E7B),
                            ),
                            child: const Text('Quên mật khẩu?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400)),
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 16), // Giảm spacing
                    
                    // NÚT HÀNH ĐỘNG CHÍNH
                    SizedBox(
                      width: double.infinity,
                      height: 52, // Thu gọn nút
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2C3E35), // Dark Sage
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), // Giảm bo góc theo nút
                          elevation: 0,
                        ),
                        onPressed: _isLoading ? null : _submitAuth,
                        child: _isLoading 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : Text(_isLoginMode ? 'Mở Cửa Không Gian' : 'Bắt Đầu Hành Trình', style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 15, letterSpacing: 0.5)),
                      ),
                    ),
                    
                    const SizedBox(height: 24), // Giảm spacing
                    
                    // DẢI PHÂN CÁCH TỐI GIẢN
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 0.5)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('Hoặc đăng nhập nhanh', style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w300)),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade300, thickness: 0.5)),
                      ],
                    ),
                    const SizedBox(height: 20), // Giảm spacing
                    
                    // TẦNG 2: SOCIAL BUTTONS (ĐƯA XUỐNG DƯỚI CÙNG)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Nút Apple
                        _buildSocialBtn(
                          const Icon(Icons.apple_rounded, color: Colors.black87, size: 26),
                          () => AppToast.show(context: context, message: 'Tính năng đăng nhập Apple đang cập nhật...', isSuccess: true)
                        ),
                        const SizedBox(width: 16), // Giảm khoảng cách giữa các khối nút
                        // Nút Google
                        _buildSocialBtn(
                          Image.asset('assets/images/google_logo.png', height: 22, errorBuilder: (_,__,___) => const Text('G', style: TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.w500, fontFamily: 'sans-serif'))),
                          () => _handleSocialAuth('Google')
                        ),
                        const SizedBox(width: 16),
                        // Nút Facebook
                        _buildSocialBtn(
                          const Icon(Icons.facebook_rounded, color: Color(0xFF1877F2), size: 26),
                          () => _handleSocialAuth('Facebook')
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24), // Giảm spacing
                    
                    // CHUYỂN ĐỔI CHẾ ĐỘ ĐĂNG NHẬP / ĐĂNG KÝ
                    // CHUYỂN ĐỔI CHẾ ĐỘ ĐĂNG NHẬP / ĐĂNG KÝ
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _isLoginMode = !_isLoginMode),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 13, fontWeight: FontWeight.w300), // Giảm size text phụ
                          children: [
                            TextSpan(text: _isLoginMode ? 'Chưa có tài khoản?  ' : 'Đã có tài khoản?  '),
                            TextSpan(
                              text: _isLoginMode ? 'Đăng ký ngay' : 'Đăng nhập', 
                              style: const TextStyle(color: Color(0xFF4A8B6F), fontWeight: FontWeight.w500)
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ), // Đóng Column (9)
              ), // Đóng Container (8)
            ), // Đóng BackdropFilter (7)
          ), // Đóng ClipRRect (6)
        ), // Đóng Container (5)
      ), // Đóng SingleChildScrollView (4)
    ), // Đóng Center (3)
    ), // Đóng SafeArea (2)
    ); // Đóng Scaffold (1)
  }
}