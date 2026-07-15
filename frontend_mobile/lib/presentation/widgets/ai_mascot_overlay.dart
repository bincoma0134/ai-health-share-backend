import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:frontend_mobile/core/network/api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/models/video_model.dart';
import '../../../data/services/notification_api_service.dart';
import 'booking_bottom_sheet.dart';
import 'auth_guard.dart'; // 🚀 Nhúng hệ thống định danh Auth
import '../screens/ai/partner_ai_chat_screen.dart'; // 🚀 Động cơ định tuyến sang luồng Chat AI Cơ sở
import 'package:rive/rive.dart' hide Animation; // 🚀 Rive namespace protection

class AiMascotOverlay extends StatefulWidget {
  final VideoModel currentVideo;
  final int videoIndex;

  const AiMascotOverlay({
    super.key,
    required this.currentVideo,
    required this.videoIndex,
  });

  @override
  State<AiMascotOverlay> createState() => _AiMascotOverlayState();
}

class _AiMascotOverlayState extends State<AiMascotOverlay> with SingleTickerProviderStateMixin {
  bool _isMascotDismissed = false;
  bool _isChatPopupOpen = false;
  String _bubbleText = '';
  
  // 🚀 QUẢN LÝ HIỆU ỨNG MỜ DẦN (FADED ANIMATION OPACITY)
  double _bubbleOpacity = 0.0;

  // 🚀 BIẾN TĨNH BẢO LƯU TRÊN RAM CHỐNG RESET KHI CUỘN VIDEO
  static bool _hasWelcomedThisSession = false;
  static DateTime? _lastNudgeTime; 

  // Quản lý Timer
  Timer? _bubbleTimer;
  Timer? _periodicCareTimer;

  // Animation cho Bong bóng thoại giật nhẹ thu hút dopamine
  late AnimationController _animationController;
  late Animation<double> _bounceAnimation;

  // 🚀 BỘ ĐIỀU KHIỂN TRẠNG THÁI RIVE MASCOT ALDO (Rive 0.14+)
  File? _riveFile;
  RiveWidgetController? _riveController;

  void _fireMascotState(String stateName) {
    final sm = _riveController?.stateMachine;
    if (sm == null) return;

    // 🚀 TÌM KIẾM INPUT THÔNG MINH KHÔNG PHÂN BIỆT CHỮ HOA CHỮ THƯỜNG
    dynamic findInput(String name) {
      try {
        return sm.inputs.firstWhere(
          (i) => i.name.toLowerCase().trim() == name.toLowerCase().trim(),
        );
      } catch (_) {
        return null;
      }
    }

    // 🚀 BỘ ÁNH XẠ TRẠNG THÁI (STATE MAPPER)
    final stateMap = <String, double>{
      'Sleep': 0.0,
      'Idle': 1.0,
      'Happy': 2.0,
      'Think': 3.0,
      'Wink': 4.0,
      'Sad': 5.0,
      'No': 6.0,
      'Upset': 7.0,
      'Mail': 8.0,
    };

    if (stateMap.containsKey(stateName)) {
      final stateInput = findInput('State');
      if (stateInput != null) {
        // Sử dụng dynamic setter để ép kiểu tự động bỏ qua rào cản Number/Enum
        stateInput.value = stateMap[stateName]!;
        return; 
      }
    }

    // 🚀 XỬ LÝ TEXT, BONG BÓNG THOẠI VÀ CHUYỂN CẢNH BẰNG DUCK TYPING (DYNAMIC RUNTIME CALL)
    final targetInput = findInput(stateName);
    if (targetInput != null) {
      try {
        // 1. Nếu đối tượng expose phương thức fire() -> Kích hoạt như một Trigger
        targetInput.fire();
        return;
      } catch (_) {
        try {
          // 2. Nếu không có fire(), thử gán value như một Boolean hoặc Number/Enum đại diện
          targetInput.value = true;
          return;
        } catch (_) {
          try {
            targetInput.value = 1.0;
            return;
          } catch (_) {}
        }
      }
    }

    // 🚀 XỬ LÝ CÁC HẬU TỐ TẮT/BẬT ĐỘNG (Off / On)
    if (stateName.toLowerCase().endsWith(' off')) {
      final baseName = stateName.substring(0, stateName.length - 4);
      final blOff = findInput(baseName);
      if (blOff != null) {
        try {
          blOff.value = false;
          return;
        } catch (_) {}
      }
    }
    if (stateName.toLowerCase().endsWith(' on')) {
      final baseName = stateName.substring(0, stateName.length - 3);
      final blOn = findInput(baseName);
      if (blOn != null) {
        try {
          blOn.value = true;
          return;
        } catch (_) {}
      }
    }

    // 4. Safe Ignore
    debugPrint("Rive State Warning: Cannot map '$stateName' to any State Number, Trigger, or Bool. Ignored safely.");
  }

