import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Controller xoay các vòng 3D nhẹ nhàng (12 giây/vòng chậm rãi, thư giãn)
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    // 2. Controller nhịp thở mềm mại (Breathing effect) cho lõi trung tâm
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.88, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    // 3. Giữ màn hình chờ 4 giây để pre-load dữ liệu ngầm cho Feeds
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await Future.delayed(const Duration(milliseconds: 4000));
    if (mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090B), // Đen tuyền chuẩn Premium
      body: Stack(
        children: [
          // LỚP 1: NỀN GRADIENT LAN TỎA (FILL TOÀN MÀN HÌNH)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center, // Ép tâm tỏa sáng chính giữa màn hình
                      colors: [
                        const Color(0xFF80BF84).withOpacity(0.15 * _pulseAnimation.value),
                        Colors.transparent,
                      ],
                      radius: 0.8,
                    ),
                  ),
                );
              },
            ),
          ),

          // LỚP 2: CỤM HOLOGRAM 3D CĂN CHÍNH GIỮA TUYỆT ĐỐI & MỞ RỘNG (FILL)
          Positioned.fill(
            child: Center( // Ép toàn bộ khối trục tọa độ ra chính giữa màn hình
              child: AnimatedBuilder(
                animation: _rotationController,
                builder: (context, child) {
                  return SizedBox(
                    width: 300, // Định cấu hình vùng chứa rộng rãi để fill các đường nét
                    height: 300,
                    child: Stack(
                      alignment: Alignment.center, // Đồng tâm các lớp đè lên nhau
                      children: [
                        
                        // QUỸ ĐẠO XOAY 1: Vòng ngoài lớn thanh thoát (Thinner Line)
                        Transform(
                          alignment: Alignment.center, // Bắt buộc xoay quanh tâm vật thể
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012) // Tạo perspective chiều sâu 3D mỏng
                            ..rotateX(_rotationController.value * 2 * pi)
                            ..rotateY(_rotationController.value * pi),
                          child: Container(
                            width: 260, // Mở rộng đường kính vòng ngoài
                            height: 260,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF80BF84).withOpacity(0.12), 
                                width: 1.0,
                              ),
                            ),
                          ),
                        ),
                        
                        // QUỸ ĐẠO XOAY 2: Vòng tầm trung xoay ngược chiều tạo hiệu ứng không gian 3D
                        Transform(
                          alignment: Alignment.center, // Đồng tâm trục xoay
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0012)
                            ..rotateZ(-_rotationController.value * 2 * pi)
                            ..rotateX(-_rotationController.value * pi),
                          child: Container(
                            width: 200, // Mở rộng đường kính vòng trong
                            height: 200,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF80BF84).withOpacity(0.22), 
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF80BF84).withOpacity(0.08), 
                                  blurRadius: 40, 
                                  spreadRadius: 8,
                                )
                              ],
                            ),
                          ),
                        ),

                        // LÕI TRUNG TÂM: Biểu tượng chiếc lá rực sáng nhẹ nhàng theo nhịp thở
                        ScaleTransition(
                          scale: _pulseAnimation,
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF09090B), // Che nền tạo độ sâu khối đặc
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF80BF84).withOpacity(0.35), 
                                  blurRadius: 45, 
                                  spreadRadius: 12,
                                )
                              ],
                            ),
                            child: const Icon(
                              Icons.eco_rounded, // Biểu tượng chiếc lá mềm mại, thư giãn
                              color: Color(0xFF80BF84), 
                              size: 44,
                            ),
                          ),
                        ),
                        
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // LỚP 3: CHỮ & THANH CÔNG CỤ LOADING DƯỚI ĐÁY MÀN HÌNH
          Positioned(
            bottom: 64,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Text(
                  'VN Share',
                  style: TextStyle(
                    color: Colors.white, 
                    fontSize: 18, 
                    fontWeight: FontWeight.w900, 
                    letterSpacing: 4.5,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 14, 
                      height: 14, 
                      child: CircularProgressIndicator(
                        color: Color(0xFF80BF84), 
                        strokeWidth: 1.8,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Chào mừng bạn đến với Hành chính Sống Khỏe...', 
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4), 
                        fontSize: 13, 
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}