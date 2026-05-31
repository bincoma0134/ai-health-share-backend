import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../data/services/admin_api_service.dart';
import '../../../data/services/user_api_service.dart';

class ModeratorProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;

  const ModeratorProfileScreen({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  State<ModeratorProfileScreen> createState() => _ModeratorProfileScreenState();
}

class _ModeratorProfileScreenState extends State<ModeratorProfileScreen> {
  String _activeTab = 'overview'; // overview | info
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'pending_total': 0, 'approved_count': 0, 'total_processed': 0};
  
  // Form Edit
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isUpdating = false;

  final ImagePicker _picker = ImagePicker();

  // Bảng màu chuẩn Moderator (Violet/Fuchsia)
  final Color _modPrimary = const Color(0xFF8B5CF6); // Violet-500
  final Color _modSecondary = const Color(0xFFD946EF); // Fuchsia-500

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile['full_name'] ?? '';
    _bioController.text = widget.profile['bio'] ?? '';
    _usernameController.text = widget.profile['username'] ?? '';
    _loadModeratorData();
  }

  Future<void> _loadModeratorData() async {
    setState(() => _isLoading = true);
    final statsData = await AdminApiService.fetchModerationStats();
    if (mounted) {
      setState(() {
        if (statsData != null) _stats = statsData;
        _isLoading = false;
      });
    }
  }

  // --- LOGIC ẢNH (XEM/ĐỔI) ---
  void _showImageOptions(String? imageUrl, String type) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.fullscreen, color: Colors.white),
                title: const Text('Xem ảnh phóng to', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(
                    context: context, 
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent, 
                      insetPadding: EdgeInsets.zero,
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity)),
                          Padding(padding: const EdgeInsets.all(16.0), child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.pop(context))),
                        ],
                      )
                    )
                  );
                },
              ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: _modPrimary),
              title: Text('Đổi ảnh mới', style: TextStyle(color: _modPrimary, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _changeImage(type);
              },
            ),
          ],
        ),
      )
    );
  }

  Future<void> _changeImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang xử lý và tải ${type == 'avatar' ? 'Ảnh đại diện' : 'Ảnh bìa'} lên...')));
      String folder = type == 'avatar' ? 'users/avatars' : 'users/covers';
      final url = await UserApiService.uploadMedia(File(image.path), folder);
      
      if (url != null) {
        await UserApiService.updateProfile({type == 'avatar' ? 'avatar_url' : 'cover_url': url});
        widget.onRefresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật ảnh thành công!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi tải ảnh!'), backgroundColor: Colors.red));
      }
    }
  }

  // --- LOGIC LƯU THÔNG TIN ---
  Future<void> _handleUpdateProfile() async {
    setState(() => _isUpdating = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang lưu hồ sơ...')));
    final success = await UserApiService.updateProfile({
      'username': _usernameController.text.trim(),
      'full_name': _nameController.text.trim(),
      'bio': _bioController.text.trim(),
    });
    setState(() => _isUpdating = false);
    
    if (success && mounted) {
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Đã cập nhật hồ sơ kiểm duyệt!'), backgroundColor: _modPrimary));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: Color(0xFF8B5CF6))));

    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                // ==========================================
                // KHỐI COVER & AVATAR CHỐNG ĐÈ LAYER
                // ==========================================
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 1. Ảnh Bìa
                    GestureDetector(
                      onTap: () => _showImageOptions(widget.profile['cover_url'], 'cover'),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1B4B), // Nền tím đậm chờ load
                          image: widget.profile['cover_url'] != null ? DecorationImage(image: NetworkImage(widget.profile['cover_url']), fit: BoxFit.cover) : null,
                        ),
                        child: widget.profile['cover_url'] == null 
                          ? Center(child: Icon(Icons.shield, color: _modPrimary.withOpacity(0.3), size: 80))
                          : Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09090b).withOpacity(0.9)]))),
                      ),
                    ),
                    
                    // 2. Nút Hành động (Xem công khai, Đăng xuất)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.white, size: 20),
                              tooltip: 'Xem công khai',
                              onPressed: () => context.push('/public-profile/${widget.profile['username']}'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                              tooltip: 'Đăng xuất',
                              onPressed: widget.onLogout,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 3. Avatar nhô lên 50px

                    // 3. Avatar nhô lên 50px
                    Positioned(
                      bottom: -50,
                      child: GestureDetector(
                        onTap: () => _showImageOptions(widget.profile['avatar_url'], 'avatar'),
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 110, height: 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF09090b),
                                border: Border.all(color: Colors.white, width: 3),
                                image: DecorationImage(image: NetworkImage(widget.profile['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=8B5CF6&color=fff'), fit: BoxFit.cover)
                              ),
                            ),
                            // Huy hiệu Moderator
                            Positioned(
                              bottom: -10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [_modPrimary, _modSecondary]),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  boxShadow: [BoxShadow(color: _modPrimary.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))]
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.shield, color: Colors.white, size: 10),
                                    SizedBox(width: 4),
                                    Text('MODERATOR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                  ],
                                ),
                              ),
                            )
                          ],
                        ),
                      ),
                    )
                  ],
                ),
                
                const SizedBox(height: 70),

                // ==========================================
                // THÔNG TIN KIỂM DUYỆT VIÊN
                // ==========================================
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(widget.profile['full_name'] ?? 'Kiểm duyệt viên', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Icon(Icons.verified_user, color: _modPrimary, size: 24),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('@${widget.profile['username']}', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 24),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(widget.profile['followers_count']?.toString() ?? '0', 'Người quan tâm'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(_stats['total_processed'].toString(), 'Đã xử lý', isHighlight: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(widget.profile['bio'] ?? "Thành viên Ban quản trị nội dung. Đóng góp duy trì một môi trường nền tảng an toàn, minh bạch.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ==========================================
          // MENU TABS NGANG
          // ==========================================
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 32),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTabBtn('BẢNG ĐIỀU KHIỂN', Icons.dashboard, 'overview'),
                  _buildTabBtn('HỒ SƠ CÁ NHÂN', Icons.edit, 'info'),
                ],
              ),
            ),
          ),

          // ==========================================
          // NỘI DUNG THEO TAB
          // ==========================================
          SliverPadding(
            padding: const EdgeInsets.all(24).copyWith(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_activeTab == 'overview') _buildOverviewTab(),
                if (_activeTab == 'info') _buildInfoTab(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: BẢNG ĐIỀU KHIỂN ---
  Widget _buildOverviewTab() {
    return Column(
      children: [
        _buildDashboardCard(
          title: 'Hàng đợi chờ duyệt',
          value: _stats['pending_total'].toString(),
          subtitle: 'Mục chờ xử lý',
          icon: Icons.hourglass_empty,
          color: Colors.amber,
          onTap: () => context.push('/moderator-dashboard'), // BẬT CẦU DAO ĐIỀU HƯỚNG
        ),
        const SizedBox(height: 16),
        _buildDashboardCard(
          title: 'Hiệu suất cá nhân',
          value: _stats['approved_count'].toString(),
          subtitle: 'Mục đã xử lý an toàn',
          icon: Icons.check_circle,
          color: Colors.green,
        ),
      ],
    );
  }

  Widget _buildDashboardCard({required String title, required String value, required String subtitle, required IconData icon, required Color color, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 32)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(value, style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1)),
                      const SizedBox(width: 8),
                      Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12))),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }

  // --- TAB 2: CHỈNH SỬA HỒ SƠ ---
  Widget _buildInfoTab() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Username định danh', _usernameController, 'Tên hiển thị trên URL hồ sơ.'),
          const SizedBox(height: 20),
          _buildTextField('Bí danh kiểm duyệt', _nameController, 'Tên hiển thị công khai trên các quyết định của bạn.'),
          const SizedBox(height: 20),
          _buildTextField('Giới thiệu chuyên môn', _bioController, null, maxLines: 4),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _modPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _isUpdating ? null : _handleUpdateProfile,
              child: _isUpdating ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THÔNG TIN HỒ SƠ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String? hint, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: InputDecoration(filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
        ),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(hint, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]
      ],
    );
  }

  // --- WIDGET HỖ TRỢ ---
  Widget _buildStatCol(String val, String label, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(val, style: TextStyle(color: isHighlight ? _modPrimary : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? _modPrimary : Colors.transparent, width: 3))),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? _modPrimary : Colors.white54),
            const SizedBox(width: 8),
            Text(label.toUpperCase(), style: TextStyle(color: isActive ? _modPrimary : Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}