import 'package:flutter/material.dart';

class ShimmerGlowWrapper extends StatefulWidget {
  final Widget child;
  final bool isEnabled;
  final Duration duration;
  final Color glowColor;

  const ShimmerGlowWrapper({
    super.key,
    required this.child,
    this.isEnabled = true,
    this.duration = const Duration(milliseconds: 1600),
    this.glowColor = const Color(0x4DFFFFFF),
  });

  @override
  State<ShimmerGlowWrapper> createState() => _ShimmerGlowWrapperState();
}

class _ShimmerGlowWrapperState extends State<ShimmerGlowWrapper> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    if (widget.isEnabled) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant ShimmerGlowWrapper oldWidget) {
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

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double xOffset = -2.0 + (_controller.value * 4.0);
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                const Color(0x00FFFFFF),
                widget.glowColor,
                const Color(0x00FFFFFF),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(xOffset, -0.3),
              end: Alignment(xOffset + 1.8, 0.3),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}