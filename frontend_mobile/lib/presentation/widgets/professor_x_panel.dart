// CREATE FILE: Mobile/lib/presentation/widgets/professor_x_panel.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../data/services/secure_storage_service.dart';
import '../../../core/router/app_router.dart'; // import cấu hình router chứa rootnavigatorkey
import 'app_toast.dart';
import 'glass_wrapper.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/user_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../data/services/secure_storage_service.dart';
import '../../../core/router/app_router.dart'; // import cấu hình router chứa rootnavigatorkey
import 'app_toast.dart';
import 'glass_wrapper.dart';
import 'package:go_router/go_router.dart';
import 'auth_guard.dart'; // Thêm dòng này

class ProfessorXPanel extends StatefulWidget {
  final Widget child;
  
  const ProfessorXPanel({super.key, required this.child});

  @override
  State<ProfessorXPanel> createState() => _ProfessorXPanelState();
}

class _ProfessorXPanelState extends State<ProfessorXPanel> with SingleTickerProviderStateMixin {
  bool _isProfessorX = false;
  bool _isOpenPanel = false;
  bool _isSwitching = false;
  String _currentEmail = '';

  // Khai báo tọa độ Floating Button
  Offset _position = const Offset(20, 100); // Vị trí mặc định
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;

  // Danh sách White-list cố định từ Website
  final List<Map<String, dynamic>> _roleAccounts = [
    {'role': 'SUPER_ADMIN', 'email': 'admin.gsx@gmail.com', 'label': 'Super Admin Tối Cao', 'icon': Icons.admin_panel_settings, 'color': Colors.redAccent},
    {'role': 'PARTNER_ADMIN', 'email': 'partner.gsx@gmail.com', 'label': 'Đối Tác Spa', 'icon': Icons.business, 'color': Colors.amber},
    {'role': 'CREATOR', 'email': 'creator.gsx@gmail.com', 'label': 'Creator Sáng Tạo', 'icon': Icons.auto_awesome, 'color': Colors.purpleAccent},
    {'role': 'MODERATOR', 'email': 'moderator.gsx@gmail.com', 'label': 'Ban Kiểm Duyệt', 'icon': Icons.shield, 'color': const Color(0xFF80BF84)},
    {'role': 'USER', 'email': 'user.gsx@gmail.com', 'label': 'Khách Hàng VIP', 'icon': Icons.person, 'color': const Color(0xFF80BF84)},
  ];

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
    _snapController.addListener(() {
      if (_snapAnimation != null) {
        setState(() => _position = _snapAnimation!.value);
      }
    });
    _loadSavedPosition();
    _checkIdentity();
  }

  Future<void> _loadSavedPosition() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble('gsx_x');
    final dy = prefs.getDouble('gsx_y');
    if (dx != null && dy != null) {
      setState(() => _position = Offset(dx, dy));
    } else {
      // Đặt mặc định sát góc phải bên dưới giống Web
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _position = Offset(MediaQuery.of(context).size.width - 70, MediaQuery.of(context).size.height - 150);
        });
      });
    }
  }

  Future<void> _savePosition(Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('gsx_x', pos.dx);
    await prefs.setDouble('gsx_y', pos.dy);
  }

  Future<void> _checkIdentity() async {
    final profile = await UserApiService.fetchPrivateProfile();
    if (profile != null && profile['profile'] != null) {
      final email = profile['profile']['email'] ?? '';
      setState(() => _currentEmail = email);
      
      // Strict White-list Validation
      final isAuthorized = _roleAccounts.any((acc) => acc['email'] == email);
      if (isAuthorized) {
        setState(() => _isProfessorX = true);
      }
    }
  }

  // Thuật toán hút biên từ tính
  void _snapToEdge(Size screenSize) {
    final double leftDist = _position.dx;
    final double rightDist = screenSize.width - _position.dx - 56; // 56 là kích thước button
    final double targetX = leftDist < rightDist ? 16.0 : screenSize.width - 72.0;

    double targetY = _position.dy;
    if (targetY < MediaQuery.of(context).padding.top + 16) targetY = MediaQuery.of(context).padding.top + 16;
    if (targetY > screenSize.height - 100) targetY = screenSize.height - 100;

    final targetOffset = Offset(targetX, targetY);
    _snapAnimation = Tween<Offset>(begin: _position, end: targetOffset).animate(CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic));
    _snapController.forward(from: 0).then((_) => _savePosition(targetOffset));
  }

  Future<void> _handleSwitchRoleNative(String targetEmail, String targetLabel) async {
    if (targetEmail == _currentEmail) {
      AppToast.show(context: context, message: 'Bạn đã ở trong vai trò này rồi.', isSuccess: false);
      return;
    }

    // 🛡️ CHỐT CHẶN AN TOÀN: Trích xuất Context bọc thép của Navigator trước khi đóng Panel
    final overlayContext = rootNavigatorKey.currentContext ?? context;

    setState(() {
      _isSwitching = true;
      _isOpenPanel = false; // Lúc này đóng panel an toàn, không lo unmounted context
    });

    // 1. Chiến thuật che mắt: phủ ngay màn hình splash giả lập đè lên toàn bộ app
    showGeneralDialog(
      context: overlayContext,
      barrierColor: const Color(0xFFF4F9F5),
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, animation, secondaryAnimation) {
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F9F5),
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.94, end: 1.06).animate(
                      CurvedAnimation(parent: animation, curve: Curves.easeInOutSine),
                    ),
                    child: Container(
                      width: 130, height: 130,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white,
                        boxShadow: [BoxShadow(color: const Color(0xFF4A8B6F).withOpacity(0.08), blurRadius: 40, spreadRadius: 8)],
                      ),
                      child: const Center(child: Icon(Icons.eco_rounded, color: Color(0xFF4A8B6F), size: 64)),
                    ),
                  ),
                  const SizedBox(height: 48),
                  const SizedBox(width: 40, child: LinearProgressIndicator(color: Color(0xFF4A8B6F), backgroundColor: Colors.black12)),
                  const SizedBox(height: 16),
                  Text('Đang nạp danh tính: $targetLabel...', style: const TextStyle(color: Color(0xFF4A8B6F), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      // 2. KÍCH HOẠT ĐĂNG XUẤT THẬT (Mượn sức mạnh AuthNotifier để phá hủy toàn bộ bộ nhớ đệm giao diện)
      // Khi hàm này chạy, GoRouter sẽ tự động phát hiện và đánh sập IndexedStack, ném app ra màn hình chờ
      await AuthNotifier.instance.logout(); 

      // 🛡️ BỌC THÉP TRÌ HOÃN: Đợi GoRouter dọn dẹp xong UI cũ (cực kỳ quan trọng để tránh kẹt State)
      await Future.delayed(const Duration(milliseconds: 1000));

      // 3. ĐĂNG NHẬP TỰ ĐỘNG VỚI DANH TÍNH MỚI (Xử lý ngầm dưới lớp mặt nạ)
      final res = await ApiClient.instance.post(
        '/auth/login',
        data: {'email': targetEmail, 'password': 'gsx123456'}
      );

      final token = res.data['access_token'] ?? res.data['data']?['access_token'];
      
      if (token != null) {
        // Lưu token nóng thẳng vào luồng kết nối hiện tại để bỏ qua độ trễ đọc đĩa
        ApiClient.instance.options.headers['Authorization'] = 'Bearer $token';
        
        // Lưu đè Token thực tế vào đĩa cứng (Kích hoạt lại chuỗi phản ứng của AuthNotifier)
        await SecureStorageService.saveToken(token);
        
        // Ép AuthNotifier kiểm tra lại ổ đĩa, xác nhận người dùng đã đăng nhập lại
        await AuthNotifier.instance.refresh();
      }

      // 4. Trì hoãn để màn hình "che mắt" hiển thị mượt mà và đảm bảo các Notifier chạy xong
      await Future.delayed(const Duration(milliseconds: 1500));

      // 5. Đánh thức hệ thống, nạp lại Profile mới tinh
      await UserApiService.fetchPrivateProfile();

      // 6. THÁO GỠ LỚP CHE MẮT & ĐIỀU HƯỚNG
      final currentRootContext = rootNavigatorKey.currentContext;
      if (currentRootContext != null && currentRootContext.mounted) {
        // Gỡ màn hình Splash giả lập
        if (Navigator.of(currentRootContext, rootNavigator: true).canPop()) {
          Navigator.of(currentRootContext, rootNavigator: true).pop();
        }

        setState(() {
          _currentEmail = targetEmail; // Cập nhật luôn email hiện tại trên Panel
        });
        
        // GoRouter ép khởi tạo lại từ /splash để phá hủy hoàn toàn State cũ kẹt trong IndexedStack
        currentRootContext.go('/splash'); 
        
        // Trễ 100ms rồi đẩy về trang chủ để đảm bảo cây UI cũ đã bị Unmount hoàn toàn
        Future.delayed(const Duration(milliseconds: 100), () {
          if (currentRootContext.mounted) {
            currentRootContext.go('/');
            AppToast.show(context: currentRootContext, message: 'Đã hoàn tất cập nhật phân vai: $targetLabel', isSuccess: true);
          }
        });
      }
    } catch (e) {
      debugPrint('Professor X Panel - Error: $e');
      final currentRootContext = rootNavigatorKey.currentContext;
      if (currentRootContext != null && currentRootContext.mounted) {
        if (Navigator.of(currentRootContext, rootNavigator: true).canPop()) {
          Navigator.of(currentRootContext, rootNavigator: true).pop();
        }
        AppToast.show(context: currentRootContext, message: 'Lỗi thiết lập phân vai, vui lòng thử lại!', isSuccess: false);
      }
    } finally {
      if (mounted) setState(() => _isSwitching = false);
    }
  }

  @override
  void dispose() {
    _snapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isProfessorX) return widget.child;

    final screenSize = MediaQuery.of(context).size;
    final activeConfig = _roleAccounts.firstWhere((acc) => acc['email'] == _currentEmail, orElse: () => _roleAccounts.last);

    return Stack(
      children: [
        widget.child, // Lớp ứng dụng chính nằm bên dưới
        
        // Modal Panel
        if (_isOpenPanel) ...[
          GestureDetector(
            onTap: () => setState(() => _isOpenPanel = false),
            child: Container(color: Colors.black54),
          ),
          Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: screenSize.width * 0.85,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.95), // Thay thế Glassmorphism bằng Solid/Opacity
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 10))
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text('GIÁO SƯ X PANEL', style: TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1)),
                              SizedBox(height: 2),
                              Text('Cố vấn & Kiểm thử hệ thống', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: const Text('NATIVE', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900)),
                          )
                        ],
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(16)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('TÀI KHOẢN HIỆN TẠI:', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(_currentEmail, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('Role: ${activeConfig['role']}', style: TextStyle(color: activeConfig['color'], fontSize: 11, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      ..._roleAccounts.map((acc) {
                        final isActive = acc['email'] == _currentEmail;
                        return GestureDetector(
                          onTap: _isSwitching ? null : () => _handleSwitchRoleNative(acc['email'], acc['label']),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.amber : Colors.white.withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Icon(acc['icon'], color: isActive ? Colors.black : Colors.white54, size: 18),
                                const SizedBox(width: 12),
                                Expanded(child: Text(acc['label'], style: TextStyle(color: isActive ? Colors.black : Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                                if (isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(6)), child: const Text('ACTIVE', style: TextStyle(color: Colors.amber, fontSize: 9, fontWeight: FontWeight.w900))),
                              ],
                            ),
                          ),
                        );
                      }).toList()
                    ],
                  ),
                ),
              ),
            ),
        ],

        // Floating Button thông minh tự bám biên
        Positioned(
          left: _position.dx,
          top: _position.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              setState(() {
                _position += details.delta;
              });
            },
            onPanEnd: (_) => _snapToEdge(screenSize),
            onTap: () => setState(() => _isOpenPanel = !_isOpenPanel),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Colors.black87, Colors.black]),
                border: Border.all(color: Colors.amber, width: 2),
                boxShadow: [BoxShadow(color: Colors.amber.withOpacity(0.4), blurRadius: 16)],
              ),
              child: _isSwitching 
                ? const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                : const Center(
                    child: Text(
                      'X',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.amber,
                        height: 1.1,
                      ),
                    ),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}