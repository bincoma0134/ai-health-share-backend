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


class DedicatedUploadScreen extends StatefulWidget {
  const DedicatedUploadScreen({super.key});

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

  // Trạng thái Bước 2 (Metadata Form)
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  
  String? _selectedPartnerName;
  String? _selectedServiceName;
  String? _selectedVoucherCode;
  
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // 🚀 ĐỒNG BỘ: Kích hoạt chặn âm thanh Feeds ngay khi Studio khởi tạo
    AudioFocusManager.instance.requestMode(AppAudioMode.studioActive);
    
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(); // Kích hoạt luồng quay vô hạn tạo sóng hạt Hologram 3D mượt màng
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

          // 🚀 KHỞI ĐỘNG LUỒNG TIỀN TẢI LÊN NGẦM SƠ BỘ: Đẩy tệp thô lên trước để chiếm băng thông
          _startBackgroundProcessing();
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

    // ĐỒNG BỘ ĐIỂM CHẶN CUỐI CÙNG: Chỉ kiểm tra cờ tải lên ngầm tại thời điểm xuất bản biểu mẫu
    final bool isUpToDate = (_trimStartPercent == _lastUploadedStartPercent) && (_trimEndPercent == _lastUploadedEndPercent);
    
    if (_isUploadingNgam || !isUpToDate || _finalCloudVideoUrl.isEmpty) {
      // Nếu người dùng điền biểu mẫu quá nhanh mà luồng ngầm chưa xử lý xong byte cuối, hiển thị tiến trình thực tế
      AppToast.show(
        context: context, 
        message: "Hệ thống đang hoàn tất truyền tải video phân đoạn (${(_uploadNgamProgress * 100).toInt()}%). Vui lòng đợi trong giây lát!", 
        isSuccess: false
      );
      
      // Khởi động lại luồng xử lý nếu phát hiện sự sai lệch cấu hình biên do bị hủy giữa chừng
      if (!isUpToDate && !_isUploadingNgam) {
        _startBackgroundProcessing();
      }
      return;
    }

    setState(() => _isSubmitting = true);

    // 🚀 ĐÓNG GÓI SIÊU TỐC TỨC THỜI (0ms): Lấy thẳng URL mạng đã chạy ngầm xong từ trước đẩy đi
    final Map<String, dynamic> payload = {
      'title': _titleController.text.trim(),
      'content': _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      'price': _priceController.text.trim().isEmpty ? null : double.tryParse(_priceController.text.trim()),
      'video_url': _finalCloudVideoUrl, // URL mạng bọc vàng bảo chứng đoạn đã cắt ngắn vật lý
      'partner_name': _selectedPartnerName,
      'service_name': _selectedServiceName,
      'voucher_code': _selectedVoucherCode,
      'trim_start_percent': _trimStartPercent,
      'trim_end_percent': _trimEndPercent,
    };

