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
      badgeText: 'TĂNG TRƯỞNG',
      gradientColors: [const Color(0xFF1B4D3E), const Color(0xFF2C6B56)],
      accentColor: const Color(0xFF4EBA87),
      icon: Icons.auto_graph_rounded,
      benefits: [
        'AI Trợ lý học sâu: Ngữ cảnh 5.000 ký tự',
        'Phí sàn ưu đãi: Giảm còn 25% (Nhận 75%)',
        'Tối đa 2 chiến dịch VIP Voucher / tháng',
        'Video Dịch vụ Full HD 1080p 60fps (3 phút)',
        'Huy hiệu PRO phát sáng trên Profile & Map',
      ],
      pricingOptions: const [
        MembershipPricingOption(durationMonths: 1, priceVnd: 599000, label: '1 Tháng'),
        MembershipPricingOption(durationMonths: 3, priceVnd: 1599000, label: '3 Tháng', discountBadge: 'Tiết kiệm 11%'),
        MembershipPricingOption(durationMonths: 12, priceVnd: 5999000, label: '1 Năm', discountBadge: 'Tiết kiệm 17%'),
      ],
    ),
    PartnerMembershipPlan(
      tier: MembershipTier.diamond,
      title: 'VIP Diamond',
      subtitle: 'Vị thế dẫn đầu & Doanh thu tối đa',
      badgeText: '👑 BEST VALUE',
      gradientColors: [const Color(0xFF3A0D15), const Color(0xFF6B1D2A), const Color(0xFFD4AF37)],
      accentColor: const Color(0xFFFFD700),
      icon: Icons.workspace_premium_rounded,
      benefits: [
        'Ghim TOP 1 Bản đồ tìm kiếm toàn Hà Nội',
        'Khung viền Avatar phát sáng Ruby Gold 5 sao',
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