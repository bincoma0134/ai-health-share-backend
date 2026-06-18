import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../data/services/notification_api_service.dart';

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

  // 0. Xin quyền hệ thống (Chạy ngầm sau Đăng nhập)
  Future<void> requestPermission() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
    } catch (e) {
      debugPrint('[Notification Permission Error] $e');
    }
  }

  // 1. Tải danh sách từ API (Kích hoạt khi mở app hoặc Pull-to-refresh)
  Future<void> loadNotifications() async {
    _isLoading = true;
    notifyListeners();
    
    _notifications = await NotificationApiService.fetchNotifications();
    
    _isLoading = false;
    notifyListeners();
  }

  // 2. Tiếp nhận trực tiếp Foreground Push từ Firebase Layer
  void handleForegroundMessage(RemoteMessage message) {
    if (message.notification != null) {
      // Giả lập cấu trúc bản ghi để đẩy thẳng vào RAM (Hiển thị tức thì)
      final newNotif = {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'title': message.notification?.title ?? 'Thông báo mới',
        'short_message': message.notification?.body ?? '',
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
        'deep_link_payload': message.data['payload'], // Cất giữ để Phase sau xử lý Deep Link
      };
      
      _notifications.insert(0, newNotif); // Đẩy lên đầu danh sách
      notifyListeners(); // Kích hoạt UI (Tăng Badge, Cập nhật List)
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