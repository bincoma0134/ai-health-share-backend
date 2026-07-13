import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/main_hub_screen.dart';
import '../../presentation/screens/feeds/tiktok_feeds_screen.dart';
import '../../presentation/screens/explore/explore_screen.dart';
import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/ai/ai_chat_screen.dart';
import '../../presentation/screens/ai/partner_ai_chat_screen.dart';
import '../../presentation/screens/ai/partner_ai_context_screen.dart';
import '../../presentation/screens/promo/promo_screen.dart';
import '../../presentation/screens/calendar/calendar_screen.dart';
import '../../presentation/screens/profile/private_profile_screen.dart';
import '../../presentation/screens/profile/user_wellness_profile_screen.dart';
import '../../presentation/screens/wallet_screen.dart'; // Bổ sung Import Ví điện tử
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/admin/moderator_dashboard_screen.dart';
import '../../presentation/screens/profile/public_profile_screen.dart';
import '../../presentation/screens/admin/partner_dashboard_screen.dart';
import '../../presentation/screens/admin/creator_dashboard_screen.dart'; // IMPORT CREATOR DASHBOARD
import '../../presentation/screens/notification_center_screen.dart';
import '../../presentation/screens/splash_screen.dart'; // Đổi đường dẫn nếu bạn lưu ở thư mục khác
import '../../presentation/screens/feeds/dedicated_upload_screen.dart'; // Import Studio sáng tạo dùng chung toàn màn hình
import '../../presentation/screens/auth/onboarding_screen.dart';
import '../../presentation/screens/login_screen.dart';
import '../../presentation/widgets/auth_guard.dart';
import '../../presentation/widgets/notification_notifier.dart';
import '../../data/models/video_model.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();


final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  // Đã gỡ bỏ restorationScopeId để vô hiệu hóa tính năng khôi phục Tab cũ, ép Router khởi động lại hoàn toàn từ initialLocation.
  initialLocation: '/splash', // Đặt Splash làm trang chạy đầu tiên
  refreshListenable: AuthNotifier.instance, // Lắng nghe thay đổi Auth để tự động cập nhật Navigation
  redirect: (context, state) {
    final isAuthRoute = state.uri.path == '/splash' || state.uri.path == '/login' || state.uri.path == '/onboarding';
    
    // 🚀 BÀN GIAO TRÁCH NHIỆM: Kích hoạt luồng thông báo an toàn. 
    // Notifier sẽ tự động chặn lặp và tự thử lại nếu mạng lỗi.
    if (!isAuthRoute) {
      NotificationNotifier.instance.requestPermission();
    }
    return null; // Không can thiệp vào luồng điều hướng UI, chỉ mượn chu kỳ chạy ngầm
  },
  routes: [
    // KHAI BÁO TUYẾN ĐƯỜNG SPLASH ĐỘC LẬP (Không dính Bottom Bar)
    GoRoute(
      path: '/splash',
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const OnboardingScreen(),
    ),
    
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainHubScreen(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => TikTokFeedsScreen(filter: state.uri.queryParameters['filter']))]), // Index 0: Home
        StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (context, state) => const ExploreScreen())]), // Index 1: Explore
        StatefulShellBranch(routes: [GoRoute(path: '/ai', builder: (context, state) => const AiChatScreen())]), // Index 2: AI Assistant
        StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (context, state) => const MapScreen())]), // Index 3: Map
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (context, state) => const PrivateProfileScreen())]), // Index 4: Profile Hub
      ],
    ),
    
    // CÁC TUYẾN ĐƯỜNG VỆ TINH (Được tách khỏi Bottom Nav, gọi trực tiếp từ Profile)
    GoRoute(
      path: '/promo',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const PromoScreen(),
    ),
    GoRoute(
      path: '/calendar',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const CalendarScreen(),
    ),
    GoRoute(
      path: '/wallet',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const WalletScreen(),
    ),

    // Tuyến đường Dashboard Admin nằm độc lập
    GoRoute(
      path: '/admin-dashboard',
      parentNavigatorKey: rootNavigatorKey, 
      builder: (context, state) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/public-profile/:username',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => PublicProfileScreen(username: state.pathParameters['username']!),
    ),
    GoRoute(
      path: '/moderator-dashboard',
      parentNavigatorKey: rootNavigatorKey, 
      builder: (context, state) => const ModeratorDashboardScreen(),
    ),
    GoRoute(
      path: '/partner-dashboard',
      parentNavigatorKey: rootNavigatorKey, 
      builder: (context, state) => const PartnerDashboardScreen(),
    ),
    // TUYẾN ĐƯỜNG CREATOR DASHBOARD
    GoRoute(
      path: '/creator-dashboard',
      parentNavigatorKey: rootNavigatorKey, 
      builder: (context, state) => const CreatorDashboardScreen(),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: rootNavigatorKey, 
      builder: (context, state) => const NotificationCenterScreen(),
    ),
    // TUYẾN ĐƯỜNG PROFILE FEED ISOLATION (Tái sử dụng Component màn hình TikTokFeedsScreen)
    GoRoute(
      path: '/isolated-feed',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return TikTokFeedsScreen(
          preloadedVideos: extra['videos'] as List<VideoModel>?,
          initialIndex: extra['index'] as int?,
        );
      },
    ),
    // Tuyến đường độc lập phục vụ Creative Studio áp dụng Inject Quyền cứng trực tiếp từ tầng router cửa ngõ
    GoRoute(
      path: '/upload-studio',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final roleParam = (state.extra as String?) ?? 'USER';
        return DedicatedUploadScreen(userRole: roleParam);
      },
    ),
    // TUYẾN ĐƯỜNG PARTNER AI CHAT (Dành riêng cho khách hàng chat với cơ sở)
    GoRoute(
      path: '/partner-ai-chat/:partnerId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final partnerId = state.pathParameters['partnerId']!;
        final partnerName = state.extra as String?;
        return PartnerAIChatScreen(
          partnerId: partnerId,
          partnerName: partnerName,
        );
      },
    ),
    // TUYẾN ĐƯỜNG SỨC KHỎE TOÀN DIỆN (WELLNESS PROFILE)
    GoRoute(
      path: '/wellness-profile',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) => const UserWellnessProfileScreen(),
    ),
    // TUYẾN ĐƯỜNG PARTNER AI CONTEXT (Dành cho cơ sở thiết lập định hướng AI)
    GoRoute(
      path: '/partner-ai-context',
      parentNavigatorKey: rootNavigatorKey,
      builder: (context, state) {
        final currentContext = (state.extra as String?) ?? '';
        return PartnerAiContextScreen(currentContext: currentContext);
      },
    ),
  ],
);