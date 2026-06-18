import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'app_router.dart';

class DeepLinkEngine {
  // Singleton Pattern bọc thép
  static final DeepLinkEngine instance = DeepLinkEngine._internal();
  DeepLinkEngine._internal();

  /// Điểm tiếp nhận duy nhất cho mọi tương tác bấm thông báo
  void handleNotificationTap(BuildContext? context, dynamic payload) {
    if (payload == null) return;

    Map<String, dynamic> data = {};
    
    // 1. Giải mã Payload JSONB an toàn
    if (payload is String) {
      try {
        data = jsonDecode(payload);
      } catch (_) {
        return;
      }
    } else if (payload is Map<String, dynamic>) {
      data = payload;
    }

    final String screen = data['screen'] ?? '';
    final String eventType = data['event_type'] ?? '';
    
    // Fallback: Sử dụng context truyền vào, hoặc lấy từ Global Key của App Router
    BuildContext? targetContext = context ?? rootNavigatorKey.currentContext;
    if (targetContext == null) return;

    // 2. Đối chiếu Ma trận Deep Link (Phase 8A) & Thực thi Routing
    try {
      if (screen == 'partner_dashboard_booking' || screen == 'partner_dashboard') {
        targetContext.push('/partner-dashboard');
      } else if (screen == 'calendar_payment' || screen == 'calendar') {
        targetContext.push('/calendar');
      } else if (screen == 'partner_wallet') {
        // Fallback điều hướng về màn hình có chứa số dư ví
        targetContext.push('/partner-dashboard'); 
      } else if (eventType == 'LEGACY') {
        // Các thông báo cũ chưa quy chuẩn, tạm thời đưa về trang chính
        targetContext.push('/calendar');
      }
    } catch (e) {
      debugPrint('[DeepLinkEngine Error] Không thể định tuyến: $e');
    }
  }
}
