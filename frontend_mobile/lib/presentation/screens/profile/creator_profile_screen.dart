import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/creator_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../widgets/mini_video_player.dart';

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
  String _activeTab = 'videos'; // videos | posts | info
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'total_likes': 0, 'approval_rate': 100};
  List<dynamic> _videos = [];
  List<dynamic> _posts = [];

  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _isUpdatingProfile = false;

  final ImagePicker _picker = ImagePicker();

  final Color _crtPrimary = const Color(0xFFF43F5E); // Rose-500
  final Color _crtSecondary = const Color(0xFFE11D48); // Rose-600

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.profile['full_name'] ?? '';
    _usernameCtrl.text = widget.profile['username'] ?? '';
    _bioCtrl.text = widget.profile['bio'] ?? '';
    _loadCreatorData();
  }

  Future<void> _loadCreatorData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      CreatorApiService.fetchStats(),
      CreatorApiService.fetchContent(),
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
    setState(() => _isUpdatingProfile = true);
    final success = await UserApiService.updateProfile({'username': _usernameCtrl.text.trim(), 'full_name': _nameCtrl.text.trim(), 'bio': _bioCtrl.text.trim()});
    setState(() => _isUpdatingProfile = false);
    if (success && mounted) { widget.onRefresh(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Đã cập nhật hồ sơ!'), backgroundColor: _crtPrimary)); }
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
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Đăng Video (Studio)', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () async { final XFile? video = await _picker.pickVideo(source: ImageSource.gallery); if (video != null) setModalState(() => selectedVideo = File(video.path)); },
                  child: Container(height: 200, width: 140, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedVideo != null ? _crtPrimary : Colors.white24, width: 2)), child: selectedVideo != null ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_file, color: Colors.pinkAccent, size: 48), SizedBox(height: 8), Text('Đã đính kèm', style: TextStyle(color: Colors.pinkAccent, fontSize: 10))]) : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_library, color: Colors.blueGrey, size: 40), SizedBox(height: 8), Text('Chọn Video', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))])),
                ),
                const SizedBox(height: 24),
                TextField(controller: titleCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Tiêu đề (Bắt buộc)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Mô tả', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const Spacer(),
                SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: isUploading ? null : () async {
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
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tạo Bài Đăng Mới', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                TextField(controller: contentCtrl, maxLines: 5, style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'Bạn đang nghĩ gì?', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async { final XFile? image = await _picker.pickImage(source: ImageSource.gallery); if (image != null) setModalState(() => selectedImage = File(image.path)); },
                  child: Container(height: 120, width: double.infinity, decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedImage != null ? _crtPrimary : Colors.white24, style: BorderStyle.solid)), child: selectedImage != null ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.file(selectedImage!, fit: BoxFit.cover)) : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.image, color: Colors.white54), SizedBox(height: 8), Text('Đính kèm ảnh', style: TextStyle(color: Colors.white54))])),
                ),
                const Spacer(),
                SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: isUploading ? null : () async {
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
    if (_isLoading) return Scaffold(backgroundColor: const Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: _crtPrimary)));

    final String? rawCover = widget.profile['cover_url'];
    final bool hasCover = rawCover != null && rawCover.trim().isNotEmpty;
    final String? rawAvatar = widget.profile['avatar_url'];
    final bool hasAvatar = rawAvatar != null && rawAvatar.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    GestureDetector(
                      onTap: () => _showImageOptions(hasCover ? rawCover : null, 'cover'),
                      child: Container(height: 220, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF4C1D95).withOpacity(0.3), image: hasCover ? DecorationImage(image: NetworkImage(rawCover), fit: BoxFit.cover) : null), child: !hasCover ? Center(child: Icon(Icons.auto_awesome, color: _crtPrimary.withOpacity(0.5), size: 60)) : Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09090b).withOpacity(0.9)])))),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10, right: 16,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.dashboard, color: Colors.pinkAccent, size: 20), onPressed: () => context.push('/creator-dashboard')),
                          IconButton(icon: const Icon(Icons.visibility, color: Colors.white, size: 20), onPressed: () => context.push('/public-profile/${widget.profile['username']}')),
                          IconButton(icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20), onPressed: widget.onLogout),
                        ]),
                      ),
                    ),
                    Positioned(
                      bottom: -50,
                      child: GestureDetector(
                        onTap: () => _showImageOptions(hasAvatar ? rawAvatar : null, 'avatar'),
                        child: Stack(
                          alignment: Alignment.bottomCenter, clipBehavior: Clip.none,
                          children: [
                            Container(width: 110, height: 110, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF09090b), border: Border.all(color: Colors.white, width: 3), image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=F43F5E&color=fff'), fit: BoxFit.cover))),
                            Positioned(bottom: -10, child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(gradient: LinearGradient(colors: [_crtPrimary, _crtSecondary]), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.2)), boxShadow: [BoxShadow(color: _crtPrimary.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))]), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, color: Colors.white, size: 10), SizedBox(width: 4), Text('CREATOR', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1))]))),
                          ],
                        ),
                      ),
                    )
                  ],
                ),
                
                const SizedBox(height: 70),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [Text(widget.profile['full_name'] ?? 'Nhà sáng tạo', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(width: 8), Icon(Icons.check_circle, color: _crtPrimary, size: 20)]),
                      const SizedBox(height: 4), Text('@${widget.profile['username']}', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(widget.profile['followers_count']?.toString() ?? '0', 'Quan tâm'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(_stats['total_likes'].toString(), 'Lượt thích', isHighlight: true),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol('${_stats['approval_rate']}%', 'Uy tín'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(widget.profile['bio'] ?? "Sáng tạo nội dung chất lượng cao. Cảm ơn bạn đã theo dõi!", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 32), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTabBtn('STUDIO', Icons.video_library, 'videos'),
                  _buildTabBtn('BÀI ĐĂNG', Icons.article, 'posts'),
                  _buildTabBtn('HỒ SƠ', Icons.edit, 'info'),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(24).copyWith(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_activeTab == 'videos') _buildStudioTab(),
                if (_activeTab == 'posts') _buildPostsTab(),
                if (_activeTab == 'info') _buildInfoTab(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudioTab() {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Video đã đăng (${_videos.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _showAddVideoModal, icon: const Icon(Icons.add, size: 16), label: const Text('Tải lên', style: TextStyle(fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 16, mainAxisSpacing: 16),
          itemCount: _videos.length,
          itemBuilder: (context, index) {
            final v = _videos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(fit: StackFit.expand, children: [
                  MiniVideoPlayer(videoUrl: v['video_url']),
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: v['status'] == 'APPROVED' ? Colors.green : Colors.amber, borderRadius: BorderRadius.circular(4)), child: Text(v['status'].toString().split('_').last, style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)))),
                  Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2))),
              ]),
            );
          },
        )
      ],
    );
  }

  Widget _buildPostsTab() {
    return Column(
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Bài viết (${_posts.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)), ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _showAddPostModal, icon: const Icon(Icons.add, size: 16), label: const Text('Tạo mới', style: TextStyle(fontWeight: FontWeight.bold)))]),
        const SizedBox(height: 16),
        ..._posts.map((p) => Container(
          margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [CircleAvatar(radius: 16, backgroundImage: NetworkImage(widget.profile['avatar_url'] ?? '')), const SizedBox(width: 8), const Text('Hôm nay', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 12),
            Text(p['content'], style: const TextStyle(color: Colors.white)),
            if (p['image_url'] != null) ...[const SizedBox(height: 12), ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(p['image_url']))]
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)), const SizedBox(height: 8), TextField(controller: controller, maxLines: maxLines, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), decoration: InputDecoration(filled: true, fillColor: Colors.black45, border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)))]);
  }

  Widget _buildStatCol(String val, String label, {bool isHighlight = false}) {
    return Column(children: [Text(val, style: TextStyle(color: isHighlight ? _crtPrimary : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)), const SizedBox(height: 4), Text(label.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5))]);
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(onTap: () => setState(() => _activeTab = tabKey), child: Container(padding: const EdgeInsets.symmetric(vertical: 16), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? _crtPrimary : Colors.transparent, width: 3))), child: Row(children: [Icon(icon, size: 16, color: isActive ? _crtPrimary : Colors.white54), const SizedBox(width: 8), Text(label.toUpperCase(), style: TextStyle(color: isActive ? _crtPrimary : Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5))])));
  }
}