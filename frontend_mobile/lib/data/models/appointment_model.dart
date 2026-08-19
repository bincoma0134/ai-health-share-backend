import 'package:flutter/foundation.dart';

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
  final String? paymentDeadline;
  final String? preferredTime;
  final int guestCount;
  final Map<String, dynamic> serviceInfo;
  final Map<String, dynamic> userInfo;
  final Map<String, dynamic> voucherInfo; 
  final Map<String, dynamic> partnerInfo; // 🗺️ Đã đồng bộ đối tượng cơ sở (Địa chỉ, Tên cơ sở)

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
    this.paymentDeadline,
    this.preferredTime,
    this.guestCount = 1,
    required this.serviceInfo,
    required this.userInfo,
    required this.voucherInfo,
    required this.partnerInfo,
  });

  factory AppointmentModel.fromJson(Map<String, dynamic> json) {
    int parsedGuestCount = 1;
    try {
      if (json['guest_count'] is int) {
        parsedGuestCount = json['guest_count'];
      } else if (json['guest_count'] != null) {
        parsedGuestCount = int.tryParse(json['guest_count'].toString()) ?? 1;
      }
    } catch (e) {
      debugPrint('[ERROR-MODEL] Lỗi parse guest_count trong AppointmentModel: $e');
      parsedGuestCount = 1;
    }

    return AppointmentModel(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      partnerId: json['partner_id']?.toString() ?? '',
      serviceId: json['service_id']?.toString(),
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      customerName: json['customer_name']?.toString() ?? '',
      customerPhone: json['customer_phone']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      status: json['status']?.toString() ?? 'WAITING_PARTNER',
      startTime: json['start_time']?.toString(),
      endTime: json['end_time']?.toString(),
      checkInCode: json['check_in_code']?.toString(),
      rejectionReason: json['rejection_reason']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      paymentDeadline: json['payment_deadline']?.toString(),
      preferredTime: json['preferred_time']?.toString(),
      guestCount: parsedGuestCount,
      serviceInfo: json['services'] is Map<String, dynamic> ? json['services'] : {},
      userInfo: json['users'] is Map<String, dynamic> ? json['users'] : {},
      voucherInfo: json['vouchers'] is Map<String, dynamic> ? json['vouchers'] : {},
      partnerInfo: json['partner'] is Map<String, dynamic> ? json['partner'] : {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'partner_id': partnerId,
      'service_id': serviceId,
      'total_amount': totalAmount,
      'customer_name': customerName,
      'customer_phone': customerPhone,
      'note': note,
      'status': status,
      'start_time': startTime,
      'end_time': endTime,
      'check_in_code': checkInCode,
      'rejection_reason': rejectionReason,
      'created_at': createdAt,
      'payment_deadline': paymentDeadline,
      'preferred_time': preferredTime,
      'guest_count': guestCount,
      'services': serviceInfo,
      'users': userInfo,
      'vouchers': voucherInfo,
      'partner': partnerInfo,
    };
  }
}