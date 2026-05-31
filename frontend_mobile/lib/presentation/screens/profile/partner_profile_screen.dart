import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../data/services/partner_api_service.dart';
import '../../../data/services/user_api_service.dart';
import '../../widgets/mini_video_player.dart';

class PartnerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  final VoidCallback onLogout;
  final VoidCallback onRefresh;

  const PartnerProfileScreen({
    super.key,
    required this.profile,
    required this.onLogout,
    required this.onRefresh,
  });

  @override
  State<PartnerProfileScreen> createState() => _PartnerProfileScreenState();
}

class _PartnerProfileScreenState extends State<PartnerProfileScreen> {
  String _activeTab = 'services';
  bool _isLoading = true;
  
  List<dynamic> _myServices = [];
  List<dynamic> _myVideos = [];

  // Controllers cho Form Hồ sơ
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  bool _isUpdatingProfile = false;

  final ImagePicker _picker = ImagePicker();

  final Color _bizPrimary = Colors.blue;
  final Color _bizSecondary = Colors.cyan;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.profile['full_name'] ?? '';
    _usernameCtrl.text = widget.profile['username'] ?? '';
    _bioCtrl.text = widget.profile['bio'] ?? '';
    _loadPartnerData();
  }

  Future<void> _loadPartnerData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      PartnerApiService.fetchMyServices(),
      PartnerApiService.fetchMyVideos(),
    ]);

    if (mounted) {
      setState(() {
        _myServices = results[0] as List<dynamic>;
        _myVideos = results[1] as List<dynamic>;
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(dynamic amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount ?? 0);
  }

  // ==========================================
  // LOGIC 1: ĐỔI ẢNH VÀ CẬP NHẬT HỒ SƠ
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
                title: const Text('Xem ảnh lớn', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pop(context);
                  showDialog(context: context, builder: (_) => Dialog(backgroundColor: Colors.transparent, insetPadding: EdgeInsets.zero, child: Stack(alignment: Alignment.topRight, children: [InteractiveViewer(child: Image.network(imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity)), Padding(padding: const EdgeInsets.all(16.0), child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.pop(context)))])));
                },
              ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: _bizPrimary),
              title: Text('Đổi ảnh doanh nghiệp', style: TextStyle(color: _bizPrimary, fontWeight: FontWeight.bold)),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đang tải ${type == 'avatar' ? 'Ảnh đại diện' : 'Ảnh bìa'} lên...')));
      
      String folder = type == 'avatar' ? 'users/avatars' : 'users/covers';
      final url = await UserApiService.uploadMedia(File(image.path), folder);
      
      if (url != null) {
        await UserApiService.updateProfile({type == 'avatar' ? 'avatar_url' : 'cover_url': url});
        widget.onRefresh();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đổi ảnh thành công!'), backgroundColor: Colors.green));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi đường truyền hoặc tải tệp!'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _handleUpdateProfile() async {
    setState(() => _isUpdatingProfile = true);
    final success = await UserApiService.updateProfile({
      'username': _usernameCtrl.text.trim(),
      'full_name': _nameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
    });
    setState(() => _isUpdatingProfile = false);
    if (success && mounted) {
      widget.onRefresh();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã cập nhật hồ sơ doanh nghiệp!'), backgroundColor: Colors.blue));
    }
  }

  // ==========================================
  // LOGIC 2: MODAL THÊM DỊCH VỤ VÀ VIDEO
  // ==========================================
  void _showAddServiceModal() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final tagsCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    File? selectedMedia;
    String mediaType = 'image';
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
                const Text('Thêm Dịch Vụ Mới', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: ChoiceChip(label: const Text('Ảnh minh họa'), selected: mediaType == 'image', onSelected: (v) => setModalState((){ mediaType = 'image'; selectedMedia = null; }), selectedColor: _bizPrimary.withOpacity(0.2), backgroundColor: Colors.white.withOpacity(0.05))),
                            const SizedBox(width: 12),
                            Expanded(child: ChoiceChip(label: const Text('Video giới thiệu'), selected: mediaType == 'video', onSelected: (v) => setModalState((){ mediaType = 'video'; selectedMedia = null; }), selectedColor: _bizPrimary.withOpacity(0.2), backgroundColor: Colors.white.withOpacity(0.05))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            final XFile? file = mediaType == 'image' ? await _picker.pickImage(source: ImageSource.gallery) : await _picker.pickVideo(source: ImageSource.gallery);
                            if (file != null) setModalState(() => selectedMedia = File(file.path));
                          },
                          child: Container(
                            height: 150, width: double.infinity,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedMedia != null ? _bizPrimary : Colors.white24, style: BorderStyle.solid)),
                            child: selectedMedia != null
                                ? const Center(child: Icon(Icons.check_circle, color: Colors.blue, size: 48)) 
                                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(mediaType == 'image' ? Icons.image : Icons.video_library, color: Colors.white54, size: 40), const SizedBox(height: 8), Text('Tải lên ${mediaType == 'image' ? 'Ảnh' : 'Video'}', style: const TextStyle(color: Colors.white54))]),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Tên dịch vụ (Bắt buộc)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold), decoration: InputDecoration(labelText: 'Giá tiền (VNĐ)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                            const SizedBox(width: 12),
                            Expanded(child: TextField(controller: tagsCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Tags (cách nhau bằng dấu phẩy)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(controller: descCtrl, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Mô tả chi tiết', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                      ]
                    )
                  )
                ),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isUploading ? null : () async {
                      if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập Tên và Giá!'))); return;
                      }
                      setModalState(() => isUploading = true);
                      
                      final payload = {
                        'service_name': nameCtrl.text,
                        'description': descCtrl.text,
                        'price': double.tryParse(priceCtrl.text) ?? 0,
                        'tags': tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                        'service_type': 'RELAXATION'
                      };
                      
                      final success = await PartnerApiService.createService(payload, selectedMedia, mediaType);
                      setModalState(() => isUploading = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadPartnerData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi dịch vụ đi chờ kiểm duyệt!'), backgroundColor: Colors.blue));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi đường truyền!'), backgroundColor: Colors.red));
                      }
                    },
                    child: isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('GỬI ĐI CHỜ KIỂM DUYỆT', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
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

  void _showAddVideoModal() {
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
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
                            if (video != null) setModalState(() => selectedVideo = File(video.path));
                          },
                          child: Container(
                            height: 200, width: 140,
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: selectedVideo != null ? Colors.blue : Colors.white24, width: 2)),
                            child: selectedVideo != null
                                ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_file, color: Colors.blue, size: 48), SizedBox(height: 8), Text('Đã đính kèm', style: TextStyle(color: Colors.blue, fontSize: 10))]) 
                                : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.video_library, color: Colors.blueGrey, size: 40), SizedBox(height: 8), Text('Chọn Video', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))]),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(controller: titleCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Tiêu đề (Bắt buộc)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                        const SizedBox(height: 12),
                        TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Mô tả', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                        const SizedBox(height: 12),
                        TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Giá tham khảo đính kèm (VNĐ)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                      ]
                    )
                  )
                ),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isUploading ? null : () async {
                      if (titleCtrl.text.isEmpty || selectedVideo == null) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đính kèm Video và nhập Tiêu đề!'))); return;
                      }
                      setModalState(() => isUploading = true);
                      
                      final payload = {
                        'title': titleCtrl.text,
                        'content': contentCtrl.text,
                        'price': double.tryParse(priceCtrl.text) ?? 0,
                      };
                      
                      final success = await PartnerApiService.createVideo(payload, selectedVideo!);
                      setModalState(() => isUploading = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadPartnerData();
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi video đi chờ duyệt!'), backgroundColor: Colors.blue));
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi đường truyền!'), backgroundColor: Colors.red));
                      }
                    },
                    child: isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('PHÁT SÓNG VIDEO', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
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
  // XÂY DỰNG GIAO DIỆN CHÍNH
  // ==========================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(backgroundColor: const Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: _bizPrimary)));

    // XỬ LÝ LỖI TRẮNG ẢNH (Kiểm tra chuỗi rỗng "" từ Backend)
    final String? rawCover = widget.profile['cover_url'];
    final bool hasCover = rawCover != null && rawCover.trim().isNotEmpty;

    final String? rawAvatar = widget.profile['avatar_url'];
    final bool hasAvatar = rawAvatar != null && rawAvatar.trim().isNotEmpty;
    final String fallbackAvatar = 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=3b82f6&color=fff';

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
                    // Ảnh Bìa
                    GestureDetector(
                      onTap: () => _showImageOptions(hasCover ? rawCover : null, 'cover'),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          image: hasCover ? DecorationImage(image: NetworkImage(rawCover), fit: BoxFit.cover) : null,
                        ),
                        child: !hasCover 
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.business, color: _bizPrimary.withOpacity(0.5), size: 60), const SizedBox(height: 8), const Text('Tải ảnh bìa cơ sở', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))]))
                          : Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09090b).withOpacity(0.9)]))),
                      ),
                    ),
                    
                    // Nút Hành động Góc phải
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 16,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white10)),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.dashboard, color: Colors.cyanAccent, size: 20),
                              tooltip: 'Dashboard',
                              onPressed: () => context.push('/partner-dashboard'), // ĐIỀU HƯỚNG DASHBOARD
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.white, size: 20),
                              tooltip: 'Xem công khai',
                              onPressed: () => context.push('/public-profile/${widget.profile['username']}'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
                              onPressed: widget.onLogout,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Avatar Doanh nghiệp nhô lên 50px
                    Positioned(
                      bottom: -50,
                      child: GestureDetector(
                        onTap: () => _showImageOptions(hasAvatar ? rawAvatar : null, 'avatar'),
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
                                image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : fallbackAvatar), fit: BoxFit.cover)
                              ),
                            ),
                            Positioned(
                              bottom: -10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [_bizPrimary, _bizSecondary]),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                                  boxShadow: [BoxShadow(color: _bizPrimary.withOpacity(0.5), blurRadius: 8, offset: const Offset(0, 4))]
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.business, color: Colors.white, size: 10),
                                    SizedBox(width: 4),
                                    Text('BUSINESS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
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

                // Thông tin Doanh nghiệp
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(widget.profile['full_name'] ?? 'Doanh nghiệp', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          Icon(Icons.verified, color: _bizPrimary, size: 24),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('@${widget.profile['username']}', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 24),
                      
                      // Chỉ số
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(widget.profile['followers_count']?.toString() ?? '0', 'Quan tâm'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(_myServices.length.toString(), 'Dịch vụ'),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol('${widget.profile['reputation_points'] ?? 92}', 'Uy tín', isHighlight: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(widget.profile['bio'] ?? "Đối tác y tế chính thức của AI Health. Cung cấp dịch vụ chăm sóc sức khỏe chủ động và chuyên nghiệp.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Tabs
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 32),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildTabBtn('DỊCH VỤ', Icons.local_mall, 'services'),
                  _buildTabBtn('STUDIO', Icons.video_library, 'studio'),
                  _buildTabBtn('HỒ SƠ', Icons.edit, 'info'),
                ],
              ),
            ),
          ),

          // Nội dung Tabs
          SliverPadding(
            padding: const EdgeInsets.all(24).copyWith(bottom: 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_activeTab == 'services') _buildServicesTab(),
                if (_activeTab == 'studio') _buildStudioTab(),
                if (_activeTab == 'info') _buildInfoTab(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Dịch vụ hiện tại (${_myServices.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _showAddServiceModal, 
              icon: const Icon(Icons.add, size: 16), 
              label: const Text('Thêm mới', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_myServices.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('Bạn chưa có dịch vụ nào.', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))))
        else
          ..._myServices.map((svc) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
            child: Row(
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)), image: svc['image_url'] != null ? DecorationImage(image: NetworkImage(svc['image_url']), fit: BoxFit.cover) : null, color: Colors.black26),
                  child: svc['image_url'] == null ? const Icon(Icons.image, color: Colors.white24) : null,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(svc['service_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(_formatCurrency(svc['price']), style: TextStyle(color: _bizSecondary, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 8),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: svc['status'] == 'APPROVED' ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: Text(svc['status'], style: TextStyle(color: svc['status'] == 'APPROVED' ? Colors.green : Colors.amber, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ))
      ],
    );
  }

  Widget _buildStudioTab() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Video của tôi (${_myVideos.length})', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _showAddVideoModal, 
              icon: const Icon(Icons.video_call, size: 16), 
              label: const Text('Tải lên', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 16, mainAxisSpacing: 16),
          itemCount: _myVideos.length,
          itemBuilder: (context, index) {
            final v = _myVideos[index];
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MiniVideoPlayer(videoUrl: v['video_url']),
                  Positioned(top: 8, left: 8, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: v['status'] == 'APPROVED' ? Colors.green : Colors.amber, borderRadius: BorderRadius.circular(4)), child: Text(v['status'], style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)))),
                  Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2))),
                ],
              ),
            );
          },
        )
      ],
    );
  }

  Widget _buildInfoTab() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.03), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTextField('Username định danh', _usernameCtrl),
          const SizedBox(height: 20),
          _buildTextField('Tên doanh nghiệp hiển thị', _nameCtrl),
          const SizedBox(height: 20),
          _buildTextField('Tiểu sử & Giới thiệu', _bioCtrl, maxLines: 4),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              onPressed: _isUpdatingProfile ? null : _handleUpdateProfile,
              child: _isUpdatingProfile ? const CircularProgressIndicator(color: Colors.white) : const Text('LƯU THÔNG TIN HỒ SƠ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, {int maxLines = 1}) {
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
      ],
    );
  }

  Widget _buildStatCol(String val, String label, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(val, style: TextStyle(color: isHighlight ? _bizPrimary : Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
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
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? _bizPrimary : Colors.transparent, width: 3))),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? _bizPrimary : Colors.white54),
            const SizedBox(width: 8),
            Text(label.toUpperCase(), style: TextStyle(color: isActive ? _bizPrimary : Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}