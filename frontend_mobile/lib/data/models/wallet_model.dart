class WalletModel {
  final double balance;
  final double pendingAmount;

  WalletModel({required this.balance, required this.pendingAmount});

  factory WalletModel.fromJson(Map<String, dynamic> json) => WalletModel(
    balance: (json['balance'] ?? 0).toDouble(),
    pendingAmount: (json['pending_amount'] ?? 0).toDouble(),
  );
}