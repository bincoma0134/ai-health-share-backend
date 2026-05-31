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
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  
  final _storage = const FlutterSecureStorage();

  Future<void> _submitAuth() async {
    setState(() => _isLoading = true);
    try {
      if (_isLoginMode) {
        // Gọi API Đăng nhập
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
        // Gọi API Đăng ký
        final res = await ApiClient.instance.post('/auth/register', data: {
          'email': _emailController.text.trim(),
          'username': _usernameController.text.trim(),
          'full_name': _fullNameController.text.trim(),
          'password': _passwordController.text,
          'role': 'USER'
        });
        
        if (res.statusCode == 200) {
          // Thành công thì chuyển sang form Đăng nhập
          setState(() => _isLoginMode = true);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đăng ký thành công! Hãy đăng nhập.')));
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? 'Lỗi kết nối máy chủ';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg, style: const TextStyle(color: Colors.white)), backgroundColor: Colors.red));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_isLoginMode ? 'Đăng nhập' : 'Tham gia mạng lưới', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            TextField(controller: _emailController, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            
            if (!_isLoginMode) ...[
              TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username', border: OutlineInputBorder())),
              const SizedBox(height: 16),
              TextField(controller: _fullNameController, decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder())),
              const SizedBox(height: 16),
            ],
            
            TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu', border: OutlineInputBorder())),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black),
                onPressed: _isLoading ? null : _submitAuth,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : Text(_isLoginMode ? 'Xác thực truy cập' : 'Tạo tài khoản', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            
            TextButton(
              onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
              child: Center(child: Text(_isLoginMode ? 'Chưa có tài khoản? Đăng ký ngay' : 'Đã có tài khoản? Đăng nhập')),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}