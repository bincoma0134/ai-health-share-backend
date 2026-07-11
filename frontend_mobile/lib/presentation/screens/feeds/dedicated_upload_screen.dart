import 'package:flutter/material.dart';
import 'dart:io'; // Giải quyết lỗi: 'File' isn't defined
import 'dart:math' as math;
import 'package:video_player/video_player.dart'; // Giải quyết lỗi: Undefined name 'VideoPlayerController'
import '../../widgets/video_uploader.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/feed_video_player.dart'; // 🚀 HOTFIX: Thêm import để định nghĩa lớp điều khiển tĩnh FeedVideoPool
import '../../../data/services/user_api_service.dart'; // 🚀 MỚI: Cổng truyền stream nhị phân lên Cloud Storage
import '../../../core/network/api_client.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart'; // Import lõi phần cứng hệ điều hành
import 'package:permission_handler/permission_handler.dart'; // Thư viện xin quyền hệ thống chuẩn
import 'package:video_compress/video_compress.dart'; // 🚀 HOTFIX: Thêm thư viện nén để nhận diện MediaInfo và VideoCompress
import '../../../core/manager/audio_focus_manager.dart';
import 'package:dio/dio.dart'; // Đảm bảo đính kèm lõi Token hủy mạng
import 'dart:async';
import '../../../data/services/secure_storage_service.dart';
import '../../../data/services/partner_api_service.dart';
import 'package:intl/intl.dart'; // 🚀 Bổ sung thư viện format số tiền cho Bottom Sheet Affiliate


class DedicatedUploadScreen extends StatefulWidget {
  final String userRole;

  const DedicatedUploadScreen({super.key, required this.userRole});

  @override
  State<DedicatedUploadScreen> createState() => _DedicatedUploadScreenState();
}

