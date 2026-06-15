// frontend_mobile/lib/widgets/liquid_glass/liquid_glass_surface.dart

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'liquid_glass_tokens.dart';
import 'liquid_glass_performance.dart';

class LiquidGlassSurface extends StatefulWidget {
  final Widget child;
  final double blur;
  final double borderRadius;
  final Color tintColor;
  final double tintOpacity;
  final bool enableShader;
  final ui.Image? backgroundImage;
  final bool isDenseList; // Cờ an toàn bảo vệ FPS khi dùng trong ScrollView

  const LiquidGlassSurface({
    Key? key,
    required this.child,
    this.blur = LiquidGlassTokens.blurMedium,
    this.borderRadius = LiquidGlassTokens.radiusMd,
    this.tintColor = LiquidGlassTokens.tintMint,
    this.tintOpacity = LiquidGlassTokens.tintBase,
    this.enableShader = true,
    this.backgroundImage,
    this.isDenseList = false, // Mặc định false. Khuyến nghị bật true cho Card/Button trong List dài
  }) : super(key: key);

  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface> {
  ui.FragmentShader? _shader;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    if (widget.enableShader && LiquidGlassPerformance.shouldRenderShader) {
      _loadShader();
    }
  }

  Future<void> _loadShader() async {
    try {
      final program = await ui.FragmentProgram.fromAsset('shaders/liquid_glass_lens.frag');
      if (mounted) {
        setState(() {
          _shader = program.fragmentShader();
        });
      }
    } catch (e) {
      debugPrint('Glass Shader fallback triggered: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tự động tắt Blur và Shader nếu component nằm trong danh sách dày đặc (isDenseList = true)
    final useBlur = LiquidGlassPerformance.shouldRenderBlur && !widget.isDenseList;
    final useShader = _shader != null && !_hasError && widget.enableShader && LiquidGlassPerformance.shouldRenderShader && !widget.isDenseList;

    // RepaintBoundary là BẮT BUỘC để cô lập Layer tính toán của Glass
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          children: [
            // Layer 1: C++/Skia Hardware Accelerated Blur (Thay thế cho 25 vòng lặp GLSL)
            if (useBlur)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
                  child: Container(color: Colors.transparent),
                ),
              ),

            // Layer 2: GPU Fragment Shader (Tính toán khúc xạ trên nền ảnh đã cung cấp, dưới lớp Tint)
            if (useShader && widget.backgroundImage != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _GlassRefractionPainter(_shader!, widget.backgroundImage!),
                ),
              ),

            // Layer 3: Tint Color (Vibrancy emulation - Đặt lên trên cùng để không bị Shader làm mất sắc độ)
            Positioned.fill(
              child: Container(
                color: widget.tintColor.withOpacity(useBlur ? widget.tintOpacity : 0.95), // Fallback gần như đặc hoàn toàn (0.95) để đảm bảo độ tương phản text khi tắt blur
              ),
            ),

            // Layer 4: Static Highlight Border (Đánh lừa thị giác 3D với chi phí 0%)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: Colors.white.withOpacity(LiquidGlassTokens.highlightSoft),
                      width: 0.5, // Viền cực mảnh chuẩn Apple
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.3),
                        Colors.white.withOpacity(0.0),
                        Colors.white.withOpacity(0.05),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Layer 5: Nội dung Semantic
            widget.child,
          ],
        ),
      ),
    );
  }
}

class _GlassRefractionPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final ui.Image backgroundImage;
  _GlassRefractionPainter(this.shader, this.backgroundImage);

  @override
  void paint(Canvas canvas, Size size) {
    // Nạp Texture nền động vào cổng uTexture (Index 0) để Shader không lấy mẫu khoảng không
    shader.setImageSampler(0, backgroundImage);
    // Truyền index chính xác tương ứng file .frag đã sửa
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, size.width / 2); // uMouse.x
    shader.setFloat(3, size.height / 2); // uMouse.y
    shader.setFloat(4, 1.0); // uEffectSize
    shader.setFloat(5, 0.0); // uBlurIntensity (Tắt hoàn toàn Blur trên Shader)
    shader.setFloat(6, 0.5); // uDispersionStrength (Khúc xạ cầu vồng)
    shader.setFloat(7, 0.0); // uTime

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassRefractionPainter oldDelegate) {
    return oldDelegate.backgroundImage != backgroundImage || oldDelegate.shader != shader;
  }
}