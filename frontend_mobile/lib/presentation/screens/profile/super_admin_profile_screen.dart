import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/admin_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/app_toast.dart';
import 'package:go_router/go_router.dart';

class SuperAdminProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;

  const SuperAdminProfileScreen({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  State<SuperAdminProfileScreen> createState() => _SuperAdminProfileScreenState();
}

class _SuperAdminProfileScreenState extends State<SuperAdminProfileScreen> {
  String _activeTab = 'activity'; 
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'followers_count': 0, 'active_services': 0, 'system_stability': 99.9};
  Map<String, dynamic> _dashboardStats = {'total_users': 0, 'total_partners': 0};

  // Form Edit
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _usernameController = TextEditingController();
  bool _isUpdating = false;

  List<dynamic> _systemLogs = [];
  bool _isLoadingLogs = true;

  // Cấu hình Toggle Tab Hệ Thống
  bool _is2FAEnabled = true;
  bool _isLoginAlertEnabled = true;

  final ImagePicker _picker = ImagePicker();
  
  final Color _admPrimary = const Color(0xFFF59E0B); 
  final Color _admSecondary = const Color(0xFF1C1C1E); 

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.profile['full_name'] ?? '';
    _bioController.text = widget.profile['bio'] ?? '';
    _usernameController.text = widget.profile['username'] ?? '';
    _loadAdminData();
    _loadSystemLogs();
  }

  Future<void> _loadAdminData() async {
    setState(() => _isLoading = true);
    
    // 1. Fetch Profile Stats Độc lập
    try {
      final statsRes = await AdminApiService.fetchStats();
      if (mounted && statsRes != null) setState(() => _stats = statsRes as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Lỗi fetchStats: $e');
    }
    
    // 2. Fetch Dashboard Stats Độc lập (Bảo vệ thông số User/Partner)
    try {
      final dashRes = await AdminApiService.fetchDashboardStats();
      if (mounted && dashRes != null) setState(() => _dashboardStats = dashRes as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Lỗi fetchDashboardStats: $e');
    }
    
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadSystemLogs() async {
    setState(() => _isLoadingLogs = true);
    try {
      // Gọi API thật: Lấy danh sách giao dịch Giải ngân làm Nhật ký hoạt động chung
      final withdrawals = await AdminApiService.fetchWithdrawals();
      
      if (mounted) {
        setState(() {
          if (withdrawals != null && withdrawals is List) {
            _systemLogs = withdrawals.take(15).map((w) {
              final status = w['status'] ?? 'PENDING';
              String type = 'warning';
              if (status == 'COMPLETED') type = 'success';
              if (status == 'REJECTED') type = 'error';
              
              // Xử lý an toàn các trường dữ liệu null
              final amountText = (w['amount'] ?? 0).toString();
              final name = w['users']?['full_name'] ?? 'Hệ thống';
              final timeStr = w['created_at']?.toString().substring(0, 10) ?? 'Gần đây';
              
              return {
                'status': type,
                'msg': 'Lệnh giải ngân $amountText VNĐ từ $name\nTrạng thái xử lý: $status',
                'time': timeStr,
              };
            }).toList();
          } else {
            _systemLogs = [];
          }
          _isLoadingLogs = false;
        });
      }
    } catch (e) {
      debugPrint('Lỗi fetchSystemLogs (Withdrawals): $e');
      if (mounted) setState(() => _isLoadingLogs = false);
    }
  }

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
      AppToast.show(context: context, message: 'Đã cập nhật hồ sơ quản trị!', isSuccess: true);
    }
  }

  // ==========================================
  // LOGIC 1: CLICK ẢNH BÌA HOẶC AVATAR (XEM / ĐỔI)
  // ==========================================
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
              leading: Icon(Icons.photo_camera, color: _admPrimary),
              title: Text('Đổi ảnh mới', style: TextStyle(color: _admPrimary, fontWeight: FontWeight.bold)),
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
        if (mounted) AppToast.show(context: context, message: 'Lỗi đường truyền, không thể tải ảnh!', isSuccess: false);
      }
    }
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
                        child: Icon(Icons.shield_outlined, color: _admPrimary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hồ sơ Quản trị', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu thông tin tối cao', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
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
                        _buildSaaSInputField(controller: _nameController, label: 'Tên hiển thị'),
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
                Container(height: 116, width: 116, decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle)),
                const SizedBox(height: 20),
                Container(height: 24, width: 160, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 8),
                Container(height: 14, width: 90, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 20),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(children: List.generate(3, (index) => Expanded(child: Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 52, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14))))))),
                const SizedBox(height: 24),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Row(children: List.generate(3, (index) => Container(margin: const EdgeInsets.symmetric(horizontal: 4), height: 32, width: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)))))),
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
    final String avatarUrl = hasAvatar ? rawAvatar : 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=F59E0B&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFFBEB),
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
              title: const Text('Hồ sơ Quản trị', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              actions: [
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
                            color: _admPrimary.withOpacity(0.15),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFFFFBEB).withOpacity(0.5),
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
                              child: Icon(Icons.add_photo_alternate_rounded, size: 18, color: _admPrimary),
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
                                  boxShadow: [BoxShadow(color: _admPrimary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
                                  image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                bottom: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [const Color(0xFFD97706), _admPrimary]),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: _admPrimary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('SUPER ADMIN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
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
                                    child: Icon(Icons.camera_alt_rounded, size: 13, color: _admPrimary),
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
                            Text(widget.profile['full_name'] ?? 'Super Admin', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, color: _admPrimary, size: 18),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@${widget.profile['username'] ?? 'admin'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 16),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMiniStatCard(
                              value: _dashboardStats['total_users']?.toString() ?? '0',
                              label: 'Người dùng',
                              icon: Icons.people_alt_rounded,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: _stats['active_services']?.toString() ?? '0',
                              label: 'Dịch vụ sàn',
                              icon: Icons.local_mall_rounded,
                              iconColor: const Color(0xFF48C9B0),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: _dashboardStats['total_partners']?.toString() ?? '0',
                              label: 'Đối tác',
                              icon: Icons.business_rounded,
                              iconColor: _admPrimary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 6))],
                          ),
                          child: Column(
                            children: [
                              _buildHubRowTile(
                                icon: Icons.shield_rounded,
                                iconColor: const Color(0xFF1A3A35),
                                iconBg: const Color(0xFFF0F7F4),
                                title: 'Cấu hình bảo mật (2FA)',
                                subtitle: 'Tường lửa & cảnh báo đăng nhập lạ',
                                value: '',
                                onTap: () => setState(() => _activeTab = 'settings'),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFF2F4F3))),
                              _buildHubRowTile(
                                icon: Icons.admin_panel_settings_rounded,
                                iconColor: _admSecondary,
                                iconBg: const Color(0xFFF3E8FF),
                                title: 'Quản lý tài khoản (Users)',
                                subtitle: 'Phân quyền & theo dõi hệ thống',
                                value: '',
                                onTap: () => AppToast.show(context: context, message: 'Database tại Neon.tech đã sẵn sàng', isSuccess: true),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // --- MAIN DASHBOARD BUTTON ---
                        InkWell(
                          onTap: () => context.push('/admin-dashboard'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _admPrimary.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.dashboard_customize_rounded, color: _admSecondary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Quản trị hệ thống (Dashboard)',
                                  style: TextStyle(color: _admSecondary, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildTabMenuButton(title: 'Hoạt động', tabKey: 'activity'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Thông tin', tabKey: 'info'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Hệ thống', tabKey: 'settings'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.all(24).copyWith(bottom: 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  if (_activeTab == 'activity') _buildActivityTab(),
                  if (_activeTab == 'info') _buildInfoTab(),
                  if (_activeTab == 'settings') _buildSettingsTab(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityTab() {
    if (_isLoadingLogs) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(color: Color(0xFFF59E0B)),
        ),
      );
    }

    if (_systemLogs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Text('Chưa có dữ liệu nhật ký hệ thống.', style: TextStyle(color: Color(0xFF617D79), fontSize: 14)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nhật ký Hệ thống', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
        const SizedBox(height: 16),
        ..._systemLogs.map((log) {
          // Xử lý icon và màu sắc động tương thích dữ liệu JSON API (Fallback linh hoạt)
          final type = log['type'] ?? log['status'] ?? 'info';
          Color iconColor = Colors.blue;
          IconData iconData = Icons.dns_rounded;
          
          if (type == 'success' || type == 'APPROVED') {
            iconColor = const Color(0xFF48C9B0);
            iconData = Icons.check_circle_rounded;
          } else if (type == 'warning' || type == 'REJECTED' || type == 'PENDING') {
            iconColor = Colors.amber;
            iconData = Icons.warning_rounded;
          } else if (type == 'error' || type == 'DELETED') {
            iconColor = Colors.redAccent;
            iconData = Icons.error_rounded;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2ECEB)), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))]),
            child: Row(
              children: [
                Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(iconData, color: iconColor, size: 20)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log['msg'] ?? log['message'] ?? log['title'] ?? 'Cập nhật hệ thống', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.3)),
                      const SizedBox(height: 4),
                      Text(log['time'] ?? log['created_at'] ?? 'Vừa xong', style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                )
              ],
            ),
          );
        }),
      ],
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
          const Text('Thông tin quản trị tối cao', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _buildSaaSFieldDisabled(label: 'Username định danh', value: widget.profile['username'] ?? 'Chưa thiết lập', icon: Icons.alternate_email_rounded),
          _buildSaaSFieldDisabled(label: 'Bí danh quản trị', value: widget.profile['full_name'] ?? 'Chưa thiết lập', icon: Icons.badge_rounded),
          _buildSaaSFieldDisabled(label: 'Email bảo mật', value: widget.profile['email'] ?? 'Chưa liên kết email', icon: Icons.mail_lock_rounded),
          _buildSaaSFieldDisabled(label: 'Giới thiệu chuyên môn', value: widget.profile['bio'] ?? 'Chưa cập nhật dữ liệu', icon: Icons.workspace_premium_rounded),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFFBEB),
                foregroundColor: _admPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: _admPrimary.withOpacity(0.3), width: 1),
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
              child: Icon(icon, size: 16, color: _admPrimary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _admSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2ECEB))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.admin_panel_settings_rounded, color: _admPrimary, size: 20),
              const SizedBox(width: 8),
              Text('Quyền lực tối cao (Level 5)', style: TextStyle(color: _admPrimary, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Tài khoản có đặc quyền cao nhất. Vui lòng cẩn trọng với các thao tác xóa và sửa đổi hệ thống.', style: TextStyle(color: Color(0xFF617D79), fontSize: 12, height: 1.4)),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Divider(height: 1, color: Color(0xFFF2F4F3))),
          _buildToggleSetting(
            title: 'Xác thực 2 lớp (2FA)', 
            subtitle: 'Bảo vệ quyền can thiệp cấp cao.', 
            isOn: _is2FAEnabled,
            onChanged: (v) {
              setState(() => _is2FAEnabled = v);
              AppToast.show(context: context, message: 'Đã ${v ? 'Bật' : 'Tắt'} Xác thực 2 lớp (2FA)', isSuccess: true);
            }
          ),
          const SizedBox(height: 16),
          _buildToggleSetting(
            title: 'Cảnh báo đăng nhập lạ', 
            subtitle: 'Gửi email khi IP thay đổi đột ngột.', 
            isOn: _isLoginAlertEnabled,
            onChanged: (v) {
              setState(() => _isLoginAlertEnabled = v);
              AppToast.show(context: context, message: 'Đã ${v ? 'Bật' : 'Tắt'} Cảnh báo đăng nhập lạ', isSuccess: true);
            }
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSetting({required String title, required String subtitle, required bool isOn, required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ),
        Switch(value: isOn, onChanged: onChanged, activeColor: Colors.white, activeTrackColor: const Color(0xFF48C9B0), inactiveThumbColor: Colors.white, inactiveTrackColor: const Color(0xFFE2ECEB)),
      ],
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

  Widget _buildHubRowTile({required IconData icon, required Color iconColor, required Color iconBg, required String title, required String subtitle, required String value, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle), child: Icon(icon, size: 20, color: iconColor)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            if (value.isNotEmpty) Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0C4C1), size: 18),
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