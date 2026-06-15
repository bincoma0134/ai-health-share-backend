import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../data/services/secure_storage_service.dart';
import 'auth_bottom_sheet.dart';

/// [AuthNotifier] là bộ quản lý trạng thái xác thực Reactive trung tâm của ứng dụng.
/// Sử dụng kiến trúc [ChangeNotifier] để phát tín hiệu cập nhật tự động tới toàn bộ UI
/// khi người dùng đăng nhập hoặc đăng xuất thành công qua bất kỳ phương thức nào (Email, Google, Facebook).
class AuthNotifier extends ChangeNotifier {
  // Singleton instance duy nhất toàn cục
  static final AuthNotifier instance = AuthNotifier._internal();

  AuthNotifier._internal();

  String? _token;
  String? _userId;
  String? _role;
  String? _name;
  bool _isInitialized = false;

  // Getters công khai bảo bọc dữ liệu nội bộ
  bool get isAuthenticated => _token != null && _token!.isNotEmpty;
  String? get token => _token;
  String? get userId => _userId;
  String? get role => _role;
  String? get name => _name;
  bool get isInitialized => _isInitialized;

  /// Khởi tạo và nạp phiên làm việc từ Local Storage khi ứng dụng khởi chạy
  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadSessionFromStorage();
    _isInitialized = true;
    notifyListeners();
  }

  /// Làm mới và đồng bộ lại trạng thái từ Storage (được gọi ngay sau khi Đăng nhập/Đăng ký/Logout thành công)
  Future<void> refresh() async {
    await _loadSessionFromStorage();
    notifyListeners();
  }

  /// Đăng xuất tập trung, dọn sạch phiên làm việc ổ cứng và xóa RAM state tức thì
  Future<void> logout() async {
    await SecureStorageService.clearSession();
    _token = null;
    _userId = null;
    _role = null;
    _name = null;
    notifyListeners();
  }

  /// Thuật toán đọc bộ nhớ bảo mật và giải mã JWT đa nguồn (Email, OAuth Google, OAuth Facebook)
  Future<void> _loadSessionFromStorage() async {
    try {
      // Đọc token từ hàm tĩnh chuẩn của hệ thống (ai_health_token)
      String? savedToken = await SecureStorageService.getToken();

      // Cơ chế bọc thép dự phòng: Nếu trống, quét nốt ngăn tủ cũ (ai-health-token) để tối đa tương thích luồng cũ
      if (savedToken == null || savedToken.isEmpty) {
        const fallbackStorage = FlutterSecureStorage();
        savedToken = await fallbackStorage.read(key: 'ai-health-token');
      }

      _token = savedToken;

      if (_token != null && _token!.isNotEmpty) {
        // 1. Phân tách và giải mã cấu trúc JWT Payload
        final parts = _token!.split('.');
        if (parts.length == 3) {
          try {
            final String normalizedPayload = base64Url.normalize(parts[1]);
            final String decodedString = utf8.decode(base64Url.decode(normalizedPayload));
            final Map<String, dynamic> payload = json.decode(decodedString);

            // Thuật toán Polymorphic JWT Decoder: Chấp nhận mọi phương thức Email/Google/Facebook Login
            _userId = (payload['sub'] ?? payload['user_id'] ?? payload['uid'])?.toString();
          } catch (e) {
            debugPrint('⚠️ Lỗi giải mã cấu trúc JWT Payload: $e');
            _userId = null;
          }
        }

        // 2. Đồng bộ các chỉ số thông tin đi kèm từ bộ nhớ tĩnh
        _role = await SecureStorageService.getRole() ?? 'USER';
        _name = await SecureStorageService.getName();
      } else {
        _userId = null;
        _role = null;
        _name = null;
      }
    } catch (e) {
      debugPrint('❌ Thất bại trong quá trình nạp dữ liệu phiên: $e');
      _token = null;
      _userId = null;
      _role = null;
      _name = null;
    }
  }
}

/// [AuthGuardWidget] là màng bọc bảo vệ giao diện (Inline Component Guard).
/// Tự động lắng nghe [AuthNotifier] và phân luồng hiển thị: nội dung bảo mật nếu đã đăng nhập,
/// hoặc giao diện thay thế ([fallbackBuilder] / [GuestProfileView]) nếu là khách.
class AuthGuardWidget extends StatelessWidget {
  final Widget Function(BuildContext context, String token, String userId) builder;
  final Widget Function(BuildContext context)? fallbackBuilder;

  const AuthGuardWidget({
    super.key,
    required this.builder,
    this.fallbackBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AuthNotifier.instance,
      builder: (context, _) {
        final auth = AuthNotifier.instance;

        // Nếu hệ thống đang nạp dữ liệu ngầm từ ổ cứng, hiển thị vòng xoay skeleton đồng bộ
        if (!auth.isInitialized) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAFAFA),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF80BF84)),
            ),
          );
        }

        // Đã xác thực thành công -> Trả về giao diện đích kèm dữ liệu định danh bọc thép
        if (auth.isAuthenticated && auth.token != null && auth.userId != null) {
          return builder(context, auth.token!, auth.userId!);
        }

        // Là khách (Guest) -> Trả về giao diện chặn quyền truy cập tùy biến
        if (fallbackBuilder != null) {
          return fallbackBuilder!(context);
        }

        // Mặc định trả về một khoảng trống an toàn nếu không định nghĩa fallbackBuilder
        return const SizedBox.shrink();
      },
    );
  }
}

/// Lớp điều phối tĩnh hỗ trợ bẫy khách trực tiếp tại các điểm tương tác chức năng (Functional Guard)
class AuthGuard {
  /// Hàm chặn hành động thông minh (Interceptor). Kiểm tra trạng thái tức thì trong RAM:
  /// - Nếu là User: Thực hiện [action] ngay lập tức.
  /// - Nếu là Guest: Chặn đứng và bung [AuthBottomSheet] lên để yêu cầu đăng nhập.
  static Future<void> run(
    BuildContext context, {
    required VoidCallback action,
    VoidCallback? onAuthRequired,
  }) async {
    final auth = AuthNotifier.instance;
    
    if (auth.isAuthenticated) {
      action();
    } else {
      if (onAuthRequired != null) {
        onAuthRequired();
      } else {
        // Mặc định mở hộp thoại ngăn kéo xác thực cao cấp và truyền callback thông báo đồng bộ
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => AuthBottomSheet(
            onSuccess: () async {
              // Đồng bộ dứt điểm trạng thái sang RAM ngay khi đăng nhập thành công
              await AuthNotifier.instance.refresh();
            },
          ),
        );
      }
    }
  }
}