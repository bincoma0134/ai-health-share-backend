class WithdrawalRequestModel {
  final String id;
  final double amount;
  final String status; // 'PENDING', 'COMPLETED', 'REJECTED'
  final DateTime createdAt;

  WithdrawalRequestModel({
    required this.id, 
    required this.amount, 
    required this.status, 
    required this.createdAt
  });

  factory WithdrawalRequestModel.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequestModel(
      id: json['id']?.toString() ?? '',
      amount: (json['amount'] ?? 0.0).toDouble(),
      status: (json['status'] ?? 'PENDING').toString().toUpperCase(),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
    );
  }
}