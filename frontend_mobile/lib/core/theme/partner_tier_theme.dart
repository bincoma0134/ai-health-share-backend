import 'package:flutter/material.dart';

enum PartnerTierType { standard, pro, diamond }

class PartnerTierTheme {
  final PartnerTierType type;
  final String label;
  final String badgeText;
  final IconData icon;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentGlowColor;
  final Color textColor;
  final Color badgeBgColor;
  final List<Color> gradientBorderColors;
  final List<Color> cardGradientColors;

  const PartnerTierTheme({
    required this.type,
    required this.label,
    required this.badgeText,
    required this.icon,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentGlowColor,
    required this.textColor,
    required this.badgeBgColor,
    required this.gradientBorderColors,
    required this.cardGradientColors,
  });

  // --- CẤU HÌNH CHO 3 CẤP ĐỘ HỘI VIÊN ĐỐI TÁC ---
  static const PartnerTierTheme standard = PartnerTierTheme(
    type: PartnerTierType.standard,
    label: 'Standard',
    badgeText: 'ĐỐI TÁC',
    icon: Icons.business_rounded,
    primaryColor: Color(0xFF64748B), // Slate Grey B2B
    secondaryColor: Color(0xFF94A3B8),
    accentGlowColor: Color(0x3364748B),
    textColor: Color(0xFF475569),
    badgeBgColor: Color(0xFFF1F5F9),
    gradientBorderColors: [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
    cardGradientColors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  static const PartnerTierTheme pro = PartnerTierTheme(
    type: PartnerTierType.pro,
    label: 'Partner Pro',
    badgeText: '💠 PRO',
    icon: Icons.electric_bolt_rounded,
    primaryColor: Color(0xFF00B4D8), // Cyber Cyan
    secondaryColor: Color(0xFF0077B6), // Sapphire Blue
    accentGlowColor: Color(0xFF00E5FF),
    textColor: Color(0xFF0077B6),
    badgeBgColor: Color(0xFFE0F7FA),
    gradientBorderColors: [Color(0xFF00E5FF), Color(0xFF0077B6)],
    cardGradientColors: [Color(0xFFFFFFFF), Color(0xFFF0FDF4)],
  );

  static const PartnerTierTheme diamond = PartnerTierTheme(
    type: PartnerTierType.diamond,
    label: 'VIP Diamond',
    badgeText: '👑 VIP DIAMOND',
    icon: Icons.workspace_premium_rounded,
    primaryColor: Color(0xFFFF2A6D), // Imperial Ruby
    secondaryColor: Color(0xFF880E4F),
    accentGlowColor: Color(0xFFFF80AB),
    textColor: Color(0xFFE63956),
    badgeBgColor: Color(0xFFFFF0F3),
    gradientBorderColors: [Color(0xFFFF2A6D), Color(0xFFFF80AB), Color(0xFFFFD700)],
    cardGradientColors: [Color(0xFFFFF7F8), Color(0xFFFFF0F3)],
  );

  // Helper chuyển đổi chuỗi từ Database sang Theme Object
  static PartnerTierTheme fromTier(dynamic isPremium, dynamic rawTier) {
    final bool premiumBool = isPremium == true || isPremium == 'true';
    if (!premiumBool) return standard;

    final String tierStr = (rawTier ?? '').toString().toUpperCase().trim();
    if (tierStr == 'DIAMOND' || tierStr == 'VIP_DIAMOND' || tierStr == 'VIP') {
      return diamond;
    } else if (tierStr == 'PRO' || tierStr == 'PARTNER_PRO') {
      return pro;
    }
    return standard;
  }
}