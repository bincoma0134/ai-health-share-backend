import 'package:flutter/material.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../../core/theme/partner_tier_theme.dart';
import 'sparkle_overlay.dart';

class PartnerAvatarFrame extends StatelessWidget {
  final String? avatarUrl;
  final double size;
  final bool isPremium;
  final String? premiumTier;
  final VoidCallback? onTap;

  const PartnerAvatarFrame({
    super.key,
    required this.avatarUrl,
    this.size = 52.0,
    this.isPremium = false,
    this.premiumTier,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = PartnerTierTheme.fromTier(isPremium, premiumTier);
    final String cleanUrl = (avatarUrl != null && avatarUrl!.trim().isNotEmpty)
        ? avatarUrl!
        : 'https://ui-avatars.com/api/?name=Partner&background=80BF84&color=fff';

    Widget avatarCore = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        image: DecorationImage(
          image: GlobalCacheProvider.create(cleanUrl, maxWidth: 300, maxHeight: 300),
          fit: BoxFit.cover,
        ),
      ),
    );

    if (theme.type == PartnerTierType.standard) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFE2ECEB), width: 1.5),
          ),
          child: avatarCore,
        ),
      );
    }

    if (theme.type == PartnerTierType.pro) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: theme.gradientBorderColors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: theme.accentGlowColor.withValues(alpha: 0.35),
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(1.5),
            child: avatarCore,
          ),
        ),
      );
    }

    // 👑 VIP DIAMOND: Viền đôi Ruby phát sáng kết hợp Sparkle Particles
    return GestureDetector(
      onTap: onTap,
      child: SparkleOverlay(
        sparkleColor: theme.accentGlowColor,
        child: Container(
          padding: const EdgeInsets.all(3.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [
                Color(0xFFFF2A6D),
                Color(0xFFFF80AB),
                Color(0xFFFFD700), // Ánh vàng khúc xạ
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF2A6D).withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 1.5,
              ),
            ],
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(2.0),
            child: avatarCore,
          ),
        ),
      ),
    );
  }
}