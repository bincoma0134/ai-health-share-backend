import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';

class PartnerAiContextScreen extends StatefulWidget {
  final String currentContext;

  const PartnerAiContextScreen({
    super.key,
    required this.currentContext,
  });

  @override
  State<PartnerAiContextScreen> createState() => _PartnerAiContextScreenState();
}

class _PartnerAiContextScreenState extends State<PartnerAiContextScreen> {
  late TextEditingController _contextController;
  bool _isSaving = false;

  final Color _bizPrimary = Colors.blue;
  final Color _bizSecondary = Colors.cyan;
  final Color _darkBgColor = const Color(0xFF1A3A35);
  final Color _partnerColor = const Color(0xFF80BF84);

  @override
  void initState() {
    super.initState();
    _contextController = TextEditingController(text: widget.currentContext);
  }

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _saveContext() async {
    final text = _contextController.text.trim();

    setState(() => _isSaving = true);
    
    try {
      final res = await ApiClient.instance.put(
        '/partner/ai-context',
        data: {'partner_ai_context': text},
      );

      if (res.statusCode == 200 && res.data['status'] == 'success') {
        if (mounted) {
          AppToast.show(context: context, message: 'Đã cập nhật định hướng AI!', isSuccess: true);
          Navigator.pop(context, true); // Trả về true để refresh màn hình trước
        }
      } else {
        if (mounted) {
          AppToast.show(context: context, message: 'Lỗi cập nhật. Vui lòng thử lại!', isSuccess: false);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context: context, message: 'Lỗi kết nối máy chủ!', isSuccess: false);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _darkBgColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Định Hướng AI Cơ Sở',
          style: TextStyle(color: _darkBgColor, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _partnerColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _partnerColor.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.tips_and_updates_rounded, color: _partnerColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Huấn luyện Trợ lý AI',
                            style: TextStyle(color: _darkBgColor, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'AI sẽ kết hợp thông tin bạn nhập dưới đây với danh sách Dịch vụ và Voucher để tư vấn chuẩn xác cho khách hàng.',
                            style: TextStyle(color: _darkBgColor.withOpacity(0.7), fontSize: 13, height: 1.4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Nội dung định hướng (Custom Context)',
                style: TextStyle(color: _darkBgColor, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _contextController,
                  maxLines: 12,
                  maxLength: 2000,
                  style: TextStyle(color: _darkBgColor, fontSize: 14, height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'Ví dụ: Cơ sở chuyên trị mụn bằng thảo dược đông y. Tư vấn nhẹ nhàng, luôn xưng "chuyên gia" và gọi khách hàng là "bạn"...',
                    hintStyle: TextStyle(color: Colors.grey.shade400),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _partnerColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: _isSaving ? null : _saveContext,
              child: _isSaving
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text(
                      'LƯU ĐỊNH HƯỚNG',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}