class _DedicatedUploadScreenState extends State<DedicatedUploadScreen> with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Animation Controller cho Quả cầu năng lượng AI 3D lướt động
  late AnimationController _orbController;

  // Trạng thái Bước 1 (Wellness Studio Layout)
  String _uploadedVideoUrl = "";
  String _currentMode = "UPLOAD"; // "CAMERA" hoặc "UPLOAD"
  bool _isLockingAction = false; // Cờ bảo vệ ngăn chặn người dùng bấm liên tục gây PlatformException
  bool _isMuted = true; // 🚀 MỚI: Quản lý trạng thái bật/tắt âm thanh của video preview (Mặc định câm để tránh xung đột luồng)

  // 🚀 MỚI: Quản lý biên trượt cắt ngắn video nhúng ngầm Metadata phát (YouTube Short Style)
  double _trimStartPercent = 0.0; // Biên trái (0.0 -> 1.0)
  double _trimEndPercent = 1.0;   // Biên phải (0.0 -> 1.0)
  
  // 🚀 TỐI ƯU 60FPS: Sử dụng ValueNotifier để cô lập phạm vi Rebuild, tránh giật lag UI Thread cha
  final ValueNotifier<double> _trimPlaybackProgressNotifier = ValueNotifier<double>(0.0);

  // 🚀 YOUTUBE SHORT ALGORITHM: Các biến quản lý luồng Tiền tải lên ngầm và File gốc đã cắt vật lý
  String _localVideoOriginalPath = ""; // Đường dẫn tệp thô ban đầu từ thư viện máy khách
  String _finalCloudVideoUrl = "";     // URL mạng trả về từ Server lưu trữ tập trung
  bool _isUploadingNgam = false;      // Cờ trạng thái hiển thị tiến trình xử lý ngầm
  double _uploadNgamProgress = 0.0;    // % tiến trình tải lên
  
  // 🚀 ĐỒNG BỘ TRẠNG THÁI BIÊN CẮT: Lưu dấu ranh giới thực tế của tệp đã tải thành công lên máy chủ
  double _lastUploadedStartPercent = -1.0;
  double _lastUploadedEndPercent = -1.0;

  // 🚀 SESSION ID: Ngăn chặn triệt để tình trạng luồng cũ đè luồng mới và tránh Crash Native
  String _currentProcessingSessionId = "";

  // 🚀 THIẾT LẬP ĐIỀU TỐC MẠNG CAO CẤP: Giữ nguyên chất lượng video nhưng giải phóng băng thông tức thì

  CancelToken? _currentUploadCancelToken;
  Timer? _debounceTrimTimer;

  // Trạng thái Bước 2 (Metadata Form & Commerce Configuration)
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _commissionController = TextEditingController(); // Bộ điều khiển trường hoa hồng cho Partner làm Affiliate

  String? _selectedPartnerName;
  String? _selectedServiceName;
  String? _selectedVoucherCode;
  String? _selectedServiceId; // Lưu ID dịch vụ thực tế để truyền payload và gỡ liên kết
  String? _selectedPartnerId; // 🚀 MỚI: Khóa ID của Đối tác được chọn để gửi payload
  
  // Lưu trữ danh sách thực tế của riêng Partner để hiển thị lựa chọn
  List<dynamic> _partnerAvailableServices = [];
  List<dynamic> _partnerAvailableVouchers = [];
  bool _isFetchingMetadata = false;

  // 🚀 MỚI: Trạng thái lưu trữ Affiliate dành riêng cho CREATOR
  List<dynamic> _creatorApprovedPartners = [];
  List<dynamic> _creatorPartnerServices = [];
  List<dynamic> _creatorPartnerVouchers = [];
  
  String _userRole = "USER"; // Sẽ tự động nạp động từ luồng trạng thái tài khoản hệ thống
  String _partnerPublishMode = "TIKTOK_FEED"; // 'TIKTOK_FEED' hoặc 'SERVICE_VIDEO'
  
  bool _isSubmitting = false;
  bool _isLoadingRole = true; // 🛡️ GÁC CỔNG TRẠNG THÁI: Ngăn chặn giao diện vẽ vội vã khi chưa nạp xong quyền

  @override
  void initState() {
    super.initState();
    // 🚀 ĐỒNG BỘ: Kích hoạt chặn âm thanh Feeds ngay khi Studio khởi tạo
    AudioFocusManager.instance.requestMode(AppAudioMode.studioActive);
    
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(); // Kích hoạt luồng quay vô hạn tạo sóng hạt Hologram 3D mượt màng

    _userRole = widget.userRole.trim().toUpperCase();
    _isLoadingRole = false;
    
    // Nếu là Partner, chủ động tiền tải dữ liệu thương mại của cơ sở để sẵn sàng cho tab 2
    if (_userRole == "PARTNER_ADMIN" || _userRole == "PARTNER") {
      _loadPartnerMetadata();
    } else if (_userRole == "CREATOR") {
      // 🚀 Luồng nạp dữ liệu Affiliate tự động cho Creator
      _loadCreatorAffiliateData();
    }
  }

  // 🚀 MỚI: Logic kéo danh sách Đối tác đã duyệt (APPROVED) của Creator
  Future<void> _loadCreatorAffiliateData() async {
    try {
      final res = await ApiClient.instance.get('/creator/affiliate/partners');
      if (res.statusCode == 200 && mounted) {
        final List<dynamic> allPartners = res.data['data'] ?? [];
        setState(() {
          _creatorApprovedPartners = allPartners.where((p) => p['status'] == 'APPROVED').toList();
        });
      }
    } catch (_) {}
  }

  // 🚀 MỚI: Logic kéo danh sách Dịch vụ của Đối tác vừa được chọn
  Future<void> _loadCreatorPartnerServices(String partnerId) async {
    try {
      final res = await ApiClient.instance.get('/creator/affiliate/partners/$partnerId/services');
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _creatorPartnerServices = res.data['data'] ?? [];
        });
      }
    } catch (_) {}
  }

  // 🚀 MỚI: Logic kéo danh sách Voucher của Đối tác dựa vào Public Profile
  Future<void> _loadCreatorPartnerVouchers(String username) async {
    try {
      final res = await ApiClient.instance.get('/user/public/$username');
      if (res.statusCode == 200 && mounted) {
        final resBody = res.data as Map<String, dynamic>?;
        final profileData = resBody?['data'] as Map<String, dynamic>?;
        setState(() {
          // Lọc voucher còn hiệu lực tương tự logic của Partner
          final now = DateTime.now();
          final allVouchers = profileData?['vouchers'] as List<dynamic>? ?? [];
          _creatorPartnerVouchers = allVouchers.where((v) {
            if (v['valid_until'] == null) return false;
            try {
              final expireDate = DateTime.parse(v['valid_until'].toString());
              return expireDate.isAfter(now);
            } catch (_) {
              return false;
            }
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Lỗi tải danh sách Voucher của Đối tác: $e');
    }
  }

  Future<void> _loadPartnerMetadata() async {
    if (_isFetchingMetadata) return;
    _isFetchingMetadata = true;
    try {
      // Tận dụng cổng API Service chuẩn hóa của Partner Private Profile
      final results = await Future.wait([
        PartnerApiService.fetchMyServices().catchError((_) => []),
        ApiClient.instance.get('/partner/vouchers').then((res) {
          if (res.data is Map && res.data.containsKey('data')) {
            return res.data['data'] is List ? res.data['data'] : [];
          }
          return res.data is List ? res.data : [];
        }).catchError((_) => []),
      ]);

      if (mounted) {
        setState(() {
          // Chỉ lấy các dịch vụ đã APPROVED để đảm bảo tính pháp lý khi nhúng vào video
          _partnerAvailableServices = (results[0] as List<dynamic>)
              .where((svc) => svc['status'] == 'APPROVED')
              .toList();
          
          // Lọc voucher do cơ sở phát hành và còn thời hạn sử dụng real-time năm 2026
          final now = DateTime.now();
          _partnerAvailableVouchers = (results[1] as List<dynamic>).where((v) {
            if (v['valid_until'] == null) return false;
            try {
              final expireDate = DateTime.parse(v['valid_until'].toString());
              return expireDate.isAfter(now);
            } catch (_) {
              return false;
            }
          }).toList();
        });
      }
    } catch (_) {}
    _isFetchingMetadata = false;
  }

  // Helper hiển thị danh sách chọn lựa mượt mà cho đối tác
  void _showSelectionBottomSheet({
    required String title,
    required List<dynamic> items,
    required String itemTitleKey,
    required String itemValueKey,
    required Function(String selectedTitle, String selectedValue) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text("Kho dữ liệu trống hoặc đang chờ phê duyệt", style: TextStyle(color: Color(0xFF617D79))))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final displayTitle = item[itemTitleKey]?.toString() ?? '';
                        final displayValue = item[itemValueKey]?.toString() ?? '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(displayTitle, style: const TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.w600, fontSize: 14)),
                          trailing: const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF80BF84), size: 20),
                          onTap: () {
                            onSelected(displayTitle, displayValue);
                            Navigator.pop(context);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTrimTimer?.cancel();
    if (_currentUploadCancelToken != null && !_currentUploadCancelToken!.isCancelled) {
      _currentUploadCancelToken!.cancel("Hủy giao diện");
    }
    _trimPlaybackProgressNotifier.dispose(); // Giải phóng bộ phát tín hiệu cô lập
    _orbController.dispose(); // Giải phóng RAM sạch sẽ chống rò rỉ bộ nhớ
    _pageController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    
    // 🚀 KHÓA AN TOÀN CUỐI CÙNG: Đảm bảo khi hủy màn hình, quyền phát tiếng luôn được trả về cho Feeds
    AudioFocusManager.instance.requestMode(AppAudioMode.feedsActive);
    super.dispose();
  }

  // 🚀 THUẬT TOÁN TIỀN TẢI LÊN (BACKGROUND PRE-UPLOAD): Thực hiện cắt tệp cứng cục bộ và đồng bộ ngầm
  Future<void> _startBackgroundProcessing() async {
    if (_localVideoOriginalPath.isEmpty) return;

    // HỦY LUỒNG MẠNG CŨ NGAY LẬP TỨC: Giải phóng 100% băng thông tải lên cho luồng mới, không để chạy song song
    try {
      if (_currentUploadCancelToken != null && !_currentUploadCancelToken!.isCancelled) {
        _currentUploadCancelToken!.cancel("Khởi tạo phân đoạn cắt mới");
      }
    } catch (_) {}
    _currentUploadCancelToken = CancelToken();

    setState(() {
      _isUploadingNgam = true;
      _uploadNgamProgress = 0.0;
    });

    File fileToUpload;

    try {
      final MediaInfo mediaInfoData = await VideoCompress.getMediaInfo(_localVideoOriginalPath);
      final double totalDurationMs = mediaInfoData.duration ?? 0;

      // 1. CHẾ ĐỘ HARD CUT CHUẨN XÁC: Ghi nhận biên độ tại thời điểm bắt đầu xử lý luồng
      final double currentStart = _trimStartPercent;
      final double currentEnd = _trimEndPercent;
      
      // Tính toán dựa trên Mili-giây để tránh lỗi làm tròn số nguyên của giây
      final int startMs = (totalDurationMs * currentStart).toInt();
      final int durationMs = (totalDurationMs * (currentEnd - currentStart)).toInt();
      final int totalMs = totalDurationMs.toInt();

      // Khởi tạo mã định danh duy nhất cho luồng xử lý này
      final String thisSessionId = DateTime.now().microsecondsSinceEpoch.toString();
      _currentProcessingSessionId = thisSessionId;

      // Chỉ bỏ qua nén cắt vật lý nếu biên độ thực tế trùng khớp tuyệt đối 100% với tệp gốc
      if (startMs > 0 || durationMs < totalMs) {
        // 🚀 BẢO TOÀN TRẢI NGHIỆM: Giữ cấu hình HighestQuality để bảo chứng hình ảnh bọc hoa hồng sắc nét tuyệt đối
        final MediaInfo? trimResult = await VideoCompress.compressVideo(
          _localVideoOriginalPath,
          quality: VideoQuality.HighestQuality,
          startTime: (startMs / 1000).toInt(),
          duration: (durationMs / 1000).toInt(),
          deleteOrigin: false,
        );

        if (_currentProcessingSessionId != thisSessionId) return;

        if (trimResult != null && trimResult.file != null) {
          fileToUpload = trimResult.file!;
        } else {
          fileToUpload = File(_localVideoOriginalPath);
        }
      } else {
        fileToUpload = File(_localVideoOriginalPath);
      }

      if (_currentProcessingSessionId != thisSessionId) return;

      // 2. TRUYỀN STREAM SONG SONG LÊN MÁY CHỦ CLOUD - Loại bỏ named parameter không định nghĩa
      final uploadedUrl = await UserApiService.uploadVideo(
        fileToUpload,
        "media/videos",
        onSendProgress: (sent, total) {
          // GÁC CỔNG TIẾN TRÌNH: Nếu Session UI đã thay đổi, lập tức cô lập dòng dữ liệu rác
          if (mounted && total > 0 && _currentProcessingSessionId == thisSessionId) {
            setState(() {
              _uploadNgamProgress = sent / total;
            });
          }
        },
      );

      // Chặn cuối cùng trước khi ghi nhận trạng thái lên State của Widget cha
      if (_currentProcessingSessionId != thisSessionId) return;

      if (mounted && uploadedUrl != null) {
        setState(() {
          _finalCloudVideoUrl = uploadedUrl;
          _lastUploadedStartPercent = currentStart;
          _lastUploadedEndPercent = currentEnd;
          _isUploadingNgam = false;
        });
        AppToast.show(context: context, message: "Mã hóa và tải lên ngầm video phân đoạn thành công!", isSuccess: true);
      }
    } catch (e) {
      debugPrint("Lỗi luồng xử lý nền YouTube Short: $e");
      if (mounted) {
        setState(() {
          _isUploadingNgam = false;
        });
      }
    }
  }

  double totalMsToSeconds(double ms) => ms / 1000;

  void _nextStep() {
    if (_uploadedVideoUrl.isEmpty) {
      AppToast.show(context: context, message: "Vui lòng chọn hoặc tải video lên hệ thống trước!", isSuccess: false);
      return;
    }

    // 🚀 PHƯƠNG ÁN TRẢI NGHIỆM KHÔNG CHẶN: Cho phép sang thẳng bước 2 điền form biểu mẫu
    // Luồng xử lý cắt xén/nén và truyền stream nhị phân vẫn tiếp tục được chạy ngầm tự do
    setState(() => _currentStep = 1);
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }

  void _previousStep() {
    setState(() => _currentStep = 0);
    _pageController.animateToPage(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.fastOutSlowIn,
    );
  }

  Future<void> _pickVideoFromGallery() async {
    if (_isLockingAction) return; // Khóa ngay lập tức nếu tiến trình cũ chưa đóng
    
    setState(() => _isLockingAction = true);

    Permission statusPermission = Permission.videos;
    PermissionStatus status = await statusPermission.status;

    if (status.isDenied) {
      status = await statusPermission.request();
    }

    if (status.isGranted) {
      try {
        final ImagePicker picker = ImagePicker();
        final XFile? video = await picker.pickVideo(source: ImageSource.gallery);

        if (video != null) {
          // 🚀 KHẮC PHỤC TRIỆT ĐỂ: Đồng bộ cơ chế phân tích tĩnh siêu tốc qua VideoCompress
          final MediaInfo mediaInfoData = await VideoCompress.getMediaInfo(video.path);
          final double durationInSeconds = (mediaInfoData.duration ?? 0) / 1000;
          final double fileSizeInMB = (mediaInfoData.filesize ?? File(video.path).lengthSync()) / (1024 * 1024);

          if (durationInSeconds > 180 || fileSizeInMB > 500) {
            setState(() => _isLockingAction = false);
            if (!mounted) return;
            AppToast.show(
              context: context, 
              message: durationInSeconds > 180 
                ? "Từ chối: Video dài ${durationInSeconds.toInt()} giây (Vượt giới hạn 3 phút)!" 
                : "Từ chối: Dung lượng file đạt ${fileSizeInMB.toInt()}MB (Vượt giới hạn 500MB)!", 
              isSuccess: false
            );
            return;
          }

          if (!mounted) return;
          AppToast.show(context: context, message: "Đã chọn video hợp lệ thành công!", isSuccess: true);
          
          setState(() {
            _localVideoOriginalPath = video.path;
            _uploadedVideoUrl = video.path;
            _currentMode = "UPLOAD";
            _isLockingAction = false; // Mở khóa ngay lập tức cho phép đổi file hoặc gỡ file
            // Reset biên trượt về trạng thái nguyên bản của tệp mới
            _trimStartPercent = 0.0;
            _trimEndPercent = 1.0;
          });
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(context: context, message: "Lỗi kết nối bộ đọc tệp hệ thống!", isSuccess: false);
        }
      }
    } else if (status.isPermanentlyDenied) {
      // 4. Trường hợp người dùng tích chọn "Không bao giờ hỏi lại", điều hướng họ vào cài đặt ứng dụng
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text("Yêu cầu quyền truy cập", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A3A35))),
          content: const Text("Ứng dụng cần quyền truy cập vào Thư viện Ảnh & Video để bạn tải nội dung Wellness lên hệ thống. Vui lòng cấp quyền trong phần Cài đặt."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Hủy bỏ", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                openAppSettings(); // Mở trang Settings hệ thống của ứng dụng này
              },
              child: const Text("Đi đến Cài đặt", style: TextStyle(color: Color(0xFF80BF84), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      if (mounted) {
        AppToast.show(context: context, message: "Quyền truy cập thư viện bị từ chối!", isSuccess: false);
      }
    }
  }

  Future<void> _handlePublish() async {
    if (_titleController.text.trim().isEmpty) {
      AppToast.show(context: context, message: "Vui lòng nhập tiêu đề bài viết!", isSuccess: false);
      return;
    }

    if ((_userRole == "PARTNER_ADMIN" || _userRole == "PARTNER") && _partnerPublishMode == "SERVICE_VIDEO") {
      if (_priceController.text.trim().isEmpty) {
        AppToast.show(context: context, message: "Lỗi: Vai trò Đối tác đăng Video dịch vụ bắt buộc phải nhập Giá bán!", isSuccess: false);
        return;
      }
      if (_commissionController.text.trim().isEmpty) {
        AppToast.show(context: context, message: "Lỗi: Vui lòng nhập tỷ lệ % Hoa hồng cho Creator làm Affiliate!", isSuccess: false);
        return;
      }
    }

    if (_localVideoOriginalPath.isEmpty) {
      AppToast.show(context: context, message: "Vui lòng chọn video trước khi đăng tải!", isSuccess: false);
      return;
    }

    // Capture state values before popping the context
    final String title = _titleController.text.trim();
    final String content = _descriptionController.text.trim();
    final double? price = _priceController.text.trim().isEmpty ? null : double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final double? affiliateRate = _commissionController.text.trim().isEmpty ? 0.0 : double.tryParse(_commissionController.text.trim());
    final String? partnerId = _userRole == "CREATOR" ? _selectedPartnerId : _selectedPartnerName;
    final String? voucherCode = _selectedVoucherCode;
    final String feedType = (_userRole == "PARTNER_ADMIN" || _userRole == "PARTNER") ? _partnerPublishMode : "TIKTOK_FEED";
    final String localVideoPath = _localVideoOriginalPath;
    final double trimStart = _trimStartPercent;
    final double trimEnd = _trimEndPercent;
    String? targetedServiceId = _selectedServiceId;
    final String currentUserRole = _userRole;
    final String partnerMode = _partnerPublishMode;

    AppToast.show(
      context: context, 
      message: 'Video đang được tải lên ngầm, vui lòng không tắt ứng dụng.', 
      isSuccess: true
    );

    // Bắt buộc mở khóa âm thanh Feed và thoát màn hình ngay lập tức
    FeedVideoPool.isGlobalMutedForUpload = false;
    final navigator = Navigator.of(context);
    navigator.pop();

    // Fire and forget upload pipeline
    Future.microtask(() async {
      try {
        // 1. Process Video Trim (From Background Logic)
        File fileToUpload = File(localVideoPath);
        final MediaInfo mediaInfoData = await VideoCompress.getMediaInfo(localVideoPath);
        final double totalDurationMs = mediaInfoData.duration ?? 0;
        final int startMs = (totalDurationMs * trimStart).toInt();
        final int durationMs = (totalDurationMs * (trimEnd - trimStart)).toInt();
        
        if (startMs > 0 || durationMs < totalDurationMs.toInt()) {
          final MediaInfo? trimResult = await VideoCompress.compressVideo(
            localVideoPath,
            quality: VideoQuality.HighestQuality,
            startTime: (startMs / 1000).toInt(),
            duration: (durationMs / 1000).toInt(),
            deleteOrigin: false,
          );
          if (trimResult != null && trimResult.file != null) {
            fileToUpload = trimResult.file!;
          }
        }

        // 2. Upload to Cloudflare R2
        final String? uploadedUrl = await UserApiService.uploadVideo(fileToUpload, "media/videos");
        if (uploadedUrl == null || uploadedUrl.isEmpty) {
          debugPrint("Background upload failed: empty URL");
          return;
        }

        // 3. Fallback Service Creation for Partner
        if ((currentUserRole == "PARTNER_ADMIN" || currentUserRole == "PARTNER") && partnerMode == "SERVICE_VIDEO" && targetedServiceId == null) {
          final Map<String, dynamic> servicePayload = {
            'service_name': title,
            'description': content.isEmpty ? null : content,
            'price': price ?? 0.0,
            'image_url': null,
            'video_url': uploadedUrl,
            'tags': [],
            'service_type': 'RELAXATION',
            'status': 'PENDING',
            'affiliate_rate': affiliateRate ?? 0.0,
          };
          try {
            final serviceRes = await ApiClient.instance.post('/services', data: servicePayload);
            if (serviceRes.statusCode == 200 && serviceRes.data != null) {
              final dynamic resData = serviceRes.data;
              if (resData is Map && resData.containsKey('id')) targetedServiceId = resData['id']?.toString();
              else if (resData is Map && resData.containsKey('data') && resData['data'] is Map) targetedServiceId = resData['data']['id']?.toString();
            }
          } catch (e) {
            debugPrint("Service creation fallback alert: $e");
          }
        }

        // 4. Create Feed Post
        final Map<String, dynamic> payload = {
          'title': title,
          'content': content.isEmpty ? null : content,
          'price': price,
          'video_url': uploadedUrl,
          'affiliate_rate': affiliateRate,
          'partner_id': partnerId,
          'service_id': targetedServiceId,
          'voucher_code': voucherCode,
          'feed_type': feedType,
          'trim_start_percent': trimStart,
          'trim_end_percent': trimEnd,
        };

        final res = await ApiClient.instance.post('/tiktok/feeds', data: payload);
        if (res.statusCode == 200) {
          if (navigator.context.mounted) {
            AppToast.show(context: navigator.context, message: "Đăng tải video hoàn tất, đang chờ duyệt!", isSuccess: true);
          }
        }
      } catch (e) {
        debugPrint("Background publish error: $e");
      }
    });
  }

  Future<bool> _onWillPop() async {
    if (_uploadedVideoUrl.isNotEmpty || _titleController.text.isNotEmpty) {
      final bool? shouldPop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Hủy bỏ sáng tạo?", style: TextStyle(color: Color(0xFF1A3A35), fontWeight: FontWeight.bold, fontSize: 18)),
          content: const Text("Toàn bộ thông tin biểu mẫu bạn vừa điền sẽ bị xóa bỏ hoàn toàn khỏi bộ nhớ tạm."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Quay lại", style: TextStyle(color: Color(0xFF617D79), fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Đồng ý hủy", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return shouldPop ?? false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && mounted) {
          // Trả lại tiêu điểm âm thanh đồng bộ trước khi thực hiện lệnh đóng Navigator Stack
          AudioFocusManager.instance.requestMode(AppAudioMode.feedsActive);
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F9F6), // Cân bằng Off-white và Sage Mint dịu mắt, cao cấp cho cả hai bước
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _buildStep1WellnessStudio(),
            _buildStep2Metadata(),
          ],
        ),
      ),
    );
  }

  // ==================== III. TÁI CẤU TRÚC HOÀN TOÀN TRANG 1 TRẢI NGHIỆM WELLNESS STUDIO ====================
  Widget _buildStep1WellnessStudio() {
    final double statusBarPadding = MediaQuery.paddingOf(context).top;

    return Stack(
      children: [
        // 1. PHÂN KHU NỀN CỐT LÕI (CAMERA HOẶC TRÌNH PHÁT VIDEO PREVIEW 9:16)
        Positioned.fill(
          child: Container(
            color: const Color(0xFFF4F9F6),
            child: _uploadedVideoUrl.isNotEmpty
                ? MiniVideoPlayer(
                    videoUrl: _uploadedVideoUrl, 
                    isMuted: _isMuted,
                    trimStartPercent: _trimStartPercent,
                    trimEndPercent: _trimEndPercent,
                    onProgressUpdate: (progress) {
                      _trimPlaybackProgressNotifier.value = progress;
                    },
                  )
                : (_currentMode == "CAMERA"
                    ? const Center(child: Text("Camera view đang khởi động luồng phần cứng...", style: TextStyle(color: Color(0xFF617D79), fontSize: 13)))
                    : Center(
                        child: GestureDetector(
                          onTap: _isLockingAction ? null : _pickVideoFromGallery,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: _orbController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    painter: _StudioOrbPainter(progress: _orbController.value),
                                    child: const SizedBox(width: 100, height: 100),
                                  );
                                },
                              ),
                              const SizedBox(height: 28),
                              const Text(
                                "Chào mừng bạn đến với trạm sáng tạo",
                                style: TextStyle(
                                  color: Color(0xFF1A3A35),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.3,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                "Nơi lan tỏa kiến thức bảo chứng và giá trị Wellness",
                                style: TextStyle(
                                  color: Color(0xFF617D79),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w400,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )),
          ),
        ),

        // 2. ĐỈNH MÀN HÌNH CHUYỂN SANG GLASS LAYOUT SÁNG SANG TRỌNG
        Positioned(
          top: statusBarPadding + 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.close_rounded, color: Color(0xFF1A3A35), size: 26),
                onPressed: () async {
                  final shouldPop = await _onWillPop();
                  if (shouldPop && mounted) context.pop();
                },
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified_rounded, color: Color(0xFF80BF84), size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Chế độ Sáng tạo nội dung",
                      style: TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF1A3A35), shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFFB0C4C1), shape: BoxShape.circle)),
                ],
              ),
            ],
          ),
        ),

        // 3. I. THANH CÔNG CỤ DỌC BÊN CẠNH TINH LỌC (RIGHT SIDEBAR TOOLBAR WELLNESS)
        Positioned(
          top: statusBarPadding + 80,
          right: 16,
          child: Column(
            children: [
              _buildStudioSidebarButton(
                icon: Icons.psychology_rounded, // 🚀 THAY ĐỔI: Quét AI thông minh
                label: "Kiểm tra AI",
                onTap: () => AppToast.show(context: context, message: "AI đang quét kiểm duyệt sơ bộ tiêu chuẩn y khoa và bản quyền âm thanh thiền...", isSuccess: true),
              ),
              _buildStudioSidebarButton(
                icon: Icons.subtitles_rounded, // 🚀 THAY ĐỔI: Máy nhắc chữ kịch bản Wellness
                label: "Kịch bản mẫu",
                onTap: () => AppToast.show(context: context, message: "Đã hiển thị cấu trúc dàn bài khuyến nghị: Triệu chứng -> Giải pháp -> Gói khám.", isSuccess: true),
              ),
              _buildStudioSidebarButton(
                icon: _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                label: _isMuted ? "Tắt tiếng" : "Bật tiếng",
                onTap: () {
                  if (_uploadedVideoUrl.isEmpty) {
                    AppToast.show(context: context, message: "Vui lòng đính kèm video trước khi điều chỉnh âm thanh!", isSuccess: false);
                    return;
                  }
                  setState(() {
                    _isMuted = !_isMuted;
                  });
                },
              ),
              if (_uploadedVideoUrl.isNotEmpty)
                _buildStudioSidebarButton(
                  icon: Icons.sync_rounded,
                  label: "Gỡ tệp",
                  onTap: () {
                    setState(() {
                      _uploadedVideoUrl = "";
                      _isLockingAction = false;
                      _trimStartPercent = 0.0;
                      _trimEndPercent = 1.0;
                      _lastUploadedStartPercent = -1.0;
                      _lastUploadedEndPercent = -1.0;
                      _finalCloudVideoUrl = "";
                    });
                    FeedVideoPool.isGlobalMutedForUpload = false;
                  },
                ),
            ],
          ),
        ),

        // 🚀 MỚI: HỆ THỐNG TIMELINE CẮT XÉN BIÊN ĐÔI DYNAMIC TRIM SLIDER (YOUTUBE SHORT STYLE)
        if (_uploadedVideoUrl.isNotEmpty)
          Positioned(
            bottom: 140,
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${(_trimStartPercent * 100).toInt()}%", style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.bold)),
                    const Text(
                      "Đoạn video đăng tải ngắn (Đã sẵn sàng)", 
                      style: TextStyle(color: Color(0xFF1A3A35), fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                    Text("${(_trimEndPercent * 100).toInt()}%", style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2ECEB).withOpacity(0.6), width: 1.5),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          RangeSlider(
                            values: RangeValues(_trimStartPercent, _trimEndPercent),
                            min: 0.0,
                            max: 1.0,
                            activeColor: const Color(0xFF80BF84),
                            inactiveColor: const Color(0xFFE2ECEB),
                            onChangeEnd: (RangeValues values) {
                              _debounceTrimTimer?.cancel();
                            },
                            onChanged: (RangeValues values) {
                              if (values.end - values.start >= 0.05) {
                                setState(() {
                                  _trimStartPercent = values.start;
                                  _trimEndPercent = values.end;
                                  _trimPlaybackProgressNotifier.value = 0.0;
                                });
                              }
                            },
                          ),
                          IgnorePointer(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _trimPlaybackProgressNotifier,
                              builder: (context, progress, child) {
                                final currentProgressPercent = _trimStartPercent + (progress * (_trimEndPercent - _trimStartPercent));
                                final targetLeft = currentProgressPercent * width;

                                return Stack(
                                  children: [
                                    AnimatedPositioned(
                                      duration: const Duration(milliseconds: 40),
                                      curve: Curves.linear,
                                      left: (targetLeft - 2).clamp(0.0, width - 4),
                                      top: 2,
                                      bottom: 2,
                                      child: Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A3A35),
                                          borderRadius: BorderRadius.circular(2),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 2, offset: const Offset(1, 1))
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

        // 4. II. KHU VỰC ĐIỀU KHIỂN TRUNG TÂM PHÍA DƯỚI (BOTTOM ACTION LAYER)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.only(top: 20, bottom: 24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  const Color(0xFF1A3A35).withOpacity(0.06),
                  const Color(0xFF1A3A35).withOpacity(0.0),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 60),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Vệ tinh Trái: Nhạc thiền tự động kích hoạt
                      GestureDetector(
                        onTap: () => AppToast.show(context: context, message: "Đã áp dụng kho nhạc nền sóng não Alpha thư thái tự động.", isSuccess: true),
                        child: Column(
                          children: [
                            Container(
                              width: 46, height: 46,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFE2ECEB), width: 1.5),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
                              ),
                              child: const Icon(Icons.spa_rounded, color: Color(0xFF80BF84), size: 20),
                            ),
                            const SizedBox(height: 8),
                            const Text("Nhạc thiền", style: TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),

                      // Trung tâm: Nút chính
                      GestureDetector(
                        onTap: () {
                          if (_uploadedVideoUrl.isNotEmpty) {
                            _nextStep();
                          } else {
                            if (!_isLockingAction) _pickVideoFromGallery();
                          }
                        },
                        child: Container(
                          width: 78, height: 78,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.4), width: 4),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _uploadedVideoUrl.isNotEmpty 
                                  ? const Color(0xFF80BF84)
                                  : const Color(0xFF1A3A35),
                              boxShadow: [
                                BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4))
                              ],
                            ),
                            child: Icon(
                              _uploadedVideoUrl.isNotEmpty ? Icons.arrow_forward_rounded : Icons.video_library_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),

                      // Vệ tinh Phải
                      Column(
                        children: [
                          Container(
                            width: 46, height: 46,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _uploadedVideoUrl.isNotEmpty ? const Color(0xFF80BF84) : const Color(0xFFE2ECEB), width: 1.5),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6)],
                            ),
                            child: Icon(
                              _uploadedVideoUrl.isNotEmpty ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                              color: _uploadedVideoUrl.isNotEmpty ? const Color(0xFF80BF84) : const Color(0xFF617D79),
                              size: 20
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(_uploadedVideoUrl.isNotEmpty ? "Đã nhận" : "Tải lên", style: const TextStyle(color: Color(0xFF617D79), fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // Helper hỗ trợ dựng các icon nút bấm kính mờ Sidebar thiết kế Premium Thượng lưu
  Widget _buildStudioSidebarButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.85),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2ECEB), width: 1.2),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))
                ],
              ),
              child: Icon(icon, color: const Color(0xFF1A3A35), size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label.toUpperCase(), 
              style: const TextStyle(
                color: Color(0xFF617D79), 
                fontSize: 8.5, 
                fontWeight: FontWeight.w800, 
                letterSpacing: 0.3
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 MỚI: Widget Bottom Sheet hiển thị danh sách dịch vụ kèm Hoa hồng (Dành cho Creator Affiliate)
  void _showCreatorServicesBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final NumberFormat currencyFormatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn Dịch vụ tiếp thị', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Chi tiết tỉ lệ hoa hồng áp dụng cho từng danh mục:', style: TextStyle(color: Color(0xFF617D79), fontSize: 12)),
              const SizedBox(height: 16),
              Flexible(
                child: _creatorPartnerServices.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text('Đang tải hoặc đối tác chưa cấu hình dịch vụ.', style: TextStyle(color: Color(0xFFB0C4C1)))))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _creatorPartnerServices.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFFE2ECEB)),
                        itemBuilder: (context, index) {
                          final s = _creatorPartnerServices[index];
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedServiceName = s['service_name'];
                                _selectedServiceId = s['id'].toString();
                                // Lấy luôn giá dịch vụ gán tạm để hiển thị cho trực quan nếu muốn
                                final double svcPrice = double.tryParse(s['price']?.toString() ?? '0') ?? 0;
                                final formatter = NumberFormat('#,###', 'en_US');
                                _priceController.text = '${formatter.format(svcPrice).replaceAll(',', '.')} VND'; 
                              });
                              Navigator.pop(context);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s['service_name'] ?? 'Dịch vụ chưa rõ tên', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 4),
                                        Text('Giá gốc: ${currencyFormatter.format(s['price'] ?? 0)}', style: const TextStyle(color: Color(0xFF617D79), fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF48C9B0).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: const Color(0xFF48C9B0).withOpacity(0.3)),
                                    ),
                                    child: Text('+${s['affiliate_rate'] ?? 0}% Hoa hồng', style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🚀 MỚI: Widget Bottom Sheet hiển thị danh sách Voucher kèm check điều kiện (Dành cho Đối tác)
  void _showPartnerVouchersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn Voucher Cơ Sở', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Các voucher bị mờ do chưa đạt đơn tối thiểu hoặc không áp dụng cho dịch vụ hiện tại.', style: TextStyle(color: Color(0xFF617D79), fontSize: 12)),
              const SizedBox(height: 16),
              Flexible(
                child: _partnerAvailableVouchers.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text('Cơ sở hiện chưa có voucher nào.', style: TextStyle(color: Color(0xFFB0C4C1)))))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _partnerAvailableVouchers.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFFE2ECEB)),
                        itemBuilder: (context, index) {
                          final v = _partnerAvailableVouchers[index];
                          
                          List<dynamic> applicableServices = [];
                          final rawServices = v['applicable_services'];
                          if (rawServices is List) {
                            applicableServices = rawServices;
                          } else if (rawServices is String && rawServices.isNotEmpty) {
                            applicableServices = rawServices.replaceAll(RegExp(r'[{}[\]]'), '').split(',').map((e) => e.trim().replaceAll('"', '').replaceAll("'", "")).where((e) => e.isNotEmpty).toList();
                          }
                          
                          double selectedServicePrice = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                              final double minOrderValue = double.tryParse(v['min_order_value']?.toString() ?? '0') ?? 0.0;
                              final double maxDiscountAmount = double.tryParse(v['max_discount_amount']?.toString() ?? '0') ?? 0.0;

                              // 🚀 ĐỒNG BỘ LOGIC CREATOR
                              bool isEligible = true;
                              String ineligibleReason = '';
                              
                              if (_selectedServiceId == null && selectedServicePrice <= 0) {
                                 isEligible = false;
                                 ineligibleReason = 'Vui lòng nhập giá hoặc chọn Gói dịch vụ trước để áp dụng ưu đãi!';
                              } else {
                                 if (applicableServices.isNotEmpty && _selectedServiceId == null) {
                                   isEligible = false;
                                   ineligibleReason = 'Voucher này chỉ áp dụng khi nhúng gói dịch vụ cụ thể!';
                                 } else if (applicableServices.isNotEmpty && !applicableServices.any((id) => id.toString() == _selectedServiceId)) {
                                   isEligible = false;
                                   ineligibleReason = 'Voucher không áp dụng cho gói dịch vụ này!';
                                 } else if (selectedServicePrice < minOrderValue) {
                                   isEligible = false;
                                   final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
                                   ineligibleReason = 'Chưa đạt giá trị tối thiểu ${formatter.format(minOrderValue)}!';
                                 }
                              }

                              final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
                              String discountText = 'Giảm ${v['discount_value'] ?? 0}${v['discount_type'] == 'PERCENTAGE' ? '%' : 'đ'}';
                              if (v['discount_type'] == 'PERCENTAGE' && maxDiscountAmount > 0) {
                                discountText += ' (Tối đa ${formatter.format(maxDiscountAmount)})';
                              }
                              if (minOrderValue > 0) {
                                discountText += '\nĐơn tối thiểu: ${formatter.format(minOrderValue)}';
                              } 

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(v['code']?.toString() ?? 'VOUCHER', style: TextStyle(color: isEligible ? const Color(0xFF1A3A35) : const Color(0xFFB0C4C1), fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text(discountText, style: TextStyle(color: isEligible ? const Color(0xFF617D79) : const Color(0xFFD1D1D6), fontSize: 12)),
                            isThreeLine: minOrderValue > 0,
                            trailing: isEligible 
                                ? const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF80BF84), size: 20)
                                : const Icon(Icons.do_not_disturb_alt_rounded, color: Color(0xFFD1D1D6), size: 18),
                            onTap: isEligible ? () {
                              setState(() {
                                _selectedVoucherCode = v['code']?.toString();
                              });
                              Navigator.pop(context);
                            } : () {
                              AppToast.show(context: context, message: ineligibleReason, isSuccess: false);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }


  // 🚀 MỚI: Widget Bottom Sheet hiển thị danh sách Voucher kèm check điều kiện (Dành cho Creator Affiliate)
  void _showCreatorVouchersBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.all(24),
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Chọn Voucher Ưu Đãi', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              const Text('Các voucher bị mờ là voucher không áp dụng cho dịch vụ bạn đang chọn.', style: TextStyle(color: Color(0xFF617D79), fontSize: 12)),
              const SizedBox(height: 16),
              Flexible(
                child: _creatorPartnerVouchers.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(24.0), child: Text('Đối tác hiện chưa có voucher nào.', style: TextStyle(color: Color(0xFFB0C4C1)))))
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _creatorPartnerVouchers.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFFE2ECEB)),
                        itemBuilder: (context, index) {
                          final v = _creatorPartnerVouchers[index];
                          
                          // 🚀 BỌC THÉP ÉP KIỂU: Cứu hộ lỗi màn hình đỏ do Backend trả về chuỗi thay vì Mảng (Type 'String' is not a subtype of type 'List<dynamic>')
                          List<dynamic> applicableServices = [];
                          final rawServices = v['applicable_services'];
                          if (rawServices is List) {
                            applicableServices = rawServices;
                          } else if (rawServices is String && rawServices.isNotEmpty) {
                            // Xử lý chuỗi Postgres Array "{id1, id2}" hoặc JSON String "['id']"
                            applicableServices = rawServices.replaceAll(RegExp(r'[{}[\]]'), '').split(',').map((e) => e.trim().replaceAll('"', '').replaceAll("'", "")).where((e) => e.isNotEmpty).toList();
                          }
                          
                          double selectedServicePrice = 0.0;
                          if (_selectedServiceId != null) {
                            try {
                              final selectedSvc = _creatorPartnerServices.firstWhere((s) => s['id'].toString() == _selectedServiceId);
                              selectedServicePrice = double.tryParse(selectedSvc['price']?.toString() ?? '0') ?? 0.0;
                            } catch (_) {}
                          }

                          final double minOrderValue = double.tryParse(v['min_order_value']?.toString() ?? '0') ?? 0.0;
                          final double maxDiscountAmount = double.tryParse(v['max_discount_amount']?.toString() ?? '0') ?? 0.0;

                          // 🚀 BỌC THÉP LUỒNG: Điều kiện voucher hợp lệ: 
                          // 1. Phải chọn dịch vụ trước để đối chiếu giá trị đơn.
                          // 2. Không bị giới hạn dịch vụ (applicable_services) hoặc nằm trong danh sách áp dụng.
                          // 3. Đạt giá trị tối thiểu (min_order_value).
                          bool isEligible = true;
                          String ineligibleReason = '';
                          
                          if (_selectedServiceId == null) {
                             isEligible = false;
                             ineligibleReason = 'Vui lòng chọn Gói dịch vụ y khoa trước để áp dụng ưu đãi!';
                          } else {
                             if (applicableServices.isNotEmpty && !applicableServices.any((id) => id.toString() == _selectedServiceId)) {
                               isEligible = false;
                               ineligibleReason = 'Voucher không áp dụng cho gói dịch vụ này!';
                             } else if (selectedServicePrice < minOrderValue) {
                               isEligible = false;
                               final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
                               ineligibleReason = 'Chưa đạt giá trị tối thiểu ${formatter.format(minOrderValue)}!';
                             }
                          }

                          final formatter = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
                          String discountText = 'Giảm ${v['discount_value'] ?? 0}${v['discount_type'] == 'PERCENTAGE' ? '%' : 'đ'}';
                          if (v['discount_type'] == 'PERCENTAGE' && maxDiscountAmount > 0) {
                            discountText += ' (Tối đa ${formatter.format(maxDiscountAmount)})';
                          }
                          if (minOrderValue > 0) {
                            discountText += '\nĐơn tối thiểu: ${formatter.format(minOrderValue)}';
                          }

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(v['code']?.toString() ?? 'VOUCHER', style: TextStyle(color: isEligible ? const Color(0xFF1A3A35) : const Color(0xFFB0C4C1), fontWeight: FontWeight.bold, fontSize: 15)),
                            subtitle: Text(discountText, style: TextStyle(color: isEligible ? const Color(0xFF617D79) : const Color(0xFFD1D1D6), fontSize: 12)),
                            isThreeLine: minOrderValue > 0,
                            trailing: isEligible 
                                ? const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF80BF84), size: 20)
                                : const Icon(Icons.do_not_disturb_alt_rounded, color: Color(0xFFD1D1D6), size: 18),
                            onTap: isEligible ? () {
                              setState(() {
                                _selectedVoucherCode = v['code']?.toString();
                              });
                              Navigator.pop(context);
                            } : () {
                              AppToast.show(context: context, message: ineligibleReason, isSuccess: false);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ==================== STEP 2: COMMERCE METADATA FORM ====================
  Widget _buildStep2Metadata() {
    final String currentRole = _userRole.trim().toUpperCase();
    final double statusBarPadding = MediaQuery.paddingOf(context).top;
        
    final bool isUserRole = currentRole == "USER";
    final bool isCreatorRole = currentRole == "CREATOR";
    final bool isPartnerRole = currentRole == "PARTNER_ADMIN" || currentRole == "PARTNER";

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.only(left: 24, right: 24, top: statusBarPadding + 16, bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Phân tầng UI bằng cấu hình rẽ nhánh Role độc lập bọc thép chuẩn Private Profile
                if (isPartnerRole) ...[
                  _buildFormSectionTitle("Chế độ đăng tải video"),
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A35).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1A3A35).withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _partnerPublishMode = "TIKTOK_FEED"),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _partnerPublishMode == "TIKTOK_FEED" ? const Color(0xFF1A3A35) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.dynamic_feed_rounded, size: 16, color: _partnerPublishMode == "TIKTOK_FEED" ? Colors.white : const Color(0xFF617D79)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "TikTok Feeds",
                                    style: TextStyle(
                                      color: _partnerPublishMode == "TIKTOK_FEED" ? Colors.white : const Color(0xFF617D79),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _partnerPublishMode = "SERVICE_VIDEO"),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _partnerPublishMode == "SERVICE_VIDEO" ? const Color(0xFF1A3A35) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.medical_information_rounded, size: 16, color: _partnerPublishMode == "SERVICE_VIDEO" ? Colors.white : const Color(0xFF617D79)),
                                  const SizedBox(width: 8),
                                  Text(
                                    "Video dịch vụ",
                                    style: TextStyle(
                                      color: _partnerPublishMode == "SERVICE_VIDEO" ? Colors.white : const Color(0xFF617D79),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  _buildFormSectionTitle("Thông tin bài đăng đối tác"),
                  _buildTextField(controller: _titleController, hint: "Nhập tiêu đề giới thiệu dịch vụ khám..."),
                  const SizedBox(height: 14),
                  _buildTextField(controller: _descriptionController, hint: "Mô tả chi tiết phác đồ trị liệu hoặc cơ sở vật chất...", maxLines: 3),
                  const SizedBox(height: 24),
                  
                  _buildFormSectionTitle("Cấu hình thương mại Đối tác"),
                  
                  // Trường giá hiển thị ở cả 2 tab nhưng có thuộc tính khóa linh hoạt và cấu hình gợi ý riêng
                  Text(
                    _partnerPublishMode == "SERVICE_VIDEO" 
                        ? 'Giá gói dịch vụ khám (Bắt buộc đối với Đối tác) *' 
                        : 'Giá gói dịch vụ tham khảo (Không bắt buộc)', 
                    style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.bold)
                  ),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (context) {
                      double originalPrice = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                      double discountAmount = 0.0;
                      bool hasValidVoucher = false;

                      if (_selectedVoucherCode != null && originalPrice > 0) {
                        try {
                          final v = _partnerAvailableVouchers.firstWhere((element) => element['code']?.toString() == _selectedVoucherCode);
                          double discountValue = double.tryParse(v['discount_value']?.toString() ?? '0') ?? 0.0;
                          double maxDiscount = double.tryParse(v['max_discount_amount']?.toString() ?? '0') ?? 0.0;
                          
                          if (v['discount_type'] == 'PERCENTAGE') {
                            discountAmount = (discountValue / 100) * originalPrice;
                            if (maxDiscount > 0 && discountAmount > maxDiscount) {
                              discountAmount = maxDiscount;
                            }
                          } else {
                            discountAmount = discountValue;
                          }
                          if (discountAmount > 0) {
                            hasValidVoucher = true;
                          }
                        } catch (_) {}
                      }

                      if (hasValidVoucher) {
                        final double finalPrice = (originalPrice - discountAmount).clamp(0.0, double.infinity);
                        final currencyFormatter = NumberFormat('#,###', 'vi_VN');

                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F5),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFE2ECEB), width: 1.2),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '${currencyFormatter.format(originalPrice)} VND',
                                style: TextStyle(
                                  color: const Color(0xFF1A3A35).withOpacity(0.4),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: const Color(0xFF1A3A35).withOpacity(0.4),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF80BF84)),
                              const SizedBox(width: 12),
                              Text(
                                '${currencyFormatter.format(finalPrice)} VND',
                                style: const TextStyle(
                                  color: Color(0xFF1A3A35),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      return _buildTextField(
                        controller: _priceController, 
                        hint: _selectedServiceName != null ? "Sử dụng giá của gói dịch vụ đã ghim" : "Nhập giá bán dịch vụ y khoa (VND)...", 
                        keyboardType: TextInputType.number,
                        readOnly: _selectedServiceName != null || hasValidVoucher // Tự động khóa cứng nếu đã chọn dịch vụ hoặc áp dụng voucher
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  
                  if (_partnerPublishMode == "SERVICE_VIDEO") ...[
                    const Text('% Hoa hồng chi trả cho Creator Affiliate *', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    _buildTextField(controller: _commissionController, hint: "Nhập tỷ lệ hoa hồng trích lập từ dịch vụ (Ví dụ: 15)...", keyboardType: TextInputType.number),
                    const SizedBox(height: 20),
                  ],
                  
                  _buildSelectableTile(
                    icon: Icons.maps_home_work_rounded,
                    label: "Gắn thẻ Cơ sở Wellness",
                    value: "Hệ thống tự động ghim cơ sở của bạn",
                    onTap: null,
                  ),
                  const Divider(height: 1, color: Color(0xFFE2ECEB)),
                  _buildSelectableTile(
                    icon: Icons.medical_services_rounded,
                    label: "Liên kết Gói dịch vụ y khoa",
                    value: _selectedServiceName ?? "Nhúng gói trị liệu nền tảng...",
                    onTap: () {
                      // 🚀 ĐỒNG BỘ UI: Map lại danh sách dịch vụ để hiển thị rõ Giá tiền (Dấu chấm hàng nghìn)
                      final formattedServices = _partnerAvailableServices.map((s) {
                        final double price = double.tryParse(s['price']?.toString() ?? '0') ?? 0;
                        final String priceStr = NumberFormat('#,###', 'en_US').format(price).replaceAll(',', '.');
                        return {
                          ...s,
                          'display_name': "${s['service_name']} ($priceStr VND)",
                        };
                      }).toList();

                      _showSelectionBottomSheet(
                        title: "Chọn Gói dịch vụ y khoa của bạn",
                        items: formattedServices,
                        itemTitleKey: "display_name", // Sử dụng key mới bọc giá tiền
                        itemValueKey: "id",
                        onSelected: (displayName, id) {
                          final selectedSvc = _partnerAvailableServices.firstWhere((element) => element['id'].toString() == id);
                          final double svcPrice = double.tryParse(selectedSvc['price']?.toString() ?? '0') ?? 0;
                          final String priceStr = NumberFormat('#,###', 'en_US').format(svcPrice).replaceAll(',', '.');
                          
                          setState(() {
                            _selectedServiceName = selectedSvc['service_name']; // Vẫn lưu tên gốc
                            _selectedServiceId = id;
                            _priceController.text = '$priceStr VND'; // Khóa và gán cứng giá trị có format
                          });
                        },
                      );
                    },
                    onRemove: _selectedServiceName == null ? null : () {
                      setState(() {
                        _selectedServiceName = null;
                        _selectedServiceId = null;
                        _priceController.clear(); // Giải phóng gán cứng, cho phép tự do nhập giá
                      });
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFE2ECEB)),
                  _buildSelectableTile(
                    icon: Icons.local_offer_rounded,
                    label: "Đính kèm Mã ưu đãi độc quyền",
                    value: _selectedVoucherCode ?? "Chọn Voucher cơ sở kích thích đặt hẹn...",
                    onTap: () {
                      double currentPrice = double.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0.0;
                      if (currentPrice <= 0 && _selectedServiceId == null) {
                        AppToast.show(context: context, message: 'Vui lòng nhập giá dịch vụ hoặc liên kết gói dịch vụ trước khi chọn Voucher!', isSuccess: false);
                        return;
                      }
                      _showPartnerVouchersBottomSheet();
                    },
                    onRemove: _selectedVoucherCode == null ? null : () {
                      setState(() {
                        _selectedVoucherCode = null;
                      });
                    },
                  ),
                ] else if (isCreatorRole) ...[
                  _buildFormSectionTitle("Studio sáng tạo - Tiếp thị liên kết (Creator)"),
                  _buildTextField(controller: _titleController, hint: "Nhập tiêu đề truyền cảm hứng hoặc kiến thức y khoa..."),
                  const SizedBox(height: 14),
                  _buildTextField(controller: _descriptionController, hint: "Thêm lời khuyên, hastag hoặc tóm tắt nội dung video ngắn...", maxLines: 3),
                  const SizedBox(height: 14),
                  
                  // TRƯỜNG GIÁ ĐƯỢC CHUYỂN LÊN ĐÂY
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 14, color: Color(0xFF80BF84)),
                        const SizedBox(width: 6),
                        const Expanded(child: Text('Giá dịch vụ (Hệ thống tự động đồng bộ từ Đối tác, không thể sửa)', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      double originalPrice = 0.0;
                      if (_selectedServiceId != null) {
                        try {
                          final selectedSvc = _creatorPartnerServices.firstWhere((s) => s['id'].toString() == _selectedServiceId);
                          originalPrice = double.tryParse(selectedSvc['price']?.toString() ?? '0') ?? 0.0;
                        } catch (_) {}
                      }

                      double discountAmount = 0.0;
                      bool hasValidVoucher = false;
                      if (_selectedVoucherCode != null && _selectedServiceId != null) {
                        try {
                          final v = _creatorPartnerVouchers.firstWhere((element) => element['code']?.toString() == _selectedVoucherCode);
                          double discountValue = double.tryParse(v['discount_value']?.toString() ?? '0') ?? 0.0;
                          double maxDiscount = double.tryParse(v['max_discount_amount']?.toString() ?? '0') ?? 0.0;
                          
                          if (v['discount_type'] == 'PERCENTAGE') {
                            discountAmount = (discountValue / 100) * originalPrice;
                            if (maxDiscount > 0 && discountAmount > maxDiscount) {
                              discountAmount = maxDiscount;
                            }
                          } else {
                            discountAmount = discountValue;
                          }
                          if (discountAmount > 0) {
                            hasValidVoucher = true;
                          }
                        } catch (_) {}
                      }

                      if (hasValidVoucher) {
                            final double finalPrice = (originalPrice - discountAmount).clamp(0.0, double.infinity);
                            
                            // 🚀 BỌC THÉP FORMAT GIÁ: Ép dấu chấm hàng nghìn chuẩn xác
                            String formatPrice(double p) => NumberFormat('#,###', 'en_US').format(p).replaceAll(',', '.');

                            return Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F5),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFE2ECEB), width: 1.2),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    '${formatPrice(originalPrice)} VND',
                                    style: TextStyle(
                                      color: const Color(0xFF1A3A35).withOpacity(0.4),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: const Color(0xFF1A3A35).withOpacity(0.4),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF80BF84)),
                                  const SizedBox(width: 12),
                                  Text(
                                    '${formatPrice(finalPrice)} VND',
                                    style: const TextStyle(
                                      color: Color(0xFF1A3A35),
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          return _buildTextField(
                            controller: _priceController, 
                            hint: _selectedServiceName != null ? "Sử dụng giá của gói dịch vụ đã ghim" : "Nhập giá bán dịch vụ y khoa (VND)...", 
                            keyboardType: TextInputType.number,
                            readOnly: _selectedServiceName != null // Bỏ khóa voucher, chỉ khóa khi nhúng dịch vụ
                          );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  _buildFormSectionTitle("Doanh thu Tiếp thị liên kết (Affiliate Engine)"),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF80BF84).withOpacity(0.08), 
                      borderRadius: BorderRadius.circular(16), 
                      border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.2))
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.monetization_on_rounded, color: Color(0xFF80BF84), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: const Text(
                            "Hệ thống tự động mở khóa tính năng nhận chiết khấu hoa hồng liên kết (10% - 25%) từ Đối tác y tế sau khi duyệt video.", 
                            style: TextStyle(color: Color(0xFF1A3A35), fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildSelectableTile(
                    icon: Icons.maps_home_work_rounded,
                    label: "Gắn thẻ Cơ sở Wellness",
                    value: _selectedPartnerName ?? "Chọn đối tác Affiliate...",
                    onTap: () {
                      _showSelectionBottomSheet(
                        title: "Chọn Đối tác liên kết (Affiliate)",
                        items: _creatorApprovedPartners,
                        itemTitleKey: "full_name",
                        itemValueKey: "partner_id",
                        onSelected: (name, id) {
                          setState(() {
                            _selectedPartnerName = name;
                            _selectedPartnerId = id;
                            // Reset Dịch vụ và Voucher khi đổi Đối tác
                            _selectedServiceName = null;
                            _selectedServiceId = null;
                            _selectedVoucherCode = null;
                            _priceController.clear();
                            _creatorPartnerServices.clear();
                            _creatorPartnerVouchers.clear();
                          });
                          _loadCreatorPartnerServices(id); // Gọi API kéo dịch vụ của Đối tác vừa chọn
                          
                          // 🚀 BỌC THÉP NULL SAFETY: Tránh crash hệ thống khi tìm kiếm
                          try {
                            final partner = _creatorApprovedPartners.firstWhere((p) => p['partner_id'] == id);
                            if (partner['username'] != null) {
                              _loadCreatorPartnerVouchers(partner['username']);
                            }
                          } catch (_) {
                            // Không tìm thấy hoặc lỗi cấu trúc, bỏ qua an toàn
                          }
                        },
                      );
                    },
                    onRemove: _selectedPartnerName == null ? null : () {
                      setState(() {
                        _selectedPartnerName = null;
                        _selectedPartnerId = null;
                        _selectedServiceName = null;
                        _selectedServiceId = null;
                        _selectedVoucherCode = null;
                        _priceController.clear();
                        _creatorPartnerServices.clear();
                        _creatorPartnerVouchers.clear();
                      });
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFE2ECEB)),
                  _buildSelectableTile(
                    icon: Icons.medical_services_rounded,
                    label: "Liên kết Gói dịch vụ y khoa",
                    value: _selectedServiceName ?? "Nhúng gói trị liệu nền tảng...",
                    onTap: _selectedPartnerId == null ? null : () {
                      _showCreatorServicesBottomSheet();
                    },
                    onRemove: _selectedServiceName == null ? null : () {
                      setState(() {
                        _selectedServiceName = null;
                        _selectedServiceId = null;
                        _priceController.clear();
                      });
                    },
                  ),
                  const Divider(height: 1, color: Color(0xFFE2ECEB)),
                  _buildSelectableTile(
                    icon: Icons.local_offer_rounded,
                    label: "Đính kèm Mã ưu đãi độc quyền",
                    value: _selectedVoucherCode ?? "Chọn Voucher công khai kích thích chuyển đổi...",
                    onTap: _selectedPartnerId == null ? null : () {
                      _showCreatorVouchersBottomSheet();
                    },
                    onRemove: _selectedVoucherCode == null ? null : () {
                      setState(() {
                        _selectedVoucherCode = null;
                      });
                    },
                  ),
                ] else ...[
                  // Mặc định hoặc USER ROLE - Khóa chặt không gian thương mại, tập trung chia sẻ nhật ký cá nhân Wellness
                  _buildFormSectionTitle("Nhật ký chia sẻ trải nghiệm (Thành viên)"),
                  _buildTextField(controller: _titleController, hint: "Nhập tiêu đề hoặc cảm nghĩ về hành trình sức khỏe của bạn..."),
                  const SizedBox(height: 14),
                  _buildTextField(controller: _descriptionController, hint: "Thêm mô tả chi tiết, câu chuyện thay đổi bản thân (tùy chọn)...", maxLines: 3),
                  const SizedBox(height: 24),
                  
                  _buildFormSectionTitle("Cấu hình thương mại / Tiếp thị liên kết"),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF1A3A35).withOpacity(0.08)),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.01), blurRadius: 10)],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: const Color(0xFF1A3A35).withOpacity(0.05), shape: BoxShape.circle),
                          child: const Icon(Icons.lock_clock_rounded, color: Color(0xFF1A3A35), size: 32),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "MỞ KHÓA TÍNH NĂNG KIẾM TIỀN",
                          style: TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                        ),
                        const SizedBox(height: 6),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            "Nhúng link gói dịch vụ, gắn thẻ cơ sở y tế và nhận hoa hồng liên kết tự động. Kích hoạt tức thì khi nâng cấp thành Chuyên gia (Creator)!",
                            style: TextStyle(color: Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.w500, height: 1.4),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1A3A35),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          onPressed: () {
                            AppToast.show(context: context, message: "Đang chuyển hướng đến cổng nộp đơn nâng cấp Creator...", isSuccess: true);
                          },
                          icon: const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF80BF84)),
                          label: const Text("Nâng cấp ngay", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        )
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 32),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, -4))],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE2ECEB), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      foregroundColor: const Color(0xFF617D79),
                    ),
                    onPressed: _isSubmitting ? null : _previousStep,
                    child: const Text("Quay lại", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 7,
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      disabledBackgroundColor: const Color(0xFFD1D1D6),
                    ),
                    onPressed: _isSubmitting ? null : _handlePublish,
                    child: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text("ĐĂNG BÀI CHỜ DUYỆT", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== TRỢ NĂNG BUILDER COMPONENTS ====================
  Widget _buildFormSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Text(title, style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String hint, int maxLines = 1, TextInputType keyboardType = TextInputType.text, bool readOnly = false}) {
    return Container(
      decoration: BoxDecoration(
        color: readOnly ? const Color(0xFFF1F5F5) : Colors.white, // Đổi màu nền xám mờ sang trọng khi bị khóa gán cứng
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2ECEB), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A3A35).withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        readOnly: readOnly,
        style: TextStyle(color: readOnly ? const Color(0xFF617D79) : const Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: const Color(0xFF1A3A35).withOpacity(0.35), fontSize: 13, fontWeight: FontWeight.w400),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildSelectableTile({required IconData icon, required String label, required String value, required VoidCallback? onTap, VoidCallback? onRemove}) {
    final bool isDisabled = onTap == null;
    final bool hasValue = onRemove != null;

    return InkWell(
      onTap: hasValue ? null : onTap, // Khóa click mở modal nếu đã chọn liên kết dữ liệu rồi
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: isDisabled ? const Color(0xFFD1D1D6) : const Color(0xFF80BF84)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: isDisabled ? const Color(0xFFB0C4C1) : const Color(0xFF617D79), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 3),
                  Text(value, style: TextStyle(color: isDisabled ? const Color(0xFFD1D1D6) : const Color(0xFF1A3A35), fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (hasValue)
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.link_off_rounded, size: 18, color: Colors.redAccent),
                onPressed: onRemove,
              )
            else
              Icon(Icons.chevron_right_rounded, size: 18, color: isDisabled ? const Color(0xFFD1D1D6) : const Color(0xFFB0C4C1)),
          ],
        ),
      ),
    );
  }
}

