import 'package:flutter/material.dart';

class ShimmerWrapper extends StatefulWidget {
  final Widget child;
  const ShimmerWrapper({super.key, required this.child});

  @override
  State<ShimmerWrapper> createState() => _ShimmerWrapperState();
}

class _ShimmerWrapperState extends State<ShimmerWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // Vận tốc quét quét 1.5s/vòng (Mượt mà, chuẩn UX)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Toán học tịnh tiến dải gradient mượt mà
        final double xOffset = -2.0 + (_controller.value * 4.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop, // Quét đè dải sáng lên phần tử bên dưới
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: const [
                Color(0x00FFFFFF), // Trong suốt
                Color(0x66FFFFFF), // Sáng lóe (Trắng 40%)
                Color(0x00FFFFFF), // Trong suốt
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(xOffset, 0),
              end: Alignment(xOffset + 2.0, 0),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}