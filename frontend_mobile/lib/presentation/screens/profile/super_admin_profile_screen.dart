import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/admin_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/mini_video_player.dart';
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
  String _activeTab = 'activity'; // activity | videos | posts | settings
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'followers_count': 0, 'active_services': 0, 'system_stability': 99.9};
  List<dynamic> _videos = [];
  List<dynamic> _posts = [];

  // Mock Logs y hệt bản Web
  final List<Map<String, dynamic>> _systemLogs = [
    {'id': 1, 'type': 'success', 'msg': 'Hệ thống sao lưu dữ liệu (Database Backup) thành công.', 'time': '10 phút trước', 'icon': Icons.storage, 'color': Colors.green},
    {'id': 2, 'type': 'warning', 'msg': 'Cảnh báo lưu lượng truy cập tăng cao tại Cụm Server A.', 'time': '1 giờ trước', 'icon': Icons.insights, 'color': Colors.orange},
    {'id': 3, 'type': 'info', 'msg': 'Đồng bộ hóa trạng thái giao dịch Escrow với cổng thanh toán.', 'time': '3 giờ trước', 'icon': Icons.dns, 'color': Colors.blue},
  ];

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadAdminData();
  }

  Future<void> _loadAdminData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AdminApiService.fetchStats(),
      AdminApiService.fetchContent(),
    ]);

    if (mounted) {
      setState(() {
        if (results[0] != null) _stats = results[0]!;
        if (results[1] != null) {
          _videos = results[1]!['videos'] ?? [];
          _posts = results[1]!['community_posts'] ?? [];
        }
        _isLoading = false;
      });
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
              leading: const Icon(Icons.photo_camera, color: Colors.amber),
              title: const Text('Đổi ảnh mới', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
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
        widget.onRefresh(); // Cập nhật lại toàn bộ UI ngoài màn hình chính
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cập nhật ảnh thành công!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi đường truyền, không thể tải ảnh!'), backgroundColor: Colors.red));
      }
    }
  }

  // ==========================================
  // LOGIC 2: ĐĂNG TẢI VIDEO (STUDIO)
  // ==========================================
  void _showUploadVideoModal() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    File? selectedVideo;
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Đăng Video Lên Studio', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withOpacity(0.3))),
                  child: const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 16), SizedBox(width: 8), Expanded(child: Text('Đặc quyền Admin: Video tự động được duyệt (Auto-Approved).', style: TextStyle(color: Colors.green, fontSize: 12)))]),
                ),
                const SizedBox(height: 16),
                
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        // Khu vực chọn Video
                        GestureDetector(
                          onTap: isUploading ? null : () async {
                            final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
                            if (video != null) setModalState(() => selectedVideo = File(video.path));
                          },
                          child: Container(
                            height: 200, width: 140,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedVideo != null ? Colors.green : Colors.white24, width: 2)),
                            child: selectedVideo != null
                                ? Column(
                                    mainAxisAlignment: MainAxisAlignment.center, 
                                    children: [
                                      const Icon(Icons.video_file, color: Colors.green, size: 48), 
                                      const SizedBox(height: 8), 
                                      const Text('Đã đính kèm Video', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                                      TextButton(onPressed: () => setModalState(() => selectedVideo = null), child: const Text('Hủy', style: TextStyle(color: Colors.red)))
                                    ]
                                  ) 
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center, 
                                    children: [
                                      Icon(Icons.video_library, color: Colors.amber, size: 40), 
                                      SizedBox(height: 8), 
                                      Text('Chọn Video', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)),
                                      Text('Tỉ lệ 9:16', style: TextStyle(color: Colors.white30, fontSize: 10))
                                    ]
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(controller: titleCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Tiêu đề (Bắt buộc)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                        const SizedBox(height: 12),
                        TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Mô tả', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                        const SizedBox(height: 12),
                        TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Giá dịch vụ đính kèm (VNĐ)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                      ]
                    )
                  )
                ),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isUploading ? null : () async {
                      if (titleCtrl.text.isEmpty || selectedVideo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đính kèm Video và nhập Tiêu đề!')));
                        return;
                      }
                      setModalState(() => isUploading = true);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tải video lên Cloudflare R2. Vui lòng đợi...'), duration: Duration(seconds: 3)));
                      
                      final success = await AdminApiService.createVideo(titleCtrl.text, contentCtrl.text, priceCtrl.text, selectedVideo!);
                      
                      setModalState(() => isUploading = false);
                      if (success) {
                        Navigator.pop(context);
                        _loadAdminData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phát sóng Video thành công!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi tải video. Kích thước file có thể quá lớn.'), backgroundColor: Colors.red));
                      }
                    },
                    child: isUploading ? const CircularProgressIndicator(color: Colors.black) : const Text('PHÁT SÓNG VIDEO', style: TextStyle(fontWeight: FontWeight.w900)),
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

  // ==========================================
  // LOGIC 3: ĐĂNG TẢI BÀI VIẾT (CỘNG ĐỒNG)
  // ==========================================
  void _showAddPostModal() {
    final contentCtrl = TextEditingController();
    File? selectedImage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tạo Thông Báo Hệ Thống', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                TextField(
                  controller: contentCtrl,
                  maxLines: 5,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(hintText: 'Viết thông báo cho cộng đồng...', hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
                    if (image != null) setModalState(() => selectedImage = File(image.path));
                  },
                  child: Container(
                    height: 120, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white24, style: BorderStyle.solid)),
                    child: selectedImage != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(selectedImage!, fit: BoxFit.cover))
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, color: Colors.white54), SizedBox(height: 8), Text('Tải ảnh đính kèm (Tùy chọn)', style: TextStyle(color: Colors.white54))]),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: () async {
                      if (contentCtrl.text.isEmpty) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang phát sóng...')));
                      final success = await AdminApiService.createPost(contentCtrl.text, selectedImage);
                      if (success) _loadAdminData();
                    },
                    child: const Text('PHÁT SÓNG THÔNG BÁO', style: TextStyle(fontWeight: FontWeight.w900)),
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
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: Colors.amber)));

    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: CustomScrollView(
        slivers: [
          // ==========================================
          // GIẢI QUYẾT OVERLAP (ĐÈ LAYER) BẰNG COLUMN+STACK
          // ==========================================
          SliverToBoxAdapter(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none, // Cho phép Avatar tràn ra ngoài vùng Cover
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 1. Lớp Ảnh bìa (Cover)
                    GestureDetector(
                      onTap: () => _showImageOptions(widget.profile['cover_url'], 'cover'),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.blueGrey.shade900,
                          image: widget.profile['cover_url'] != null ? DecorationImage(image: GlobalCacheProvider.create(widget.profile['cover_url'], maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                        ),
                        child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09090b).withOpacity(0.9)]))),
                      ),
                    ),
                    
                    // 2. Lớp Nút Bấm Hệ Thống (Dashboard, Settings, Logout)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.dashboard, color: Colors.amber, size: 20),
                              tooltip: 'Admin Dashboard',
                              onPressed: () => context.push('/admin-dashboard'), // Điều hướng sang Dashboard
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.white, size: 20),
                              tooltip: 'Xem công khai',
                              onPressed: () => context.push('/public-profile/${widget.profile['username']}'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings, color: Colors.white, size: 20),
                              tooltip: 'Cài đặt',
                              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang chuẩn bị màn hình Cài đặt...'))),
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

                    // 3. Lớp Avatar (Đẩy lòi ra ngoài Cover 50px)
                    Positioned(
                      bottom: -50,
                      child: GestureDetector(
                        onTap: () => _showImageOptions(widget.profile['avatar_url'], 'avatar'),
                        child: Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF09090b), // Màu viền tiệp với nền để tạo nét cắt
                            border: Border.all(color: Colors.amber, width: 3),
                            image: DecorationImage(image: NetworkImage(widget.profile['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}'), fit: BoxFit.cover)
                          ),
                        ),
                      ),
                    )
                  ],
                ),
                
                // Khoảng đệm 60px để bù đắp cho phần Avatar bị lồi xuống
                const SizedBox(height: 60),

                // 4. Lớp Thông tin cá nhân
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(widget.profile['full_name'] ?? 'Admin', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          const Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
                        ],
                      ),
                      Text('@${widget.profile['username']}', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 24),
                      
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(_stats['followers_count'].toString(), 'Người quan tâm'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(_stats['active_services'].toString(), 'Dịch vụ Active'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol('${_stats['system_stability']}%', 'Độ ổn định', isHighlight: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Tabs
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTabBtn('HOẠT ĐỘNG', Icons.local_activity, 'activity'),
                  _buildTabBtn('STUDIO', Icons.video_library, 'videos'),
                  _buildTabBtn('BÀI ĐĂNG', Icons.article, 'posts'),
                  _buildTabBtn('CẤU HÌNH', Icons.admin_panel_settings, 'settings'),
                ],
              ),
            ),
          ),

          // Nội dung Tabs
          SliverPadding(
            padding: const EdgeInsets.all(24).copyWith(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_activeTab == 'activity') _buildActivityTab(),
                if (_activeTab == 'videos') _buildStudioTab(),
                if (_activeTab == 'posts') _buildPostsTab(),
                if (_activeTab == 'settings') _buildSettingsTab(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // --- TAB 1: HOẠT ĐỘNG ---
  Widget _buildActivityTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nhật ký Hệ thống Tự động', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ..._systemLogs.map((log) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: log['color'].withOpacity(0.1), shape: BoxShape.circle), child: Icon(log['icon'], color: log['color'], size: 20)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(log['msg'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(log['time'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
        )),
      ],
    );
  }

  // --- TAB 2: STUDIO (Quản lý Video) ---
  Widget _buildStudioTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Studio Video (${_videos.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _showUploadVideoModal, 
              icon: const Icon(Icons.video_call, size: 16), 
              label: const Text('Tải Video', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 16, mainAxisSpacing: 16),
          itemCount: _videos.length,
          itemBuilder: (context, index) {
            final v = _videos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MiniVideoPlayer(videoUrl: v['video_url']),
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(4)), child: const Text('AUTO-APPROVED', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)))),
                  Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2))),
                ],
              ),
            );
          },
        )
      ],
    );
  }

  // --- TAB 3: BÀI ĐĂNG CỘNG ĐỒNG ---
  Widget _buildPostsTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Thông báo (${_posts.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              onPressed: _showAddPostModal, 
              icon: const Icon(Icons.edit, size: 16), 
              label: const Text('Viết')
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._posts.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundImage: NetworkImage(widget.profile['avatar_url']), radius: 16),
                  const SizedBox(width: 8),
                  const Text('System Announcement', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 12),
              Text(p['content'], style: const TextStyle(color: Colors.white)),
              if (p['image_url'] != null) ...[
                const SizedBox(height: 12),
                ClipRRect(borderRadius: BorderRadius.circular(12), child: GlobalCacheImage(imageUrl: p['image_url'], memCacheWidth: 600)),
              ]
            ],
          ),
        )),
      ],
    );
  }

  // --- TAB 4: CẤU HÌNH ---
  Widget _buildSettingsTab() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Quyền lực tối cao (Level 5)', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.w900, letterSpacing: 1)),
          const SizedBox(height: 8),
          const Text('Tài khoản có đặc quyền cao nhất. Vui lòng cẩn trọng với các thao tác xóa và sửa đổi hệ thống.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const Divider(height: 32, color: Colors.white10),
          _buildToggleSetting('Xác thực 2 lớp (2FA)', 'Bảo vệ quyền can thiệp cấp cao.', true),
          const SizedBox(height: 16),
          _buildToggleSetting('Cảnh báo đăng nhập lạ', 'Gửi email khi IP thay đổi đột ngột.', true),
        ],
      ),
    );
  }

  Widget _buildToggleSetting(String title, String subtitle, bool isOn) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ]),
        Switch(value: isOn, onChanged: (v){}, activeColor: Colors.amber),
      ],
    );
  }

  // --- WIDGET HỖ TRỢ ---
  Widget _buildStatCol(String val, String label, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(val, style: TextStyle(color: isHighlight ? Colors.amber : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? Colors.amber : Colors.transparent, width: 2))),
        child: Column(
          children: [
            Icon(icon, size: 20, color: isActive ? Colors.amber : Colors.white54),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: isActive ? Colors.amber : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}