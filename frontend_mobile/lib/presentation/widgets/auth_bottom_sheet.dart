import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/network/api_client.dart';

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
          widget.onSuccess(); 
          if (mounted) Navigator.pop(context); 
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đăng ký thành công! Đăng nhập ngay.', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              backgroundColor: Color(0xFF80BF84),
            )
          );
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? 'Lỗi kết nối máy chủ. Vui lòng thử lại!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
          backgroundColor: Colors.redAccent
        )
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // WIDGET W1: KHUNG NHẬP LIỆU KÍNH MỜ (PREMIUM INPUT)
  Widget _buildGlassInput({
    required TextEditingController controller, 
    required String hint, 
    required IconData icon, 
    bool isPassword = false
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04), // Độ trong suốt cực thấp chuẩn ảnh
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1.5),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontWeight: FontWeight.w400),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.4), size: 22),
          suffixIcon: isPassword 
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white.withOpacity(0.4), size: 20),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ) 
            : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  // WIDGET W2: NÚT ĐĂNG NHẬP MẠNG XÃ HỘI NỔI KHỐI
  Widget _buildSocialBtn(Widget iconWidget) {
    return Container(
      width: 64, height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 1.5),
      ),
      child: Center(child: iconWidget),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25), // Làm mờ sâu để tách biệt với nền video
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 32, 
            left: 28, right: 28, top: 16
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F13).withOpacity(0.85), // Nền Jet Black sang trọng
            borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.15), width: 1.5)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center, // Căn giữa toàn bộ theo thiết kế
              children: [
                // Thanh Drag Handle bo tròn mượt
                Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 32), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10))),
                
                // HEADER TITLES
                Text(
                  _isLoginMode ? 'Chào mừng trở lại' : 'Tạo tài khoản mới', 
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                ),
                const SizedBox(height: 8),
                Text(
                  _isLoginMode ? 'Đăng nhập để lưu video và tương tác.' : 'Mở khóa toàn bộ trải nghiệm y tế.', 
                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500)
                ),
                const SizedBox(height: 36),
                
                // FORM NHẬP LIỆU
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
                      padding: const EdgeInsets.only(bottom: 24, top: 4),
                      child: Text('Quên mật khẩu?', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  const SizedBox(height: 24),
                
                // NÚT HÀNH ĐỘNG CHÍNH
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF80BF84), // XanhSM Signature
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Bo góc 20px 
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _submitAuth,
                    child: _isLoading 
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 3)) 
                        : Text(_isLoginMode ? 'ĐĂNG NHẬP' : 'TẠO TÀI KHOẢN', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1.0)),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // DẢI PHÂN CÁCH "HOẶC TIẾP TỤC VỚI"
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Hoặc tiếp tục với', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    Expanded(child: Divider(color: Colors.white.withOpacity(0.1), thickness: 1.5)),
                  ],
                ),
                const SizedBox(height: 24),
                
                // CỤM NÚT SOCIAL LOGIN
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildSocialBtn(const Icon(Icons.apple_rounded, color: Colors.white, size: 30)),
                    const SizedBox(width: 20),
                    _buildSocialBtn(const Text('G', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, fontFamily: 'sans-serif'))),
                    const SizedBox(width: 20),
                    _buildSocialBtn(const Icon(Icons.facebook_rounded, color: Colors.blueAccent, size: 30)),
                  ],
                ),
                
                const SizedBox(height: 36),
                
                // CHUYỂN ĐỔI CHẾ ĐỘ
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14, fontWeight: FontWeight.w500),
                      children: [
                        TextSpan(text: _isLoginMode ? 'Chưa có tài khoản?  ' : 'Đã có tài khoản?  '),
                        TextSpan(
                          text: _isLoginMode ? 'Đăng ký' : 'Đăng nhập', 
                          style: const TextStyle(color: Color(0xFF80BF84), fontWeight: FontWeight.w800)
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}