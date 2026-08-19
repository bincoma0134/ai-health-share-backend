class WalletModel {
  final double balance;
  final double pendingAmount;
  final double pointsBalance;

  WalletModel({required this.balance, required this.pendingAmount, this.pointsBalance = 0.0});

  factory WalletModel.fromJson(Map<String, dynamic> json) {
    // 🚀 BỌC THÉP NÂNG CẤP: Dò tìm linh hoạt points_balance (Từ Wallet API hoặc từ User Profile)
    double parsedPoints = 0.0;
    if (json.containsKey('points_balance')) {
      parsedPoints = (json['points_balance'] ?? 0).toDouble();
    } else if (json.containsKey('profile') && json['profile']['points_balance'] != null) {
      parsedPoints = (json['profile']['points_balance'] ?? 0).toDouble();
    }

    return WalletModel(
      balance: (json['balance'] ?? 0).toDouble(),
      pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
      pointsBalance: parsedPoints,
    );
  }
}