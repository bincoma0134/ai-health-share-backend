import 'dart:math' as math;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Widget Wrapper cốt lõi dùng chung để biến bất kỳ Widget nào thành hiệu ứng kính lỏng Apple.
/// Kết hợp mượt mà giữa BackdropFilter thời gian thực và Fragment Shader chạy bằng GPU phần cứng.
@Deprecated('Xung đột kiến trúc và tốn GPU: Vui lòng chuyển sang sử dụng LiquidGlassSurface hoặc LiquidGlassPanel để đảm bảo 60FPS.')
class GlassWrapper extends StatefulWidget {
  final Widget child;
  final double blurX;
  final double blurY;
  final BorderRadius borderRadius;
  final Border? border;
  final Color? fallbackColor;
  final bool isLensMode; 
  final ui.Image? backgroundImage; // Thuộc tính nhận ảnh nền động được chuyển lên trên cùng hợp lệ

  const GlassWrapper({
    super.key,
    required this.child,
    this.blurX = 16.0,
    this.blurY = 16.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.border,
    this.fallbackColor,
  }) : isLensMode = false, backgroundImage = null; // Gán mặc định null để sửa lỗi compile constructor thường

  // Named Constructor cấu hình thấu kính khúc xạ Clear iOS cố định tâm cho thanh điều hướng
  const GlassWrapper.lens({
    super.key,
    required this.child,
    required this.backgroundImage,
    this.blurX = 0.0, 
    this.blurY = 0.0,
    this.borderRadius = const BorderRadius.all(Radius.circular(35)),
    this.border,
    this.fallbackColor,
  }) : isLensMode = true;

  @override
  State<GlassWrapper> createState() => _GlassWrapperState();
}

class _GlassWrapperState extends State<GlassWrapper> with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late AnimationController _timeController;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // Tắt lệnh .repeat() để khóa vòng lặp render vô tận, tiết kiệm pin.
    // Hiệu ứng dòng chảy sẽ tĩnh ở trạng thái mặc định để đảm bảo 60fps trên máy yếu.
    _timeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _loadShader();
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
      debugPrint('Kích hoạt Glassmorphism Shader lỗi, tự động chuyển sang cấu hình Fallback: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _timeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glassBorder = Border.all(
      color: Colors.white.withOpacity(0.22),
      width: 1.2,
    );

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          // Lớp 1: Kính mờ hấp thụ pixel nền (Chỉ kích hoạt khi ở chế độ dòng chảy lỏng thông thường)
          if (!widget.isLensMode)
            Positioned.fill(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: widget.blurX, sigmaY: widget.blurY),
                child: Container(
                  decoration: BoxDecoration(
                    color: widget.fallbackColor ?? Colors.white.withOpacity(0.07),
                    borderRadius: widget.borderRadius,
                  ),
                ),
              ),
            ),
          
          // Lớp 2: Phủ Shader hiệu ứng ánh sáng lỏng hoặc khúc xạ thấu kính Clear iOS dựa theo chế độ
          if (_shader != null && !_hasError)
            Positioned.fill(
              child: widget.isLensMode
                  ? LayoutBuilder(
                      builder: (context, constraints) {
                        return CustomPaint(
                          painter: _GlassLensShaderPainter(
                            shader: _shader!,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            backgroundImage: widget.backgroundImage,
                          ),
                        );
                      },
                    )
                  : AnimatedBuilder(
                      animation: _timeController,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: _GlassShaderPainter(
                            shader: _shader!,
                            time: _timeController.value * 2 * math.pi,
                          ),
                        );
                      },
                    ),
            ),

          // Lớp 3: Viền bắt sáng tinh tế tạo khối 3D cho bề mặt kính
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: widget.border ?? glassBorder,
                ),
              ),
            ),
          ),

          // Lớp 4: Nội dung tương tác bên trong (Nút bấm, Văn bản, Icon)
          widget.child,
        ],
      ),
    );
  }
}

/// Bộ painter truyền dữ liệu uniforms thấu kính tương thích chuẩn xác cấu trúc liquid_glass_lens.frag
class _GlassLensShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double width;
  final double height;
  final ui.Image? backgroundImage;

  _GlassLensShaderPainter({
    required this.shader,
    required this.width,
    required this.height,
    required this.backgroundImage,
  });

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    // Nạp Texture nền động vào cổng uTexture index 0 giống hệt Repo mẫu
    if (backgroundImage != null) {
      shader.setImageSampler(0, backgroundImage!);
    }

    // Sử dụng đúng thuộc tính toán học size.width và size.height có sẵn của CustomPainter để sửa triệt để lỗi compile
    final w = size.width;
    final h = size.height;

    // index 0, 1: uniform vec2 uResolution (Đồng bộ theo kích thước widget kén cục bộ)
    shader.setFloat(0, w);
    shader.setFloat(1, h);

    // index 2, 3: uniform vec2 uMouse (Khóa cố định tại tâm đối xứng hình học của thanh kén điều hướng)
    shader.setFloat(2, w / 2);
    shader.setFloat(3, h / 2);

    // index 4: uniform float uEffectSize (Phủ rộng toàn bộ bề mặt thanh điều hướng)
    shader.setFloat(4, 12.0);

    // index 5: uniform float uBlurIntensity (Kích hoạt chế độ Frosted Glass mờ ảo của Apple)
    shader.setFloat(5, 1.5);

    // index 6: uniform float uDispersionStrength (Tăng nhẹ độ sắc sai cầu vồng ở rìa kính)
    shader.setFloat(6, 0.8);

    final paint = ui.Paint()..shader = shader;
    canvas.drawRect(ui.Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassLensShaderPainter oldDelegate) {
    return oldDelegate.width != width || 
           oldDelegate.height != height || 
           oldDelegate.shader != shader || 
           oldDelegate.backgroundImage != backgroundImage;
  }
}

/// Bộ painter truyền dữ liệu uniforms vào Fragment Shader thực tế
class _GlassShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;

  _GlassShaderPainter({
    required this.shader,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Đồng bộ chỉ số Uniform chính xác với bản cập nhật liquid_glass_lens.frag
    shader.setFloat(0, size.width);  // uResolution.x
    shader.setFloat(1, size.height); // uResolution.y
    shader.setFloat(2, size.width / 2);  // uMouse.x (Cố định tâm)
    shader.setFloat(3, size.height / 2); // uMouse.y
    shader.setFloat(4, 1.0);  // uEffectSize
    shader.setFloat(5, 0.0);  // uBlurIntensity
    shader.setFloat(6, 0.5);  // uDispersionStrength
    shader.setFloat(7, time); // uTime (Bản cập nhật đẩy xuống index 7)

    final paint = Paint()..shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _GlassShaderPainter oldDelegate) {
    return oldDelegate.time != time || oldDelegate.shader != shader;
  }
}

/// Component Nút bấm đa năng ứng dụng hiệu ứng Glassmorphic
class GlassButton extends StatelessWidget {
  final VoidCallback onPressed;
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? color;

  const GlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.padding = const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GlassWrapper(
      borderRadius: borderRadius,
      fallbackColor: color ?? Colors.white.withOpacity(0.12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: borderRadius,
        splashColor: Colors.white.withOpacity(0.15),
        highlightColor: Colors.white.withOpacity(0.05),
        child: Padding(
          padding: padding,
          child: Center(
            widthFactor: 1.0,
            heightFactor: 1.0,
            child: child,
          ),
        ),
      ),
    );
  }
}