import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AnimatedPremiumLikeButton extends StatefulWidget {
  final bool isLiked;
  final String likeCount;
  final VoidCallback onTap;

  const AnimatedPremiumLikeButton({
    super.key,
    required this.isLiked,
    required this.likeCount,
    required this.onTap,
  });

  @override
  State<AnimatedPremiumLikeButton> createState() => _AnimatedPremiumLikeButtonState();
}

class _AnimatedPremiumLikeButtonState extends State<AnimatedPremiumLikeButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _particleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600), // Tổng thời lượng 600ms chuẩn xác
    );

    // Chuỗi Scale: Nén xuống (0.7) -> Bùng nổ phóng to (1.3) -> Đàn hồi về chuẩn (1.0)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7).chain(CurveTween(curve: Curves.easeOut)), weight: 15.0),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.3).chain(CurveTween(curve: Curves.fastOutSlowIn)), weight: 25.0),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)), weight: 60.0),
    ]).animate(_controller);

    // Vận tốc hạt bắn ra xa (Từ tâm 0.0 -> viền ngoài 1.0)
    _particleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.15, 0.8, curve: Curves.easeOut)),
    );

    // Hạt mờ dần và biến mất khi ra đến mép
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)),
    );
  }

  @override
  void didUpdateWidget(AnimatedPremiumLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tự động kích hoạt khi trạng thái chuyển từ [Chưa Like] -> [Đã Like] (Cover luôn cả luồng Double Tap)
    if (widget.isLiked && !oldWidget.isLiked) {
      _controller.forward(from: 0.0);
      // Rung phản hồi vật lý khớp nhịp với thời điểm trái tim bùng nổ khỏi độ nén
      Future.delayed(const Duration(milliseconds: 80), () {
        HapticFeedback.mediumImpact();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildParticles() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 0 || _controller.value == 1) return const SizedBox.shrink();
        
        final particles = <Widget>[];
        // Bản phối màu đa sắc lấy cảm hứng từ YouTube/TikTok
        final colors = [Colors.amber, Colors.blueAccent, const Color(0xFF48C9B0), Colors.purpleAccent, Colors.orange];
        const int particleCount = 5;
        const double maxRadius = 45.0; // Bán kính nổ tối đa

        for (int i = 0; i < particleCount; i++) {
          // Tính toán tọa độ phân bổ đều 360 độ bằng Lượng giác (Sin, Cos)
          final double angle = (i * (360 / particleCount)) * (math.pi / 180);
          final double currentRadius = maxRadius * _particleAnimation.value;
          
          final double dx = math.cos(angle) * currentRadius;
          final double dy = math.sin(angle) * currentRadius;

          particles.add(
            Transform.translate(
              offset: Offset(dx, dy),
              child: Opacity(
                opacity: _opacityAnimation.value,
                child: Transform.scale(
                  scale: 1.0 - (_particleAnimation.value * 0.5), // Thu nhỏ dần về cuối hành trình
                  child: Icon(
                    i % 2 == 0 ? Icons.favorite_rounded : Icons.star_rounded, // Đan xen Tim và Sao
                    color: colors[i],
                    size: 14,
                  ),
                ),
              ),
            ),
          );
        }

        return Stack(alignment: Alignment.center, children: particles);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isLiked ? const Color(0xFFFE2C55) : Colors.white;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap, 
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                _buildParticles(), // Hệ thống hạt bay nằm lót dưới
                AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(scale: _scaleAnimation.value, child: child);
                  },
                  child: Icon(
                    Icons.favorite_rounded, 
                    color: color, 
                    size: 36,
                    shadows: [
                      Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                      Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              widget.likeCount, 
              style: TextStyle(
                color: color == Colors.white ? Colors.white : color, 
                fontWeight: FontWeight.w700, 
                fontSize: 12, 
                letterSpacing: -0.2,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(0, 1.5))]
              )
            ),
          ],
        ),
      ),
    );
  }
}