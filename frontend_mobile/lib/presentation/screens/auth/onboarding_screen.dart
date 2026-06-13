import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/user_api_service.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _usernameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _selectedGender = 'Khác';
  bool _isLoading = false;

  Future<void> _submitProfile() async {
    final username = _usernameCtrl.text.trim();
    if (username.isEmpty || username.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Username phải từ 3 ký tự trở lên')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await UserApiService.updateProfile({
        'username': username,
        'gender': _selectedGender,
        'phone': _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
      });

      if (success && mounted) {
        context.go('/');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật thất bại. Username có thể đã tồn tại.')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.zinc950,
      appBar: AppBar(
        title: const Text('Hoàn thiện hồ sơ', style: TextStyle(color: Colors.white, fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('Bỏ qua', style: TextStyle(color: Colors.grey)),
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Chào mừng bạn mới!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.zinc50)),
            const SizedBox(height: 8),
            const Text('Cung cấp thêm một chút thông tin để chúng tôi cá nhân hóa trải nghiệm của bạn.', style: TextStyle(color: Colors.grey, height: 1.5)),
            const SizedBox(height: 40),
            
            TextField(
              controller: _usernameCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Username (Bắt buộc)', 
                labelStyle: const TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800))
              ),
            ),
            const SizedBox(height: 24),

            const Text('Giới tính', style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            Row(
              children: ['Nam', 'Nữ', 'Khác'].map((gender) => Expanded(
                child: RadioListTile<String>(
                  title: Text(gender, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  value: gender,
                  groupValue: _selectedGender,
                  activeColor: AppTheme.blue500,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _selectedGender = val!),
                ),
              )).toList(),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Số điện thoại (Tuỳ chọn)', 
                labelStyle: const TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade800))
              ),
            ),
            const SizedBox(height: 48),

            _isLoading 
              ? const Center(child: CircularProgressIndicator(color: AppTheme.blue500)) 
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.blue500,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _submitProfile,
                  child: const Text('Tiếp tục', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
          ],
        ),
      ),
    );
  }
}