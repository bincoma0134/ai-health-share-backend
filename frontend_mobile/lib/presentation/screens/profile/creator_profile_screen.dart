import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/creator_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/mini_video_player.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/shimmer_wrapper.dart';

class CreatorProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;

  const CreatorProfileScreen({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  String _activeTab = 'studio'; 
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'total_likes': 0, 'approval_rate': 100, 'bookings_count': 0};
  List<dynamic> _videos = [];
  List<dynamic> _posts = [];
  List<dynamic> _savedItems = [];
  int _visibleSavesCount = 5;

  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _isUpdatingProfile = false;

  final ImagePicker _picker = ImagePicker();

  // Đồng bộ bộ mã màu sắc nhận diện thương hiệu cao cấp Rose Gold thượng lưu theo phiên bản Website
  final Color _crtPrimary = const Color(0xFFFF7A8A); 
  final Color _crtSecondary = const Color(0xFFE06C75); 

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.profile['full_name'] ?? '';
    _usernameCtrl.text = widget.profile['username'] ?? '';
    _bioCtrl.text = widget.profile['bio'] ?? '';
    _phoneCtrl.text = widget.profile['phone'] ?? '';
    _emailCtrl.text = widget.profile['email'] ?? '';
    _loadCreatorData();
  }

  Future<void> _loadCreatorData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      CreatorApiService.fetchStats(),
      CreatorApiService.fetchContent(),
      UserApiService.fetchSavedItems().catchError((_) => []),
    ]);

    if (mounted) {
      setState(() {
        if (results[0] != null) {
          _stats = results[0] as Map<String, dynamic>;
        }
        if (results[1] != null) {
          final contentData = results[1] as Map<String, dynamic>?;
          _videos = contentData?['videos'] ?? [];
          _posts = contentData?['community_posts'] ?? [];
        }
        if (results[2] != null) {
          _savedItems = results[2] as List<dynamic>;
        }
        _isLoading = false;
      });
    }
  }

  // --- HÌNH ẢNH & HỒ SƠ ---
  void _showImageOptions(String? imageUrl, String type) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24), decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: Icon(Icons.photo_camera, color: _crtPrimary), title: Text('Đổi ảnh mới', style: TextStyle(color: _crtPrimary, fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); _changeImage(type); }),
          ],
        ),
      )
    );
  }

  Future<void> _changeImage(String type) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tải ảnh lên...')));
      String folder = type == 'avatar' ? 'users/avatars' : 'users/covers';
      final url = await UserApiService.uploadMedia(File(image.path), folder);
      if (url != null) {
        await UserApiService.updateProfile({type == 'avatar' ? 'avatar_url' : 'cover_url': url});
        widget.onRefresh();
      }
    }
  }

  Future<void> _handleUpdateProfile() async {
    final name = _nameCtrl.text.trim();
    final uname = _usernameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || uname.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tên, Username và SĐT không được để trống!'), backgroundColor: Colors.redAccent)
      );
      return;
    }

    setState(() => _isUpdatingProfile = true);
    final success = await UserApiService.updateProfile({
      'full_name': name,
      'username': uname,
      'phone': phone,
      'bio': _bioCtrl.text.trim(),
    });
    setState(() => _isUpdatingProfile = false);
    
    if (success && mounted) {
      widget.onRefresh();
      _loadCreatorData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Đã lưu thay đổi hồ sơ Creator'), backgroundColor: _crtPrimary)
      );
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;
    final url = await UserApiService.uploadMedia(File(image.path), 'users/avatars');
    if (url != null) {
      final success = await UserApiService.updateProfile({'avatar_url': url});
      if (success && mounted) { widget.onRefresh(); _loadCreatorData(); }
    }
  }

  Future<void> _pickAndUploadCover() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;
    final url = await UserApiService.uploadMedia(File(image.path), 'users/covers');
    if (url != null) {
      final success = await UserApiService.updateProfile({'cover_url': url});
      if (success && mounted) { widget.onRefresh(); _loadCreatorData(); }
    }
  }

  void _showEditModal() {
    _nameCtrl.text = widget.profile['full_name'] ?? '';
    _usernameCtrl.text = widget.profile['username'] ?? '';
    _bioCtrl.text = widget.profile['bio'] ?? '';
    _phoneCtrl.text = widget.profile['phone'] ?? '';
    _emailCtrl.text = widget.profile['email'] ?? '';

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
                        child: Icon(Icons.person_outline_rounded, color: _crtSecondary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hồ sơ Creator', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu hệ thống kênh', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
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
                        _buildSaaSInputField(controller: _nameCtrl, label: 'Tên hiển thị'),
                        const SizedBox(height: 24),
                        _buildSaaSInputField(controller: _usernameCtrl, label: 'Tên đăng nhập'),
                        const SizedBox(height: 24),
                        _buildSaaSInputField(controller: _phoneCtrl, label: 'Số điện thoại', keyboardType: TextInputType.phone),
                        const SizedBox(height: 24),
                        _buildSaaSLockedField(label: 'Email xác thực', value: _emailCtrl.text, badgeText: 'Bảo mật'),
                        const SizedBox(height: 24),
                        _buildSaaSInputField(controller: _bioCtrl, label: 'Tiểu sử / Giới thiệu kênh', maxLines: 3),
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
                        onPressed: _isUpdatingProfile ? null : () async {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(color: const Color(0xFFF2F2F7), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE5E5EA))),
          child: Row(
            children: [
              Expanded(child: Text(value.isEmpty ? 'Trống' : value, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 16))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHubRowTile({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: iconColor),
            ),
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
            Row(
              children: [
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFFB0C4C1), size: 18),
              ],
            )
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

  Widget _buildSaaSFieldDisabled({required String label, required String value, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: _crtPrimary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _crtSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- MODAL UPLOAD VIDEO ---
  void _showAddVideoModal() {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    File? selectedVideo; bool isUploading = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                const Text('Chia sẻ video sáng tạo', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                const Text('Nội dung sẽ được đưa vào hàng đợi kiểm duyệt hệ thống dành cho Creator.', style: TextStyle(color: Color(0xFF617D79), fontSize: 13)),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () async { final XFile? video = await _picker.pickVideo(source: ImageSource.gallery); if (video != null) setModalState(() => selectedVideo = File(video.path)); },
                          child: Container(
                            height: 160, 
                            width: double.infinity, 
                            decoration: BoxDecoration(color: const Color(0xFFF7FBF9), borderRadius: BorderRadius.circular(20), border: Border.all(color: selectedVideo != null ? _crtPrimary : const Color(0xFFE2ECEB), width: 1.5)), 
                            child: selectedVideo != null 
                                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_file, color: _crtPrimary, size: 44), const SizedBox(height: 8), Text('Đã chọn tệp video sẵn sàng phát', style: TextStyle(color: _crtPrimary, fontSize: 12, fontWeight: FontWeight.bold))]) 
                                : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_library_rounded, color: Color(0xFFB0C4C1), size: 36), SizedBox(height: 8), Text('Chọn video ngắn từ thư viện của bạn', style: TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w600))]),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Tiêu đề / Nội dung video', style: TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.bold))),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E5EA)), boxShadow: [BoxShadow(color: _crtPrimary.withOpacity(0.01), blurRadius: 4, offset: const Offset(0, 2))]),
                          child: TextField(controller: titleCtrl, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w500), decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nhập tiêu đề video bắt buộc...', hintStyle: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14), contentPadding: EdgeInsets.all(16))),
                        ),
                        const SizedBox(height: 20),
                        const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Mô tả chi tiết nội dung', style: TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.bold))),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E5EA))),
                          child: TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w500), decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nhập mô tả thêm về video chia sẻ (tùy chọn)...', hintStyle: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14), contentPadding: EdgeInsets.all(16))),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity, 
                  height: 52, 
                  margin: const EdgeInsets.only(bottom: 32),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), disabledBackgroundColor: const Color(0xFFD1D1D6)), 
                    onPressed: isUploading ? null : () async {
                  if (titleCtrl.text.isEmpty || selectedVideo == null) return;
                  setModalState(() => isUploading = true);
                  final success = await CreatorApiService.createVideo({'title': titleCtrl.text, 'content': contentCtrl.text}, selectedVideo!);
                  setModalState(() => isUploading = false);
                  if (success && mounted) { Navigator.pop(context); _loadCreatorData(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi chờ duyệt!'), backgroundColor: Colors.green)); }
                }, child: isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('PHÁT SÓNG', style: TextStyle(fontWeight: FontWeight.w900)))),
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      )
    );
  }

  // --- MODAL TẠO BÀI ĐĂNG CỘNG ĐỒNG ---
  void _showAddPostModal() {
    final contentCtrl = TextEditingController();
    File? selectedImage; bool isUploading = false;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.78,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 5,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                const Text('Tạo Bài Đăng Diễn Đàn', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E5EA))),
                          child: TextField(controller: contentCtrl, maxLines: 4, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w500), decoration: const InputDecoration(hintText: 'Chia sẻ kiến thức hoặc cảm nghĩ sức khỏe hôm nay của bạn...', hintStyle: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14), border: InputBorder.none, contentPadding: EdgeInsets.all(16))),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: () async { final XFile? image = await _picker.pickImage(source: ImageSource.gallery); if (image != null) setModalState(() => selectedImage = File(image.path)); },
                          child: Container(
                            height: 140, 
                            width: double.infinity, 
                            decoration: BoxDecoration(color: const Color(0xFFF7FBF9), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedImage != null ? _crtPrimary : const Color(0xFFE2ECEB), width: 1)), 
                            child: selectedImage != null 
                                ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(selectedImage!, fit: BoxFit.cover)) 
                                : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.image_search_rounded, color: Color(0xFFB0C4C1), size: 32), SizedBox(height: 8), Text('Đính kèm hình ảnh minh họa', style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w600))]),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity, 
                  height: 52, 
                  margin: const EdgeInsets.only(bottom: 32),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), disabledBackgroundColor: const Color(0xFFD1D1D6)), 
                    onPressed: isUploading ? null : () async {
                  if (contentCtrl.text.isEmpty) return;
                  setModalState(() => isUploading = true);
                  final success = await CreatorApiService.createPost(contentCtrl.text, selectedImage);
                  setModalState(() => isUploading = false);
                  if (success && mounted) { Navigator.pop(context); _loadCreatorData(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã đăng bài!'), backgroundColor: Colors.green)); }
                }, child: isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('ĐĂNG BÀI', style: TextStyle(fontWeight: FontWeight.w900)))),
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
    // 🚀 SKELETON ENGINE: Khởi dựng bộ khung xương mượt mà, tịnh tiến dải gradient khử hoàn toàn vòng xoay loading AI thô kệch
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FBF9),
        body: ShimmerWrapper(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                // Khung bìa giả lập (Cover Skeleton)
                Container(height: 220, color: const Color(0xFFE2ECEB)),
                const SizedBox(height: 16),
                // Khung Avatar tròn lớn 116px đồng bộ
                Container(
                  height: 116, width: 116,
                  decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle),
                ),
                const SizedBox(height: 20),
                // Chữ định danh tên giả lập
                Container(height: 24, width: 160, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 8),
                Container(height: 14, width: 90, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 20),
                // Cụm 3 ô Mini-Card thống kê Premium
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(3, (index) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 52,
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                      ),
                    )),
                  ),
                ),
                const SizedBox(height: 24),
                // Thanh Tab Menu sương mai
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(4, (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 32, width: 70,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    )),
                  ),
                ),
                const SizedBox(height: 32),
                // Vùng lưới Video Studio
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: 9 / 16,
                    children: List.generate(3, (index) => Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
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
    final String avatarUrl = hasAvatar ? rawAvatar : 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=FF7A8A&color=fff';

    final int balance = widget.profile['svalue_balance'] ?? 0;
    final int userLevel = (balance / 400).floor() + 1;
    final int currentExp = balance % 400;
    final double expPercent = currentExp / 400.0;
    
    String titleLevel = 'Tập Sự Sức Khỏe';
    if (userLevel == 2) titleLevel = 'Chiến Sĩ Thể Chất';
    if (userLevel == 3) titleLevel = 'Đại Sứ Wellness';
    if (userLevel >= 4) titleLevel = 'Kiện Tướng Sinh Học';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFF0F2),
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
              title: const Text('Hồ sơ Creator', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: _crtPrimary, size: 24),
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
                  // Định ra một không gian hộp chứa Stack có chiều cao mở rộng tường minh (212px) để chứa trọn vẹn Avatar 116px + Badge bung ra ngoài đáy an toàn
                  SizedBox(
                    height: 212,
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8EAA).withOpacity(0.1),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFFFF0F2).withOpacity(0.5),
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
                            onTap: _pickAndUploadCover,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                              child: Icon(Icons.add_photo_alternate_rounded, size: 18, color: _crtPrimary),
                            ),
                          ),
                        ),
                        // Đặt vị trí top dịch xuống khéo léo (84px), kết hợp phân tầng Z-Index tự nhiên bên trong Column của Sliver
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
                                  boxShadow: [BoxShadow(color: _crtPrimary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
                                  image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                bottom: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [_crtSecondary, _crtPrimary]),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: _crtPrimary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.auto_awesome, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('CREATOR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 2, bottom: 4,
                                child: GestureDetector(
                                  onTap: _pickAndUploadAvatar,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
                                    child: Icon(Icons.camera_alt_rounded, size: 13, color: _crtSecondary),
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
                            Text(widget.profile['full_name'] ?? 'Nhà sáng tạo', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                            const SizedBox(width: 6),
                            Icon(Icons.check_circle_rounded, color: _crtPrimary, size: 18),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@${widget.profile['username'] ?? 'username'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),

                        // [THUẬT TOÁN CO LẬP BADGE PRESTIGE] Trích xuất danh sách icon đã mở khóa theo thứ tự xếp hạng đẳng cấp
                        () {
                          final int streak = widget.profile['streak_count'] ?? 0;
                          final int followers = widget.profile['followers_count'] ?? 0;
                          final int totalLikes = _stats['total_likes'] ?? 0;

                          // Tập hợp danh sách cặp dữ liệu: Icon và Trạng thái mở khóa thực tế
                          final List<IconData> unlockedIcons = [];
                          
                          // Tầng 1: Độc quyền & Bảo chứng hệ thống (Luôn Unlocked)
                          unlockedIcons.add(Icons.diamond_rounded); // Bậc Thầy Wellness
                          unlockedIcons.add(Icons.auto_awesome_rounded); // Khởi Đầu Vàng
                          
                          // Tầng 2: Sức hút & Cộng đồng
                          if (totalLikes >= 500) unlockedIcons.add(Icons.favorite_rounded);
                          if (followers >= 100) unlockedIcons.add(Icons.stars_rounded);
                          
                          // Tầng 3: Tần suất hoạt động
                          if (_videos.length >= 10) unlockedIcons.add(Icons.video_library_rounded);
                          if (streak >= 7) unlockedIcons.add(Icons.local_fire_department_rounded);

                          final int totalUnlocked = unlockedIcons.length;
                          final List<IconData> displayBadges = unlockedIcons.take(3).toList();
                          final int hiddenCount = totalUnlocked - 3;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // Kết xuất tối đa 3 icon tinh tế, thu gọn không khung hộp
                                ...displayBadges.map((iconData) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF0F2),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _crtPrimary.withOpacity(0.2), width: 0.5),
                                  ),
                                  child: Icon(iconData, size: 13, color: _crtSecondary),
                                )),
                                // Khối hình tròn tinh tế kèm theo dấu + và số badge đang ẩn đi khi vượt ngưỡng 3
                                if (hiddenCount > 0)
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    padding: const EdgeInsets.all(5),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: const Color(0xFFE2ECEB), width: 0.8),
                                    ),
                                    child: Text(
                                      '+$hiddenCount',
                                      style: TextStyle(
                                        color: _crtSecondary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }(),

                        // Tái cấu trúc cụm thống kê thành các Mini-Card Premium, bo góc mượt mà và trực quan sâu lắng
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildMiniStatCard(
                              value: '${widget.profile['followers_count'] ?? 0}',
                              label: 'Quan tâm',
                              icon: Icons.people_alt_rounded,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: '${_stats['total_likes'] ?? 0}',
                              label: 'Lượt thích',
                              icon: Icons.favorite_rounded,
                              iconColor: _crtSecondary,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: '100%',
                              label: 'Độ ổn định',
                              icon: Icons.verified_user_rounded,
                              iconColor: const Color(0xFF48C9B0),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // [LOGIC 1] Thanh EXP level chuyển sang tông Hồng Creator Premium
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(color: _crtPrimary, borderRadius: BorderRadius.circular(8)),
                                        child: Text('LV $userLevel', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(titleLevel, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  Text('$currentExp / 400 EXP', style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: expPercent,
                                  backgroundColor: const Color(0xFFFFF0F2),
                                  valueColor: AlwaysStoppedAnimation<Color>(_crtPrimary),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // [ĐIỂM CHẠM MỚI] Trạm theo dõi Hành trình Wellness cá nhân hóa
                        InkWell(
                          onTap: () => context.push('/wellness-profile'),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _crtPrimary.withOpacity(0.4), width: 1.2),
                              boxShadow: [
                                BoxShadow(color: _crtPrimary.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Vòng tròn năng lượng tỏa sáng nhẹ (Glowing Orb)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        _crtPrimary.withOpacity(0.25),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.3, 1.0],
                                    ),
                                    border: Border.all(color: _crtPrimary.withOpacity(0.7), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(color: _crtPrimary.withOpacity(0.4), blurRadius: 12),
                                    ],
                                  ),
                                  child: Icon(Icons.all_inclusive_rounded, color: _crtSecondary, size: 22),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hành trình Wellness của tôi',
                                        style: TextStyle(color: Color(0xFF1A3A35), fontSize: 15.5, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Khám phá tiến trình cân bằng sinh học',
                                        style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded, color: _crtSecondary, size: 14),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // [ĐIỂM CHẠM MỚI] Trạm theo dõi Hành trình Wellness cá nhân hóa
                        InkWell(
                          onTap: () => context.push('/wellness-profile'),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: _crtPrimary.withOpacity(0.4), width: 1.2),
                              boxShadow: [
                                BoxShadow(color: _crtPrimary.withOpacity(0.12), blurRadius: 24, offset: const Offset(0, 8)),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Vòng tròn năng lượng tỏa sáng nhẹ (Glowing Orb)
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: RadialGradient(
                                      colors: [
                                        _crtPrimary.withOpacity(0.25),
                                        Colors.transparent,
                                      ],
                                      stops: const [0.3, 1.0],
                                    ),
                                    border: Border.all(color: _crtPrimary.withOpacity(0.7), width: 1.5),
                                    boxShadow: [
                                      BoxShadow(color: _crtPrimary.withOpacity(0.4), blurRadius: 12),
                                    ],
                                  ),
                                  child: Icon(Icons.all_inclusive_rounded, color: _crtSecondary, size: 22),
                                ),
                                const SizedBox(width: 16),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hành trình Wellness của tôi',
                                        style: TextStyle(color: Color(0xFF1A3A35), fontSize: 15.5, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                      ),
                                      SizedBox(height: 4),
                                      Text(
                                        'Khám phá tiến trình cân bằng sinh học',
                                        style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios_rounded, color: _crtSecondary, size: 14),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // [LOGIC 2 & 3] Khối Điểm SValue & Ví thanh toán bảo chứng
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
                                icon: Icons.stars_rounded,
                                iconColor: _crtSecondary,
                                iconBg: const Color(0xFFFFF0F2),
                                title: 'SValue & Ví Voucher',
                                subtitle: 'Chuỗi điểm danh ${widget.profile['streak_count'] ?? 0} ngày liên tiếp',
                                value: widget.profile['svalue_balance']?.toString() ?? '0',
                                onTap: () => context.push('/promo'),
                              ),
                              const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Divider(height: 1, color: Color(0xFFF2F4F3))),
                              _buildHubRowTile(
                                icon: Icons.account_balance_wallet_rounded,
                                iconColor: const Color(0xFF2196F3),
                                iconBg: const Color(0xFFE3F2FD),
                                title: 'Ví thanh toán bảo chứng',
                                subtitle: 'Bảo vệ dòng tiền ký gửi Escrow PayOS',
                                value: '••••••',
                                onTap: () => context.push('/wallet'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // [LOGIC 4] Lịch trình đặt lịch hẹn y tế
                        InkWell(
                          onTap: () => context.push('/calendar'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_crtSecondary, _crtPrimary],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), shape: BoxShape.circle),
                                  child: const Icon(Icons.calendar_today_rounded, color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Lịch trình đặt lịch hẹn y tế', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(
                                        _stats['bookings_count'] != null && _stats['bookings_count'] > 0
                                            ? 'Bạn có tổng cộng ${_stats['bookings_count']} hồ sơ theo dõi lịch trình'
                                            : 'Chưa có cuộc hẹn nào được thiết lập tại quầy',
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Nút "Bảng điều khiển" chuẩn cấu trúc hướng SaaS định tuyến trực tiếp đến Creator Dashboard
                        InkWell(
                          onTap: () => context.push('/creator-dashboard'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _crtPrimary.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.space_dashboard_rounded, color: _crtSecondary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Bảng điều khiển Studio',
                                  style: TextStyle(color: _crtSecondary, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // [LOGIC 5] Hệ thống 4 thanh tab menu giữ nguyên đúng như của User, nút Nâng cấp đổi thành "Creator"
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildTabMenuButton(title: 'Studio', tabKey: 'studio'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Thành tựu', tabKey: 'achievements'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Cá nhân', tabKey: 'personal'),
                              const SizedBox(width: 6),
                              TweenAnimationBuilder<double>(
                                tween: Tween<double>(begin: -1.0, end: 2.0),
                                duration: const Duration(milliseconds: 2500),
                                builder: (context, alignmentOffset, child) {
                                  final bool isSelected = _activeTab == 'creator_info';
                                  final List<Color> activeGradientColors = [
                                    _crtSecondary,
                                    _crtPrimary,
                                    Colors.white.withOpacity(0.8),
                                    _crtPrimary,
                                    _crtSecondary,
                                  ];
                                  final List<Color> inactiveGradientColors = [
                                    _crtSecondary.withOpacity(0.08),
                                    _crtPrimary.withOpacity(0.2),
                                    const Color(0xFFFFD6DA).withOpacity(0.6),
                                    _crtPrimary.withOpacity(0.2),
                                    _crtSecondary.withOpacity(0.08),
                                  ];

                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _activeTab = 'creator_info');
                                    },
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment(alignmentOffset - 0.4, -1.0),
                                          end: Alignment(alignmentOffset + 0.4, 1.0),
                                          colors: isSelected ? activeGradientColors : inactiveGradientColors,
                                          stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isSelected ? _crtSecondary : _crtPrimary.withOpacity(0.4),
                                          width: 1.2,
                                        ),
                                      ),
                                      child: Text(
                                        'Creator',
                                        style: TextStyle(
                                          color: isSelected ? Colors.white : _crtSecondary,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                onEnd: () => setState(() {}),
                              ),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Đã lưu', tabKey: 'saves'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        _buildDynamicTabBody(widget.profile),
                        
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 24, bottom: 130),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFF0F2),
                              foregroundColor: _crtSecondary,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () {
                              final username = widget.profile['username'];
                              if (username != null && username.toString().trim().isNotEmpty) {
                                context.push('/public-profile/$username');
                              }
                            },
                            child: const Text('Xem hồ sơ hiển thị công khai', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: CreatorFloatingActionButton(
        crtPrimary: _crtPrimary,
        profile: widget.profile,
      ),
    );
  }

  Widget _buildDynamicTabBody(Map<String, dynamic> profile) {
    if (_activeTab == 'saves') {
      if (_savedItems.isEmpty) return _buildEmptyBox(Icons.bookmark_border_rounded, 'Danh mục lưu trữ đang trống');
      return Column(
        children: _savedItems.take(_visibleSavesCount).map((item) {
          final author = item['author'] ?? {};
          final String title = item['title'] ?? 'Nội dung chia sẻ sức khỏe';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2ECEB))),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled_rounded, color: Color(0xFFFF7A8A), size: 22),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700))),
              ],
            ),
          );
        }).toList(),
      );
    }
    
    if (_activeTab == 'achievements') {
      final int streak = profile['streak_count'] ?? 0;
      final int followers = profile['followers_count'] ?? 0;
      final int totalLikes = _stats['total_likes'] ?? 0;

      final bool isChuyenCanUnlocked = streak >= 7;
      final bool isSieuSaoUnlocked = followers >= 100;
      final bool isYeuThichUnlocked = totalLikes >= 500;
      final bool isKienTuongUnlocked = _videos.length >= 10;

      // Trình bày phẳng hoàn toàn bỏ qua cấu trúc Box cứng nhắc, tạo nhịp thở khoáng đạt cho UI
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPremiumRowBadge(
              icon: Icons.auto_awesome_rounded,
              title: 'Khởi Đầu Vàng',
              desc: 'Hồ sơ chuyên gia sáng tạo nội dung đã được bộ phận kiểm duyệt xác thực.',
              progress: 'Hoàn thành',
              isUnlocked: true,
            ),
            _buildPremiumRowBadge(
              icon: Icons.local_fire_department_rounded,
              title: 'Ngọn Lửa Wellness',
              desc: 'Tích lũy chuỗi điểm danh tương tác liên tiếp trong vòng 7 ngày.',
              progress: '$streak / 7 ngày',
              isUnlocked: isChuyenCanUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.stars_rounded,
              title: 'Chuyên Gia Thu Hút',
              desc: 'Tạo sức ảnh hưởng lớn trên sàn, đạt mốc 100 thành viên quan tâm.',
              progress: '$followers / 100',
              isUnlocked: isSieuSaoUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.favorite_rounded,
              title: 'Sứ Giả Truyền Cảm Hứng',
              desc: 'Sản xuất các video Wellness chất lượng cao đạt mốc 500 lượt thích.',
              progress: '$totalLikes / 500',
              isUnlocked: isYeuThichUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.video_library_rounded,
              title: 'Kiện Tướng Phát Sóng',
              desc: 'Duy trì tần suất truyền thông, xuất bản tối thiểu 10 video ngắn đã duyệt.',
              progress: '${_videos.length} / 10',
              isUnlocked: isKienTuongUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.diamond_rounded,
              title: 'Bậc Thầy Wellness',
              desc: 'Được bảo chứng tuyệt đối bởi hệ thống với chỉ số độ ổn định kênh đạt 100%.',
              progress: 'Đang ghim',
              isUnlocked: true,
              isLast: true,
            ),
          ],
        ),
      );
    }

    if (_activeTab == 'studio') {
      if (_videos.isEmpty) return _buildEmptyBox(Icons.video_library_outlined, 'Studio chưa có video chia sẻ');
      return Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Video đã đăng (${_videos.length})', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w800)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white),
                onPressed: () => context.push('/upload-studio'),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Tải lên', style: TextStyle(fontWeight: FontWeight.bold)),
              )
            ],
          ),
          const SizedBox(height: 16),
          // Nâng cấp chia lưới thành 3 cột cân đối chuẩn Creator Dashboard Studio cao cấp
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, 
              childAspectRatio: 9 / 16, 
              crossAxisSpacing: 8, 
              mainAxisSpacing: 8,
            ),
            itemCount: _videos.length,
            itemBuilder: (context, index) {
              final v = _videos[index];
              final String status = v['status']?.toString() ?? 'PENDING';
              
              Color dotColor;
              String statusText;

              switch (status.toUpperCase()) {
                case 'APPROVED':
                case 'PUBLISHED':
                  dotColor = const Color(0xFF48C9B0);
                  statusText = 'Đã duyệt';
                  break;
                case 'PENDING_EDIT':
                  dotColor = Colors.blue.shade600;
                  statusText = 'Sửa';
                  break;
                case 'PENDING_DELETE':
                  dotColor = Colors.red.shade600;
                  statusText = 'Xóa';
                  break;
                case 'PENDING':
                default:
                  dotColor = Colors.amber.shade700;
                  statusText = 'Chờ duyệt';
                  break;
              }

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MiniVideoPlayer(videoUrl: v['video_url'] ?? ''),
                      // Nhãn trạng thái thu gọn tinh tế phù hợp lưới 3 cột
                      Positioned(
                        top: 6, left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 4, height: 4, decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text(statusText, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 8, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                      // Tích hợp cụm nút thao tác (Chỉnh sửa, Xóa) bọc thép từ User Private Profile
                      Positioned(
                        top: 6, right: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    final titleCtrl = TextEditingController(text: v['title']?.toString() ?? '');
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (context) => Container(
                                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 16),
                                        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Sửa tiêu đề video', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 12),
                                            TextField(controller: titleCtrl, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Nhập tiêu đề mới...')),
                                            const SizedBox(height: 16),
                                            SizedBox(
                                              width: double.infinity,
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary),
                                                onPressed: () async {
                                                  final res = await ApiClient.instance.patch('/user/my-tiktok-feeds/${v['id']}', data: {'title': titleCtrl.text.trim()});
                                                  if (res.statusCode == 200 && context.mounted) {
                                                    Navigator.pop(context);
                                                    _loadCreatorData();
                                                  }
                                                },
                                                child: const Text('LƯU THAY ĐỔI', style: TextStyle(color: Colors.white)),
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, color: Color(0xFF64748B), size: 12)),
                                ),
                              ),
                              Container(width: 0.5, height: 10, color: const Color(0xFFE2ECEB)),
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('Gỡ Video'),
                                        content: const Text('Bạn có chắc chắn muốn yêu cầu gỡ video này không?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
                                          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Gỡ', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      final res = await ApiClient.instance.delete('/user/my-tiktok-feeds/${v['id']}');
                                      if (res.statusCode == 200) {
                                        _loadCreatorData();
                                      }
                                    }
                                  },
                                  child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
                          child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600, height: 1.2), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    if (_activeTab == 'personal') {
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
            const Text('Thông tin cá nhân', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _buildSaaSFieldDisabled(label: 'Giới thiệu', value: profile['bio'] ?? 'Chưa thiết lập tiểu sử', icon: Icons.text_snippet_outlined),
            _buildSaaSFieldDisabled(label: 'Điện thoại', value: profile['phone'] ?? 'Chưa cập nhật', icon: Icons.phone_android_rounded),
            _buildSaaSFieldDisabled(label: 'Email bảo mật', value: profile['email'] ?? 'Chưa liên kết email', icon: Icons.mail_lock_rounded),
            const SizedBox(height: 20),
            // Tích hợp button chỉnh sửa thông tin cá nhân phẳng cao cấp thừa kế chuẩn nghiệp vụ từ User Profile
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFF0F2),
                  foregroundColor: _crtSecondary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  side: BorderSide(color: _crtPrimary.withOpacity(0.3), width: 1),
                ),
                onPressed: _showEditModal,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: const Text('Chỉnh sửa thông tin', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      );
    }

    // Tab Creator (creator_info) chuyển dịch sang cấu trúc phân tích biểu đồ tăng trưởng tối giản hữu cơ cao cấp (SValue Growth Flow)
    if (_activeTab == 'creator_info') {
      final double rawApprovalRate = (_stats['approval_rate'] ?? 100).toDouble();
      final int activePublications = _videos.length + _posts.length;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Biểu đồ 1: Minh họa xu hướng ổn định phân phối (Tỷ lệ duyệt thành công)
            _buildPremiumGrowthChartRow(
              icon: Icons.insights_rounded,
              title: 'Xu hướng ổn định phân phối',
              desc: 'Đo lường biên độ an toàn và độ đồng bộ nội dung Wellness được phê duyệt định kỳ.',
              chartColor: const Color(0xFF48C9B0),
              sparkValues: [0.4, 0.5, 0.45, 0.7, 0.6, 0.85, rawApprovalRate / 100.0],
            ),
            // Biểu đồ 2: Minh họa tần suất cống hiến truyền thông (Số lượng tài nguyên xuất bản)
            _buildPremiumGrowthChartRow(
              icon: Icons.grid_view_rounded,
              title: 'Mức độ lan tỏa Wellness',
              desc: 'Tần suất xuất bản video ngắn kết hợp bài viết đóng góp diễn đàn thời gian thực.',
              chartColor: _crtSecondary,
              sparkValues: [0.2, 0.35, 0.3, 0.5, 0.45, 0.6, activePublications > 0 ? 0.85 : 0.1],
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.only(left: 40),
              child: Divider(height: 0.5, color: Color(0xFFF0F4F3)),
            ),
            const SizedBox(height: 20),
            // Button hành động cao cấp: Định tuyến toàn màn hình chuẩn xác sang trung tâm quản trị chuyên sâu
            InkWell(
              onTap: () => context.push('/creator-dashboard'),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F2),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _crtPrimary.withOpacity(0.2), width: 1),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Chi tiết bảng điều khiển nâng cao',
                      style: TextStyle(color: _crtSecondary, fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: _crtSecondary),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildEmptyBox(IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon, size: 40, color: const Color(0xFFE2ECEB)),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: Color(0xFFB0C4C1), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(IconData icon, String title, String desc, bool isUnlocked) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: const Color(0xFFFFF0F2), borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Icon(icon, size: 28, color: _crtPrimary),
          Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPostsTab() {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Bài viết (${_posts.length})', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _showAddPostModal, icon: const Icon(Icons.add, size: 16), label: const Text('Tạo mới', style: TextStyle(fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 16),
        ..._posts.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2ECEB)), boxShadow: [BoxShadow(color: const Color(0xFFFF7A8A).withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 16, backgroundImage: NetworkImage(widget.profile['avatar_url'] ?? '')), const SizedBox(width: 8), const Text('Hôm nay', style: TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 12),
            Text(p['content'], style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w500, fontSize: 14.5)),
            if (p['image_url'] != null) ...[const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(12), child: GlobalCacheImage(imageUrl: p['image_url'], memCacheWidth: 600))]
          ]),
        ))
      ],
    );
  }

  Widget _buildInfoTab() {
    return Container(
      padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Username định danh', _usernameCtrl), const SizedBox(height: 20),
          _buildTextField('Tên Kênh Hiển Thị', _nameCtrl), const SizedBox(height: 20),
          _buildTextField('Giới thiệu Kênh (Bio)', _bioCtrl, maxLines: 4), const SizedBox(height: 32),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _isUpdatingProfile ? null : _handleUpdateProfile, child: _isUpdatingProfile ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THÔNG TIN HỒ SƠ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1))))
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)), 
        const SizedBox(height: 8), 
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2ECEB)),
            boxShadow: [BoxShadow(color: const Color(0xFFFF7A8A).withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: TextField(
            controller: controller, 
            maxLines: maxLines, 
            style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold), 
            decoration: const InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.all(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCol(String val, String label, {bool isHighlight = false}) {
    return Column(children: [Text(val, style: TextStyle(color: isHighlight ? _crtPrimary : const Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5))]);
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(onTap: () => setState(() => _activeTab = tabKey), child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? _crtPrimary : Colors.transparent, width: 3))), child: Row(children: [Icon(icon, size: 16, color: isActive ? _crtPrimary : const Color(0xFFB0C4C1)), const SizedBox(width: 8), Text(label.toUpperCase(), style: TextStyle(color: isActive ? _crtPrimary : const Color(0xFFB0C4C1), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5))])));
  }

  // Kiến tạo phong cách Row phẳng tinh tế, loại bỏ hoàn toàn các box đóng cứng nhắc rập khuôn
  Widget _buildPremiumRowBadge({
    required IconData icon,
    required String title,
    required String desc,
    required String progress,
    required bool isUnlocked,
    bool isLast = false,
  }) {
    return Opacity(
      opacity: isUnlocked ? 1.0 : 0.45,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isUnlocked ? const Color(0xFFFFF0F2) : const Color(0xFFF2F2F7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isUnlocked ? _crtSecondary : const Color(0xFF8E8E93),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Color(0xFF1A3A35),
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            progress,
                            style: TextStyle(
                              color: isUnlocked ? _crtSecondary : const Color(0xFF8E8E93),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desc,
                        style: const TextStyle(
                          color: Color(0xFF617D79),
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!isLast) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.only(left: 40),
                child: Divider(height: 0.5, color: Color(0xFFF0F4F3)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Hàm xây dựng cấu trúc ô thống kê phẳng Sleek Mini-Card cao cấp
  // Khởi tạo phương thức kết xuất biểu đồ tăng trưởng Sparkline dạng thanh phẳng hữu cơ siêu mượt
  Widget _buildPremiumGrowthChartRow({
    required IconData icon,
    required String title,
    required String desc,
    required Color chartColor,
    required List<double> sparkValues,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF0F2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: _crtSecondary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF1A3A35),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: const TextStyle(
                    color: Color(0xFF617D79),
                    fontSize: 11.5,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                // Thanh Custom Paint vẽ biểu đồ xu hướng phẳng tinh tế không chiếm dụng không gian diện tích
                SizedBox(
                  height: 24,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _PremiumSparklinePainter(
                      values: sparkValues,
                      color: chartColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Khối hình tròn tinh tế kèm theo dấu + và số badge đang ẩn đi khi vượt ngưỡng 3
  Widget _buildMiniStatCard({
    required String value,
    required String label,
    required IconData icon,
    Color? iconColor,
  }) {
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
                Text(
                  value,
                  style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// Khai báo cấu trúc Painter xử lý dải cột biểu đồ dập nổi thanh lịch
class _PremiumSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;

  _PremiumSparklinePainter({required this.values, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    
    final paint = Paint()
      ..color = color.withOpacity(0.8)
      ..style = PaintingStyle.fill
      ..strokeCap = StrokeCap.round;

    final double widthBetween = size.width / (values.length - 1 + 0.6);
    final double barWidth = 6.0;

    for (int i = 0; i < values.length; i++) {
      final double x = i * widthBetween + barWidth;
      // Tránh Overflowed chiều cao và tạo độ thoải mượt mọc từ đáy
      final double currentHeight = values[i].clamp(0.08, 1.0) * size.height;
      final double y = size.height - currentHeight;

      // Khởi tạo bo tròn mượt cho dải biểu đồ cột phẳng Premium
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, currentHeight),
          const Radius.circular(3),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PremiumSparklinePainter oldDelegate) => oldDelegate.values != values;
}

// [LOGIC 6] Thành phần Widget Floating Action Button độc lập, chuẩn hóa phân rã mã nguồn Flutter
class CreatorFloatingActionButton extends StatelessWidget {
  final Color crtPrimary;
  final Map<String, dynamic> profile;

  const CreatorFloatingActionButton({
    super.key, 
    required this.crtPrimary,
    required this.profile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 102.0, right: 6),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1A3A35),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.2),
          boxShadow: [
            BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                final currentRole = profile['role'] ?? 'CREATOR';
                context.push('/upload-studio', extra: currentRole.toString());
              },
              splashColor: crtPrimary.withOpacity(0.2),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.movie_creation_rounded, color: Colors.white, size: 20),
                    Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Text(
                        "Sáng tạo ngay",
                        style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}