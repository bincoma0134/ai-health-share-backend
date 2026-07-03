import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../data/services/partner_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/image_uploader.dart';
import '../../widgets/video_uploader.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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
  final _addressCtrl = TextEditingController();
  double? _latitude;
  double? _longitude;
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
    _addressCtrl.text = widget.profile['physical_address'] ?? '';
    _latitude = widget.profile['latitude'] != null ? double.tryParse(widget.profile['latitude'].toString()) : null;
    _longitude = widget.profile['longitude'] != null ? double.tryParse(widget.profile['longitude'].toString()) : null;
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
    final address = _addressCtrl.text.trim();

    if (name.isEmpty || uname.isEmpty || phone.isEmpty) {
      AppToast.show(context: context, message: 'Tên, Username và SĐT không được để trống!', isSuccess: false);
      return;
    }

    setState(() => _isUpdatingProfile = true);

    final Map<String, dynamic> payload = {
      'username': uname,
      'full_name': name,
      'bio': _bioCtrl.text.trim(),
      'phone': phone,
      'physical_address': address,
    };
    
    // Sử dụng tọa độ an toàn, chuẩn hóa chính xác 6 chữ số thập phân (chuẩn định vị GPS) để tránh lỗi parse Backend
    if (_latitude != null && _longitude != null) {
      payload['latitude'] = double.parse(_latitude!.toStringAsFixed(6));
      payload['longitude'] = double.parse(_longitude!.toStringAsFixed(6));
    }

    final success = await UserApiService.updateProfile(payload);
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

  void _showLocationPickerBottomSheet() async {
    final query = _addressCtrl.text.trim();
    if (query.isEmpty) {
      AppToast.show(context: context, message: 'Vui lòng nhập địa chỉ trước khi ghim!', isSuccess: false);
      return;
    }

    LatLng center = _latitude != null && _longitude != null 
        ? LatLng(_latitude!, _longitude!) 
        : const LatLng(21.028511, 105.804817);
    
    bool isMapLoading = true;
    List<dynamic> suggestions = [];
    bool hasSearched = false;
    final MapController innerMapController = MapController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          // Thực hiện quét tìm kiếm khoanh vùng nâng cao (Tối đa 5 kết quả tốt nhất)
          if (isMapLoading && !hasSearched) {
            hasSearched = true;
            
            // 1. CẤU HÌNH THUẬT TOÁN BIAS: Ưu tiên lãnh thổ VN và vùng lân cận
            final Map<String, dynamic> geoParams = {
              'q': query, 
              'format': 'json', 
              'limit': 5,
              'countrycodes': 'vn', // Khóa cứng lãnh thổ Việt Nam, loại bỏ kết quả nhiễu nước ngoài
            };
            
            // Nếu có tọa độ cũ, tạo Viewbox (~50km) để ưu tiên kết quả cùng Tỉnh/Thành phố
            if (_latitude != null && _longitude != null) {
              geoParams['viewbox'] = '${_longitude! - 0.5},${_latitude! + 0.5},${_longitude! + 0.5},${_latitude! - 0.5}';
              geoParams['bounded'] = 0; // Ưu tiên (không bắt buộc tuyệt đối)
            }

            // 2. BẢO MẬT API BÊN THỨ 3: Dùng Dio độc lập (Clean Client), tránh gửi Auth Token của hệ thống 
            // sang OpenStreetMap gây lỗi 403 Forbidden. Thêm User-Agent chuẩn để tuân thủ luật tường lửa Nominatim.
            Dio().get(
              'https://nominatim.openstreetmap.org/search',
              queryParameters: geoParams,
              options: Options(headers: {'User-Agent': 'AIHealthPartnerApp/1.0'}),
            ).then((res) {
              if (res.statusCode == 200 && res.data is List && (res.data as List).isNotEmpty) {
                final List<dynamic> list = res.data;
                final double? lat = double.tryParse(list[0]['lat'].toString());
                final double? lon = double.tryParse(list[0]['lon'].toString());
                
                if (mounted) {
                  setModalState(() {
                    suggestions = list;
                    if (lat != null && lon != null) {
                      center = LatLng(lat, lon);
                    }
                    isMapLoading = false;
                  });
                  
                  if (lat != null && lon != null) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (mounted) innerMapController.move(LatLng(lat, lon), 16.0);
                    });
                  }
                }
              } else {
                // Xử lý báo lỗi hiển thị rõ ràng khi địa chỉ quá ngóc ngách, OpenStreetMap không tìm thấy
                if (mounted) {
                  setModalState(() => isMapLoading = false);
                  AppToast.show(context: context, message: 'Địa chỉ quá chi tiết hoặc chưa có mặt trên bản đồ vệ tinh. Vui lòng rê điểm ghim thủ công!', isSuccess: false);
                }
              }
            }).catchError((e) {
              // Bắt lỗi kết nối mạng hoặc bị chặn IP
              debugPrint('❌ OpenStreetMap API Error: $e');
              if (mounted) {
                setModalState(() => isMapLoading = false);
                AppToast.show(context: context, message: 'Lỗi định vị vị trí tự động. Vui lòng rê điểm ghim thủ công!', isSuccess: false);
              }
            });
          }

          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 48, height: 5, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 16),
                const Text('Xác nhận Vị trí', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                const Text('Chọn địa chỉ chính xác và tinh chỉnh tâm ghim', style: TextStyle(color: Color(0xFF617D79), fontSize: 13)),
                const SizedBox(height: 12),
                
                // HỘP THOẠI CHỌN ĐỊA CHỈ PHÂN VÙNG GỢI Ý (STYLE SHOPEE)
                if (!isMapLoading && suggestions.isNotEmpty)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FBF9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2ECEB)),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      itemCount: suggestions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1, color: Color(0xFFE2ECEB)),
                      itemBuilder: (context, index) {
                        final item = suggestions[index];
                        final displayName = item['display_name'] ?? '';
                        return InkWell(
                          onTap: () {
                            final double? lat = double.tryParse(item['lat'].toString());
                            final double? lon = double.tryParse(item['lon'].toString());
                            if (lat != null && lon != null) {
                              setModalState(() {
                                center = LatLng(lat, lon);
                                // Điều hướng dịch chuyển ống kính bản đồ đến tọa độ được chọn lập tức
                                innerMapController.move(center, 16.0);
                              });
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF48C9B0)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF1A3A35), fontWeight: FontWeight.w500),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: isMapLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF48C9B0)))
                    : Stack(
                        children: [
                          FlutterMap(
                            mapController: innerMapController,
                            options: MapOptions(
                              initialCenter: center,
                              initialZoom: 16.0,
                              onPositionChanged: (position, hasGesture) {
                                // Bỏ điều kiện hasGesture để đồng bộ biến center 
                                // trong mọi trường hợp camera di chuyển (rê tay hoặc chọn gợi ý)
                                if (position.center != null) {
                                  center = position.center!;
                                }
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.aihealth.partner',
                              ),
                            ],
                          ),
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.only(bottom: 40),
                              child: Icon(Icons.location_on, size: 40, color: Color(0xFFE63946)),
                            ),
                          ),
                        ],
                      ),
                ),
                
                // GIA CỐ HẠ TẦNG PADDING: Tự động co giãn theo độ dày của thanh điều hướng hệ thống
                Padding(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 24,
                    bottom: 24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            side: const BorderSide(color: Color(0xFFE2ECEB)),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Hủy', style: TextStyle(color: Color(0xFF617D79), fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A3A35),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          onPressed: () {
                            setState(() {
                              _latitude = center.latitude;
                              _longitude = center.longitude;
                            });
                            Navigator.pop(context);
                            AppToast.show(context: context, message: 'Đã xác nhận điểm ghim!', isSuccess: true);
                          },
                          child: const Text('LƯU ĐIỂM GHIM', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
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
    // 🚀 ĐỒNG BỘ MAP ICON: Tự động nhận diện ngữ cảnh tiêu đề để gán Icon Line-art cao cấp phù hợp
    IconData prefixIcon = Icons.edit_note_rounded;
    if (label.contains('Tên doanh nghiệp')) prefixIcon = Icons.business_rounded;
    else if (label.contains('Username')) prefixIcon = Icons.alternate_email_rounded;
    else if (label.contains('Điện thoại')) prefixIcon = Icons.phone_iphone_rounded;
    else if (label.contains('Địa chỉ')) prefixIcon = Icons.location_on_rounded;
    else if (label.contains('Tiểu sử')) prefixIcon = Icons.auto_stories_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A3A35).withOpacity(0.04), // Bóng đổ Neumorphic khuếch tán đa tầng mịn màng
            blurRadius: 12,
            offset: const Offset(0, 4),
            spreadRadius: -2,
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF617D79), fontSize: 14, fontWeight: FontWeight.w500),
          floatingLabelStyle: const TextStyle(color: Color(0xFF48C9B0), fontSize: 13, fontWeight: FontWeight.bold),
          prefixIcon: Icon(prefixIcon, color: const Color(0xFF94A3B8), size: 18),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF48C9B0), width: 1.5), // Kích hoạt đổi màu viền khi tương tác gõ chữ
          ),
        ),
      ),
    );
  }

  Widget _buildSaaSLockedField({required String label, required String value, required String badgeText}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC), // Tone màu nền xám mờ bảo vệ dữ liệu khóa
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: InkWell(
        onTap: () {
          // Đồng bộ SnackBar thô sơ cũ sang kiến trúc AppToast cao cấp
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
          // Khu vực UX: Tách biệt luồng Nhập văn bản & Xác thực bản đồ
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSaaSField(controller: _addressCtrl, label: 'Địa chỉ hoạt động', maxLines: 2),
              const SizedBox(height: 12),
              SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF48C9B0),
                        backgroundColor: const Color(0xFF48C9B0).withOpacity(0.05),
                        side: const BorderSide(color: Color(0xFF48C9B0), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _showLocationPickerBottomSheet,
                      icon: const Icon(Icons.location_on_rounded, size: 20),
                      label: Text(
                        _latitude != null ? 'Sửa điểm ghim trên bản đồ' : 'Xác nhận vị trí trên bản đồ', 
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Nhắc nhở Business Logic: Cần có Dịch vụ được duyệt để lên Bản đồ khám phá
                  if (_latitude != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline_rounded, color: Colors.orange, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Đã có tọa độ. Để cơ sở xuất hiện trên Bản đồ khám phá, hãy đảm bảo bạn có ít nhất 1 Dịch vụ ở trạng thái Đã duyệt.',
                              style: TextStyle(color: Color(0xFFD97706), fontSize: 12, height: 1.4),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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