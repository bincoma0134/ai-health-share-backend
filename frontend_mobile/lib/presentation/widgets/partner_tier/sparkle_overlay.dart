import 'dart:math';
import 'package:flutter/material.dart';

class SparkleOverlay extends StatefulWidget {
  final Widget child;
  final bool isEnabled;
  final Color sparkleColor;
  final int particleCount;

  const SparkleOverlay({
    super.key,
    required this.child,
    this.isEnabled = true,
    this.sparkleColor = const Color(0xFFFF80AB),
    this.particleCount = 5,
  });

  @override
  State<SparkleOverlay> createState() => _SparkleOverlayState();
}

class _SparkleOverlayState extends State<SparkleOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random _random = Random(42);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.isEnabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SparkleOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEnabled && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isEnabled && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEnabled) return widget.child;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned.fill(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return CustomPaint(
                  painter: _SparklePainter(
                    progress: _controller.value,
                    sparkleColor: widget.sparkleColor,
                    count: widget.particleCount,
                    random: _random,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SparklePainter extends CustomPainter {
  final double progress;
  final Color sparkleColor;
  final int count;
  final Random random;

  _SparklePainter({
    required this.progress,
    required this.sparkleColor,
    required this.count,
    required this.random,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      // Xác định quỹ đạo điểm sao xung quanh viền
      final double phase = (progress + (i / count)) % 1.0;
      final double angle = (i * (2 * pi / count)) + (progress * 2 * pi * 0.3);
      final double radiusX = size.width * 0.52;
      final double radiusY = size.height * 0.52;

      final double cx = (size.width / 2) + cos(angle) * radiusX;
      final double cy = (size.height / 2) + sin(angle) * radiusY;

      // Độ mờ nhấp nháy theo phase
      final double opacity = sin(phase * pi);
      final double starSize = 2.0 + sin(phase * pi) * 2.5;

      paint.color = sparkleColor.withValues(alpha: opacity.clamp(0.0, 1.0));

      // Vẽ hình ngôi sao 4 cánh siêu nhỏ
      final Path path = Path();
      path.moveTo(cx, cy - starSize);
      path.quadraticBezierTo(cx, cy, cx + starSize, cy);
      path.quadraticBezierTo(cx, cy, cx, cy + starSize);
      path.quadraticBezierTo(cx, cy, cx - starSize, cy);
      path.quadraticBezierTo(cx, cy, cx, cy - starSize);
      path.close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.progress != progress;
}