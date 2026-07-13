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
import '../../../data/models/video_model.dart';
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
  List<dynamic> _savedItems = [];
  int _visibleSavesCount = 5;
  
  Map<String, dynamic> _stats = {'total_bookings': 0, 'response_rate': 100, 'reputation_points': 100};
  bool _isFetchingLock = false;

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

  Future<void> _loadPartnerData() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    if (mounted) setState(() => _isLoading = true);
    
    final results = await Future.wait([
      PartnerApiService.fetchMyServices().catchError((_) => []),
      PartnerApiService.fetchMyVideos().catchError((_) => []),
      UserApiService.fetchSavedItems().catchError((_) => []),
    ]);

    if (mounted) {
      setState(() {
        _myServices = results[0] as List<dynamic>;
        _myVideos = results[1] as List<dynamic>;
        _savedItems = results[2] as List<dynamic>;
        
        _stats = {
          'total_bookings': widget.profile['bookings_count'] ?? 0,
          'response_rate': 100,
          'reputation_points': widget.profile['reputation_points'] ?? 100
        };
        _isLoading = false;
      });
    }
    _isFetchingLock = false;
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
        _loadPartnerData();
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
    
    if (_latitude != null && _longitude != null) {
      payload['latitude'] = double.parse(_latitude!.toStringAsFixed(6));
      payload['longitude'] = double.parse(_longitude!.toStringAsFixed(6));
    }

    final success = await UserApiService.updateProfile(payload);
    setState(() => _isUpdatingProfile = false);
    
    if (success && mounted) {
      widget.onRefresh();
      _loadPartnerData();
      AppToast.show(context: context, message: 'Đã cập nhật hồ sơ doanh nghiệp!', isSuccess: true);
    }
  }

  void _showEditModal() {
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
                        child: Icon(Icons.business_center_outlined, color: _bizPrimary, size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Hồ sơ Đối tác', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu thông tin doanh nghiệp', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
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
                        _buildSaaSField(controller: _nameCtrl, label: 'Tên doanh nghiệp hiển thị'),
                        _buildSaaSField(controller: _usernameCtrl, label: 'Username định danh'),
                        _buildSaaSField(controller: _phoneCtrl, label: 'Số điện thoại', keyboardType: TextInputType.phone),
                        _buildSaaSLockedField(label: 'Email xác thực', value: widget.profile['email'] ?? '', badgeText: 'Bảo mật'),
                        _buildSaaSField(controller: _addressCtrl, label: 'Địa chỉ hoạt động', maxLines: 2),
                        const SizedBox(height: 4),
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
                            onPressed: () {
                              Navigator.pop(context);
                              _showLocationPickerBottomSheet();
                            },
                            icon: const Icon(Icons.location_on_rounded, size: 20),
                            label: Text(
                              _latitude != null ? 'Sửa điểm ghim trên bản đồ' : 'Xác nhận vị trí trên bản đồ', 
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildSaaSField(controller: _bioCtrl, label: 'Tiểu sử & Giới thiệu', maxLines: 3),
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
              child: Icon(icon, size: 16, color: _bizPrimary),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: _bizSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
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
                    color: isUnlocked ? const Color(0xFFE8F5E9) : const Color(0xFFF2F2F7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 18,
                    color: isUnlocked ? _bizPrimary : const Color(0xFF8E8E93),
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
                              color: isUnlocked ? _bizPrimary : const Color(0xFF8E8E93),
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
    final String avatarUrl = hasAvatar ? rawAvatar : 'https://ui-avatars.com/api/?name=${widget.profile['full_name']}&background=3b82f6&color=fff';

    final int reputation = widget.profile['reputation_points'] ?? 100;
    final int userLevel = (reputation / 200).floor() + 1;
    final int currentExp = reputation % 200;
    final double expPercent = currentExp / 200.0;
    
    String titleLevel = 'Cơ Sở Khởi Nghiệp';
    if (userLevel == 2) titleLevel = 'Đối Tác Đồng Hành';
    if (userLevel == 3) titleLevel = 'Trung Tâm Uy Tín';
    if (userLevel >= 4) titleLevel = 'Thương Hiệu Bảo Chứng';

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBF9),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD),
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
                icon: const Icon(Icons.smart_toy_rounded, color: Color(0xFF1A3A35), size: 22),
                onPressed: () async {
                  final String currentContext = widget.profile['partner_ai_context'] ?? '';
                  final result = await context.push<bool>('/partner-ai-context', extra: currentContext);
                  if (result == true) {
                    widget.onRefresh();
                    _loadPartnerData();
                  }
                },
                splashRadius: 20,
                tooltip: 'Huấn luyện AI',
              ),
              title: const Text('Hồ sơ Đối tác', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
              actions: [
                IconButton(
                  icon: Icon(Icons.edit_note_rounded, color: _bizPrimary, size: 24),
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
                            color: const Color(0xFF2196F3).withOpacity(0.1),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFE3F2FD).withOpacity(0.5),
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
                              child: Icon(Icons.add_photo_alternate_rounded, size: 18, color: _bizPrimary),
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
                                  boxShadow: [BoxShadow(color: _bizPrimary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8))],
                                  image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                                ),
                              ),
                              Positioned(
                                bottom: -12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors: [_bizSecondary, _bizPrimary]),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [BoxShadow(color: _bizPrimary.withOpacity(0.4), blurRadius: 10, offset: const Offset(0, 4))],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.business_center_rounded, color: Colors.white, size: 10),
                                      SizedBox(width: 4),
                                      Text('BUSINESS', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.6)),
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
                                    child: Icon(Icons.camera_alt_rounded, size: 13, color: _bizSecondary),
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
                            Text(widget.profile['full_name'] ?? 'Doanh nghiệp', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, color: _bizPrimary, size: 18),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('@${widget.profile['username'] ?? 'username'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),

                        () {
                          final int totalBookings = widget.profile['bookings_count'] ?? 0;
                          final int reputationPoints = widget.profile['reputation_points'] ?? 100;
                          final List<IconData> unlockedIcons = [];
                          
                          unlockedIcons.add(Icons.verified_user_rounded);
                          unlockedIcons.add(Icons.gavel_rounded); 
                          
                          if (totalBookings >= 10) unlockedIcons.add(Icons.star_rounded);
                          if (reputationPoints >= 150) unlockedIcons.add(Icons.diamond_rounded);
                          if (_myServices.length >= 5) unlockedIcons.add(Icons.local_mall_rounded);

                          final int totalUnlocked = unlockedIcons.length;
                          final List<IconData> displayBadges = unlockedIcons.take(3).toList();
                          final int hiddenCount = totalUnlocked - 3;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ...displayBadges.map((iconData) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE3F2FD),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _bizPrimary.withOpacity(0.2), width: 0.5),
                                  ),
                                  child: Icon(iconData, size: 13, color: _bizSecondary),
                                )),
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
                                        color: _bizSecondary,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        }(),

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
                              value: '${_myServices.length}',
                              label: 'Dịch vụ sàn',
                              icon: Icons.local_mall_rounded,
                              iconColor: _bizSecondary,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStatCard(
                              value: '${widget.profile['reputation_points'] ?? 100}',
                              label: 'Điểm uy tín',
                              icon: Icons.star_rounded,
                              iconColor: const Color(0xFFF59E0B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

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
                                        decoration: BoxDecoration(color: _bizPrimary, borderRadius: BorderRadius.circular(8)),
                                        child: Text('LV $userLevel', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w900)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(titleLevel, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                  Text('$currentExp / 200 EXP', style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: expPercent,
                                  backgroundColor: const Color(0xFFE3F2FD),
                                  valueColor: AlwaysStoppedAnimation<Color>(_bizPrimary),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

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
                                iconColor: const Color(0xFFF59E0B),
                                iconBg: const Color(0xFFFFF8E1),
                                title: 'Điểm uy tín tích lũy',
                                subtitle: 'Cơ sở phục vụ an toàn chuẩn y tế sàn',
                                value: widget.profile['reputation_points']?.toString() ?? '100',
                                onTap: () {},
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

                        InkWell(
                          onTap: () => context.push('/calendar'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_bizSecondary, _bizPrimary],
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
                                        _stats['total_bookings'] != null && _stats['total_bookings'] > 0
                                            ? 'Cơ sở có tổng cộng ${_stats['total_bookings']} hồ sơ đặt lịch'
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

                        InkWell(
                          onTap: () => context.push('/partner-dashboard'),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _bizPrimary.withOpacity(0.3), width: 1),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.space_dashboard_rounded, color: _bizSecondary, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Bảng điều khiển Studio Doanh nghiệp',
                                  style: TextStyle(color: _bizSecondary, fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: -0.2),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          child: Row(
                            children: [
                              _buildTabMenuButton(title: 'Dịch vụ', tabKey: 'services'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Studio', tabKey: 'studio'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Thành tựu', tabKey: 'achievements'),
                              const SizedBox(width: 6),
                              _buildTabMenuButton(title: 'Cá nhân', tabKey: 'info'),
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
                              backgroundColor: const Color(0xFFE3F2FD),
                              foregroundColor: _bizPrimary,
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
      floatingActionButton: Padding(
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
                        final currentRole = widget.profile['role'] ?? 'PARTNER';
                        context.push('/upload-studio', extra: currentRole.toString());
                      },
                      splashColor: const Color(0xFF80BF84).withOpacity(0.2),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.movie_creation_rounded, color: _bizSecondary, size: 20),
                      const Padding(
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
      ),
    );
  }

  Widget _buildDynamicTabBody(Map<String, dynamic> profile) {
    if (_activeTab == 'services') return _buildServicesTab();
    if (_activeTab == 'studio') return _buildStudioTab();
    if (_activeTab == 'info') return _buildInfoTab();
    
    if (_activeTab == 'saves') {
      if (_savedItems.isEmpty) return _buildEmptyBox(Icons.bookmark_border_rounded, 'Danh mục lưu trữ đang trống');
      return Column(
        children: _savedItems.take(_visibleSavesCount).map((item) {
          final String title = item['title'] ?? 'Nội dung chia sẻ sức khỏe';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2ECEB))),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled_rounded, color: Colors.blue, size: 22),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700))),
              ],
            ),
          );
        }).toList(),
      );
    }
    
    if (_activeTab == 'achievements') {
      final int totalBookings = profile['bookings_count'] ?? 0;
      final int reputationPoints = profile['reputation_points'] ?? 100;

      final bool isChuyenCanUnlocked = totalBookings >= 10;
      final bool isSieuSaoUnlocked = reputationPoints >= 150;
      final bool isYeuThichUnlocked = _myServices.length >= 5;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPremiumRowBadge(
              icon: Icons.verified_user_rounded,
              title: 'Chứng Nhận Sàn',
              desc: 'Hồ sơ doanh nghiệp y tế đã được xác minh tính chính danh và giấy phép.',
              progress: 'Hoàn thành',
              isUnlocked: true,
            ),
            _buildPremiumRowBadge(
              icon: Icons.star_rounded,
              title: 'Cơ Sở Tấp Nập',
              desc: 'Đạt cột mốc phục vụ tối thiểu 10 lượt đặt hẹn thành công trên sàn.',
              progress: '$totalBookings / 10 cuộc hẹn',
              isUnlocked: isChuyenCanUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.diamond_rounded,
              title: 'Thương Hiệu Vàng',
              desc: 'Tích lũy điểm uy tín hệ thống vượt mốc 150 điểm bảo chứng chất lượng.',
              progress: '$reputationPoints / 150 Điểm',
              isUnlocked: isSieuSaoUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.local_mall_rounded,
              title: 'Hệ Sinh Thái Đa Dạng',
              desc: 'Thiết lập danh mục phân phối dịch vụ đa tầng, tối thiểu 5 gói dịch vụ.',
              progress: '${_myServices.length} / 5 gói',
              isUnlocked: isYeuThichUnlocked,
            ),
            _buildPremiumRowBadge(
              icon: Icons.gavel_rounded,
              title: 'Cam Kết Chất Lượng',
              desc: 'Được bảo chứng tuyệt đối bởi ban kiểm duyệt với tỷ lệ phản hồi lịch hẹn đạt 100%.',
              progress: 'Đang ghim',
              isUnlocked: true,
              isLast: true,
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, 
              childAspectRatio: 9 / 16, 
              crossAxisSpacing: 8, 
              mainAxisSpacing: 8
            ),
            itemCount: _myServices.length,
            itemBuilder: (context, index) {
              final svc = _myServices[index];
              final bool isApproved = svc['status'] == 'APPROVED';
              
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Thumbnail nền dịch vụ
                      Container(
                        color: const Color(0xFFF7FBF9),
                        child: svc['image_url'] != null 
                            ? GlobalCacheImage(imageUrl: svc['image_url'], fit: BoxFit.cover)
                            : const Center(child: Icon(Icons.spa_outlined, color: Color(0xFFB0C4C1), size: 28)),
                      ),
                      
                      // Cụm action buttons lơ lửng góc trên bên phải (Tinh chỉnh layer)
                      Positioned(
                        top: 6, right: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              color: Colors.white.withOpacity(0.8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _showEditServiceModal(svc),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.edit_rounded, color: Color(0xFF64748B), size: 14),
                                      ),
                                    ),
                                  ),
                                  Container(width: 0.5, height: 12, color: const Color(0xFFE2ECEB)),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _handleDeleteService(svc['id']),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Khối thông tin và nhãn thông minh hạ tầng xuống đáy (Không bị đè)
                      Positioned(
                        bottom: 0, left: 0, right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.4), Colors.transparent],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                svc['service_name'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatCurrency(svc['price']),
                                style: TextStyle(color: _bizSecondary, fontSize: 11, fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 6),
                              
                              // Status Badge thông minh hạ tầng đáy
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isApproved ? const Color(0xFF48C9B0).withOpacity(0.2) : Colors.amber.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isApproved ? const Color(0xFF48C9B0) : Colors.amber,
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 4, height: 4,
                                      decoration: BoxDecoration(
                                        color: isApproved ? const Color(0xFF48C9B0) : Colors.amber,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isApproved ? 'Đã duyệt' : 'Chờ duyệt',
                                      style: TextStyle(
                                        color: isApproved ? const Color(0xFF48C9B0) : Colors.amber,
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 9/16, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemCount: _myVideos.length,
            itemBuilder: (context, index) {
              final v = _myVideos[index];
              final bool isApproved = v['status'] == 'APPROVED';
              
              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.5), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GestureDetector(
                    onTap: () {
                      final String currentStatus = v['status']?.toString().toUpperCase() ?? 'PENDING';
                      if (currentStatus == 'APPROVED' || currentStatus == 'PUBLISHED') {
                        final approvedVideos = _myVideos.where((vid) {
                          final st = vid['status']?.toString().toUpperCase() ?? 'PENDING';
                          return st == 'APPROVED' || st == 'PUBLISHED';
                        }).toList();
                        final int tappedIndex = approvedVideos.indexWhere((vid) => vid['id'] == v['id']);
                        final List<VideoModel> models = approvedVideos.map((json) {
                          final Map<String, dynamic> videoMap = Map<String, dynamic>.from(json);
                          // Tiêm bổ sung metadata của Private Profile vào thực thể map thô trước khi nạp model giải quyết dứt điểm lỗi khuyết tên/avatar
                          videoMap['author'] = {
                            'id': widget.profile['id'] ?? '',
                            'username': widget.profile['username'] ?? '',
                            'full_name': widget.profile['full_name'] ?? '',
                            'avatar_url': widget.profile['avatar_url'] ?? '',
                          };
                          return VideoModel.fromJson(videoMap);
                        }).toList();
                        
                        // Đóng gói tham số định tuyến kèm filter cách ly 'is_private_profile' để TikTokFeedsScreen kích hoạt Auto-Wakeup Engine chuẩn xác
                        context.push('/isolated-feed?filter=is_private_profile', extra: {
                          'videos': models,
                          'index': tappedIndex >= 0 ? tappedIndex : 0,
                        }).then((_) {
                          // Đồng bộ hóa tức thì trạng thái Like/Save ngược về lưới Private Profile khi Back trở ra
                          if (mounted) {
                            setState(() {});
                          }
                        });
                      } else {
                        AppToast.show(context: context, message: 'Video đang ở trạng thái chờ duyệt hoặc cần chỉnh sửa, chưa thể phát!', isSuccess: false);
                      }
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MiniVideoPlayer(videoUrl: v['video_url']),
                      
                      // Cụm action buttons dịch chuyển lên góc trên bên phải (Rút gọn khoảng cách tránh va chạm)
                      Positioned(
                        top: 6, right: 6,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              color: Colors.white.withOpacity(0.8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _showEditVideoModal(v),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.edit_rounded, color: Color(0xFF64748B), size: 14),
                                      ),
                                    ),
                                  ),
                                  Container(width: 0.5, height: 12, color: const Color(0xFFE2ECEB)),
                                  Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _handleDeleteVideo(v['id']),
                                      child: const Padding(
                                        padding: EdgeInsets.all(6),
                                        child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Khối thông tin vệt mờ dốc (Gradient) tích hợp đẩy nhãn Status xuống đáy an toàn
                      Positioned(
                        bottom: 0, left: 0, right: 0, 
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8), 
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter, 
                              end: Alignment.topCenter, 
                              colors: [Colors.black.withOpacity(0.85), Colors.black.withOpacity(0.3), Colors.transparent]
                            )
                          ), 
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                v['title'] ?? '', 
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.2), 
                                maxLines: 1, 
                                overflow: TextOverflow.ellipsis
                              ),
                              const SizedBox(height: 6),
                              
                              // Nhãn thông minh (Smart Status Badge) được ghim an toàn dưới đáy
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), 
                                decoration: BoxDecoration(
                                  color: isApproved ? const Color(0xFF48C9B0).withOpacity(0.2) : Colors.amber.withOpacity(0.2), 
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: isApproved ? const Color(0xFF48C9B0) : Colors.amber,
                                    width: 0.5,
                                  ),
                                ), 
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 4, height: 4,
                                      decoration: BoxDecoration(
                                        color: isApproved ? const Color(0xFF48C9B0) : Colors.amber,
                                        shape: BoxShape.circle
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isApproved ? 'Đã duyệt' : 'Chờ duyệt', 
                                      style: TextStyle(
                                        color: isApproved ? const Color(0xFF48C9B0) : Colors.amber, 
                                        fontSize: 8, 
                                        fontWeight: FontWeight.bold
                                      )
                                    ),
                                  ],
                                )
                              ),
                            ],
                          ),
                        )
                      ),
                    ],
                  ),
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
          const Text('Thông tin cơ sở đối tác', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _buildSaaSFieldDisabled(label: 'Tên doanh nghiệp', value: widget.profile['full_name'] ?? 'Chưa thiết lập tên', icon: Icons.business_rounded),
          _buildSaaSFieldDisabled(label: 'Giới thiệu', value: widget.profile['bio'] ?? 'Chưa thiết lập tiểu sử', icon: Icons.text_snippet_outlined),
          _buildSaaSFieldDisabled(label: 'Điện thoại cơ sở', value: widget.profile['phone'] ?? 'Chưa cập nhật', icon: Icons.phone_android_rounded),
          _buildSaaSFieldDisabled(label: 'Email bảo mật', value: widget.profile['email'] ?? 'Chưa liên kết email', icon: Icons.mail_lock_rounded),
          _buildSaaSFieldDisabled(label: 'Địa chỉ hoạt động', value: widget.profile['physical_address'] ?? 'Chưa cập nhật địa chỉ', icon: Icons.location_on_rounded),
          if (_latitude != null) ...[
            const SizedBox(height: 8),
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
                      'Cơ sở đã kích hoạt định vị. Để cơ sở xuất hiện trên Bản đồ khám phá, hãy đảm bảo bạn có ít nhất 1 Dịch vụ ở trạng thái Đã duyệt.',
                      style: TextStyle(color: Color(0xFFD97706), fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE3F2FD),
                foregroundColor: _bizPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                side: BorderSide(color: _bizPrimary.withOpacity(0.3), width: 1),
              ),
              onPressed: _showEditModal,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Chỉnh sửa thông tin đối tác', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            ),
          ),
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