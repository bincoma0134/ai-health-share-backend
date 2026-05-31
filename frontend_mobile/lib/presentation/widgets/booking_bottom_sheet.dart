import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../data/models/video_model.dart';
import '../../core/network/api_client.dart';

class BookingBottomSheet extends StatefulWidget {
  final VideoModel video;
  const BookingBottomSheet({super.key, required this.video});

  @override
  State<BookingBottomSheet> createState() => _BookingBottomSheetState();
}

class _BookingBottomSheetState extends State<BookingBottomSheet> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isLoading = false;

  Future<void> _submitBooking() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập Họ tên và SĐT')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await ApiClient.instance.post('/appointments/request', data: {
        'partner_id': widget.video.authorId,
        'video_id': widget.video.id,
        'total_amount': widget.video.price,
        'customer_name': _nameController.text.trim(),
        'customer_phone': _phoneController.text.trim(),
        'note': _noteController.text.trim(),
      });

      if (res.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yêu cầu đặt lịch đã được gửi đến cơ sở!', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
        }
      }
    } on DioException catch (e) {
      final msg = e.response?.data['detail'] ?? 'Lỗi đặt lịch';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      setState(() => _isLoading = false);
    }
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
            Text('Đặt lịch: ${widget.video.title}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('${widget.video.price} VND', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Số điện thoại', border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(controller: _noteController, maxLines: 2, decoration: const InputDecoration(labelText: 'Ghi chú (Tùy chọn)', border: OutlineInputBorder())),
            const SizedBox(height: 24),

            const Text('Bạn chưa cần thanh toán lúc này. Hệ thống sẽ giữ chỗ sau khi cơ sở xác nhận.', style: TextStyle(color: Colors.blue, fontSize: 12)),
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black),
                onPressed: _isLoading ? null : _submitBooking,
                child: _isLoading ? const CircularProgressIndicator(color: Colors.black) : const Text('Gửi yêu cầu đặt lịch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}