import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../presentation/screens/main_hub_screen.dart';
import '../../presentation/screens/feeds/tiktok_feeds_screen.dart';
import '../../presentation/screens/explore/explore_screen.dart';
import '../../presentation/screens/map/map_screen.dart';
import '../../presentation/screens/ai/ai_chat_screen.dart';
import '../../presentation/screens/promo/promo_screen.dart';
import '../../presentation/screens/calendar/calendar_screen.dart';
import '../../presentation/screens/profile/private_profile_screen.dart';
import '../../presentation/screens/admin/admin_dashboard_screen.dart';
import '../../presentation/screens/admin/moderator_dashboard_screen.dart';
import '../../presentation/screens/profile/public_profile_screen.dart';
import '../../presentation/screens/admin/partner_dashboard_screen.dart';
import '../../presentation/screens/admin/creator_dashboard_screen.dart'; // IMPORT CREATOR DASHBOARD
import '../../presentation/screens/splash_screen.dart'; // Đổi đường dẫn nếu bạn lưu ở thư mục khác
import '../../presentation/screens/auth/onboarding_screen.dart';
import '../../presentation/screens/login_screen.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash', // Đặt Splash làm trang chạy đầu tiên
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
        StatefulShellBranch(routes: [GoRoute(path: '/', builder: (context, state) => const TikTokFeedsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/explore', builder: (context, state) => const ExploreScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/promo', builder: (context, state) => const PromoScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/ai', builder: (context, state) => const AiChatScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (context, state) => const MapScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/calendar', builder: (context, state) => const CalendarScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (context, state) => const PrivateProfileScreen())]),
      ],
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
  ],
);