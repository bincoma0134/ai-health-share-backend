class VoucherModel {
  final String id;
  final String code;
  final String discountType;
  final double discountValue;
  final double minOrderValue;
  final int totalQuantity;
  final int usedQuantity;
  final String validFrom;
  final String validUntil;
  final String issuerType;
  final String? partnerName;
  final String? partnerUsername;
  final String? walletStatus;
  bool isClaimedLocal;

  VoucherModel({
    required this.id,
    required this.code,
    required this.discountType,
    required this.discountValue,
    required this.minOrderValue,
    required this.totalQuantity,
    required this.usedQuantity,
    required this.validFrom,
    required this.validUntil,
    required this.issuerType,
    this.partnerName,
    this.partnerUsername,
    this.walletStatus,
    this.isClaimedLocal = false,
  });

  factory VoucherModel.fromJson(Map<String, dynamic> json) {
    return VoucherModel(
      id: json['id'] ?? json['voucher_id'] ?? '',
      code: json['code'] ?? 'CODE',
      discountType: json['discount_type'] ?? 'FIXED_AMOUNT',
      discountValue: (json['discount_value'] ?? 0).toDouble(),
      minOrderValue: (json['min_order_value'] ?? 0).toDouble(),
      totalQuantity: json['total_quantity'] ?? 100,
      usedQuantity: json['used_quantity'] ?? 0,
      validFrom: json['valid_from'] ?? '',
      validUntil: json['valid_until'] ?? '',
      issuerType: (json['issuer_type'] ?? 'PARTNER').toString().toUpperCase(),
      partnerName: json['partner_name'],
      partnerUsername: json['partner_username'],
      walletStatus: json['wallet_status'],
      isClaimedLocal: false,
    );
  }
}