    try {
      final res = await ApiClient.instance.post('/tiktok/feeds', data: payload);
      if (res.statusCode == 200) {
        // Giải phóng hoàn toàn trạng thái âm thanh lỗi ngầm trước khi pop đóng màn hình
        FeedVideoPool.isGlobalMutedForUpload = false;
        if (mounted) {
          AppToast.show(context: context, message: "Gửi video lên hàng đợi duyệt thành công!", isSuccess: true);
          context.pop();
        }
      } else {
        if (mounted) AppToast.show(context: context, message: "Lỗi gửi dữ liệu lên máy chủ!", isSuccess: false);
      }
    } catch (e) {
      if (mounted) AppToast.show(context: context, message: "Kết nối máy chủ thất bại!", isSuccess: false);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
        backgroundColor: _currentStep == 0 ? Colors.black : const Color(0xFFF7FBF9), // Bước 1 dùng Dark Studio nền đen sang trọng chuyên nghiệp
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
            color: Colors.black,
            child: _uploadedVideoUrl.isNotEmpty
                ? MiniVideoPlayer(
                    videoUrl: _uploadedVideoUrl, 
                    isMuted: _isMuted,
                    trimStartPercent: _trimStartPercent,
                    trimEndPercent: _trimEndPercent,
                    onProgressUpdate: (progress) {
                      // 🚀 TỐI ƯU 60FPS: Cập nhật trực tiếp giá trị vào notifier mà không thông qua setState cha
                      _trimPlaybackProgressNotifier.value = progress;
                    },
                  )
                : (_currentMode == "CAMERA"
                    ? const Center(child: Text("Camera view đang khởi động luồng phần cứng...", style: TextStyle(color: Colors.white54, fontSize: 13)))
                    : Center(
                        child: GestureDetector(
                          onTap: _isLockingAction ? null : _pickVideoFromGallery,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // KHỐI RENDER TOÁN HỌC CANVAS ORB ANIMATION CAO CẤP TRÍCH XUẤT TỪ AI CHAT
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
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                "Nơi lan tỏa kiến thức bảo chứng và giá trị Wellness",
                                style: TextStyle(
                                  color: Colors.white38,
                                  fontSize: 11,
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

        // 2. III. NÂNG CẤP HOÀN THIỆN ĐỈNH MÀN HÌNH (TOP BAR PREMIUM GLASS LAYOUT)
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
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 26),
                onPressed: () async {
                  final shouldPop = await _onWillPop();
                  if (shouldPop && mounted) context.pop();
                },
              ),
              // Thanh trạng thái Kính mờ Premium thay thế hoàn toàn thanh chọn âm thanh cũ của TikTok
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.verified_rounded, color: Color(0xFF80BF84), size: 16),
                    SizedBox(width: 6),
                    Text(
                      "Chế độ Sáng tạo nội dung",
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
              // Điểm điều hướng tiến độ 2 bước tinh tế
              Row(
                children: [
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle)),
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
            bottom: 140, // Nằm cân đối phía trên dải nút Shutter chính
            left: 24,
            right: 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("${(_trimStartPercent * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                    // Hiển thị động tiến độ xử lý ngầm của YouTube Shorts
                    Text(
                      _isUploadingNgam 
                          ? "Đang xử lý video: ${(_uploadNgamProgress * 100).toInt()}%" 
                          : "Đoạn video đăng tải ngắn (Đã sẵn sàng)", 
                      style: TextStyle(color: _isUploadingNgam ? Colors.amberAccent : const Color(0xFF80BF84), fontSize: 10, fontWeight: FontWeight.bold)
                    ),
                    Text("${(_trimEndPercent * 100).toInt()}%", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;

                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          // 1. Lớp nền dải trượt biên đôi của YouTube
                          RangeSlider(
                            values: RangeValues(_trimStartPercent, _trimEndPercent),
                            min: 0.0,
                            max: 1.0,
                            activeColor: const Color(0xFF80BF84),
                            inactiveColor: Colors.white10,
                            onChangeEnd: (RangeValues values) {
                              // Chặn bớt các nhấp chuột gạt biên quá nhanh của người dùng trước khi tính toán file nặng
                              _debounceTrimTimer?.cancel();
                              _debounceTrimTimer = Timer(const Duration(milliseconds: 600), () {
                                if (mounted) {
                                  _startBackgroundProcessing();
                                }
                              });
                            },
                            onChanged: (RangeValues values) {
                              if (values.end - values.start >= 0.05) {
                                setState(() {
                                  _trimStartPercent = values.start;
                                  _trimEndPercent = values.end;
                                  _trimPlaybackProgressNotifier.value = 0.0; // Reset kim về đầu biên trượt khi chỉnh biên
                                });
                              }
                            },
                          ),
                          // 2. KIM PHÁT ĐỘNG PHẢN HỒI 60FPS cô lập (PLAYBACK NEEDLE WITH MICROTICK LERPING)
                          IgnorePointer(
                            child: ValueListenableBuilder<double>(
                              valueListenable: _trimPlaybackProgressNotifier,
                              builder: (context, progress, child) {
                                final currentProgressPercent = _trimStartPercent + (progress * (_trimEndPercent - _trimStartPercent));
                                final targetLeft = currentProgressPercent * width;

                                return Stack(
                                  children: [
                                    // Sử dụng AnimatedPositioned với thời gian lerp cực ngắn để làm mượt hoàn toàn các bước nhảy FPS của Controller
                                    AnimatedPositioned(
                                      duration: const Duration(milliseconds: 40),
                                      curve: Curves.linear,
                                      left: (targetLeft - 2).clamp(0.0, width - 4),
                                      top: 2,
                                      bottom: 2,
                                      child: Container(
                                        width: 4,
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(2),
                                          boxShadow: [
                                            BoxShadow(color: Colors.black45, blurRadius: 3, offset: const Offset(1, 1))
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
            padding: const EdgeInsets.only(top: 24, bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.9), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 4.1 Hệ thống hàng nút bấm Shutter lỏng đối xứng trung tâm mới
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
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white38, width: 1.5),
                              ),
                              child: const Icon(Icons.spa_rounded, color: Color(0xFF80BF84), size: 20),
                            ),
                            const SizedBox(height: 6),
                            const Text("Nhạc thiền", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),

                      // Trung tâm: Nút hành động chính Liquid Glass - Đóng vai trò chọn tệp hoặc Next bước tiếp theo
                      GestureDetector(
                        onTap: () {
                          if (_uploadedVideoUrl.isNotEmpty) {
                            _nextStep();
                          } else {
                            if (!_isLockingAction) _pickVideoFromGallery();
                          }
                        },
                        child: Container(
                          width: 76, height: 76,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withOpacity(0.6), width: 4),
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _uploadedVideoUrl.isNotEmpty 
                                  ? const Color(0xFF80BF84) // Đổi sang màu ngọc xanh nếu có tệp để sẵn sàng Next
                                  : const Color(0xFF1A3A35),
                            ),
                            child: Icon(
                              _uploadedVideoUrl.isNotEmpty ? Icons.arrow_forward_rounded : Icons.video_library_rounded, // 🚀 CẬP NHẬT: Thay thế icon quay thành icon thư viện
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),

                      // Vệ tinh Phải: Trạng thái hiển thị chữ chỉ dẫn thông báo tương tác nhanh
                      Column(
                        children: [
                          Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _uploadedVideoUrl.isNotEmpty ? const Color(0xFF80BF84) : Colors.white12, width: 1.5),
                            ),
                            child: Icon(
                              _uploadedVideoUrl.isNotEmpty ? Icons.check_circle_rounded : Icons.cloud_upload_outlined,
                              color: _uploadedVideoUrl.isNotEmpty ? const Color(0xFF80BF84) : Colors.white38,
                              size: 20
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(_uploadedVideoUrl.isNotEmpty ? "Đã nhận" : "Tải lên", style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600)),
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
                color: const Color(0xFF1A3A35).withOpacity(0.5),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.2), width: 1.2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 2))
                ],
              ),
              child: Icon(icon, color: const Color(0xFFE2ECEB), size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label.toUpperCase(), 
              style: const TextStyle(
                color: Colors.white70, 
                fontSize: 8.5, 
                fontWeight: FontWeight.w700, 
                letterSpacing: 0.3
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== STEP 2: COMMERCE METADATA FORM ====================
  Widget _buildStep2Metadata() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFormSectionTitle("Thông tin bài đăng ngắn"),
                _buildTextField(controller: _titleController, hint: "Nhập tiêu đề hấp dẫn về sức khỏe..."),
                const SizedBox(height: 14),
                _buildTextField(controller: _descriptionController, hint: "Thêm mô tả chi tiết, cảm nghĩ hoặc lời khuyên chuyên gia (tùy chọn)...", maxLines: 3),
                const SizedBox(height: 24),

                _buildFormSectionTitle("Cấu hình thương mại / Tiếp thị"),
                _buildTextField(controller: _priceController, hint: "Đặt mức giá hiển thị dịch vụ (VND) nếu có...", keyboardType: TextInputType.number),
                const SizedBox(height: 16),

                _buildSelectableTile(
                  icon: Icons.maps_home_work_rounded,
                  label: "Gắn thẻ Cơ sở Wellness",
                  value: _selectedPartnerName ?? "Chọn đối tác y tế phân phối lịch hẹn...",
                  onTap: () {
                    setState(() => _selectedPartnerName = "Bệnh Viện Đa Khoa Hồng Ngọc");
                  },
                ),
                const Divider(height: 1, color: Color(0xFFE2ECEB)),
                _buildSelectableTile(
                  icon: Icons.medical_services_rounded,
                  label: "Liên kết Gói dịch vụ",
                  value: _selectedServiceName ?? "Nhúng gói trị liệu bọc hoa hồng nền tảng...",
                  onTap: _selectedPartnerName == null ? null : () {
                    setState(() => _selectedServiceName = "Gói Trị Liệu Chuyên Sâu Cơ Xương Khớp");
                  },
                ),
                const Divider(height: 1, color: Color(0xFFE2ECEB)),
                _buildSelectableTile(
                  icon: Icons.local_offer_rounded,
                  label: "Đính kèm Mã ưu đãi độc quyền",
                  value: _selectedVoucherCode ?? "Chọn Voucher công khai kích thích chuyển đổi...",
                  onTap: _selectedPartnerName == null ? null : () {
                    setState(() => _selectedVoucherCode = "WELLNESS50K");
                  },
                ),
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

  Widget _buildTextField({required TextEditingController controller, required String hint, int maxLines = 1, TextInputType keyboardType = TextInputType.text}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E5EA), width: 1),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFB0C4C1), fontSize: 13.5),
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildSelectableTile({required IconData icon, required String label, required String value, required VoidCallback? onTap}) {
    final bool isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
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
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2.5;
    
    final paintOrb = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF80BF84).withOpacity(0.85),
          const Color(0xFF1A3A35).withOpacity(0.4),
          const Color(0xFF80BF84).withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.6))
      ..style = PaintingStyle.fill;

    // Lõi năng lượng phát sáng khuếch tán hữu cơ
    canvas.drawCircle(center, baseRadius, paintOrb);

    final paintLine = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.0;
    final int particleCount = 28;

    // Thuật toán lượng giác vẽ các vòng hạt sóng điện từ ép góc Elip tạo không gian 3D
    for (int layer = 0; layer < 3; layer++) {
      paintLine.color = const Color(0xFF80BF84).withOpacity(0.5 - (layer * 0.15));
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