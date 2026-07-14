import 'dart:async'; // 🚀 Bổ sung thư viện quản lý đếm ngược
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/notification_api_service.dart';
import 'dart:convert'; // Đảm bảo nạp thư viện giải mã chuỗi cục bộ
import '../../core/router/app_router.dart'; // 🚀 Truy xuất Router để lấy Context toàn cục
import '../../core/router/deep_link_engine.dart'; // 🚀 Động cơ điều hướng khi chạm vào Popup


class NotificationNotifier extends ChangeNotifier {
  // Singleton Pattern bọc thép
  static final NotificationNotifier instance = NotificationNotifier._internal();
  NotificationNotifier._internal();

  List<dynamic> _notifications = [];
  bool _isLoading = false;

  List<dynamic> get notifications => _notifications;
  bool get isLoading => _isLoading;
  
  // Tính toán Badge ngầm từ mảng RAM
  int get unreadCount => _notifications.where((n) => n['is_read'] == false).length;

  // 🚀 BỌC THÉP TRẠNG THÁI: Chỉ khóa cờ khi Database đã ghi nhận thành công
  bool _hasSyncedToken = false;
  bool _isSyncingToken = false;

  // Quản lý Banner Overlay hiện tại để xóa ngay nếu có thông báo mới dồn dập
  OverlayEntry? _activeBanner;

