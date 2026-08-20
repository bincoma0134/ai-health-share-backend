import 'package:flutter/material.dart';
import '../../../core/theme/partner_tier_theme.dart';

class PartnerTierBadge extends StatelessWidget {
  final bool isPremium;
  final String? premiumTier;
  final double fontSize;
  final bool isCompact;

  const PartnerTierBadge({
    super.key,
    required this.isPremium,
    this.premiumTier,
    this.fontSize = 10.0,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = PartnerTierTheme.fromTier(isPremium, premiumTier);
    if (theme.type == PartnerTierType.standard) return const SizedBox.shrink();

    final bool isDiamond = theme.type == PartnerTierType.diamond;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 5 : 8,
        vertical: isCompact ? 2 : 3.5,
      ),
      decoration: BoxDecoration(
        color: theme.badgeBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.primaryColor.withValues(alpha: 0.4),
          width: 0.8,
        ),
        boxShadow: isDiamond
            ? [
                BoxShadow(
                  color: theme.primaryColor.withValues(alpha: 0.18),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            theme.icon,
            size: fontSize + 2,
            color: theme.primaryColor,
          ),
          if (!isCompact) ...[
            const SizedBox(width: 3.5),
            Text(
              isDiamond ? 'VIP DIAMOND' : 'PRO',
              style: TextStyle(
                color: theme.primaryColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}