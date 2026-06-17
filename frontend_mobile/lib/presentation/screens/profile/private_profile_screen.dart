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
import '../../widgets/auth_guard.dart';
import '../../widgets/glass_wrapper.dart';
import '../../widgets/app_toast.dart';
import '../../../core/network/global_cache_engine.dart';

class PrivateProfileScreen extends StatefulWidget {
  const PrivateProfileScreen({super.key});

  @override
  State<PrivateProfileScreen> createState() => _PrivateProfileScreenState();
}

class _PrivateProfileScreenState extends State<PrivateProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  List<dynamic> _savedItems = []; // Lưu trữ danh sách mục đã lưu
  
  String _activeTab = 'saves'; // saves | history

  // Form Edit
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    // Gọi API song song để tăng tốc độ tải
    final results = await Future.wait([
      UserApiService.fetchPrivateProfile(),
      UserApiService.fetchSavedItems(),
    ]);
    
    if (!mounted) return;
    setState(() {
      _profileData = results[0] as Map<String, dynamic>?;
      _savedItems = results[1] as List<dynamic>? ?? [];
      _isLoading = false;
    });
  }

  Future<void> _handleLogout() async {
    // Giao quyền dọn dẹp cho AuthNotifier để kích hoạt luồng đăng xuất toàn cục
    await AuthNotifier.instance.logout();
    
    setState(() {
      _profileData = null;
    });
  }

  // --- LOGIC TẢI ẢNH AVATAR (ĐÃ FIX LỖI UPLOAD MEDIA) ---
  Future<void> _pickAndUploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang xử lý ảnh đại diện...', isSuccess: true, duration: const Duration(seconds: 2));

    // VÁ LỖ HỔNG: Sử dụng uploadMedia và truyền đúng thư mục
    final url = await UserApiService.uploadMedia(File(image.path), 'users/avatars');
    if (url != null) {
      final success = await UserApiService.updateProfile({'avatar_url': url});
      if (success && mounted) {
        AppToast.show(context: context, message: 'Cập nhật ảnh đại diện thành công!', isSuccess: true);
        _loadData();
      } else if (mounted) {
        AppToast.show(context: context, message: 'Lỗi cập nhật hồ sơ!', isSuccess: false);
      }
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi tải ảnh lên máy chủ!', isSuccess: false);
    }
  }

  // --- LOGIC TẢI ẢNH BÌA ---
  Future<void> _pickAndUploadCover() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang xử lý ảnh bìa...', isSuccess: true, duration: const Duration(seconds: 2));

    final url = await UserApiService.uploadMedia(File(image.path), 'users/covers');
    if (url != null) {
      final success = await UserApiService.updateProfile({'cover_url': url});
      if (success && mounted) {
        AppToast.show(context: context, message: 'Cập nhật ảnh bìa thành công!', isSuccess: true);
        _loadData();
      } else if (mounted) {
        AppToast.show(context: context, message: 'Lỗi cập nhật hồ sơ!', isSuccess: false);
      }
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi tải ảnh lên máy chủ!', isSuccess: false);
    }
  }

  // --- MODAL CHỈNH SỬA THÔNG TIN ---
  void _showEditModal() {
    final profile = _profileData?['profile'] ?? {};
    _nameController.text = profile['full_name'] ?? '';
    _usernameController.text = profile['username'] ?? '';
    _bioController.text = profile['bio'] ?? '';
    _phoneController.text = profile['phone'] ?? '';
    _emailController.text = profile['email'] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.88, 
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(color: Color(0xFFF2F2F7), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // DRAG HANDLE (Pill indicator)
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40, 
                    height: 5, 
                    decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)),
                  ),
                ),

                // HEADER LAYER
                Container(
                  padding: const EdgeInsets.only(top: 12, left: 24, right: 16, bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.person_outline_rounded, color: Color(0xFF1C1C1E), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Hồ sơ cá nhân', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu hệ thống', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFFE5E5EA), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93), size: 18),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // SCROLLABLE FORM (Loại bỏ lưới 2 cột, trả về 1 cột dọc rộng rãi)
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSaaSField(controller: _nameController, label: 'Tên hiển thị'),
                        const SizedBox(height: 24),

                        _buildSaaSField(controller: _usernameController, label: 'Tên đăng nhập'),
                        const SizedBox(height: 24),

                        _buildSaaSField(controller: _phoneController, label: 'Số điện thoại', keyboardType: TextInputType.phone),
                        const SizedBox(height: 24),

                        _buildSaaSLockedField(label: 'Email xác thực', value: _emailController.text, badgeText: 'Bảo mật'),
                        const SizedBox(height: 24),

                        _buildSaaSField(controller: _bioController, label: 'Tiểu sử / Giới thiệu', maxLines: 3),
                      ],
                    ),
                  ),
                ),

                // STICKY BOTTOM ACTION LAYER
                Container(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -4))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF2F2F7),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Hủy bỏ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isUpdating ? null : () async {
                          final name = _nameController.text.trim();
                          final uname = _usernameController.text.trim();
                          final phone = _phoneController.text.trim();

                          if (name.isEmpty || uname.isEmpty || phone.isEmpty) {
                            AppToast.show(context: context, message: 'Tên, Username và SĐT không được để trống!', isSuccess: false);
                            return;
                          }

                          setModalState(() => _isUpdating = true);
                          
                          final success = await UserApiService.updateProfile({
                            'full_name': name,
                            'username': uname,
                            'bio': _bioController.text.trim(),
                            'phone': phone,
                          });
                          
                          if (success && mounted) {
                            Navigator.pop(context);
                            _loadData();
                            AppToast.show(context: context, message: 'Đã lưu thay đổi hồ sơ', isSuccess: true);
                          } else if (mounted) {
                            setModalState(() => _isUpdating = false);
                            AppToast.show(context: context, message: 'Cập nhật thất bại. Username có thể đã tồn tại!', isSuccess: false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          disabledBackgroundColor: const Color(0xFFD1D1D6),
                        ),
                        child: _isUpdating 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Text('Lưu thay đổi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSaaSField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          // Bỏ Uppercase, dùng chữ thường mềm mại, font size 14
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12), // Giảm bo góc
            border: Border.all(color: const Color(0xFFE5E5EA), width: 1), // Thêm viền mỏng thanh lịch
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))], // Bóng siêu mờ
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textAlign: TextAlign.left,
            style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 16, fontWeight: FontWeight.w400), // Nét chữ mỏng hơn một chút
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16), // Padding rộng rãi
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSaaSLockedField({required String label, required String value, required String badgeText}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        InkWell(
          onTap: () {
            AppToast.show(context: context, message: 'Trường dữ liệu này đã được hệ thống bảo vệ.', isSuccess: false);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7), // Nền xám nhạt thay vì quá nổi
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? 'Trống' : value,
                    textAlign: TextAlign.left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w400),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                  ),
                  child: Text(badgeText, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => Scaffold(backgroundColor: const Color(0xFFF7FBF9), body: GuestProfileView(onSuccess: () async { await AuthNotifier.instance.refresh(); _loadData(); })),
      builder: (context, token, userId) {
        if (_isLoading) return const Scaffold(backgroundColor: Color(0xFFF7FBF9), body: Center(child: CircularProgressIndicator(color: Color(0xFF48C9B0))));

        // Cầu dao rẽ nhánh giao diện (Routing)
        final role = _profileData?['profile']?['role'] ?? 'USER';
        if (role == 'SUPER_ADMIN') {
          return SuperAdminProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'MODERATOR') {
          return ModeratorProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'PARTNER' || role == 'PARTNER_ADMIN') {
          return PartnerProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'CREATOR') {
          return CreatorProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }

        // Giao diện người dùng tiêu chuẩn
        return Scaffold(
          backgroundColor: const Color(0xFFF7FBF9),
          body: _buildPrivateProfile(),
        );
      },
    );
  }

  Widget _buildPrivateProfile() {
    final profile = _profileData?['profile'] ?? {};
    final stats = _profileData?['stats'] ?? {};
    final avatarUrl = profile['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${profile['full_name'] ?? 'NU'}&background=80BF84&color=fff';
    final role = profile['role'] ?? 'USER';
    
    final String? rawCover = profile['cover_url'] != null && profile['cover_url'].toString().trim().isNotEmpty 
        ? '${profile['cover_url']}?w=800&q=70' 
        : null;
    final bool hasCover = rawCover != null;

    return CustomScrollView(
      slivers: [
        // App Bar Cấu hình (Logout) - Pinned & Clean (Apple Style)
        SliverAppBar(
          backgroundColor: const Color(0xFFF7FBF9),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20),
            onPressed: () {
              AppToast.show(
                context: context,
                message: 'Đây là màn hình gốc, không thể quay lại.',
                isSuccess: false,
              );
            },
            splashRadius: 20,
          ),
          title: const Text('Hồ sơ', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Color(0xFF1A3A35), size: 22), 
              onPressed: () {
                AppToast.show(
                  context: context,
                  message: 'Tính năng cài đặt đang được cập nhật!',
                  isSuccess: true,
                );
              },
              splashRadius: 20,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22), 
              onPressed: _handleLogout,
              splashRadius: 20,
            ),
            const SizedBox(width: 8),
          ],
        ),

        // Khối Ảnh bìa (Cover Image) & Avatar
        SliverToBoxAdapter(
          child: Column(
            children: [
              SizedBox(
                height: 192, // 140 (Cover) + 52 (Nửa dưới Avatar)
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // Lớp ảnh bìa + Gradient Fade (Apple Style)
                    Stack(
                      children: [
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFF7FBF9).withOpacity(0.5),
                                  const Color(0xFFF7FBF9), // Tệp tiệp vào màu nền hệ thống
                                ],
                                stops: const [0.3, 0.8, 1.0],
                              ),
                            ),
                          ),
                        ),
                        // Nút thay đổi ảnh bìa nổi ở góc phải trên
                        Positioned(
                          top: 16,
                          right: 16,
                          child: GestureDetector(
                            onTap: _pickAndUploadCover,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                              ),
                              child: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Color(0xFF1A3A35)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Avatar lơ lửng đè lên viền dưới của ảnh bìa (Nằm hoàn toàn trong bounds 192)
                    Positioned(
                      top: 88, // Bắt đầu ở điểm 140 - 52
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 104, height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.8), blurRadius: 24, offset: const Offset(0, 8))],
                              image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                            ),
                          ),
                          GestureDetector(
                            onTap: _pickAndUploadAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFF7FBF9), width: 2),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                              ),
                              child: const Icon(Icons.edit_rounded, size: 14, color: Color(0xFF48C9B0)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12), // Rút gọn vì 192px đã bao trọn Avatar
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Tên người dùng & Username
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(profile['full_name'] ?? 'Chưa có tên', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                        if (profile['full_name'] == null || profile['full_name'].toString().trim().isEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFFFFEBEE), shape: BoxShape.circle),
                            child: const Icon(Icons.priority_high_rounded, size: 14, color: Colors.redAccent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('@${profile['username'] ?? 'username'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500)),
                        if (profile['username'] == null || profile['username'].toString().trim().isEmpty)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: Color(0xFFFFEBEE), shape: BoxShape.circle),
                            child: const Icon(Icons.priority_high_rounded, size: 10, color: Colors.redAccent),
                          ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // KHỐI 1: Thông tin căn bản / Liên hệ
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, 
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          _buildInfoTile(Icons.info_outline_rounded, 'Tiểu sử', profile['bio'] ?? 'Chưa cập nhật', onTap: _showEditModal, isMissing: (profile['bio'] == null || profile['bio'].toString().trim().isEmpty)),
                          _buildInfoTile(Icons.shield_outlined, 'Vai trò', role == 'USER' ? 'Người dùng tiêu chuẩn' : role, onTap: null),
                          _buildInfoTile(Icons.phone_outlined, 'Điện thoại', profile['phone'] ?? 'Chưa cập nhật', onTap: _showEditModal, isMissing: (profile['phone'] == null || profile['phone'].toString().trim().isEmpty)),
                          _buildInfoTile(Icons.email_outlined, 'Email', profile['email'] ?? 'Chưa cập nhật', onTap: _showEditModal, isMissing: (profile['email'] == null || profile['email'].toString().trim().isEmpty)),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                const SizedBox(height: 32),

                // Tiêu đề Thống kê
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('TƯƠNG TÁC', style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ),
                const SizedBox(height: 16),

                // KHỐI 2: Thống kê (3 Thẻ ngang độc lập kết hợp luồng xử lý tương tác chuẩn công thái học)
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          // Luồng 1: Hiện Toast thông báo rồi delay 600ms để người dùng kịp đọc trước khi chuyển trang
                          AppToast.show(context: context, message: 'Đang áp dụng bộ lọc Video đã thích...', isSuccess: true);
                          await Future.delayed(const Duration(milliseconds: 600));
                          if (mounted) context.go('/?filter=liked');
                        },
                        borderRadius: BorderRadius.circular(28),
                        child: _buildSquareStatCard(Icons.favorite_rounded, stats['likes_count']?.toString() ?? '0', 'Đã thích'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          // Luồng 2: Kích hoạt tab đã lưu nội tại và cuộn xem tại chỗ
                          setState(() {
                            _activeTab = 'saves';
                          });
                          AppToast.show(context: context, message: 'Đã chuyển đến mục Dịch vụ đã lưu', isSuccess: true);
                        },
                        borderRadius: BorderRadius.circular(28),
                        child: _buildSquareStatCard(Icons.bookmark_rounded, stats['saved_count']?.toString() ?? '0', 'Đang lưu'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          // Luồng 3: Điều hướng tập trung sang phân hệ lịch trình của ứng dụng thông qua GoRouter
                          context.go('/calendar');
                        },
                        borderRadius: BorderRadius.circular(28),
                        child: _buildSquareStatCard(Icons.calendar_today_rounded, stats['bookings_count']?.toString() ?? '0', 'Lịch hẹn'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Tiêu đề Quản lý & Tab
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _activeTab = 'saves'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeTab == 'saves' ? const Color(0xFF1A3A35) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Đã lưu', style: TextStyle(color: _activeTab == 'saves' ? Colors.white : const Color(0xFFB0C4C1), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _activeTab = 'history'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _activeTab == 'history' ? const Color(0xFF1A3A35) : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('Lịch sử khám', style: TextStyle(color: _activeTab == 'history' ? Colors.white : const Color(0xFFB0C4C1), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // KHỐI 3: Hiển thị nội dung động theo Tab
                if (_activeTab == 'saves')
                  _savedItems.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))]),
                        child: const Column(
                          children: [
                            Icon(Icons.bookmark_border_rounded, size: 48, color: Color(0xFFE2ECEB)),
                            SizedBox(height: 12),
                            Text('Chưa lưu nội dung nào', style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14)),
                          ],
                        ),
                      )
                    : Column(
                        children: _savedItems.map((item) => _buildSavedItemCard(item)).toList(),
                      )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))]),
                    child: const Column(
                      children: [
                        Icon(Icons.history_rounded, size: 48, color: Color(0xFFE2ECEB)),
                        SizedBox(height: 12),
                        Text('Lịch sử khám đang trống', style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14)),
                      ],
                    ),
                  ),
                
                // NÚT CTA CHÍNH: Vùng đệm 130px an toàn tránh bị che bởi Liquid Glass Bottom Nav
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 40, bottom: 130),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE8F5E9),
                      foregroundColor: const Color(0xFF1A3A35),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                    ),
                    onPressed: () => context.push('/public-profile/${profile['username']}'),
                    child: const Text('Xem Hồ Sơ Công Khai', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ],
    );
  }

  // --- WIDGET HELPER MỚI CHO GIAO DIỆN APPLE-INSPIRED ---

  Widget _buildInfoTile(IconData icon, String label, String value, {VoidCallback? onTap, bool isMissing = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      highlightColor: const Color(0xFFE8F5E9).withOpacity(0.5),
      splashColor: const Color(0xFFE8F5E9).withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: const Color(0xFF48C9B0)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFFB0C4C1), fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (isMissing)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Color(0xFFFFEBEE), shape: BoxShape.circle),
                child: const Icon(Icons.priority_high_rounded, size: 14, color: Colors.redAccent),
              ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFFB0C4C1)),
          ],
        ),
      ),
    );
  }

  Widget _buildSquareStatCard(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: const Color(0xFF48C9B0)),
          ),
          const SizedBox(height: 16),
          Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildActionTile(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(32),
      highlightColor: const Color(0xFFE8F5E9).withOpacity(0.5),
      splashColor: const Color(0xFFE8F5E9).withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Color(0xFFF7FBF9), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: Color(0xFF1A3A35)),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2))),
            const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFFB0C4C1)),
          ],
        ),
      ),
    );
  }

  // Giao diện thẻ Card cho từng mục đã lưu (Phong cách bo góc hiện đại)
  Widget _buildSavedItemCard(Map<String, dynamic> item) {
    final author = item['author'] ?? {};
    final String title = item['title'] ?? 'Nội dung';
    final String authorName = author['full_name'] ?? author['username'] ?? 'Tác giả';
    final String avatarUrl = author['avatar_url'] ?? 'https://ui-avatars.com/api/?name=$authorName&background=80BF84&color=fff';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            // Khi bấm vào có thể chuyển tiếp hoặc mở preview (Tuỳ thiết kế mở rộng sau này)
            AppToast.show(context: context, message: 'Tính năng xem chi tiết đang phát triển', isSuccess: true);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Icon loại nội dung (Tạm thời là Video)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBF9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                  ),
                  child: const Center(child: Icon(Icons.play_circle_filled_rounded, color: Color(0xFF48C9B0), size: 24)),
                ),
                const SizedBox(width: 16),
                // Thông tin
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w700), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          CircleAvatar(radius: 8, backgroundImage: GlobalCacheProvider.create(avatarUrl, maxWidth: 100, maxHeight: 100)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(authorName, style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFB0C4C1), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}