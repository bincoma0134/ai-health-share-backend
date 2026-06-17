import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../../data/services/partner_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/image_uploader.dart';
import '../../widgets/video_uploader.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';

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
  
  bool _isFetchingLock = false;
  bool _hasFetchedServices = false;
  bool _hasFetchedVideos = false;

  // Controllers cho Form Hồ sơ
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
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
    _phoneCtrl.text = widget.profile['phone'] ?? '';
    _loadPartnerData();
  }

  // [PHASE 2 & PHASE 4] Request Deduplication & Lazy Loading
  Future<void> _loadPartnerData() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    try {
      if (mounted) setState(() => _isLoading = true);
      // Chỉ tải Tab mặc định ban đầu (Dịch vụ) để tăng tốc độ nạp trang tối đa
      final services = await PartnerApiService.fetchMyServices();
      
      if (mounted) {
        setState(() {
          _myServices = services as List<dynamic>;
          _hasFetchedServices = true;
          _isLoading = false;
        });
      }
    } finally {
      _isFetchingLock = false;
    }
  }

  // Khởi chạy ngầm tải Video khi user thật sự bấm vào Tab Studio
  bool _isLazyFetching = false;
  Future<void> _loadTabDataIfNeeded(String tab) async {
    if (_isLazyFetching) return;
    
    bool needsFetch = false;
    if (tab == 'services' && !_hasFetchedServices) needsFetch = true;
    if (tab == 'studio' && !_hasFetchedVideos) needsFetch = true;
    
    if (!needsFetch) return;

    _isLazyFetching = true;
    try {
      if (tab == 'services') {
        final services = await PartnerApiService.fetchMyServices();
        if (mounted) setState(() { _myServices = services as List<dynamic>; _hasFetchedServices = true; });
      } else if (tab == 'studio') {
        final videos = await PartnerApiService.fetchMyVideos();
        if (mounted) setState(() { _myVideos = videos as List<dynamic>; _hasFetchedVideos = true; });
      }
    } finally {
      _isLazyFetching = false;
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
                  showDialog(context: context, builder: (_) => Dialog(backgroundColor: Colors.transparent, insetPadding: EdgeInsets.zero, child: Stack(alignment: Alignment.topRight, children: [InteractiveViewer(child: GlobalCacheImage(imageUrl: imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity, memCacheWidth: 1200)), Padding(padding: const EdgeInsets.all(16.0), child: IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 32), onPressed: () => Navigator.pop(context)))])));
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
      AppToast.show(context: context, message: 'Đang tải ${type == 'avatar' ? 'Ảnh đại diện' : 'Ảnh bìa'} lên...', isSuccess: true);
      
      String folder = type == 'avatar' ? 'users/avatars' : 'users/covers';
      final url = await UserApiService.uploadMedia(File(image.path), folder);
      
      if (url != null) {
        await UserApiService.updateProfile({type == 'avatar' ? 'avatar_url' : 'cover_url': url});
        widget.onRefresh();
        if (mounted) AppToast.show(context: context, message: 'Đổi ảnh thành công!', isSuccess: true);
      } else {
        if (mounted) AppToast.show(context: context, message: 'Lỗi đường truyền hoặc tải tệp!', isSuccess: false);
      }
    }
  }

  Future<void> _handleUpdateProfile() async {
    final name = _nameCtrl.text.trim();
    final uname = _usernameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    if (name.isEmpty || uname.isEmpty || phone.isEmpty) {
      AppToast.show(context: context, message: 'Tên, Username và SĐT không được để trống!', isSuccess: false);
      return;
    }

    setState(() => _isUpdatingProfile = true);
    final success = await UserApiService.updateProfile({
      'username': uname,
      'full_name': name,
      'bio': _bioCtrl.text.trim(),
      'phone': phone,
    });
    setState(() => _isUpdatingProfile = false);
    if (success && mounted) {
      widget.onRefresh();
      AppToast.show(context: context, message: 'Đã cập nhật hồ sơ doanh nghiệp!', isSuccess: true);
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
    String uploadedMediaUrl = '';
    String mediaType = 'image';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          
          InputDecoration _inputDeco(String label) => InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500),
            filled: true,
            fillColor: const Color(0xFFF7FBF9),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF48C9B0), width: 1.5)),
          );

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48, height: 5,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Text('Thêm Dịch Vụ Mới', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                const Text('Thiết lập thông tin và tải lên phương tiện giới thiệu.', style: TextStyle(color: Color(0xFF617D79), fontSize: 14)),
                const SizedBox(height: 28),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Cụm Segmented Control Mềm Mại
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F7F4),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setModalState((){ mediaType = 'image'; uploadedMediaUrl = ''; }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: mediaType == 'image' ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: mediaType == 'image' ? [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))] : [],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('Hình ảnh', style: TextStyle(color: mediaType == 'image' ? const Color(0xFF1A3A35) : const Color(0xFF617D79), fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setModalState((){ mediaType = 'video'; uploadedMediaUrl = ''; }),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    decoration: BoxDecoration(
                                      color: mediaType == 'video' ? Colors.white : Colors.transparent,
                                      borderRadius: BorderRadius.circular(20),
                                      boxShadow: mediaType == 'video' ? [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4))] : [],
                                    ),
                                    alignment: Alignment.center,
                                    child: Text('Video', style: TextStyle(color: mediaType == 'video' ? const Color(0xFF1A3A35) : const Color(0xFF617D79), fontWeight: FontWeight.bold, fontSize: 14)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // Khu vực Tải lên Lơ lửng (Floating Upload Zone)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                                child: const Icon(Icons.cloud_upload_rounded, size: 36, color: Color(0xFF48C9B0))
                              ),
                              const SizedBox(height: 16),
                              const Text('Khu vực tải lên Media', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text(mediaType == 'image' ? 'Hỗ trợ định dạng JPG, PNG (Tối đa 10MB)' : 'Hỗ trợ định dạng MP4 (Tỉ lệ 9:16 hoặc 16:9)', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13)),
                              const SizedBox(height: 20),
                              if (mediaType == 'image')
                                ImageUploader(
                                  label: 'Duyệt tìm tệp hình ảnh',
                                  onUploadSuccess: (url) => setModalState(() => uploadedMediaUrl = url),
                                )
                              else
                                VideoUploader(
                                  label: 'Duyệt tìm tệp video',
                                  folder: 'services/videos',
                                  onUploadSuccess: (url) => setModalState(() => uploadedMediaUrl = url),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Form Fields
                        const Text('Thông tin chi tiết', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 16),
                        TextField(controller: nameCtrl, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w600), decoration: _inputDeco('Tên dịch vụ (Bắt buộc)')),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold), decoration: _inputDeco('Giá tiền (VNĐ)'))),
                            const SizedBox(width: 16),
                            Expanded(child: TextField(controller: tagsCtrl, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Tags (cách nhau ,)'))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: descCtrl, maxLines: 3, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Mô tả dịch vụ')),
                        const SizedBox(height: 32),
                      ]
                    )
                  )
                ),
                Container(
                  width: double.infinity, 
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2B5A53)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white, 
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))
                    ),
                    onPressed: isSubmitting ? null : () async {
                      if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng nhập Tên và Giá!', isSuccess: false); return;
                      }
                      setModalState(() => isSubmitting = true);
                      
                      final payload = {
                        'service_name': nameCtrl.text,
                        'description': descCtrl.text,
                        'price': double.tryParse(priceCtrl.text) ?? 0,
                        'tags': tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                        'service_type': 'RELAXATION',
                        if (mediaType == 'image' && uploadedMediaUrl.isNotEmpty) 'image_url': uploadedMediaUrl,
                        if (mediaType == 'video' && uploadedMediaUrl.isNotEmpty) 'video_url': uploadedMediaUrl,
                      };
                      
                      final success = await PartnerApiService.createService(payload, null, mediaType);
                      setModalState(() => isSubmitting = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadPartnerData();
                        AppToast.show(context: context, message: 'Đã gửi dịch vụ đi chờ kiểm duyệt!', isSuccess: true);
                      } else if (mounted) {
                        AppToast.show(context: context, message: 'Lỗi đường truyền!', isSuccess: false);
                      }
                    },
                    child: isSubmitting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('GỬI YÊU CẦU DUYỆT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
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
    String uploadedVideoUrl = '';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          
          InputDecoration _inputDeco(String label) => InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500),
            filled: true,
            fillColor: const Color(0xFFF7FBF9),
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF48C9B0), width: 1.5)),
          );

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48, height: 5,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const Text('Tải Lên Video Studio', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 6),
                const Text('Chia sẻ không gian và quy trình dịch vụ của bạn.', style: TextStyle(color: Color(0xFF617D79), fontSize: 14)),
                const SizedBox(height: 28),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 8))],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle),
                                child: const Icon(Icons.video_library_rounded, size: 36, color: Color(0xFF48C9B0))
                              ),
                              const SizedBox(height: 16),
                              const Text('Video ngắn (Tỉ lệ 9:16)', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 20),
                              VideoUploader(
                                width: 140,
                                label: 'Chọn tệp Video',
                                folder: 'tiktok_feeds/videos',
                                onUploadSuccess: (url) => setModalState(() => uploadedVideoUrl = url),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text('Thông tin chi tiết', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                        const SizedBox(height: 16),
                        TextField(controller: titleCtrl, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w600), decoration: _inputDeco('Tiêu đề video (Bắt buộc)')),
                        const SizedBox(height: 16),
                        TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Mô tả nội dung')),
                        const SizedBox(height: 16),
                        TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold), decoration: _inputDeco('Giá tham khảo đính kèm (VNĐ)')),
                        const SizedBox(height: 32),
                      ]
                    )
                  )
                ),
                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2B5A53)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent, 
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white, 
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))
                    ),
                    onPressed: isSubmitting ? null : () async {
                      if (uploadedVideoUrl.isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng chờ hệ thống tải video lên!', isSuccess: false); return;
                      }
                      if (titleCtrl.text.isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng nhập Tiêu đề cho video!', isSuccess: false); return;
                      }
                      setModalState(() => isSubmitting = true);
                      
                      final payload = {
                        'title': titleCtrl.text,
                        'content': contentCtrl.text.isEmpty ? null : contentCtrl.text,
                        'price': priceCtrl.text.isEmpty ? null : double.tryParse(priceCtrl.text),
                        'video_url': uploadedVideoUrl,
                      };
                      
                      try {
                        final res = await ApiClient.instance.post('/tiktok/feeds', data: payload);
                        final success = res.statusCode == 200;
                        setModalState(() => isSubmitting = false);
                        
                        if (success && mounted) {
                          Navigator.pop(context);
                          _loadPartnerData();
                          AppToast.show(context: context, message: 'Đã gửi video đi chờ duyệt!', isSuccess: true);
                        } else if (mounted) {
                          AppToast.show(context: context, message: 'Lỗi dữ liệu không hợp lệ!', isSuccess: false);
                        }
                      } catch (e) {
                        setModalState(() => isSubmitting = false);
                        if (mounted) AppToast.show(context: context, message: 'Lỗi kết nối máy chủ!', isSuccess: false);
                      }
                    },
                    child: isSubmitting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('PHÁT SÓNG VIDEO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
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

  Future<void> _handleDeleteService(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.08), blurRadius: 32, offset: const Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F2), 
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFE63946).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]
                ), 
                child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE63946), size: 36)
              ),
              const SizedBox(height: 24),
              const Text('Xóa Dịch Vụ', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              const Text('Bạn muốn xóa dịch vụ này?\nHành động này không thể hoàn tác.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 15, height: 1.5)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFF7FBF9), foregroundColor: const Color(0xFF617D79)), 
                      onPressed: () => Navigator.pop(context, false), 
                      child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                    )
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(boxShadow: [BoxShadow(color: const Color(0xFFE63946).withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))]),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFE63946), foregroundColor: Colors.white, elevation: 0), 
                        onPressed: () => Navigator.pop(context, true), 
                        child: const Text('Xóa ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                      ),
                    )
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang gửi yêu cầu xóa...', isSuccess: true);
    
    final success = await PartnerApiService.deleteService(id);
    if (success && mounted) {
      _loadPartnerData();
      AppToast.show(context: context, message: 'Đã gửi yêu cầu xóa chờ duyệt!', isSuccess: true);
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi khi xóa dịch vụ!', isSuccess: false);
    }
  }

  void _showEditServiceModal(Map<String, dynamic> svc) {
    final nameCtrl = TextEditingController(text: svc['service_name']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: svc['price']?.toString() ?? '');
    
    String tagsText = '';
    if (svc['tags'] != null) {
      if (svc['tags'] is List) { tagsText = (svc['tags'] as List).join(', '); } 
      else if (svc['tags'] is String) { tagsText = svc['tags']; }
    }
    final tagsCtrl = TextEditingController(text: tagsText);
    final descCtrl = TextEditingController(text: svc['description']?.toString() ?? '');
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          InputDecoration _inputDeco(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500), filled: true, fillColor: const Color(0xFFF7FBF9), contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF48C9B0), width: 1.5)));

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)))),
                const Text('Sửa Dịch Vụ', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: nameCtrl, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w600), decoration: _inputDeco('Tên dịch vụ (Bắt buộc)')),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold), decoration: _inputDeco('Giá tiền (VNĐ)'))),
                            const SizedBox(width: 16),
                            Expanded(child: TextField(controller: tagsCtrl, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Tags (cách nhau ,)'))),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(controller: descCtrl, maxLines: 3, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Mô tả chi tiết')),
                        const SizedBox(height: 32),
                      ]
                    )
                  )
                ),
                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2B5A53)]), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                    onPressed: isUploading ? null : () async {
                      if (nameCtrl.text.isEmpty || priceCtrl.text.isEmpty) { AppToast.show(context: context, message: 'Vui lòng nhập Tên và Giá!', isSuccess: false); return; }
                      setModalState(() => isUploading = true);
                      
                      final payload = {
                        'service_name': nameCtrl.text,
                        'description': descCtrl.text,
                        'price': double.tryParse(priceCtrl.text) ?? 0,
                        'tags': tagsCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                      };
                      
                      final success = await PartnerApiService.updateService(svc['id'], payload);
                      setModalState(() => isUploading = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadPartnerData();
                        AppToast.show(context: context, message: 'Bản sửa đổi đã được gửi duyệt lại!', isSuccess: true);
                      } else if (mounted) {
                        AppToast.show(context: context, message: 'Lỗi đường truyền!', isSuccess: false);
                      }
                    },
                    child: isUploading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
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

  Future<void> _handleDeleteVideo(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.08), blurRadius: 32, offset: const Offset(0, 16))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F2), 
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: const Color(0xFFE63946).withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 8))]
                ), 
                child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE63946), size: 36)
              ),
              const SizedBox(height: 24),
              const Text('Gỡ Video Studio', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              const Text('Bạn muốn gỡ video này khỏi Studio?\nHành động này không thể hoàn tác.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 15, height: 1.5)),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFF7FBF9), foregroundColor: const Color(0xFF617D79)), 
                      onPressed: () => Navigator.pop(context, false), 
                      child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                    )
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(boxShadow: [BoxShadow(color: const Color(0xFFE63946).withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 8))]),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFE63946), foregroundColor: Colors.white, elevation: 0), 
                        onPressed: () => Navigator.pop(context, true), 
                        child: const Text('Gỡ ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))
                      ),
                    )
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang gửi yêu cầu gỡ video...', isSuccess: true);
    
    final success = await PartnerApiService.deleteVideo(id);
    if (success && mounted) {
      _loadPartnerData();
      AppToast.show(context: context, message: 'Đã gửi yêu cầu gỡ video chờ duyệt!', isSuccess: true);
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi khi gỡ video!', isSuccess: false);
    }
  }

  void _showEditVideoModal(Map<String, dynamic> vid) {
    final titleCtrl = TextEditingController(text: vid['title']?.toString() ?? '');
    final contentCtrl = TextEditingController(text: vid['content']?.toString() ?? '');
    final priceCtrl = TextEditingController(text: vid['price']?.toString() ?? '');
    bool isUploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          InputDecoration _inputDeco(String label) => InputDecoration(labelText: label, labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500), filled: true, fillColor: const Color(0xFFF7FBF9), contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF48C9B0), width: 1.5)));

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10)))),
                const Text('Sửa Thông Tin Video', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(controller: titleCtrl, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w600), decoration: _inputDeco('Tiêu đề video (Bắt buộc)')),
                        const SizedBox(height: 16),
                        TextField(controller: contentCtrl, maxLines: 3, style: const TextStyle(color: Color(0xFF1A3A35)), decoration: _inputDeco('Mô tả nội dung')),
                        const SizedBox(height: 16),
                        TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold), decoration: _inputDeco('Giá tham khảo đính kèm (VNĐ)')),
                        const SizedBox(height: 32),
                      ]
                    )
                  )
                ),
                Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(100), gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2B5A53)]), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 8))]),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, shadowColor: Colors.transparent, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100))),
                    onPressed: isUploading ? null : () async {
                      if (titleCtrl.text.isEmpty) { AppToast.show(context: context, message: 'Vui lòng nhập Tiêu đề!', isSuccess: false); return; }
                      setModalState(() => isUploading = true);
                      
                      final payload = {
                        'title': titleCtrl.text,
                        'content': contentCtrl.text.isEmpty ? null : contentCtrl.text,
                        'price': priceCtrl.text.isEmpty ? null : double.tryParse(priceCtrl.text),
                      };
                      
                      final success = await PartnerApiService.updateVideo(vid['id'], payload);
                      setModalState(() => isUploading = false);
                      
                      if (success && mounted) {
                        Navigator.pop(context);
                        _loadPartnerData();
                        AppToast.show(context: context, message: 'Bản sửa đổi video đã được gửi duyệt lại!', isSuccess: true);
                      } else if (mounted) {
                        AppToast.show(context: context, message: 'Lỗi đường truyền!', isSuccess: false);
                      }
                    },
                    child: isUploading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
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
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF7FBF9),
        body: ShimmerWrapper(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              children: [
                // Skeleton Khối Cover & Avatar
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(height: 220, width: double.infinity, color: const Color(0xFFE2ECEB)),
                    Positioned(
                      bottom: -50,
                      child: Container(
                        width: 110, height: 110,
                        decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4)),
                        child: Container(decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle)),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 70),
                // Skeleton Tiêu đề Doanh nghiệp
                Container(height: 24, width: 180, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                const SizedBox(height: 8),
                Container(height: 14, width: 100, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(6))),
                const SizedBox(height: 24),
                // Skeleton 3 Thẻ Stats Chỉ số
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(3, (index) => Expanded(child: Container(margin: EdgeInsets.only(right: index < 2 ? 12 : 0), height: 60, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(20))))),
                  ),
                ),
                const SizedBox(height: 40),
                // Skeleton Bộ Menu Tabs Segmented
                Container(margin: const EdgeInsets.symmetric(horizontal: 24), height: 50, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(24))),
                const SizedBox(height: 24),
                // Skeleton Khối Dịch vụ (Trải dọc)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: List.generate(2, (index) => Container(margin: const EdgeInsets.only(bottom: 16), height: 100, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(24)))),
                  ),
                )
              ],
            ),
          ),
        ),
      );
    }

    // XỬ LÝ LỖI TRẮNG ẢNH (Kiểm tra chuỗi rỗng "" từ Backend)
    final String? rawCover = widget.profile['cover_url'];
    final bool hasCover = rawCover != null && rawCover.trim().isNotEmpty;

    final String? rawAvatar = widget.profile['avatar_url'];
    final bool hasAvatar = rawAvatar != null && rawAvatar.trim().isNotEmpty;
    final String fallbackAvatar = 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=3b82f6&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Ảnh Bìa (Fade xuống nền sáng)
                    GestureDetector(
                      onTap: () => _showImageOptions(hasCover ? rawCover : null, 'cover'),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                        ),
                        child: !hasCover 
                          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.business, color: _bizPrimary.withOpacity(0.5), size: 60), const SizedBox(height: 8), Text('Tải ảnh bìa cơ sở', style: TextStyle(color: const Color(0xFF617D79), fontWeight: FontWeight.bold))]))
                          : Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFFF7FBF9).withOpacity(0.5), const Color(0xFFF7FBF9)]))),
                      ),
                    ),
                    
                    // Nút Hành động Góc phải (Áp dụng Liquid Glass)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      right: 16,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white.withOpacity(0.5))),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(Icons.dashboard_rounded, color: _bizPrimary, size: 20),
                                  tooltip: 'Dashboard',
                                  onPressed: () => context.push('/partner-dashboard'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.visibility_rounded, color: Color(0xFF1A3A35), size: 20),
                                  tooltip: 'Xem công khai',
                                  onPressed: () => context.push('/public-profile/${widget.profile['username']}'),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                                  onPressed: widget.onLogout,
                                ),
                              ],
                            ),
                          ),
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
                                color: Colors.white,
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 8))],
                                image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : fallbackAvatar), fit: BoxFit.cover)
                              ),
                            ),
                            // Giữ nguyên màu Blue cho Badge theo yêu cầu
                            Positioned(
                              bottom: -10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [_bizPrimary, _bizSecondary]),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white, width: 1.5),
                                  boxShadow: [BoxShadow(color: _bizPrimary.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
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
                          Text(widget.profile['full_name'] ?? 'Doanh nghiệp', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                          const SizedBox(width: 6),
                          Icon(Icons.verified_rounded, color: _bizPrimary, size: 22),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('@${widget.profile['username']}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 24),
                      
                      // Chỉ số - Thiết kế dạng thẻ nổi (Premium Floating Cards)
                      Row(
                        children: [
                          Expanded(child: _buildPremiumStatCard(Icons.favorite_rounded, widget.profile['followers_count']?.toString() ?? '0', 'Quan tâm', iconColor: const Color(0xFFF43F5E))),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPremiumStatCard(Icons.local_mall_rounded, _myServices.length.toString(), 'Dịch vụ', iconColor: _bizPrimary)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildPremiumStatCard(Icons.star_rounded, '${widget.profile['reputation_points'] ?? 100}', 'Uy tín', iconColor: const Color(0xFFF59E0B), isHighlight: true)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(widget.profile['bio'] ?? "Đối tác y tế chính thức của AI Health. Cung cấp dịch vụ chăm sóc sức khỏe chủ động và chuyên nghiệp.", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF617D79), fontSize: 14, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Tabs - Tái cấu trúc thành Segmented Control hiện đại
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 32, left: 24, right: 24),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
              ),
              child: Row(
                children: [
                  _buildTabBtn('Dịch vụ', Icons.local_mall_rounded, 'services'),
                  _buildTabBtn('Studio', Icons.video_library_rounded, 'studio'),
                  _buildTabBtn('Hồ sơ', Icons.edit_rounded, 'info'),
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
            Text('Dịch vụ hiện tại (${_myServices.length})', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: _bizPrimary.withOpacity(0.1),
                foregroundColor: _bizPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              ),
              onPressed: _showAddServiceModal, 
              icon: const Icon(Icons.add_rounded, size: 18), 
              label: const Text('Thêm mới', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_myServices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40), 
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.spa_rounded, size: 48, color: const Color(0xFFB0C4C1).withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('Chưa có dịch vụ nào', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Hãy thiết lập dịch vụ đầu tiên để thu hút\nkhách hàng đến với không gian của bạn.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 13, height: 1.5)),
                ],
              )
            )
          )
        else
          ..._myServices.map((svc) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(24), 
              boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))]
            ),
            child: Row(
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16), 
                    image: svc['image_url'] != null ? DecorationImage(image: GlobalCacheProvider.create(svc['image_url'], maxWidth: 300, maxHeight: 300), fit: BoxFit.cover) : null, 
                    color: const Color(0xFFF7FBF9),
                    border: Border.all(color: const Color(0xFFE2ECEB).withOpacity(0.5))
                  ),
                  child: svc['image_url'] == null ? const Icon(Icons.spa_outlined, color: Color(0xFFB0C4C1)) : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(svc['service_name'] ?? '', style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(_formatCurrency(svc['price']), style: TextStyle(color: _bizPrimary, fontWeight: FontWeight.w900, fontSize: 14)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), 
                            decoration: BoxDecoration(
                              color: svc['status'] == 'APPROVED' ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1), 
                              borderRadius: BorderRadius.circular(8),
                            ), 
                            child: Text(
                              svc['status'] == 'APPROVED' ? 'Đã duyệt' : 'Chờ duyệt', 
                              style: TextStyle(color: svc['status'] == 'APPROVED' ? const Color(0xFF48C9B0) : Colors.amber.shade700, fontSize: 10, fontWeight: FontWeight.bold)
                            )
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: (svc['tags'] != null && svc['tags'] is List && (svc['tags'] as List).isNotEmpty)
                              ? Row(
                                  children: [
                                    const Icon(Icons.label_outline_rounded, size: 14, color: Color(0xFFB0C4C1)),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text((svc['tags'] as List).first.toString(), style: const TextStyle(color: Color(0xFF617D79), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  ],
                                )
                              : const SizedBox(),
                          ),
                          Row(
                            children: [
                              Material(
                                color: const Color(0xFFF2F2F7),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: () => _showEditServiceModal(svc),
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.edit_rounded, color: Color(0xFF617D79), size: 18),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Material(
                                color: const Color(0xFFFFF0F0),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: () => _handleDeleteService(svc['id']),
                                  customBorder: const CircleBorder(),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
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
            Text('Video của tôi (${_myVideos.length})', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
            TextButton.icon(
              style: TextButton.styleFrom(
                backgroundColor: _bizPrimary.withOpacity(0.1),
                foregroundColor: _bizPrimary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)
              ),
              onPressed: _showAddVideoModal, 
              icon: const Icon(Icons.video_call_rounded, size: 18), 
              label: const Text('Tải lên', style: TextStyle(fontWeight: FontWeight.bold))
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_myVideos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40), 
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.video_library_rounded, size: 48, color: const Color(0xFFB0C4C1).withOpacity(0.5)),
                  const SizedBox(height: 16),
                  const Text('Chưa có video nào', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Đăng tải video ngắn để giới thiệu không gian\nvà dịch vụ đến nhiều khách hàng hơn.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 13, height: 1.5)),
                ],
              )
            )
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 16, mainAxisSpacing: 16),
            itemCount: _myVideos.length,
            itemBuilder: (context, index) {
              final v = _myVideos[index];
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MiniVideoPlayer(videoUrl: v['video_url']),
                      
                      // Status Badge (SaaS Clean Style)
                      Positioned(
                        top: 10, left: 10, 
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), 
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85), 
                                borderRadius: BorderRadius.circular(8),
                              ), 
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6, height: 6,
                                    decoration: BoxDecoration(
                                      color: v['status'] == 'APPROVED' ? const Color(0xFF48C9B0) : Colors.amber.shade600,
                                      shape: BoxShape.circle
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    v['status'] == 'APPROVED' ? 'Đã duyệt' : 'Chờ duyệt', 
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 10, fontWeight: FontWeight.bold)
                                  ),
                                ],
                              )
                            ),
                          ),
                        )
                      ),

                      // Action Buttons (Clean White)
                      Positioned(
                        top: 10, right: 10,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _showEditVideoModal(v),
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.edit_rounded, color: Color(0xFF64748B), size: 16),
                                      ),
                                    ),
                                  ),
                                  Container(width: 1, height: 16, color: const Color(0xFFE2ECEB)), // Divider mỏng
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _handleDeleteVideo(v['id']),
                                      child: const Padding(
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Gradient Title - Refined
                      Positioned(
                        bottom: 0, left: 0, right: 0, 
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 32, 12, 12), 
                          decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])
                          ), 
                          child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis)
                        )
                      ),
                    ],
                  ),
                ),
              );
            },
          )
      ],
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
          child: Text(label, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2))],
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textAlign: TextAlign.left,
            style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 16, fontWeight: FontWeight.w400),
            decoration: const InputDecoration(
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trường dữ liệu này đã được hệ thống bảo vệ.'), backgroundColor: Colors.orange)
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
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
                    border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
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

  Widget _buildInfoTab() {
    final email = widget.profile['email'] ?? '';
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECEB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSaaSField(controller: _nameCtrl, label: 'Tên doanh nghiệp hiển thị'),
          const SizedBox(height: 20),
          _buildSaaSField(controller: _usernameCtrl, label: 'Username định danh'),
          const SizedBox(height: 20),
          _buildSaaSField(controller: _phoneCtrl, label: 'Số điện thoại', keyboardType: TextInputType.phone),
          const SizedBox(height: 20),
          _buildSaaSLockedField(label: 'Email xác thực', value: email, badgeText: 'Bảo mật'),
          const SizedBox(height: 20),
          _buildSaaSField(controller: _bioCtrl, label: 'Tiểu sử & Giới thiệu', maxLines: 4),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A3A35), 
                foregroundColor: Colors.white, 
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
              ),
              onPressed: _isUpdatingProfile ? null : _handleUpdateProfile,
              child: _isUpdatingProfile 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const Text('LƯU THÔNG TIN HỒ SƠ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
        Text(label, style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w500, fontSize: 15),
          decoration: InputDecoration(
            filled: true, 
            fillColor: Colors.white, 
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2ECEB))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _bizPrimary, width: 1.5)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2ECEB))),
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumStatCard(IconData icon, String value, String label, {required Color iconColor, bool isHighlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isHighlight ? iconColor.withOpacity(0.4) : Colors.white, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: isHighlight ? iconColor.withOpacity(0.15) : const Color(0xFF94A3B8).withOpacity(0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.w900, height: 1), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey) {
    final isActive = _activeTab == tabKey;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _activeTab = tabKey);
          _loadTabDataIfNeeded(tabKey); // Kích hoạt nạp dữ liệu trễ chuyên dụng
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF1A3A35) : Colors.transparent,
            borderRadius: BorderRadius.circular(20)
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: isActive ? Colors.white : const Color(0xFFB0C4C1)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(color: isActive ? Colors.white : const Color(0xFFB0C4C1), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}