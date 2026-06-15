import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../data/models/service_model.dart';
import '../../core/network/api_client.dart';
import 'auth_guard.dart';

class ServiceBookingBottomSheet extends StatefulWidget {
  final ServiceModel service;
  const ServiceBookingBottomSheet({super.key, required this.service});

  @override
  State<ServiceBookingBottomSheet> createState() => _ServiceBookingBottomSheetState();
}

class _ServiceBookingBottomSheetState extends State<ServiceBookingBottomSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  final _affiliateController = TextEditingController();
  bool _isSubmitting = false;

  Future<void> _submitBooking() async {
    AuthGuard.run(context, action: () async {
      if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập Họ tên và SĐT')));
        return;
      }

      setState(() => _isSubmitting = true);
    try {
      // 1. Kiểm tra mã Affiliate nếu có
      final code = _affiliateController.text.trim();
      if (code.isNotEmpty) {
        await ApiClient.instance.get('/affiliates/validate', queryParameters: {'code': code});
      }

      // 2. Gửi yêu cầu đặt lịch
      final res = await ApiClient.instance.post('/appointments/request', data: {
        'partner_id': widget.service.partnerId,
        'service_id': widget.service.id,
        'affiliate_code': code.isEmpty ? null : code,
        'total_amount': widget.service.price,
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'note': _noteController.text.trim(),
      });

      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop(); // Giải phóng luồng an toàn
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yêu cầu đặt lịch đã được gửi đến cơ sở!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: Colors.green));
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? 'Lỗi đặt lịch';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() => _isSubmitting = false);
    }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đặt lịch: ${widget.service.serviceName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${widget.service.price} VND', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _noteController, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú (Tùy chọn)', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _affiliateController, decoration: const InputDecoration(labelText: 'Mã giới thiệu (Tùy chọn)', border: OutlineInputBorder())),
            const SizedBox(height: 24),

            const Text('Bạn chưa cần thanh toán lúc này. Hệ thống sẽ giữ chỗ sau khi cơ sở xác nhận.', style: TextStyle(color: Colors.blue, fontSize: 12)),
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black),
                onPressed: _isSubmitting ? null : _submitBooking,
                child: _isSubmitting ? const CircularProgressIndicator(color: Colors.black) : const Text('Gửi yêu cầu đặt lịch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}