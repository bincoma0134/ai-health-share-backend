import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/user_api_service.dart';
import '../../../data/services/secure_storage_service.dart';
import '../../widgets/guest_profile_view.dart';
import 'super_admin_profile_screen.dart'; 
import 'moderator_profile_screen.dart';
import 'package:go_router/go_router.dart';
import 'partner_profile_screen.dart'; 
import 'creator_profile_screen.dart'; // IMPORT CREATOR

class PrivateProfileScreen extends StatefulWidget {
  const PrivateProfileScreen({super.key});

  @override
  State<PrivateProfileScreen> createState() => _PrivateProfileScreenState();
}

class _PrivateProfileScreenState extends State<PrivateProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = true;
  bool _isAuthenticated = false;
  Map<String, dynamic>? _profileData;
  
  String _activeTab = 'saves'; // saves | history

  // Form Edit
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    setState(() => _isLoading = true);
    
    // Sử dụng hàm chuẩn hóa để quét đúng key 'ai_health_token'
    final token = await SecureStorageService.getToken();
    
    if (token == null || token.isEmpty) {
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    } else {
      setState(() => _isAuthenticated = true);
      final data = await UserApiService.fetchPrivateProfile();
      setState(() {
        _profileData = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    // Sử dụng hàm dọn dẹp tổng thể thay vì xóa tay từng key
    await SecureStorageService.clearSession();
    
    setState(() {
      _isAuthenticated = false;
      _profileData = null;
    });
  }

  // --- LOGIC TẢI ẢNH AVATAR (ĐÃ FIX LỖI UPLOAD MEDIA) ---
  Future<void> _pickAndUploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tải ảnh lên...')));

    // VÁ LỖ HỔNG: Sử dụng uploadMedia và truyền đúng thư mục
    final url = await UserApiService.uploadMedia(File(image.path), 'users/avatars');
    if (url != null) {
      final success = await UserApiService.updateProfile({'avatar_url': url});
      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật ảnh thành công!'), backgroundColor: Color(0xFF80BF84)));
        _checkAuthAndLoad();
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi tải ảnh'), backgroundColor: Colors.red));
    }
  }

  // --- MODAL CHỈNH SỬA THÔNG TIN ---
  void _showEditModal() {
    _nameController.text = _profileData?['profile']['full_name'] ?? '';
    _bioController.text = _profileData?['profile']['bio'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Chỉnh sửa hồ sơ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(labelText: 'Tên hiển thị', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 16),
                
                TextField(
                  controller: _bioController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(labelText: 'Tiểu sử (Bio)', labelStyle: const TextStyle(color: Colors.white54), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 24),
                
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: _isUpdating ? null : () async {
                      setModalState(() => _isUpdating = true);
                      final success = await UserApiService.updateProfile({
                        'full_name': _nameController.text.trim(),
                        'bio': _bioController.text.trim(),
                      });
                      setModalState(() => _isUpdating = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _checkAuthAndLoad();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã lưu thay đổi'), backgroundColor: Color(0xFF80BF84)));
                      }
                    },
                    child: _isUpdating ? const CircularProgressIndicator(color: Colors.black) : const Text('Lưu thay đổi', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))));
    if (!_isAuthenticated) return Scaffold(backgroundColor: const Color(0xFF09090b), body: GuestProfileView(onSuccess: _checkAuthAndLoad));

    // Cầu dao rẽ nhánh giao diện (Routing)
    final role = _profileData?['profile']?['role'] ?? 'USER';
    if (role == 'SUPER_ADMIN') {
      return SuperAdminProfileScreen(
        profile: _profileData?['profile'] ?? {}, 
        onLogout: _handleLogout, 
        onRefresh: _checkAuthAndLoad
      );
    }
    if (role == 'MODERATOR') {
      return ModeratorProfileScreen(
        profile: _profileData?['profile'] ?? {}, 
        onLogout: _handleLogout, 
        onRefresh: _checkAuthAndLoad
      );
    }
    if (role == 'PARTNER' || role == 'PARTNER_ADMIN') {
      return PartnerProfileScreen(
        profile: _profileData?['profile'] ?? {}, 
        onLogout: _handleLogout, 
        onRefresh: _checkAuthAndLoad
      );
    }
    if (role == 'CREATOR') {
      return CreatorProfileScreen(
        profile: _profileData?['profile'] ?? {}, 
        onLogout: _handleLogout, 
        onRefresh: _checkAuthAndLoad
      );
    }

    // Giao diện người dùng tiêu chuẩn
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: _buildPrivateProfile(),
    );
  }

  Widget _buildPrivateProfile() {
    final profile = _profileData?['profile'] ?? {};
    final stats = _profileData?['stats'] ?? {};
    final avatarUrl = profile['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${profile['full_name'] ?? 'NU'}&background=80BF84&color=fff';

    return CustomScrollView(
      slivers: [
        // App Bar Cấu hình (Logout)
        SliverAppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(icon: const Icon(Icons.settings_outlined, color: Colors.white), onPressed: () {}),
            IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent), onPressed: _handleLogout),
          ],
        ),

        // Khối Thông tin cá nhân
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Avatar kèm nút Chụp ảnh đè lên
                GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white24, width: 2), image: DecorationImage(image: NetworkImage(avatarUrl), fit: BoxFit.cover)),
                      ),
                      Container(
                        width: 120, height: 120,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withOpacity(0.3)),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 32),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Tên & Username
                Text(profile['full_name'] ?? 'Chưa có tên', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                Text('@${profile['username'] ?? 'username'}', style: const TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 24),

                // Dàn Nút Tương tác
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                      onPressed: () => context.push('/public-profile/${profile['username']}'), 
                      icon: const Icon(Icons.visibility, size: 18), 
                      label: const Text('Xem công khai', style: TextStyle(fontWeight: FontWeight.bold))
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.1), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                      onPressed: _showEditModal, 
                      icon: const Icon(Icons.edit, size: 18), 
                      label: const Text('Chỉnh sửa', style: TextStyle(fontWeight: FontWeight.bold))
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Thống kê (Dữ liệu trả về từ API)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatCol(stats['likes_count']?.toString() ?? '0', 'Đã thích'),
                    _buildStatCol(stats['saved_count']?.toString() ?? '0', 'Đang lưu'),
                    _buildStatCol(stats['bookings_count']?.toString() ?? '0', 'Lịch hẹn'),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Bio
                Text(profile['bio'] ?? 'Người dùng này chưa cập nhật tiểu sử.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),

        // Tabs Section
        SliverToBoxAdapter(
          child: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildTabBtn('DỊCH VỤ ĐÃ LƯU', Icons.bookmark, 'saves'),
                _buildTabBtn('LỊCH SỬ KHÁM', Icons.history, 'history'),
              ],
            ),
          ),
        ),

        // Nội dung rỗng (Do Backend chưa trả mảng dữ liệu thật cho 2 list này ở endpoint /user/profile)
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 40, bottom: 120),
            child: Column(
              children: [
                Icon(_activeTab == 'saves' ? Icons.grid_view : Icons.event_busy, size: 48, color: Colors.white24),
                const SizedBox(height: 16),
                Text(_activeTab == 'saves' ? 'Chưa lưu dịch vụ nào' : 'Chưa có lịch sử khám', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        )
      ],
    );
  }

  Widget _buildStatCol(String val, String label) {
    return Column(
      children: [
        Text(val, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: isActive ? const Color(0xFF80BF84) : Colors.transparent, width: 2))),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? const Color(0xFF80BF84) : Colors.white54),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: isActive ? const Color(0xFF80BF84) : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}