  // 🚀 Tọa độ kéo thả hít biên (Mặc định ở Top-Left dưới nút Back)
  double _dx = 16.0;
  double _dy = 120.0;
  bool _isDragging = false;
  bool _isSnapping = false; // Trạng thái đang hiệu ứng hít biên mượt
  bool _isAnchoredLeft = true; // Cờ xác định bong bóng thoại lệch sang trái hay phải

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _bounceAnimation = Tween<double>(begin: 0.0, end: -6.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _loadRiveMascot();
    _initMascotState();
  }

  @override
  void didUpdateWidget(AiMascotOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoIndex != widget.videoIndex) {
      _triggerContextualNudge();
    }
  }

  @override
  void dispose() {
    _bubbleTimer?.cancel();
    _periodicCareTimer?.cancel();
    _animationController.dispose();
    _riveController?.dispose();
    _riveFile?.dispose();
    super.dispose();
  }

  // 🚀 HÀM KHỞI TẠO RIVE FILE + STATE MACHINE (API 0.14+)
  Future<void> _loadRiveMascot() async {
    try {
      final file = await File.asset(
        'assets/lottie/27606-52145-aldo.riv',
        riveFactory: Factory.rive,
      );
      if (!mounted || file == null) return;

      _riveFile = file;
      _riveController = RiveWidgetController(
        file,
        stateMachineSelector: StateMachineSelector.byName('State Machine 1'),
      );

      if (mounted) setState(() {});

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final sm = _riveController?.stateMachine;
        if (sm == null) {
          debugPrint('🚨 [CRITICAL] KHÔNG THỂ KẾT NỐI STATE MACHINE');
          return;
        }

        debugPrint('====================================================');
        debugPrint('🔍 [RIVE CORE MAP] DỮ LIỆU INPUT THỰC TẾ TRÊN RAM');
        debugPrint('====================================================');
        for (var input in sm.inputs) {
          debugPrint('👉 INPUT TÊN: "${input.name}" | TYPE: ${input.runtimeType}');
        }
        debugPrint('====================================================');
      });
    } catch (e) {
      debugPrint('🚨 Rive load failed: $e');
    }
  }

  // 🚀 KHỞI TẠO TOÀN DIỆN VỚI DELAY VÀ CHUỖI HỘI THOẠI CHÀO MỪNG FADED
  Future<void> _initMascotState() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Mascot chỉ bị tắt trong RAM của phiên hiện tại.
