import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Bổ sung thư viện
import 'core/router/app_router.dart';
import 'presentation/widgets/auth_guard.dart';
import 'core/network/global_cache_engine.dart'; // Nạp Engine để xả RAM toàn cục
import 'package:firebase_messaging/firebase_messaging.dart';
import 'presentation/widgets/notification_notifier.dart';
import 'core/router/deep_link_engine.dart';
import 'core/router/app_router.dart';

void main() async { // Đổi thành hàm async
  WidgetsFlutterBinding.ensureInitialized();
  
  // BẮT BUỘC: Khởi tạo Firebase trước khi chạy App
  await Firebase.initializeApp();
  
  // BẮT BUỘC: Nạp phiên đăng nhập vào RAM trước khi dựng UI
  await AuthNotifier.instance.initialize();
  
  // KHỞI TẠO LỚP TIẾP NHẬN THÔNG BÁO (RECEIVE LAYER)
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    NotificationNotifier.instance.handleForegroundMessage(message);
  });
  
  runApp(const VNShareApp());
}


class VNShareApp extends StatefulWidget {
  const VNShareApp({super.key});

  @override
  State<VNShareApp> createState() => _VNShareAppState();
}

// Chuyển đổi sang StatefulWidget và tích hợp WidgetsBindingObserver để lắng nghe OS
class _VNShareAppState extends State<VNShareApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Đăng ký lắng nghe Hệ điều hành
    
    // 1. Xử lý chạm thông báo khi App đang chạy nền (Background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['payload'] != null) {
        DeepLinkEngine.instance.handleNotificationTap(rootNavigatorKey.currentContext, message.data['payload']);
      }
    });

    // 2. Xử lý chạm thông báo khi App bị tắt hoàn toàn (Terminated / Cold Start)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null && message.data['payload'] != null) {
        // Đợi Flutter dựng xong khung Widget (Frame đầu tiên) rồi mới kích hoạt Router
        WidgetsBinding.instance.addPostFrameCallback((_) {
          DeepLinkEngine.instance.handleNotificationTap(rootNavigatorKey.currentContext, message.data['payload']);
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 🚀 THUẬT TOÁN CLEANUP AN TOÀN: Kích hoạt ngay khi Android/iOS báo động đầy RAM
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    GlobalCacheEngine.clearMemoryCache(); // Giải phóng lập tức bộ nhớ tạm
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      restorationScopeId: 'vnshare_app_root', // 🚀 BẬT ROOT APP RESTORATION ENGINE: Yêu cầu OS cấp phát ổ đĩa lưu trữ State khẩn cấp
      title: 'AI Health Share',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF80BF84)), // Lấy mã màu xanh lá từ UI Web
        useMaterial3: true,
      ),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}