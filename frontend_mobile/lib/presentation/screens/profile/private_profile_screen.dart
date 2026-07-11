import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/user_api_service.dart';
import '../../../data/services/secure_storage_service.dart';
import '../../widgets/guest_profile_view.dart';
import 'super_admin_profile_screen.dart'; 
import 'moderator_profile_screen.dart';
import 'package:go_router/go_router.dart';
import 'partner_profile_screen.dart'; 
import 'creator_profile_screen.dart';
import '../../widgets/auth_guard.dart';
import '../../widgets/glass_wrapper.dart';
import '../../widgets/app_toast.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/video_uploader.dart'; // Import bọc thép widget tải tệp
import '../../../core/network/api_client.dart'; // Import để gọi biểu mẫu đăng bài lên TikTokFeeds
import '../../widgets/mini_video_player.dart';


class PrivateProfileScreen extends StatefulWidget {
  const PrivateProfileScreen({super.key});

  @override
  State<PrivateProfileScreen> createState() => _PrivateProfileScreenState();
}

class _PrivateProfileScreenState extends State<PrivateProfileScreen> {
  final ImagePicker _picker = ImagePicker();
  
  bool _isLoading = true;
  Map<String, dynamic>? _profileData;
  List<dynamic> _savedItems = [];
  int _visibleSavesCount = 5; // Giới hạn hiển thị ban đầu tối đa 10 video đã lưu gần nhất
  
  // Mở rộng điều hướng phân tầng nội bộ: Đã chuyển đổi hiển thị mặc định sang Studio cá nhân chuẩn nghiệp vụ
  String _activeTab = 'studio';

  // Trạng thái quản lý bộ nhớ đệm Studio & Lazy Loading của User
  List<dynamic> _userVideos = [];
  bool _isLoadingStudio = false;
  bool _hasFetchedStudio = false;

  // Form Edit
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  bool _isUpdating = false;

  // Trạng thái bọc thép quản lý phân hệ Creator Upgrade Phase 3
  String? _upgradeStatus;
  String? _moderationNote;
  bool _isLoadingUpgradeState = false;
  bool _isSubmittingUpgradeRequest = false;
  String? _surveyAnswer;

  @override
  void initState() {
    super.initState();
    _loadData();
    _fetchUpgradeStatus();
  }

  // Hàm đồng bộ nạp trạng thái hồ sơ nâng cấp từ Backend API
  Future<void> _fetchUpgradeStatus() async {
    setState(() => _isLoadingUpgradeState = true);
    try {
      final res = await ApiClient.instance.get('/user/creator-upgrade/status');
      if (res.statusCode == 200 && res.data != null) {
        setState(() {
          _upgradeStatus = res.data['status'];
          _moderationNote = res.data['moderation_note'];
        });
      }
    } catch (_) {}
    setState(() => _isLoadingUpgradeState = false);
  }

  // Hàm kích hoạt luồng gửi đơn yêu cầu nâng cấp bọc thép
  Future<void> _submitUpgradeRequest() async {
    if (_surveyAnswer == null || !['Có', 'Rất có'].contains(_surveyAnswer)) return;
    setState(() => _isSubmittingUpgradeRequest = true);
    try {
      final res = await ApiClient.instance.post(
        '/user/creator-upgrade/request',
        data: {'reason_answer': _surveyAnswer},
      );
      if (res.statusCode == 200) {
        setState(() {
          _upgradeStatus = 'PENDING';
          _moderationNote = null;
        });
        if (mounted) {
          AppToast.show(context: context, message: 'Bạn đã nộp đơn yêu cầu nâng cấp thành công!', isSuccess: true);
        }
      } else {
        if (mounted) {
          AppToast.show(context: context, message: 'Gửi yêu cầu thất bại. Vui lòng kiểm tra lại điều kiện!', isSuccess: false);
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context: context, message: 'Lỗi kết nối máy chủ hệ thống!', isSuccess: false);
      }
    }
    setState(() => _isSubmittingUpgradeRequest = false);
  }

