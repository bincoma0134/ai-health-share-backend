class PartnerMapModel {
  final String id;
  final String username;
  final String fullName;
  final String avatarUrl;
  final double latitude;
  final double longitude;
  double distance;
  final List<String> tags;
  final List<dynamic> services;
  final bool isPremium; // 🚀 PHASE 08: Trạng thái hội viên VIP
  final String premiumTier; // 'STANDARD' | 'PRO' | 'DIAMOND'

  PartnerMapModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.latitude,
    required this.longitude,
    required this.distance,
    required this.tags,
    required this.services,
    this.isPremium = false,
    this.premiumTier = 'STANDARD',
  });

  // 🚀 GETTER HỖ TRỢ NHẬN DIỆN CẤP BẬC NHANH
  bool get isDiamond => isPremium && premiumTier.toUpperCase() == 'DIAMOND';
  bool get isPro => isPremium && premiumTier.toUpperCase() == 'PRO';

  factory PartnerMapModel.fromJson(Map<String, dynamic> json) {
    // Giải nén an toàn kiểu boolean cho is_premium
    final dynamic rawPremium = json['is_premium'];
    final bool isPrem = rawPremium == true || rawPremium == 'true' || rawPremium == 1;

    return PartnerMapModel(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? json['username']?.toString() ?? 'Đối tác',
      avatarUrl: json['avatar_url']?.toString() ?? '',
      // Mặc định tọa độ trung tâm Hà Nội nếu null
      latitude: (json['latitude'] != null) ? (json['latitude'] as num).toDouble() : 21.028511,
      longitude: (json['longitude'] != null) ? (json['longitude'] as num).toDouble() : 105.804817,
      distance: (json['distance'] != null) ? (json['distance'] as num).toDouble() : 0.0,
      tags: json['tags'] != null ? List<String>.from(json['tags']) : [],
      services: json['services'] is List ? json['services'] : [],
      isPremium: isPrem,
      premiumTier: (json['premium_tier'] ?? 'STANDARD').toString().toUpperCase(),
    );
  }
}