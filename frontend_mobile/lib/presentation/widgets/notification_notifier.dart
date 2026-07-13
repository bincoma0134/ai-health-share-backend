import 'dart:async'; // 🚀 Bổ sung thư viện quản lý đếm ngược
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

      // Giả lập cấu trúc bản ghi để đẩy thẳng vào RAM (Hiển thị tức thì)
      final newNotif = {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
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
      if (!newNotif['id'].startsWith('temp_')) {
        NotificationApiService.sendAck(newNotif['id']);
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