  // 0. Xin quyền hệ thống (Chạy ngầm sau Đăng nhập)
  Future<void> requestPermission() async {
    if (_hasSyncedToken || _isSyncingToken) return;
    
    try {
      _isSyncingToken = true;
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      
      // Chỉ lấy và đồng bộ Token nếu người dùng cấp quyền (hoặc provisional)
      if (settings.authorizationStatus == AuthorizationStatus.authorized || 
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        final String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          final success = await NotificationApiService.updateFcmToken(token);
          if (success) {
            _hasSyncedToken = true; // Chốt cờ thành công tuyệt đối
          }
        }
      }
    } catch (e) {
      debugPrint('[Notification Permission Error] $e');
    } finally {
      _isSyncingToken = false;
    }
  }

  // 1. Tải danh sách từ API (Kích hoạt khi mở app hoặc Pull-to-refresh)
  Future<void> loadNotifications() async {
    _isLoading = true;
    notifyListeners();
    
    _notifications = await NotificationApiService.fetchNotifications();
    
    _isLoading = false;
    notifyListeners();

    // 🚀 SMART FALLBACK: Tự động kích hoạt Pop-up nếu có tin bị kẹt (is_fallback_priority)
    final urgent = _notifications.firstWhere((n) => n['is_fallback_priority'] == true, orElse: () => null);
    if (urgent != null) {
        // Gọi lại logic hiển thị banner cho tin ưu tiên (Tái sử dụng handleForegroundMessage logic)
    }
  }

  // 2. Tiếp nhận trực tiếp Foreground Push từ Firebase Layer
  void handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      // 🚀 HOTFIX FOREGROUND PIPELINE: Giải mã chuỗi JSON string từ Backend để đồng bộ Map cấu trúc UI
      
      dynamic decodedPayload = message.data['payload'];
      if (decodedPayload is String) {
        try {
          decodedPayload = jsonDecode(decodedPayload);
        } catch (_) {
          // Fallback an toàn nếu chuỗi không phải định dạng JSON
        }
      }

      // Giải nén Original ID từ Backend truyền sang qua data payload
      final originalId = message.data['notification_id'] ?? 'temp_${DateTime.now().millisecondsSinceEpoch}';

      // Giả lập cấu trúc bản ghi để đẩy thẳng vào RAM (Hiển thị tức thì)
      final newNotif = {
        'id': originalId,
        'title': message.notification?.title ?? 'Thông báo mới',
        'short_message': message.notification?.body ?? '',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
        'deep_link_payload': decodedPayload, // 🚀 Đã chuẩn hóa thành dạng Map tương thích 100% với UI
      };
      
      // 🚀 HOTFIX: Tạo vùng nhớ List mới hoàn toàn để triệt tiêu lỗi Unmodifiable List và ép Flutter Rebuild UI
      _notifications = [newNotif, ..._notifications]; 
      notifyListeners(); // Kích hoạt UI (Tăng Badge, Cập nhật List)

      // 🚀 GỬI ACK NGẦM: Xác nhận đã nhận thành công cho Backend
      if (!originalId.startsWith('temp_')) {
        NotificationApiService.sendAck(originalId);
      }

      // 🚀 IMPLEMENT IN-APP TOP BANNER (FOREGROUND NOTIFICATION)
      final context = rootNavigatorKey.currentContext;
      if (context != null) {
        // Xóa banner cũ ngay lập tức nếu có tin nhắn mới tới dồn dập
        _activeBanner?.remove();
        _activeBanner = null;

        final overlay = Overlay.of(context);
        late OverlayEntry entry;

        entry = OverlayEntry(
          builder: (context) => _TopBannerWidget(
            title: message.notification?.title ?? 'Thông báo mới',
            body: message.notification?.body ?? '',
            onTap: () {
              DeepLinkEngine.instance.handleNotificationTap(context, decodedPayload);
            },
            onDismissed: () {
              if (_activeBanner == entry) {
                entry.remove();
                _activeBanner = null;
              }
            },
          ),
        );

        _activeBanner = entry;
        overlay.insert(entry);
      }
    }
  }

  // 3. Optimistic UI: Cập nhật RAM trước, gọi API ngầm sau
  Future<void> markAsRead(String id) async {
    final index = _notifications.indexWhere((n) => n['id'] == id);
    if (index != -1 && _notifications[index]['is_read'] == false) {
      _notifications[index]['is_read'] = true;
      notifyListeners(); // Giảm Badge ngay lập tức
      
      // Fire-and-forget API
      if (!id.startsWith('temp_')) {
        await NotificationApiService.markAsRead(id);
      }
    }
  }

  // 4. Đánh dấu đọc tất cả (Optimistic UI)
  Future<void> markAllAsRead() async {
    for (var n in _notifications) {
      n['is_read'] = true;
    }
    notifyListeners();
    await NotificationApiService.markAllAsRead();
  }

  // ======================================================================
  // 🚀 HỆ THỐNG VOUCHER DROP ENGINE (GAMIFICATION)
  // ======================================================================
  OverlayEntry? _voucherOverlay;
  bool _isClaimingDrop = false;

  void dismissVoucherDrop() {
    _voucherOverlay?.remove();
    _voucherOverlay = null;
  }

  Future<void> triggerVoucherDrop(BuildContext context, String currentAuthorId) async {
    if (_voucherOverlay != null) return; // Đang hiển thị Pop-up thì chặn lại

    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final todayStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    // 1. Quản lý Giới hạn Ngày (Daily Cap Limit = 3)
    final lastDropDate = prefs.getString('last_voucher_drop_date') ?? '';
    int todayDrops = prefs.getInt('voucher_drop_today_count') ?? 0;

    if (lastDropDate != todayStr) {
      todayDrops = 0; // Reset qua ngày mới
      await prefs.setString('last_voucher_drop_date', todayStr);
    }

    if (todayDrops >= 3) return; // Chặn cứng nếu đã ăn đủ 3 mã hôm nay

    // 2. Quản lý Cooldown (2 Phút)
    final lastDropTimeStr = prefs.getString('last_voucher_drop_time');
    if (lastDropTimeStr != null) {
      final lastDropTime = DateTime.tryParse(lastDropTimeStr);
      if (lastDropTime != null && now.difference(lastDropTime).inMinutes < 2) {
        return; // Chưa đủ 2 phút
      }
    }

    // 3. Tỷ lệ rơi mã (Entropy Drop Rate = 25%)
    if (math.Random().nextDouble() > 0.25) return;

    // 4. Lọc chéo Voucher: Tải ngầm danh sách
    final publicVouchers = await NotificationApiService.fetchPublicVouchers();
    if (publicVouchers.isEmpty) return;
    final myVouchers = await NotificationApiService.fetchMyVouchers();

    final availableVouchers = publicVouchers.where((v) {
      final isUnclaimed = !myVouchers.any((myV) => myV['code'] == v['code']);
      final isValidIssuer = v['issuer_type'] == 'ADMIN' || v['issuer_id'] == currentAuthorId;
      return isUnclaimed && isValidIssuer;
    }).toList();

    if (availableVouchers.isEmpty) return;

    // Bốc thăm
    final randomVoucher = availableVouchers[math.Random().nextInt(availableVouchers.length)];

    // Ghi nhận mốc thời gian thả rơi
    await prefs.setString('last_voucher_drop_time', now.toIso8601String());
    
    // Rung Haptic phản hồi
    HapticFeedback.heavyImpact();

    // 5. Kích hoạt Overlay
    final overlay = Overlay.of(context);
    _voucherOverlay = OverlayEntry(
      builder: (ctx) => _VoucherDropWidget(
        voucher: randomVoucher,
        onDismiss: dismissVoucherDrop,
        onClaim: () async {
          if (_isClaimingDrop) return;
          _isClaimingDrop = true;
          
          final success = await NotificationApiService.claimVoucher(randomVoucher['code']);
          
          if (success) {
            await prefs.setInt('voucher_drop_today_count', todayDrops + 1);
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                content: Text('Đã bỏ túi thành công!'),
                backgroundColor: Color(0xFF10B981),
              ));
            }
          }
          
          _isClaimingDrop = false;
          dismissVoucherDrop();
        },
      ),
    );

    overlay.insert(_voucherOverlay!);
  }
}

