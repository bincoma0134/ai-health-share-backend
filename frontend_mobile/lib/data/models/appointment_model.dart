class AppointmentModel {
  final String id;
  final String userId;
  final String partnerId;
  final String? serviceId;
  final double totalAmount;
  final String customerName;
  final String customerPhone;
  final String note;
  final String status;
  final String? startTime;
  final String? endTime;
  final String? checkInCode;
  final String? rejectionReason;
  final String createdAt;
  final Map<String, dynamic> serviceInfo;
  final Map<String, dynamic> userInfo;

  AppointmentModel({
    required this.id,
    required this.userId,
    required this.partnerId,
    this.serviceId,
    required this.totalAmount,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.status,
    this.startTime,
    this.endTime,
    this.checkInCode,
    this.rejectionReason,
    required this.createdAt,
    required this.serviceInfo,
    required this.userInfo,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    return AppointmentModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      partnerId: json['partner_id'] ?? '',
      serviceId: json['service_id'],
      totalAmount: (json['total_amount'] ?? 0).toDouble(),
      customerName: json['customer_name'] ?? '',
      customerPhone: json['customer_phone'] ?? '',
      note: json['note'] ?? '',
      status: json['status'] ?? 'WAITING_PARTNER',
      startTime: json['start_time'],
      endTime: json['end_time'],
      checkInCode: json['check_in_code'],
      rejectionReason: json['rejection_reason'],
      createdAt: json['created_at'] ?? '',
      serviceInfo: json['services'] ?? {},
      userInfo: json['users'] ?? {},
    );
  }
}