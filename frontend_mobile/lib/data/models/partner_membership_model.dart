import 'package:flutter/material.dart';

enum MembershipTier { standard, pro, diamond }

class MembershipPricingOption {
  final int durationMonths;
  final double priceVnd;
  final String label;
  final String? discountBadge;

  const MembershipPricingOption({
    required this.durationMonths,
    required this.priceVnd,
    required this.label,
    this.discountBadge,
  });
}

class PartnerMembershipPlan {
  final MembershipTier tier;
  final String title;
  final String subtitle;
  final String badgeText;
  final List<Color> gradientColors;
  final Color accentColor;
  final IconData icon;
  final List<String> benefits;
  final List<MembershipPricingOption> pricingOptions;

  const PartnerMembershipPlan({
    required this.tier,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.gradientColors,
    required this.accentColor,
    required this.icon,
    required this.benefits,
    required this.pricingOptions,
  });

  static List<PartnerMembershipPlan> get defaultPlans => [
    PartnerMembershipPlan(
      tier: MembershipTier.pro,
      title: 'Partner Pro',
      subtitle: 'Tối ưu nhận diện & Chốt lịch tự động',
      badgeText: '💠 PRO PARTNER',
      gradientColors: [
        const Color(0xFF0A192F),
        const Color(0xFF0D3B66),
        const Color(0xFF005F73),
      ],
      accentColor: const Color(0xFF00E5FF), // Cyber Cyan Neon
      icon: Icons.electric_bolt_rounded,
      benefits: [
        'AI Trợ lý học sâu: Ngữ cảnh 5.000 ký tự',
        'Phí sàn ưu đãi: Giảm còn 25% (Nhận 75%)',
        'Tối đa 2 chiến dịch VIP Voucher / tháng',
        'Video Dịch vụ Full HD 1080p 60fps (3 phút)',
        'Huy hiệu 💠 PRO phát sáng trên Profile & Map',
      ],
      pricingOptions: const [
        MembershipPricingOption(durationMonths: 1, priceVnd: 599000, label: '1 Tháng'),
        MembershipPricingOption(durationMonths: 3, priceVnd: 1599000, label: '3 Tháng', discountBadge: 'Tiết kiệm 11%'),
        MembershipPricingOption(durationMonths: 12, priceVnd: 5999000, label: '1 Năm', discountBadge: 'Tiết kiệm 17%'),
      ],
    ),
    PartnerMembershipPlan(
      tier: MembershipTier.diamond,
      title: 'DIAMOND PARTNER',
      subtitle: 'Vị thế dẫn đầu & Doanh thu tối đa',
      badgeText: '👑 DIAMOND PARTNER',
      gradientColors: [
        const Color(0xFF2A080C),
        const Color(0xFF5E0B1B),
        const Color(0xFF880E4F),
      ],
      accentColor: const Color(0xFFFF2A6D), // Imperial Ruby & Prismatic Flare
      icon: Icons.workspace_premium_rounded,
      benefits: [
        'Ghim TOP 1 Bản đồ tìm kiếm toàn Hà Nội',
        'Khung viền Avatar phát sáng Ruby 5 sao công khai',
        'AI Trợ lý không giới hạn (10.000 ký tự, LLM 70B)',
        'Phí sàn thấp nhất: Chỉ 20% (Nhận 80% ròng)',
        'Không giới hạn phát hành Voucher VIP Store',
        'Video Dịch vụ 4K Ultra HD gốc (10 phút)',
      ],
      pricingOptions: const [
        MembershipPricingOption(durationMonths: 1, priceVnd: 1299000, label: '1 Tháng'),
        MembershipPricingOption(durationMonths: 3, priceVnd: 3499000, label: '3 Tháng', discountBadge: 'Tiết kiệm 10%'),
        MembershipPricingOption(durationMonths: 12, priceVnd: 9999000, label: '1 Năm', discountBadge: 'Tiết kiệm 36%'),
      ],
    ),
  ];
}

class PartnerSubscriptionStatus {
  final bool isPremium;
  final String premiumTier;
  final DateTime? premiumUntil;
  final int daysRemaining;

  PartnerSubscriptionStatus({
    required this.isPremium,
    required this.premiumTier,
    this.premiumUntil,
    required this.daysRemaining,
  });

  factory PartnerSubscriptionStatus.fromJson(Map<String, dynamic> json) {
    return PartnerSubscriptionStatus(
      isPremium: json['is_premium'] ?? false,
      premiumTier: (json['premium_tier'] ?? 'STANDARD').toString().toUpperCase(),
      premiumUntil: json['premium_until'] != null ? DateTime.tryParse(json['premium_until']) : null,
      daysRemaining: json['days_remaining'] ?? 0,
    );
  }
}