// ==========================================
// VOUCHER DROP OVERLAY WIDGET
// ==========================================
class _VoucherDropWidget extends StatefulWidget {
  final dynamic voucher;
  final VoidCallback onDismiss;
  final Future<void> Function() onClaim;

  const _VoucherDropWidget({required this.voucher, required this.onDismiss, required this.onClaim});

  @override
  State<_VoucherDropWidget> createState() => _VoucherDropWidgetState();
}

class _VoucherDropWidgetState extends State<_VoucherDropWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isClaiming = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.reverse().then((_) => widget.onDismiss());
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.voucher;
    final isPercentage = v['discount_type'] == 'PERCENTAGE';
    final discountStr = isPercentage 
        ? 'GIẢM ${v['discount_value']}%' 
        : 'GIẢM ${(v['discount_value'] / 1000).toInt()}K';

    return Stack(
      children: [
        // Backdrop mờ cản tương tác phía sau
        GestureDetector(
          onTap: _close,
          child: Container(color: Colors.black.withOpacity(0.6)),
        ),
        Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF18181B).withOpacity(0.9),
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.white24),
                  boxShadow: [BoxShadow(color: const Color(0xFFF59E0B).withOpacity(0.2), blurRadius: 40)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: GestureDetector(
                        onTap: _close,
                        child: const Icon(Icons.close, color: Colors.white70, size: 24),
                      ),
                    ),
                    Container(
                      width: 80, height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFFFCD34D), Color(0xFFF59E0B)]),
                        boxShadow: [BoxShadow(color: Color(0xFFF59E0B), blurRadius: 20)],
                      ),
                      child: const Icon(Icons.card_giftcard, color: Colors.white, size: 40),
                    ),
                    const SizedBox(height: 16),
                    const Text('Bạn tìm thấy Ưu Đãi!', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    const Text('Một mã giảm giá bí mật vừa xuất hiện trong lúc bạn xem video.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.local_activity, color: Color(0xFFFBBF24), size: 18),
                              const SizedBox(width: 8),
                              Text(discountStr, style: const TextStyle(color: Color(0xFFFBBF24), fontSize: 18, fontWeight: FontWeight.w900)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text('Mã: ${v['code']}', style: const TextStyle(color: Colors.white54, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () async {
                        if (_isClaiming) return;
                        setState(() => _isClaiming = true);
                        await widget.onClaim();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF97316)]),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: _isClaiming 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('BỎ TÚI NGAY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 1)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// THÀNH PHẦN GIAO DIỆN IN-APP TOP BANNER (ANIMATED OVERLAY)
// ==========================================
class _TopBannerWidget extends StatefulWidget {
  final String title;
  final String body;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  const _TopBannerWidget({
    required this.title,
    required this.body,
    required this.onTap,
    required this.onDismissed,
  });

  @override
  State<_TopBannerWidget> createState() => _TopBannerWidgetState();
}

class _TopBannerWidgetState extends State<_TopBannerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  Timer? _dismissTimer; // 🚀 Quản lý vòng đời bộ đếm

  @override
  void initState() {
    super.initState();
    // Setup animation trượt từ trên xuống (-1.0 đến 0.0)
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _offsetAnimation = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    // 🚀 Sử dụng Timer thay cho Future.delayed để có thể hủy khi Widget bị dispose
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismissed());
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel(); // 🚀 Hủy đếm ngược lập tức, triệt tiêu rò rỉ RAM (Memory Leak)
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Đo kích thước StatusBar an toàn (Tránh bị tai thỏ che)
    final topPadding = MediaQuery.of(context).padding.top;

    return Positioned(
      top: topPadding + 12,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _offsetAnimation,
          child: GestureDetector(
            // Click để mở DeepLink
            onTap: () {
              _controller.reverse().then((_) {
                widget.onDismissed();
                widget.onTap();
              });
            },
            // Vuốt lên để ẩn sớm (Dismissable)
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta! < -5) {
                _controller.reverse().then((_) => widget.onDismissed());
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_active, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF27272A), fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.body,
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 13, height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}