  bool _isFetchingLock = false;
  Future<void> _loadData() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    try {
      setState(() => _isLoading = true);
      
      // BỌC THÉP LOGIC: Đánh sập cờ cache bộ nhớ đệm Studio trước khi nạp để bảo đảm dữ liệu đếm video chuẩn xác 100%
      _hasFetchedStudio = false;

      final results = await Future.wait([
        UserApiService.fetchPrivateProfile(),
        UserApiService.fetchSavedItems(),
      ]);
      
      if (!mounted) return;
      setState(() {
        _profileData = results[0] as Map<String, dynamic>?;
        _savedItems = results[1] as List<dynamic>? ?? [];
        _isLoading = false;
      });

      // BỌC THÉP LOGIC: Tự động kéo lại danh sách video thật từ Server nếu tab hiện tại đang là Studio
      if (_activeTab == 'studio') {
        await _loadUserStudioIfNeeded();
      }
    } finally {
      _isFetchingLock = false;
    }
  }

  // Luồng Lazy Loading lấy danh sách Video Studio riêng của User
  Future<void> _loadUserStudioIfNeeded() async {
    if (_hasFetchedStudio || _isLoadingStudio) return;

    setState(() => _isLoadingStudio = true);
    try {
      final res = await ApiClient.instance.get('/user/my-tiktok-feeds');
      if (mounted && res.statusCode == 200) {
        setState(() {
          _userVideos = res.data['data'] ?? [];
          _hasFetchedStudio = true;
          _isLoadingStudio = false;
        });
      } else {
        if (mounted) setState(() => _isLoadingStudio = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingStudio = false);
    }
  }

  Future<void> _handleLogout() async {
    await AuthNotifier.instance.logout();
    setState(() {
      _profileData = null;
      _userVideos = [];
      _savedItems = [];
      _visibleSavesCount = 10;
      _hasFetchedStudio = false;
    });
  }

  Future<void> _pickAndUploadAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang xử lý ảnh đại diện...', isSuccess: true, duration: const Duration(seconds: 2));

    final url = await UserApiService.uploadMedia(File(image.path), 'users/avatars');
    if (url != null) {
      final success = await UserApiService.updateProfile({'avatar_url': url});
      if (success && mounted) {
        AppToast.show(context: context, message: 'Cập nhật ảnh đại diện thành công!', isSuccess: true);
        _loadData();
      } else if (mounted) {
        AppToast.show(context: context, message: 'Lỗi cập nhật hồ sơ!', isSuccess: false);
      }
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi tải ảnh lên máy chủ!', isSuccess: false);
    }
  }

  Future<void> _pickAndUploadCover() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (image == null) return;

    if (!mounted) return;
    AppToast.show(context: context, message: 'Đang xử lý ảnh bìa...', isSuccess: true, duration: const Duration(seconds: 2));

    final url = await UserApiService.uploadMedia(File(image.path), 'users/covers');
    if (url != null) {
      final success = await UserApiService.updateProfile({'cover_url': url});
      if (success && mounted) {
        AppToast.show(context: context, message: 'Cập nhật ảnh bìa thành công!', isSuccess: true);
        _loadData();
      } else if (mounted) {
        AppToast.show(context: context, message: 'Lỗi cập nhật hồ sơ!', isSuccess: false);
      }
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi tải ảnh lên máy chủ!', isSuccess: false);
    }
  }

  // Luồng hiển thị biểu mẫu đăng video phẳng Sleek Bottom Sheet không viền thiết kế riêng cho User
  void _showUserUploadVideoModal() {
    final titleCtrl = TextEditingController();
    String uploadedVideoUrl = '';
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 24, right: 24, top: 12
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(32))
            ),
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
                const Text('Chia sẻ video sức khỏe', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                const Text('Nội dung sẽ được đưa vào hàng đợi kiểm duyệt hệ thống.', style: TextStyle(color: Color(0xFF617D79), fontSize: 13)),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Vùng bọc tải tệp nét đứt phẳng
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7FBF9),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                          ),
                          child: Column(
                            children: [
                              const Icon(Icons.video_call_rounded, size: 32, color: Color(0xFF80BF84)),
                              const SizedBox(height: 12),
                              VideoUploader(
                                width: 130,
                                label: 'Chọn Video ngắn',
                                folder: 'tiktok_feeds/videos', // Đồng bộ thư mục lưu trữ đích hệ thống
                                onUploadSuccess: (url) {
                                  setModalState(() => uploadedVideoUrl = url);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Khung nhập liệu phẳng borderless
                        const Padding(
                          padding: EdgeInsets.only(left: 4, bottom: 8),
                          child: Text('Tiêu đề / Nội dung chia sẻ', style: TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
                          ),
                          child: TextField(
                            controller: titleCtrl,
                            maxLines: 3,
                            style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w500),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Nhập tiêu đề hoặc cảm nghĩ về sức khỏe của bạn...',
                              hintStyle: TextStyle(color: Color(0xFFB0C4C1), fontSize: 14),
                              contentPadding: EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                // Nút kích hoạt phẳng dưới đáy Bottom Sheet
                Container(
                  width: double.infinity,
                  height: 52,
                  margin: const EdgeInsets.only(bottom: 32),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      disabledBackgroundColor: const Color(0xFFD1D1D6)
                    ),
                    onPressed: isSubmitting ? null : () async {
                      if (uploadedVideoUrl.isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng chọn và đợi tải video lên xong!', isSuccess: false);
                        return;
                      }
                      if (titleCtrl.text.trim().isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng điền nội dung tiêu đề video!', isSuccess: false);
                        return;
                      }

                      setModalState(() => isSubmitting = true);
                      final payload = {
                        'title': titleCtrl.text.trim(),
                        'content': null,
                        'price': null, // Giới hạn quyền User: không cấu hình trường giá SaaS thương mại
                        'video_url': uploadedVideoUrl,
                      };

                      try {
                        final res = await ApiClient.instance.post('/tiktok/feeds', data: payload);
                        if (res.statusCode == 200) {
                          if (mounted) {
                            Navigator.pop(context);
                            
                            // Thuật toán cập nhật đón đầu (Optimistic Update) chống Race Condition của Backend Queue
                            final mockNewVideo = {
                              'id': 'mock_${DateTime.now().millisecondsSinceEpoch}',
                              'title': titleCtrl.text.trim(),
                              'status': 'PENDING',
                              'video_url': uploadedVideoUrl,
                              'created_at': DateTime.now().toIso8601String(),
                            };
                            
                            setState(() {
                              _userVideos.insert(0, mockNewVideo); // Chèn tức thì vào đầu lưới hiển thị UI
                              _hasFetchedStudio = false; // Đặt lại cờ cache để nạp chuẩn dữ liệu thật ở chu kỳ sau
                            });
                            
                            // BỌC THÉP LOGIC: Gọi lại luồng nạp dữ liệu gốc để tái đồng bộ số lượng video_count phục vụ luồng nâng cấp
                            _loadData();
                            
                            AppToast.show(context: context, message: 'Gửi video lên hàng đợi duyệt thành công!', isSuccess: true);
                          }
                        } else {
                          setModalState(() => isSubmitting = false);
                          if (mounted) AppToast.show(context: context, message: 'Lỗi gửi dữ liệu máy chủ!', isSuccess: false);
                        }
                      } catch (e) {
                        setModalState(() => isSubmitting = false);
                        if (mounted) AppToast.show(context: context, message: 'Kết nối thất bại!', isSuccess: false);
                      }
                    },
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('ĐĂNG BÀI CHỜ DUYỆT', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showEditModal() {
    final profile = _profileData?['profile'] ?? {};
    _nameController.text = profile['full_name'] ?? '';
    _usernameController.text = profile['username'] ?? '';
    _bioController.text = profile['bio'] ?? '';
    _phoneController.text = profile['phone'] ?? '';
    _emailController.text = profile['email'] ?? '';

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
                    width: 40, 
                    height: 5, 
                    decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(top: 12, left: 24, right: 16, bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F2F7),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white, 
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
                        ),
                        child: const Icon(Icons.person_outline_rounded, color: Color(0xFF1C1C1E), size: 24),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('Hồ sơ cá nhân', style: TextStyle(color: Color(0xFF1C1C1E), fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
                            SizedBox(height: 4),
                            Text('Cập nhật dữ liệu hệ thống', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(color: Color(0xFFE5E5EA), shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, color: Color(0xFF8E8E93), size: 18),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
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
                        _buildSaaSField(controller: _nameController, label: 'Tên hiển thị'),
                        const SizedBox(height: 24),
                        _buildSaaSField(controller: _usernameController, label: 'Tên đăng nhập'),
                        const SizedBox(height: 24),
                        _buildSaaSField(controller: _phoneController, label: 'Số điện thoại', keyboardType: TextInputType.phone),
                        const SizedBox(height: 24),
                        _buildSaaSLockedField(label: 'Email xác thực', value: _emailController.text, badgeText: 'Bảo mật'),
                        const SizedBox(height: 24),
                        _buildSaaSField(controller: _bioController, label: 'Tiểu sử / Giới thiệu', maxLines: 3),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 32),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -4))],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          backgroundColor: const Color(0xFFF2F2F7),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text('Hủy bỏ', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isUpdating ? null : () async {
                          final name = _nameController.text.trim();
                          final uname = _usernameController.text.trim();
                          final phone = _phoneController.text.trim();

                          if (name.isEmpty || uname.isEmpty || phone.isEmpty) {
                            AppToast.show(context: context, message: 'Tên, Username và SĐT không được để trống!', isSuccess: false);
                            return;
                          }

                          setModalState(() => _isUpdating = true);
                          
                          final success = await UserApiService.updateProfile({
                            'full_name': name,
                            'username': uname,
                            'bio': _bioController.text.trim(),
                            'phone': phone,
                          });
                          
                          if (success && mounted) {
                            Navigator.pop(context);
                            _loadData();
                            AppToast.show(context: context, message: 'Đã lưu thay đổi hồ sơ', isSuccess: true);
                          } else if (mounted) {
                            setModalState(() => _isUpdating = false);
                            AppToast.show(context: context, message: 'Cập nhật thất bại. Username có thể đã tồn tại!', isSuccess: false);
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1C1C1E),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          disabledBackgroundColor: const Color(0xFFD1D1D6),
                        ),
                        child: _isUpdating 
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                            : const Text('Lưu thay đổi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
            border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
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

  Widget _buildSaaSFieldDisabled({required String label, required String value, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 16, color: const Color(0xFF617D79)),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  value, 
                  style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 3, 
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
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
            AppToast.show(context: context, message: 'Trường dữ liệu này đã được hệ thống bảo vệ.', isSuccess: false);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
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
                    border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
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

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => Scaffold(backgroundColor: const Color(0xFFF7FBF9), body: GuestProfileView(onSuccess: () async { await AuthNotifier.instance.refresh(); _loadData(); })),
      builder: (context, token, userId) {
        if (_isLoading) {
          return Scaffold(
            backgroundColor: const Color(0xFFF7FBF9),
            body: ShimmerWrapper(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  children: [
                    Container(height: 192, color: const Color(0xFFE2ECEB)),
                    const SizedBox(height: 16),
                    Container(height: 24, width: 120, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                    const SizedBox(height: 32),
                    Container(margin: const EdgeInsets.symmetric(horizontal: 24), height: 200, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32))),
                    const SizedBox(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (index) => Container(margin: const EdgeInsets.symmetric(horizontal: 6), height: 80, width: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)))),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final role = _profileData?['profile']?['role'] ?? 'USER';
        if (role == 'SUPER_ADMIN') {
          return SuperAdminProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'MODERATOR') {
          return ModeratorProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'PARTNER' || role == 'PARTNER_ADMIN') {
          return PartnerProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }
        if (role == 'CREATOR') {
          return CreatorProfileScreen(
            profile: _profileData?['profile'] ?? {}, 
            onLogout: _handleLogout, 
            onRefresh: _loadData
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFFF7FBF9),
          body: _buildPrivateProfile(),
          // Tinh chỉnh tối giản: Gỡ bỏ chiều rộng tĩnh, kích hoạt luồng tự động co giãn ôm khít tự nhiên (Intrinsic Fit)
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: 102.0, right: 6),
            child: Container(
              height: 52, // Giữ nguyên chiều cao chuẩn mực của một Capsule Button cao cấp
              decoration: BoxDecoration(
                color: const Color(0xFF1A3A35), // Sắc xanh rêu Wellness sâu lắng thương hiệu
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1A3A35).withOpacity(0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                    final currentVerifiedRole = _profileData?['profile']?['role'] ?? 'USER';
                    context.push('/upload-studio', extra: currentVerifiedRole.toString());
                  },
                  splashColor: const Color(0xFF80BF84).withOpacity(0.2),
                    highlightColor: Colors.transparent,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20), // Tạo khoảng đệm lót đối xứng giúp nút tự co giãn hoàn hảo theo chữ
                      child: Row(
                        mainAxisSize: MainAxisSize.min, // Cưỡng ép Row chỉ chiếm vừa đủ diện tích của các phần tử con
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            Icons.movie_creation_rounded, // Biểu tượng truyền thông điện ảnh thể hiện luồng Đăng tải video ngắn
                            color: Color(0xFF80BF84), // Màu sắc xanh sương mai hữu cơ mát lành
                            size: 20,
                          ),
                          Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Text(
                              "Sáng tạo ngay", // Chữ thể hiện thông điệp hành động trang nhã cao cấp
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
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
      },
    );
  }

  Widget _buildPrivateProfile() {
    final profile = _profileData?['profile'] ?? {};
    final stats = _profileData?['stats'] ?? {};
    final avatarUrl = profile['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${profile['full_name'] ?? 'NU'}&background=80BF84&color=fff';
    
    final String? rawCover = profile['cover_url'] != null && profile['cover_url'].toString().trim().isNotEmpty 
        ? '${profile['cover_url']}?w=800&q=70' 
        : null;
    final bool hasCover = rawCover != null;

    final int balance = profile['svalue_balance'] ?? 0;
    final int userLevel = (balance / 400).floor() + 1;
    final int currentExp = balance % 400;
    final double expPercent = currentExp / 400.0;
    
    String titleLevel = 'Tập Sự Sức Khỏe';
    if (userLevel == 2) titleLevel = 'Chiến Sĩ Thể Chất';
    if (userLevel == 3) titleLevel = 'Đại Sứ Wellness';
    if (userLevel >= 4) titleLevel = 'Kiện Tướng Sinh Học';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          backgroundColor: const Color(0xFFF7FBF9),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          pinned: true,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20),
            onPressed: () {
              AppToast.show(context: context, message: 'Màn hình gốc không thể quay lại.', isSuccess: false);
            },
            splashRadius: 20,
          ),
          title: const Text('Hồ sơ', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.5)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF1A3A35), size: 24),
              onPressed: _showEditModal,
              splashRadius: 20,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 22), 
              onPressed: _handleLogout,
              splashRadius: 20,
            ),
            const SizedBox(width: 8),
          ],
        ),

        SliverToBoxAdapter(
          child: Column(
            children: [
              SizedBox(
                height: 192,
                child: Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8F5E9),
                            image: hasCover ? DecorationImage(image: GlobalCacheProvider.create(rawCover, maxWidth: 800, maxHeight: 600), fit: BoxFit.cover) : null,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  const Color(0xFFF7FBF9).withOpacity(0.5),
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
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.8),
                                shape: BoxShape.circle,
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                              ),
                              child: const Icon(Icons.add_photo_alternate_rounded, size: 18, color: Color(0xFF1A3A35)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 88,
                      child: Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 104, height: 104,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                              boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.8), blurRadius: 24, offset: const Offset(0, 8))],
                              image: DecorationImage(image: GlobalCacheProvider.create(avatarUrl, maxWidth: 300, maxHeight: 300), fit: BoxFit.cover),
                            ),
                          ),
                          GestureDetector(
                            onTap: _pickAndUploadAvatar,
                            child: Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFF7FBF9), width: 2),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
                              ),
                              child: const Icon(Icons.camera_alt_rounded, size: 13, color: Color(0xFF80BF84)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(profile['full_name'] ?? 'Thành viên mới', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('@${profile['username'] ?? 'username'}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 4))],
                        border: Border.all(color: const Color(0xFFE2ECEB).withOpacity(0.5), width: 1),
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
                                    decoration: BoxDecoration(color: const Color(0xFF80BF84), borderRadius: BorderRadius.circular(8)),
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
                              backgroundColor: const Color(0xFFF0F4F2),
                              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF80BF84)),
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
                            iconColor: const Color(0xFF4CAF50),
                            iconBg: const Color(0xFFE8F5E9),
                            title: 'SValue & Ví Voucher',
                            subtitle: 'Chuỗi điểm danh ${profile['streak_count'] ?? 0} ngày liên tiếp',
                            value: profile['svalue_balance']?.toString() ?? '0',
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

                    InkWell(
                      onTap: () => context.push('/calendar'),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF1A3A35), Color(0xFF2A5951)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4))],
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
                                    stats['bookings_count'] != null && stats['bookings_count'] > 0
                                        ? 'Bạn có tổng cộng ${stats['bookings_count']} hồ sơ theo dõi lịch trình'
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
                    const SizedBox(height: 24),

                    // Tái cấu trúc bọc cuộn chống Overflowed và tích hợp Animation lấp lánh sắc Hồng thương hiệu Creator
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildTabMenuButton(title: 'Studio', tabKey: 'studio'),
                          const SizedBox(width: 6),
                          _buildTabMenuButton(title: 'Thành tựu', tabKey: 'achievements'),
                          const SizedBox(width: 6),
                          _buildTabMenuButton(title: 'Cá nhân', tabKey: 'history'),
                          const SizedBox(width: 6),
                          
                          // Thiết lập nút Nâng cấp bọc thép hiệu ứng luồng sáng chéo Gradient Premium chạy vô hạn
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: -1.0, end: 2.0),
                            duration: const Duration(milliseconds: 2500),
                            builder: (context, alignmentOffset, child) {
                              final bool isSelected = _activeTab == 'upgrade';
                              
                              // Thiết lập mảng màu dải sáng chéo Premium chèn giữa nền Hồng Creator
                              final List<Color> activeGradientColors = [
                                const Color(0xFFFF6B8B),
                                const Color(0xFFFF8EAA),
                                Colors.white.withOpacity(0.8), // Điểm giao thoa ánh sáng chéo lấp lánh cực đỉnh
                                const Color(0xFFFF8EAA),
                                const Color(0xFFFF6B8B),
                              ];

                              final List<Color> inactiveGradientColors = [
                                const Color(0xFFFF6B8B).withOpacity(0.08),
                                const Color(0xFFFF8EAA).withOpacity(0.2),
                                const Color(0xFFFFD6DA).withOpacity(0.6), // Dải sáng chéo mờ thanh lịch khi chưa chọn
                                const Color(0xFFFF8EAA).withOpacity(0.2),
                                const Color(0xFFFF6B8B).withOpacity(0.08),
                              ];

                              return GestureDetector(
                                onTap: () {
                                  setState(() => _activeTab = 'upgrade');
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
                                      color: isSelected 
                                          ? const Color(0xFFFF4B72) 
                                          : const Color(0xFFFF6B8B).withOpacity(0.4),
                                      width: 1.2,
                                    ),
                                    boxShadow: isSelected ? [
                                      BoxShadow(
                                        color: const Color(0xFFFF6B8B).withOpacity(0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      )
                                    ] : null,
                                  ),
                                  child: Text(
                                    'Nâng cấp',
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : const Color(0xFFFF4B72),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              );
                            },
                            onEnd: () {
                              // Chạy cơ chế khởi động lại luồng lập lịch lặp vô hạn (Infinite Loop Auto-Restart)
                              setState(() {});
                            },
                          ),
                          const SizedBox(width: 6),
                          _buildTabMenuButton(title: 'Đã lưu', tabKey: 'saves'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    _buildDynamicTabBody(profile),
                    
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 24, bottom: 130),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE8F5E9),
                          foregroundColor: const Color(0xFF1A3A35),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: () {
                          final username = profile['username'];
                          if (username != null && username.toString().trim().isNotEmpty) {
                            context.push('/public-profile/$username');
                          } else {
                            AppToast.show(context: context, message: 'Vui lòng bổ sung Tên đăng nhập để công khai hồ sơ!', isSuccess: false);
                            _showEditModal();
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
      onTap: () {
        setState(() => _activeTab = tabKey);
        if (tabKey == 'studio') {
          _loadUserStudioIfNeeded(); // Kích hoạt nạp trễ an toàn
        }
      },
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

  Widget _buildDynamicTabBody(Map<String, dynamic> profile) {
    if (_activeTab == 'saves') {
      if (_savedItems.isEmpty) {
        return _buildEmptyBox(icon: Icons.bookmark_border_rounded, message: 'Danh mục lưu trữ đang trống');
      }
      
      final displayedItems = _savedItems.take(_visibleSavesCount).toList();
      final bool hasMore = _savedItems.length > _visibleSavesCount;
      
      return Column(
        children: [
          ...displayedItems.map((item) => _buildSavedItemCard(item)),
          if (hasMore) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFE2ECEB), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  foregroundColor: const Color(0xFF1A3A35),
                  backgroundColor: Colors.white,
                  elevation: 0,
                ),
                onPressed: () {
                  setState(() {
                    _visibleSavesCount++; // Tải thêm đúng 1 video tiếp theo từ mảng cache
                  });
                },
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18, color: Color(0xFF80BF84)),
                label: Text(
                  'Xem thêm nội dung (${_savedItems.length - _visibleSavesCount} còn lại)',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.2),
                ),
              ),
            ),
          ],
        ],
      );
    }
    
    if (_activeTab == 'achievements') {
      final int streak = profile['streak_count'] ?? 0;
      final int balance = profile['svalue_balance'] ?? 0;
      
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Huy chương cá nhân đạt được', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
              children: [
                _buildBadgeItem(Icons.verified_user_rounded, 'Khởi Đầu Vàng', 'Đăng ký tài khoản', true),
                _buildBadgeItem(Icons.local_fire_department_rounded, 'Chuyên Cần', 'Điểm danh 7 ngày', streak >= 7),
                _buildBadgeItem(Icons.health_and_safety_rounded, 'Thần Nông', 'Tích lũy >500 SValue', balance >= 500),
              ],
            ),
          ],
        ),
      );
    }

    // Kết xuất giao diện phân hệ Tab Studio cá nhân phẳng mượt của User phổ thông
    if (_activeTab == 'studio') {
      if (_isLoadingStudio) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))),
        );
      }
      return Column(
        children: [
          if (_userVideos.isEmpty)
            _buildEmptyBox(icon: Icons.video_library_outlined, message: 'Studio chưa có video chia sẻ')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 9 / 16,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _userVideos.length,
              itemBuilder: (context, index) {
                final v = _userVideos[index];
                final String status = v['status']?.toString() ?? 'PENDING';
                
                Color badgeBgColor;
                Color dotColor;
                Color textColor;
                String statusText;

                switch (status.toUpperCase()) {
                  case 'APPROVED':
                  case 'PUBLISHED':
                    badgeBgColor = const Color(0xFFE8F5E9).withOpacity(0.9);
                    dotColor = const Color(0xFF48C9B0);
                    textColor = const Color(0xFF1A3A35);
                    statusText = '';
                    break;
                  case 'PENDING_EDIT':
                    badgeBgColor = const Color(0xFFE3F2FD).withOpacity(0.9);
                    dotColor = Colors.blue.shade600;
                    textColor = Colors.blue.shade900;
                    statusText = '';
                    break;
                  case 'PENDING_DELETE':
                    badgeBgColor = const Color(0xFFFFEBEE).withOpacity(0.9);
                    dotColor = Colors.red.shade600;
                    textColor = Colors.red.shade900;
                    statusText = 'Chờ duyệt xóa';
                    break;
                  case 'PENDING':
                  default:
                    badgeBgColor = const Color(0xFFFFF8E1).withOpacity(0.9);
                    dotColor = Colors.amber.shade700;
                    textColor = Colors.amber.shade900;
                    statusText = '';
                    break;
                }

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
                        MiniVideoPlayer(videoUrl: v['video_url'] ?? ''),
                        Positioned(
                          top: 10, left: 10,
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
                                    color: dotColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  statusText,
                                  style: TextStyle(color: textColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10, right: 10,
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
                                    onTap: () {
                                      final titleCtrl = TextEditingController(text: v['title']?.toString() ?? '');
                                      bool isSubmitting = false;

                                      showModalBottomSheet(
                                        context: context,
                                        isScrollControlled: true,
                                        useRootNavigator: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) => StatefulBuilder(
                                          builder: (context, setModalState) {
                                            return Container(
                                              height: MediaQuery.of(context).size.height * 0.6,
                                              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 12),
                                              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Center(child: Container(width: 40, height: 5, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(100)))),
                                                  const Text('Sửa thông tin video', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 20, fontWeight: FontWeight.w800)),
                                                  const SizedBox(height: 24),
                                                  Expanded(
                                                    child: SingleChildScrollView(
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          const Padding(padding: EdgeInsets.only(left: 4, bottom: 8), child: Text('Tiêu đề / Nội dung chia sẻ', style: TextStyle(color: Color(0xFF617D79), fontSize: 13, fontWeight: FontWeight.bold))),
                                                          Container(
                                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE5E5EA), width: 1)),
                                                            child: TextField(
                                                              controller: titleCtrl,
                                                              maxLines: 3,
                                                              style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w500),
                                                              decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.all(16)),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    width: double.infinity,
                                                    height: 52,
                                                    margin: const EdgeInsets.only(bottom: 32),
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A3A35), foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                                                      onPressed: isSubmitting ? null : () async {
                                                        if (titleCtrl.text.trim().isEmpty) {
                                                          AppToast.show(context: context, message: 'Vui lòng điền nội dung tiêu đề!', isSuccess: false);
                                                          return;
                                                        }
                                                        setModalState(() => isSubmitting = true);
                                                        try {
                                                          final res = await ApiClient.instance.patch('/user/my-tiktok-feeds/${v['id']}', data: {'title': titleCtrl.text.trim()});
                                                          if (res.statusCode == 200) {
                                                            Navigator.pop(context);
                                                            _hasFetchedStudio = false;
                                                            _loadUserStudioIfNeeded();
                                                            AppToast.show(context: context, message: 'Yêu cầu sửa đổi đã gửi lên hàng đợi duyệt!', isSuccess: true);
                                                          } else {
                                                            setModalState(() => isSubmitting = false);
                                                            AppToast.show(context: context, message: 'Lỗi đồng bộ dữ liệu!', isSuccess: false);
                                                          }
                                                        } catch (e) {
                                                          setModalState(() => isSubmitting = false);
                                                          AppToast.show(context: context, message: 'Kết nối máy chủ thất bại!', isSuccess: false);
                                                        }
                                                      },
                                                      child: isSubmitting ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('LƯU THAY ĐỔI', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      );
                                    },
                                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.edit_rounded, color: Color(0xFF64748B), size: 16)),
                                  ),
                                ),
                                Container(width: 1, height: 16, color: const Color(0xFFE2ECEB)),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          elevation: 0,
                                          child: Container(
                                            padding: const EdgeInsets.all(32),
                                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: Colors.white, width: 2), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.08), blurRadius: 32, offset: const Offset(0, 16))]),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: const Color(0xFFFFF0F2), shape: BoxShape.circle), child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE63946), size: 36)),
                                                const SizedBox(height: 24),
                                                const Text('Gỡ Video', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 22, fontWeight: FontWeight.w900)),
                                                const SizedBox(height: 12),
                                                const Text('Bạn muốn gỡ video này khỏi Studio?\nYêu cầu sẽ được chuyển đến người kiểm duyệt.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 15, height: 1.5)),
                                                const SizedBox(height: 32),
                                                Row(
                                                  children: [
                                                    Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFF7FBF9), foregroundColor: const Color(0xFF617D79)), onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(fontWeight: FontWeight.bold)))),
                                                    const SizedBox(width: 12),
                                                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), backgroundColor: const Color(0xFFE63946), foregroundColor: Colors.white, elevation: 0), onPressed: () => Navigator.pop(context, true), child: const Text('Gỡ ngay', style: TextStyle(fontWeight: FontWeight.bold)))),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                      if (confirm == true) {
                                        try {
                                          final res = await ApiClient.instance.delete('/user/my-tiktok-feeds/${v['id']}');
                                          if (res.statusCode == 200) {
                                            _hasFetchedStudio = false;
                                            _loadUserStudioIfNeeded();
                                            
                                            // BỌC THÉP LOGIC: Gọi lại luồng nạp dữ liệu gốc để làm sạch trường đếm video_count, chặn đứng lỗ hổng Client-Side Bypass
                                            _loadData();
                                            
                                            AppToast.show(context: context, message: 'Đã gửi yêu cầu gỡ video chờ duyệt!', isSuccess: true);
                                          } else {
                                            AppToast.show(context: context, message: 'Lỗi thực thi lệnh gỡ!', isSuccess: false);
                                          }
                                        } catch (e) {
                                          AppToast.show(context: context, message: 'Lỗi kết nối máy chủ!', isSuccess: false);
                                        }
                                      }
                                    },
                                    child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0, left: 0, right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 32, 12, 12),
                            decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
                            child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
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
    
    if (_activeTab == 'upgrade') {
      if (_isLoadingUpgradeState) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))),
        );
      }

      // NÂNG CẤP THUẬT TOÁN BỌC THÉP: Đếm trực tiếp các video có nhãn trạng thái Đã duyệt trong mảng Studio
      final int videoCount = _userVideos.where((v) {
        final String status = (v['status'] ?? '').toString().toUpperCase();
        return status == 'APPROVED' || status == 'PUBLISHED';
      }).length;

      final int streakCount = profile['streak_count'] ?? 0;

      final bool condVideos = videoCount >= 5;
      final bool condStreak = streakCount >= 3;
      final bool hasSurveySelected = _surveyAnswer != null && ['Có', 'Rất có'].contains(_surveyAnswer);
      final bool isFormQualified = condVideos && condStreak && hasSurveySelected;

      final String displayName = profile['full_name'] ?? 'Bạn';

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: const Color(0xFFE2ECEB).withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_upgradeStatus == 'REJECTED') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF0F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFD6DA)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Yêu cầu nâng cấp lên Creator của bạn đã bị từ chối bởi kiểm duyệt viên. Vui lòng nhấn Xem lý do để biết thêm chi tiết.',
                        style: TextStyle(color: Colors.red.shade900, fontSize: 13, fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Text('Điều kiện nâng cấp Creator', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 15, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),

            // Dòng kiểm tra điều kiện đăng tải video
            Row(
              children: [
                Icon(condVideos ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: condVideos ? const Color(0xFF80BF84) : const Color(0xFFB0C4C1), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Đăng tải tối thiểu 5 video ngắn (Chỉ tính các video đã được duyệt thành công) (Hiện tại: $videoCount/5)', style: TextStyle(color: const Color(0xFF1A3A35), fontSize: 13.5, fontWeight: condVideos ? FontWeight.w600 : FontWeight.w400)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Icon(condStreak ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: condStreak ? const Color(0xFF80BF84) : const Color(0xFFB0C4C1), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Điểm danh liên tục tối thiểu 3 ngày (Hiện tại: $streakCount/3 ngày)', style: TextStyle(color: const Color(0xFF1A3A35), fontSize: 13.5, fontWeight: condStreak ? FontWeight.w600 : FontWeight.w400)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: Color(0xFFE2ECEB)),
            const SizedBox(height: 16),

            Text('$displayName có yêu VN Share không?', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(
              children: [
                Radio<String>(
                  value: 'Có',
                  groupValue: _surveyAnswer,
                  activeColor: const Color(0xFF1A3A35),
                  onChanged: _upgradeStatus == 'PENDING' ? null : (val) => setState(() => _surveyAnswer = val),
                ),
                const Text('Có', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 14)),
                const SizedBox(width: 24),
                Radio<String>(
                  value: 'Rất có',
                  groupValue: _surveyAnswer,
                  activeColor: const Color(0xFF1A3A35),
                  onChanged: _upgradeStatus == 'PENDING' ? null : (val) => setState(() => _surveyAnswer = val),
                ),
                const Text('Rất có 🇻🇳', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 14)),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: _upgradeStatus == 'PENDING'
                  ? ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFF8E1),
                        disabledBackgroundColor: const Color(0xFFFFF8E1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.amber.shade800, strokeWidth: 2)),
                          const SizedBox(width: 10),
                          Text('ĐANG CHỜ DUYỆT HỒ SƠ...', style: TextStyle(color: Colors.amber.shade900, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ],
                      ),
                    )
                  : _upgradeStatus == 'REJECTED'
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: () {
                            // Gọi Pop-up hiển thị lý do bọc GlassWrapper cao cấp an toàn tham số
                            showDialog(
                              context: context,
                              builder: (context) => Dialog(
                                backgroundColor: Colors.transparent,
                                elevation: 0,
                                child: GlassWrapper(
                                  child: Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.9),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: const BoxDecoration(color: Color(0xFFFFEBEE), shape: BoxShape.circle),
                                          child: const Icon(Icons.gavel_rounded, color: Colors.redAccent, size: 28),
                                        ),
                                        const SizedBox(height: 16),
                                        const Text('Lý do từ chối nâng cấp', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
                                        const SizedBox(height: 12),
                                        Text(
                                          _moderationNote ?? 'Kiểm duyệt viên từ chối hồ sơ của bạn nhưng không để lại ghi chú chi tiết.',
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(color: Color(0xFF617D79), fontSize: 14, height: 1.5, fontWeight: FontWeight.w500),
                                        ),
                                        const SizedBox(height: 24),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton(
                                                style: TextButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  backgroundColor: const Color(0xFFF2F2F7),
                                                ),
                                                onPressed: () => Navigator.pop(context),
                                                child: const Text('Tôi đã hiểu', style: TextStyle(color: Color(0xFF617D79), fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  backgroundColor: const Color(0xFF1A3A35),
                                                  foregroundColor: Colors.white,
                                                  elevation: 0,
                                                ),
                                                onPressed: !isFormQualified ? null : () {
                                                  Navigator.pop(context);
                                                  _submitUpgradeRequest();
                                                },
                                                child: const Text('Gửi lại yêu cầu', style: TextStyle(fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: const Text('XEM LÝ DO', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        )
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A3A35),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFFD1D1D6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          onPressed: (!isFormQualified || _isSubmittingUpgradeRequest)
                              ? null
                              : () async {
                                  final bool? confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => Dialog(
                                      backgroundColor: Colors.transparent,
                                      elevation: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28)),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(padding: const EdgeInsets.all(14), decoration: const BoxDecoration(color: Color(0xFFE8F5E9), shape: BoxShape.circle), child: const Icon(Icons.rocket_launch_rounded, color: Color(0xFF80BF84), size: 28)),
                                            const SizedBox(height: 16),
                                            const Text('Xác nhận nộp đơn', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
                                            const SizedBox(height: 10),
                                            const Text('Bạn có chắc chắn muốn gửi yêu cầu nâng cấp lên tài khoản Creator lên sàn VN Share không?', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF617D79), fontSize: 14, height: 1.4)),
                                            const SizedBox(height: 24),
                                            Row(
                                              children: [
                                                Expanded(child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: const Color(0xFFF7FBF9)), onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF617D79), fontWeight: FontWeight.bold)))),
                                                const SizedBox(width: 12),
                                                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), backgroundColor: const Color(0xFF1A3A35), foregroundColor: Colors.white, elevation: 0), onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận', style: TextStyle(fontWeight: FontWeight.bold)))),
                                              ],
                                            )
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                  if (confirm == true) {
                                    _submitUpgradeRequest();
                                  }
                                },
                          child: _isSubmittingUpgradeRequest
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('NÂNG CẤP TÀI KHOẢN', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Thông tin cá nhân', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _buildSaaSFieldDisabled(label: 'Giới thiệu', value: profile['bio'] ?? 'Chưa thiết lập tiểu sử', icon: Icons.text_snippet_outlined),
          _buildSaaSFieldDisabled(label: 'Điện thoại', value: profile['phone'] ?? 'Chưa cập nhật', icon: Icons.phone_android_rounded),
          _buildSaaSFieldDisabled(label: 'Email bảo mật', value: profile['email'] ?? 'Chưa liên kết email', icon: Icons.mail_lock_rounded),
        ],
      ),
    );
  }

  Widget _buildBadgeItem(IconData icon, String title, String desc, bool isUnlocked) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isUnlocked ? const Color(0xFFF7FBF9) : const Color(0xFFF2F2F7).withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUnlocked ? const Color(0xFFE2ECEB) : Colors.transparent, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: isUnlocked ? const Color(0xFF80BF84) : const Color(0xFFB0C4C1)),
          const SizedBox(height: 6),
          Text(title, style: TextStyle(color: isUnlocked ? const Color(0xFF1A3A35) : const Color(0xFFB0C4C1), fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(desc, style: const TextStyle(color: Color(0xFF617D79), fontSize: 9), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildEmptyBox({required IconData icon, required String message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
      child: Column(
        children: [
          Icon(icon, size: 40, color: const Color(0xFFE2ECEB)),
          const SizedBox(height: 10),
          Text(message, style: const TextStyle(color: Color(0xFFB0C4C1), fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildSavedItemCard(Map<String, dynamic> item) {
    final author = item['author'] ?? {};
    final String title = item['title'] ?? 'Nội dung chia sẻ sức khỏe';
    final String authorName = author['full_name'] ?? author['username'] ?? 'Chuyên gia';
    final String authorAvatar = author['avatar_url'] ?? 'https://ui-avatars.com/api/?name=$authorName&background=80BF84&color=fff';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2ECEB).withOpacity(0.7), width: 1),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            AppToast.show(context: context, message: 'Tính năng xem chi tiết bài đăng đang phát triển.', isSuccess: true);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7FBF9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                  ),
                  child: const Center(child: Icon(Icons.play_circle_filled_rounded, color: Color(0xFF80BF84), size: 22)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          CircleAvatar(radius: 7, backgroundImage: GlobalCacheProvider.create(authorAvatar, maxWidth: 100, maxHeight: 100)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(authorName, style: const TextStyle(color: Color(0xFF617D79), fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFB0C4C1), size: 14),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}