// Khi app bị kill và mở lại, static state reset → mascot xuất hiện lại.
_isMascotDismissed = false;
    _dx = prefs.getDouble('mascot_dx') ?? 16.0;
    _dy = prefs.getDouble('mascot_dy') ?? 120.0;
    _isAnchoredLeft = _dx < 100;
    
    if (_isMascotDismissed) {
      setState(() {});
      return;
    }

    // 🚀 LỚP TRỄ CHUẨN (2 GIÂY SPLASH SCREEN SAFETY DELAY)
    Timer(const Duration(milliseconds: 2000), () async {
      if (!mounted || _isMascotDismissed || _isChatPopupOpen) return;

      // Kiểm tra trạng thái xóa đa nhiệm qua biến RAM static
      if (!_hasWelcomedThisSession) {
        _hasWelcomedThisSession = true;

        // Phân tích tham số thời gian thực lấy buổi trong ngày
        final hour = DateTime.now().hour;
        String timeOfDay = 'buổi tối';  
        if (hour >= 5 && hour < 11) {
          timeOfDay = 'buổi sáng';
        } else if (hour >= 11 && hour < 14) {
          timeOfDay = 'buổi trưa';
        } else if (hour >= 14 && hour < 18) {
          timeOfDay = 'buổi chiều';
        }

        // Tên fallback lấy trực tiếp từ hệ thống định danh người dùng đăng nhập hiện tại giống hệt Booking Bottom Sheet
        String displayName = 'bạn';
        try {
          final res = await ApiClient.instance.get('/user/profile');
          final dynamic userData = res.data;
          if (userData != null) {
            Map<String, dynamic> data = {};
            if (userData is Map && userData.containsKey('data') && userData['data'] is Map && userData['data'].containsKey('profile')) {
              data = userData['data']['profile'];
            }
            if (data.isNotEmpty) {
              final name = data['full_name'] ?? data['fullName'] ?? data['name'] ?? '';
              if (name.toString().trim().isNotEmpty) {
                // Bảo lưu toàn bộ chuỗi tên hiển thị đầy đủ của tài khoản đăng nhập
                displayName = name.toString().trim();
              }
            }
          }
        } catch (_) {
          displayName = 'bạn'; // Fallback im lặng nếu mất kết nối hoặc chưa đăng nhập
        }

        // THỰC THI CHUỖI HỘI THOẠI TUẦN TỰ FADED (2 giây / câu)
        _fireMascotState('Text-Hello'); // 🚀 Mascot: Vẫy tay và hiện Text Hello
        _fireMascotState('Happy'); // 🚀 Mascot: Cười thân thiện
        await _executeFadedDialogue('Chào mừng $displayName trở lại VN Share!');
        await _executeFadedDialogue('Chúc $displayName có một $timeOfDay nhiều năng lượng.');
        await _executeFadedDialogue('Ngày hôm nay của bạn thế nào?');
        
        _lastNudgeTime = DateTime.now(); // Ghi nhận mốc để tính cooldown nudge lướt video
      } else {
        _triggerContextualNudge();
      }
    });

    // Vòng lặp định kỳ 10 phút thầm thì quan tâm
    _periodicCareTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      if (!mounted || _isMascotDismissed || _isChatPopupOpen) return;
      
      final greetings = [
        'Bạn đã lướt video 10 phút rồi đấy, chớp mắt vài cái và uống một ngụm nước ấm cùng tớ nhé!',
        'Ngồi lâu mỏi lưng, bạn nhớ vươn vai thư giãn một chút nha!',
        'Đừng quên kiểm tra điểm số sinh lực Wellness của bạn hôm nay nha!'
      ];
      
      final randomCare = greetings[DateTime.now().millisecond % greetings.length];
      _showTransientBubble(randomCare);
    });

    setState(() {});
  }

  // 🚀 HÀM BẤT ĐỒNG BỘ ĐIỀU KHIỂN CHUỖI FADED QUEUE
  Future<void> _executeFadedDialogue(String text) async {
    if (!mounted || _isChatPopupOpen) return;
    
    setState(() {
      _bubbleText = text;
      _bubbleOpacity = 1.0; // Hiện ra mịn màng
    });
    HapticFeedback.selectionClick();

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;

    setState(() {
      _bubbleOpacity = 0.0; // Biến mất dần (Faded)
    });
    await Future.delayed(const Duration(milliseconds: 300)); // Đợi hoạt họa mờ kết thúc
  }

  void _showTransientBubble(String text, {int durationSeconds = 3}) {
    _bubbleTimer?.cancel();
    setState(() {
      _bubbleText = text;
      _bubbleOpacity = 1.0;
    });
    HapticFeedback.selectionClick();
    
    _bubbleTimer = Timer(Duration(seconds: durationSeconds), () {
      if (mounted) setState(() => _bubbleOpacity = 0.0);
    });
  }

  // 🚀 SỬA LỖI SPAM: CHỈ CHO PHÉP BUNG BONG BÓNG LƯỚT VIDEO SAU MỖI 5 - 10 PHÚT
  void _triggerContextualNudge() {
    _bubbleTimer?.cancel();
    if (mounted) setState(() => _bubbleOpacity = 0.0);

    final now = DateTime.now();
    // Khóa điều kiện biên: Nếu chưa đủ 5 phút Cooldown lướt video -> Hủy bỏ, chặn spam lặp tin
    if (_lastNudgeTime != null && now.difference(_lastNudgeTime!).inMinutes < 5) {
      return; 
    }

    _bubbleTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted || _isMascotDismissed || _isChatPopupOpen || _isDragging) return;

      final title = widget.currentVideo.title.toLowerCase();
      if (title.contains('spa') || title.contains('massage')) {
        _bubbleText = 'Cơ thể bạn đang căng thẳng mỏi mệt đúng không?';
      } else if (widget.currentVideo.price > 0) {
        _bubbleText = 'Gói trị liệu y khoa này đang trống lịch hẹn hỏa tốc đấy!';
      } else {
        _bubbleText = 'Bạn cần tớ tư vấn thêm thông tin sức khỏe nào không?';
      }

      _lastNudgeTime = now; // Cập nhật mốc thời gian khóa

      setState(() => _bubbleOpacity = 1.0);
      HapticFeedback.selectionClick(); 
      _fireMascotState('Think'); // 🚀 Mascot: Nghiêng đầu suy nghĩ tư vấn
      _fireMascotState('Text-How');   // 🚀 Mascot: Bật bong bóng mồi câu

      _bubbleTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _bubbleOpacity = 0.0);
      });
    });
  }

  // 🚀 THUẬT TOÁN KÉO THẢ VÀ HÍT BIÊN
  void _onPanStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _isSnapping = false;
      _bubbleOpacity = 0.0; // Ẩn chữ đi khi đang kéo cho gọn thông qua Opacity
    });
    _fireMascotState('Click');     // 🚀 Mascot: Chuyển tư thế nhấc chân, co người (Vật lý)
    _fireMascotState('Follow Off'); // 🚀 Mascot: Ngắt Tracking ánh mắt để lướt tự do
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _dx += details.delta.dx;
      _dy += details.delta.dy;
    });
  }

  Future<void> _onPanEnd(DragEndDetails details) async {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    
    setState(() {
      _isDragging = false;
      _isSnapping = true; // Bật hiệu ứng animation hít biên
    });

    // 1. Giới hạn chống tràn trục Y (tránh chìm vào tai thỏ hoặc thanh bottom bar)
    if (_dy < safeAreaTop + 16) _dy = safeAreaTop + 16;
    if (_dy > screenHeight - 200) _dy = screenHeight - 200;

    // 2. Toán học Hít Biên Trục X (Trái hoặc Phải)
    final double mascotSize = 52.0;
    if (_dx + (mascotSize / 2) < screenWidth / 2) {
      _dx = 16.0; // Hít sát biên trái
      _isAnchoredLeft = true;
    } else {
      _dx = screenWidth - mascotSize - 16.0; // Hít sát biên phải
      _isAnchoredLeft = false;
    }

    // 3. Lưu trữ cấu hình bền vững vào bộ nhớ điện thoại
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('mascot_dx', _dx);
    await prefs.setDouble('mascot_dy', _dy);

    // Đợi Animation hít biên hoàn tất (200ms) rồi tắt cờ
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _isSnapping = false);
        _fireMascotState('NoClick');  // 🚀 Mascot: Chạm đất, bung người nẩy quán tính
        _fireMascotState('Follow On'); // 🚀 Mascot: Bật lại ánh mắt dính theo User
        HapticFeedback.lightImpact(); 
      }
    });
  }

  void _dismissMascotPermanently() {
  setState(() {
    _isMascotDismissed = true;
    _bubbleOpacity = 0.0;
  });
}
  void _openMiniChatPopup() {
    setState(() {
      _bubbleOpacity = 0.0;
      _isChatPopupOpen = true;
    });
    HapticFeedback.mediumImpact();
    _fireMascotState('Text-LetsdoIt'); // 🚀 Mascot: Hoạt họa vung tay mời thao tác
    _fireMascotState('Happy');    // 🚀 Mascot: Cảm xúc tươi tắn chốt sale
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("BUILD RIVE");
    if (_isMascotDismissed) return const SizedBox.shrink();

    return Stack(
      children: [
        // LỚP 1: Cụm Widget Mascot kéo thả thông minh (Top-Left Origin)
        AnimatedPositioned(
          duration: _isSnapping ? const Duration(milliseconds: 200) : Duration.zero,
          curve: Curves.easeOutBack, // Hiệu ứng hít biên hơi nảy nhẹ mềm mại
          top: _dy,
          left: _dx,
          child: GestureDetector(
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            // Sử dụng Stack phụ bên trong để định hướng bong bóng (lệch trái hoặc phải tùy biên hít)
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // 1. Thân hình Mascot (.riv Asset Wrapper)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: _openMiniChatPopup,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFF161616), // Nền xám đen bọc khối Rive sáng
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                          border: Border.all(color: const Color(0xFF80BF84), width: 1.5),
                        ),
                        child: ClipOval( // Bo tròn hoạt họa Rive
                          child: Transform.scale(
                            scale: 2, // 🚀 Zoom mascot Aldo (tăng/giảm tại đây)
                            child: _riveController == null
                                ? const SizedBox.shrink()
                                : RiveWidget(
                                    controller: _riveController!,
                                    fit: Fit.cover,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    // Nút X: Tự động đổi vị trí tránh bị ngón tay che khi kéo
                    Positioned(
                      top: -4,
                      right: _isAnchoredLeft ? -4 : null, // Nếu áp biên trái, nút X lòi ra bên phải Mascot
                      left: _isAnchoredLeft ? null : -4,  // Ngược lại
                      child: GestureDetector(
                        onTap: _dismissMascotPermanently,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, color: Colors.white, size: 10),
                        ),
                      ),
                    ),
                  ],
                ),
                
                // 2. Bong bóng thoại động tích hợp hiệu ứng AnimatedOpacity mờ dần tinh tế
                if (!_isDragging)
                  Positioned(
                    top: 60, // Rớt bong bóng xuống dưới chân Mascot thay vì lơ lửng bên trên
                    left: _isAnchoredLeft ? 0 : null, // Neo cạnh trái nếu đang đứng ở biên trái
                    right: !_isAnchoredLeft ? 0 : null, // Ngược lại neo cạnh phải
                    child: AnimatedOpacity(
                      opacity: _bubbleOpacity,
                      duration: const Duration(milliseconds: 300), // Thời gian mờ dần mượt mà
                      child: AnimatedBuilder(
                        animation: _bounceAnimation,
                        builder: (context, child) {
                          return Transform.translate(
                            offset: Offset(0, _bounceAnimation.value), // Giật dọc
                            child: child,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 180),
                          decoration: BoxDecoration(
                            color: const Color(0xFF18181B).withOpacity(0.85),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white24, width: 0.5),
                          ),
                          child: Text(
                            _bubbleText,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // LỚP 2: Mini Popup Chat Kính Mờ Đè Lên Tại Chỗ (Conversion Funnel Panel)
        if (_isChatPopupOpen) ...[
          GestureDetector(
            onTap: () {
              setState(() => _isChatPopupOpen = false);
              _fireMascotState('NoText'); // 🚀 Mascot: Xóa Box Text ảo
              _fireMascotState('Sad');    // 🚀 Mascot: Phản hồi buồn vì User đóng Form
            },
            child: Container(color: Colors.transparent),
          ),
          Positioned(
            bottom: 110,
            left: 16,
            right: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF18181B).withOpacity(0.75),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.auto_awesome, color: Color(0xFF80BF84), size: 16),
                              SizedBox(width: 6),
                              Text('AI TRỢ LÝ SỨC KHỎE', style: TextStyle(color: Color(0xFF80BF84), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                            ],
                          ),
                          GestureDetector(
                            onTap: () {
                              setState(() => _isChatPopupOpen = false);
                              _fireMascotState('NoText');
                              _fireMascotState('Sad');
                            },
                            child: const Icon(Icons.close, color: Colors.white60, size: 18),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Chào bạn! Tớ nhận thấy chuyên gia tại đây sở hữu gói [${widget.currentVideo.title}] kiểm duyệt vô cùng uy tín. Cơ sở đang có lịch hẹn trống.',
                        style: const TextStyle(color: Color(0xFFEEEEEE), fontSize: 13, height: 1.4, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 14),
                      // REPLACE
                      // 🚀 LOGIC PHÂN LUỒNG NGHIỆP VỤ BỌC THÉP: Xác định Role đăng bài để hiển thị nút
                      Builder(
                        builder: (context) {
                          final String authorRole = widget.currentVideo.author['role']?.toString().toUpperCase() ?? 'USER';
                          
                          // Điều kiện 1: Đăng bởi Partner
                          final bool isPartnerAuthor = (authorRole == 'PARTNER_ADMIN' || authorRole == 'PARTNER');
                          
                          // Điều kiện 2: Đăng bởi Creator nhưng phải gắn đủ cả PartnerID và ServiceID để chuyển đổi Affiliate
                          final bool isCreatorWithAffiliate = (authorRole == 'CREATOR' && 
                              widget.currentVideo.partnerId != null && widget.currentVideo.partnerId!.isNotEmpty &&
                              widget.currentVideo.serviceId != null && widget.currentVideo.serviceId!.isNotEmpty);

                          final bool shouldShowActions = isPartnerAuthor || isCreatorWithAffiliate;
                                             
                          if (!shouldShowActions) {
                            return const Text(
                              'Video này là nhật ký chia sẻ hành trình cá nhân, hiện chưa ghim thông tin cơ sở khám chữa bệnh nào.',
                              style: TextStyle(color: Color(0xFF617D79), fontSize: 12, fontStyle: FontStyle.italic),
                            );
                          }

                          // Mở khóa hộp công cụ cho Luồng 2 (Creator Affiliate) và Luồng 3 (Partner)
                          return Row(
                            children: [
                              if (widget.currentVideo.price > 0) ...[
                                // Nút Đặt lịch (Phân bổ tỷ trọng lớn hơn nếu có giá)
                            Expanded(
                              flex: 3,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => _isChatPopupOpen = false);
                                  
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    useRootNavigator: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (ctx) => BookingBottomSheet(video: widget.currentVideo),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF80BF84),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.25), blurRadius: 8)],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'GIỮ LỊCH NGAY',
                                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          
                          // Nút Tư Vấn AI 24/7 (Phủ Glassmorphism nhẹ)
                          Expanded(
                            flex: widget.currentVideo.price > 0 ? 2 : 1, // Tràn viền nếu không có giá dịch vụ
                            child: GestureDetector(
                              onTap: () {
                                setState(() => _isChatPopupOpen = false);
                                // 🚀 BỌC THÉP ROUTING: Trích xuất chính xác ID và Tên Đối tác an toàn qua cấu trúc thô author của VideoModel
                                final String targetPartnerId = (widget.currentVideo.partnerId != null && widget.currentVideo.partnerId!.isNotEmpty)
                                    ? widget.currentVideo.partnerId!
                                    : widget.currentVideo.authorId;
                                
                                String targetPartnerName = 'Trợ lý AI Cơ Sở';
                                final dynamic authorData = widget.currentVideo.author;
                                
                                if (isCreatorWithAffiliate) {
                                  // Kiểm tra an toàn các khóa chứa tên đối tác liên kết trong thực thể author/partner của map thô
                                  if (authorData is Map && authorData.containsKey('partner') && authorData['partner'] is Map) {
                                    targetPartnerName = authorData['partner']['full_name']?.toString() ?? 
                                                        authorData['partner']['company_name']?.toString() ?? 
                                                        'Trợ lý AI Cơ Sở';
                                  }
                                } else if (isPartnerAuthor) {
                                  // Nếu tự Partner đăng thì lấy trực tiếp tên hiển thị của chính Partner đó
                                  if (authorData is Map) {
                                    targetPartnerName = authorData['full_name']?.toString() ?? 
                                                        authorData['company_name']?.toString() ?? 
                                                        'Trợ lý AI Cơ Sở';
                                  }
                                }
                                
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => PartnerAIChatScreen(
                                      partnerId: targetPartnerId,
                                      partnerName: targetPartnerName,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.3), width: 1),
                                ),
                                child: const Center(
                                  child: Text(
                                    'TƯ VẤN 24/7',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.2),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ]
      ],
    );
  }
}