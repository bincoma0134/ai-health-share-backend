import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../../../data/services/admin_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/app_toast.dart';

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
                          InteractiveViewer(child: GlobalCacheImage(imageUrl: imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity, memCacheWidth: 1200)),
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
      AppToast.show(context: context, message: 'Đang tải ${type == 'avatar' ? 'Ảnh đại diện' : 'Ảnh bìa'} lên...', isSuccess: true);
      String folder = type == 'avatar' ? 'users/avatars' : 'users/covers';
      final url = await UserApiService.uploadMedia(File(image.path), folder);
      
      if (url != null) {
        await UserApiService.updateProfile({type == 'avatar' ? 'avatar_url' : 'cover_url': url});
        widget.onRefresh();
        if (mounted) AppToast.show(context: context, message: 'Cập nhật ảnh thành công!', isSuccess: true);
      } else {
        if (mounted) AppToast.show(context: context, message: 'Lỗi tải ảnh!', isSuccess: false);
      }
    }
  }

  // --- LOGIC LƯU THÔNG TIN ---
  Future<void> _handleUpdateProfile() async {
    setState(() => _isUpdating = true);
    final success = await UserApiService.updateProfile({
      'username': _usernameController.text.trim(),
      'full_name': _nameController.text.trim(),
      'bio': _bioController.text.trim(),
    });
    setState(() => _isUpdating = false);
    
    if (success && mounted) {
      widget.onRefresh();
      AppToast.show(context: context, message: 'Đã cập nhật hồ sơ kiểm duyệt!', isSuccess: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FBF9),
        body: ShimmerWrapper(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                Container(height: 220, color: const Color(0xFFE2ECEB)),
                const SizedBox(height: 16),
                Container(
                  height: 116, width: 116,
                  decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle),
                ),
                const SizedBox(height: 20),
                Container(height: 24, width: 160, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 8),
                Container(height: 14, width: 90, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(2, (index) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 52,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      ),
                    )),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(2, (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 32, width: 120,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    )),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final String? rawCover = widget.profile['cover_url'];
    final bool hasCover = rawCover != null && rawCover.trim().isNotEmpty;
    final String? rawAvatar = widget.profile['avatar_url'];
    final bool hasAvatar = rawAvatar != null && rawAvatar.trim().isNotEmpty;
    final String avatarUrl = hasAvatar ? rawAvatar : 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=8B5CF6&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3E8FF),
              Color(0xFFF7FBF9),
            ],
            stops: [0.0, 0.45],
          ),
        ),
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              pinned: true,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20),
                onPressed: () => context.pop(),
                splashRadius: 20,
              ),
              title: const Text('Hồ sơ Kiểm duyệt', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: _modPrimary, size: 24),
                  onPressed: _showEditModal,
                  splashRadius: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22), 
                  onPressed: widget.onLogout,
                  splashRadius: 20,
                ),
                const SizedBox(width: 8),
              ],
            ),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  SizedBox(
                    height: 212,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: _modPrimary.withOpacity(0.1),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFF3E8FF).withOpacity(0.5),
                                  const Color(0xFFF7FBF9),
                                ],
                                stops: const [0.3, 0.8, 1.0],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 16,
                          right: 16,
                          child: GestureDetector(
                            onTap: () => _showImageOptions(hasCover ? rawCover : null, 'cover'),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: Icon(Icons.add_photo_alternate_rounded, size: 18, color: _modPrimary),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 84,
                          child: Stack(
                            alignment: Alignment.bottomCenter,
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 116, height: 116,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 4),
                                  boxShadow: [BoxShadow(color: _modPrimary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
                                  image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                bottom: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [_modSecondary, _modPrimary]),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: _modPrimary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.shield, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('MODERATOR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 2, bottom: 4,
                                child: GestureDetector(
                                  onTap: () => _showImageOptions(hasAvatar ? rawAvatar : null, 'avatar'),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
                                    child: Icon(Icons.camera_alt_rounded, size: 13, color: _modSecondary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(widget.profile['full_name'] ?? 'Kiểm duyệt viên', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                            const SizedBox(width: 6),
                            Icon(Icons.verified_user_rounded, color: _modPrimary, size: 18),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@${widget.profile['username'] ?? 'username'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMiniStatCard(
                              value: widget.profile['followers_count']?.toString() ?? '0',
                              label: 'Người quan tâm',
                              icon: Icons.people_alt_rounded,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: _stats['total_processed'].toString(),
                              label: 'Tổng đã xử lý',
                              icon: Icons.assignment_turned_in_rounded,
                              iconColor: _modSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.profile['bio'] ?? "Thành viên Ban quản trị nội dung. Đóng góp duy trì một môi trường nền tảng an toàn, minh bạch.",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 24),

                        // --- HUB: BỘ CÔNG CỤ KIỂM DUYỆT NHANH ---
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () => AppToast.show(context: context, message: 'Đang mở tra cứu Lịch sử hoạt động...', isSuccess: true),
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: const BoxDecoration(color: Color(0xFFF3E8FF), shape: BoxShape.circle),
                                        child: Icon(Icons.history_rounded, size: 20, color: _modPrimary),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Nhật ký hoạt động', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                                            SizedBox(height: 2),
                                            Text('Tra cứu lịch sử quyết định kiểm duyệt', style: TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0C4C1), size: 18),
                                    ],
                                  ),
                                ),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFF2F4F3))),
                              InkWell(
                                onTap: () => AppToast.show(context: context, message: 'Đang tải bộ Tiêu chuẩn cộng đồng...', isSuccess: true),
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: const BoxDecoration(color: Color(0xFFFDF4FF), shape: BoxShape.circle),
                                        child: Icon(Icons.policy_rounded, size: 20, color: _modSecondary),
                                      ),
                                      const SizedBox(width: 14),
                                      const Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Tiêu chuẩn nền tảng', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                                            SizedBox(height: 2),
                                            Text('Cẩm nang quy tắc và định mức vi phạm', style: TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500)),
                                          ],
                                        ),
                                      ),
                                      const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0C4C1), size: 18),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // --- MAIN DASHBOARD BUTTON ---
                        InkWell(
                          onTap: () => context.push('/moderator-dashboard'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _modPrimary.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.admin_panel_settings_rounded, color: _modSecondary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Trung tâm Quản trị & Kiểm duyệt',
                                  style: TextStyle(color: _modSecondary, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      _buildTabMenuButton(title: 'Bảng điều khiển', tabKey: 'overview'),
                      const SizedBox(width: 6),
                      _buildTabMenuButton(title: 'Hồ sơ cá nhân', tabKey: 'info'),
                    ],
                  ),
                ),
              ),
            ),

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
      ),
    );
  }

  Widget _buildOverviewTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDashboardCard(
          title: 'Hàng đợi chờ duyệt',
          value: _stats['pending_total'].toString(),
          subtitle: 'Mục chờ xử lý hệ thống',
          icon: Icons.hourglass_empty_rounded,
          color: Colors.amber.shade700,
          onTap: () => context.push('/moderator-dashboard'),
        ),
        const SizedBox(height: 12),
        _buildDashboardCard(
          title: 'Hiệu suất cá nhân',
          value: _stats['approved_count'].toString(),
          subtitle: 'Mục đã xử lý an toàn',
          icon: Icons.check_circle_rounded,
          color: const Color(0xFF48C9B0),
        ),
      ],
    );
  }

  Widget _buildDashboardCard({required String title, required String value, required String subtitle, required IconData icon, required Color color, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE2ECEB), width: 0.8),
          boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 6),
                      Text(subtitle, style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFB0C4C1), size: 14),
          ],
        ),
      ),
    );
  }

  void _showEditModal() {
    _nameController.text = widget.profile['full_name'] ?? '';
    _usernameController.text = widget.profile['username'] ?? '';
    _bioController.text = widget.profile['bio'] ?? '';

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
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 12, bottom: 4),
                    width: 40, height: 5,
                    decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(top: 12, left: 24, right: 16, bottom: 20),
                  decoration: const BoxDecoration(color: Color(0xFFF2F2F7)),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                        child: Icon(Icons.shield_outlined, color: _modPrimary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hồ sơ Kiểm duyệt', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu thông tin quản trị', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSaaSInputField(controller: _nameController, label: 'Bí danh kiểm duyệt'),
                        const SizedBox(height: 24),
                        _buildSaaSInputField(controller: _usernameController, label: 'Username định danh'),
                        const SizedBox(height: 24),
                        _buildSaaSLockedField(label: 'Email xác thực', value: widget.profile['email'] ?? '', badgeText: 'Bảo mật'),
                        const SizedBox(height: 24),
                        _buildSaaSInputField(controller: _bioController, label: 'Giới thiệu chuyên môn', maxLines: 3),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 32),
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Hủy bỏ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1C1C1E), foregroundColor: Colors.white, elevation: 0),
                        onPressed: _isUpdating ? null : () async {
                          Navigator.pop(context);
                          _handleUpdateProfile();
                        },
                        child: const Text('Lưu thay đổi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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

  Widget _buildInfoTab() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECEB), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thông tin ban quản trị', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _buildSaaSFieldDisabled(label: 'Username định danh', value: widget.profile['username'] ?? 'Chưa thiết lập', icon: Icons.alternate_email_rounded),
          _buildSaaSFieldDisabled(label: 'Bí danh kiểm duyệt', value: widget.profile['full_name'] ?? 'Chưa thiết lập', icon: Icons.badge_rounded),
          _buildSaaSFieldDisabled(label: 'Email bảo mật', value: widget.profile['email'] ?? 'Chưa liên kết email', icon: Icons.mail_lock_rounded),
          _buildSaaSFieldDisabled(label: 'Giới thiệu chuyên môn', value: widget.profile['bio'] ?? 'Chưa cập nhật dữ liệu', icon: Icons.workspace_premium_rounded),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF3E8FF),
                foregroundColor: _modPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: _modPrimary.withOpacity(0.3), width: 1),
              ),
              onPressed: _showEditModal,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Chỉnh sửa thông tin hồ sơ', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaaSInputField({required TextEditingController controller, required String label, int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E5EA))),
          child: TextField(
            controller: controller, maxLines: maxLines, keyboardType: keyboardType,
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.all(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildSaaSLockedField({required String label, required String value, required String badgeText}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: InkWell(
        onTap: () {
          AppToast.show(
            context: context,
            message: 'Trường thông tin xác thực mật định đã được hệ thống mã hóa bảo vệ an toàn.',
            isSuccess: false,
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: Color(0xFF94A3B8), size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text(
                      value.isEmpty ? 'Chưa cập nhật dữ liệu' : value,
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                ),
                child: Text(badgeText, style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSaaSFieldDisabled({required String label, required String value, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: _modPrimary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _modSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatCard({required String value, required String label, required IconData icon, Color? iconColor}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2ECEB), width: 0.8),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: iconColor ?? const Color(0xFF617D79)),
                const SizedBox(width: 4),
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -0.3)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabMenuButton({required String title, required String tabKey}) {
    final bool isSelected = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1A3A35) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFFB0C4C1),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

}