// --- 🚀 TOÁN HỌC CANVAS CHUYỂN ĐỔI: VẼ QUẢ CẦU WELLNESS HOLOGRAM NĂNG LƯỢNG 3D MƯỢT MÀ ---
class _StudioOrbPainter extends CustomPainter {
  final double progress;
  _StudioOrbPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double baseRadius = size.width / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final paintOrb = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF80BF84).withOpacity(0.35),
          const Color(0xFFB0C4C1).withOpacity(0.15),
          const Color(0xFF80BF84).withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.6))
      ..style = PaintingStyle.fill;

    // Lõi năng lượng phát sáng khuếch tán hữu cơ
    canvas.drawCircle(center, baseRadius, paintOrb);

    final paintLine = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final int particleCount = 28;

    // Thuật toán lượng giác vẽ các vòng hạt sóng điện từ ép góc Elip tạo không gian 3D
    for (int layer = 0; layer < 3; layer++) {
      paintLine.color = const Color(0xFF1A3A35).withOpacity(0.35 - (layer * 0.1));
      final path = Path();

      for (int i = 0; i <= particleCount; i++) {
        final double angle = (i * 2 * math.pi) / particleCount;
        final double wave = math.sin(angle * (layer + 2) + (progress * 2 * math.pi)) * 4.0;
        final double r = baseRadius + wave;
        
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle) * (0.6 + (layer * 0.15));

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paintLine);
    }
  }

  @override
  bool shouldRepaint(covariant _StudioOrbPainter oldDelegate) => true;
}