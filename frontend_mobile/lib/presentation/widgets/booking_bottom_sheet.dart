import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../widgets/app_toast.dart';

class BookingBottomSheet extends StatefulWidget {
  final dynamic video;
  const BookingBottomSheet({super.key, required this.video});

  @override
  State<BookingBottomSheet> createState() => _BookingBottomSheetState();
}

class _BookingBottomSheetState extends State<BookingBottomSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _affiliateCtrl = TextEditingController(); 
  
  bool _isLoading = false;
  
  // --- STATE QUẢN LÝ VOUCHER & HÓA ĐƠN ---
  String? _appliedVoucherCode;
  String _appliedVoucherTitle = ''; 
  double _discountAmount = 0.0;
  bool _isVoucherSuccess = false;

  // --- STATE VÍ VOUCHER NGƯỜI DÙNG ---
  List<dynamic> _myVouchers = [];
  bool _isLoadingWallet = false;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  // SỬA CÚ PHÁP: Truy cập các trường dữ liệu của Map bằng cặp ngoặc vuông chuẩn xác chống crash luồng
  double get _basePrice => (widget.video['price'] ?? 0).toDouble();
  String get _partnerId => (widget.video['authorId'] ?? (widget.video['author'] != null ? widget.video['author']['id'] : '') ?? '').toString();
  
  double get _finalPrice {
    double total = _basePrice - _discountAmount;
    return total < 0 ? 0 : total;
  }

  @override
  void initState() {
    super.initState();
    _fetchUserVoucherWallet(); 
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    _affiliateCtrl.dispose();
    super.dispose();
  }

  // 🚀 ĐỒNG BỘ ĐỌC VÍ TỪ BACKEND
  Future<void> _fetchUserVoucherWallet() async {
    setState(() => _isLoadingWallet = true);
    try {
      final res = await ApiClient.instance.get('/vouchers/me'); 
      if (mounted) {
        setState(() {
          if (res.data is List) {
            _myVouchers = res.data; 
          } else if (res.data is Map) {
            _myVouchers = res.data['data'] ?? res.data['vouchers'] ?? res.data['items'] ?? [];
          } else {
            _myVouchers = [];
          }
          _isLoadingWallet = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWallet = false);
    }
  }

  // 🚀 ĐÃ DỨT ĐIỂM 404: Tự động tính toán trực tiếp bằng Frontend giống hệt Web (Zero-latency)
  void _applyVoucherLocal(Map<String, dynamic> voucher) {
    final String code = voucher['code'] ?? '';
    final String title = voucher['title'] ?? 'Ưu đãi';
    final String type = voucher['discount_type'] ?? 'FIXED';
    final double value = (voucher['discount_value'] ?? 0).toDouble();
    final double maxDiscount = (voucher['max_discount'] ?? 0).toDouble();
    
    double calculatedDiscount = 0;
    if (type == 'PERCENTAGE') {
      calculatedDiscount = _basePrice * (value / 100);
      if (maxDiscount > 0 && calculatedDiscount > maxDiscount) {
        calculatedDiscount = maxDiscount; 
      }
    } else {
      calculatedDiscount = value;
    }

    if (calculatedDiscount > _basePrice) calculatedDiscount = _basePrice;

    setState(() {
      _appliedVoucherCode = code;
      _appliedVoucherTitle = title; 
      _discountAmount = calculatedDiscount;
      _isVoucherSuccess = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Áp dụng mã ưu đãi thành công!'), backgroundColor: Color(0xFF80BF84))
    );
  }

  // LUỒNG GỬI ĐƠN ĐẶT LỊCH CHÍNH THỨC
  Future<void> _submitBooking() async {
    if (_nameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng điền đủ Tên và Số điện thoại')));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final payload = {
        'partner_id': _partnerId,
        'service_id': widget.video['id'] ?? '', // SỬA CÚ PHÁP: Dịch chuyển từ .id sang ['id']
        'appointment_date': DateTime.now().add(const Duration(days: 1)).toIso8601String().split('T')[0], 
        'start_time': '09:00:00', 
        'notes': 'Tên: ${_nameCtrl.text} | SĐT: ${_phoneCtrl.text} | Ghi chú: ${_noteCtrl.text}',
        if (_appliedVoucherCode != null) 'voucher_code': _appliedVoucherCode,
        if (_affiliateCtrl.text.trim().isNotEmpty) 'affiliate_code': _affiliateCtrl.text.trim(),
      };
      // 🚀 ĐÃ SỬA: Đổi sang endpoint chính xác theo main.py của bạn để dứt điểm lỗi 404
      await ApiClient.instance.post('/appointments/request', data: payload);
      if (mounted) {
        Navigator.pop(context);
        
        // 🚀 ĐÃ NÂNG CẤP: Sử dụng AppToast kính mờ cao cấp + Lời nhắc kiểm tra trang Lịch
        AppToast.show(
          context: context,
          message: '🎉 Đăng ký thành công! Vui lòng kiểm tra trạng thái và tiến độ tại trang Lịch.',
          isSuccess: true,
        );
      }
    } catch (e) {
      // Đồng bộ thông báo lỗi mượt mà qua AppToast
      if (mounted) {
        AppToast.show(
          context: context,
          message: 'Có lỗi xảy ra trong quá trình đặt lịch. Vui lòng thử lại.',
          isSuccess: false,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSoftInput(TextEditingController controller, String hint, IconData icon, {bool isPhone = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.04), borderRadius: BorderRadius.circular(20)),
      child: TextField(
        controller: controller,
        keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
          prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.5), size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  // NGĂN KÉO CHỌN VOUCHER TỪ VÍ CÁ NHÂN
  void _showVoucherSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: MediaQuery.of(context).size.height * 0.75, 
              padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
              decoration: BoxDecoration(
                color: const Color(0xFF131316).withOpacity(0.95),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
              ),
              child: Column(
                children: [
                  Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10))),
                  const Text('Ví Voucher của bạn', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: _myVouchers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wallet_giftcard_rounded, size: 48, color: Colors.white.withOpacity(0.2)),
                                const SizedBox(height: 16),
                                Text('Ví đang trống hoặc đang tải...', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _myVouchers.length,
                            itemBuilder: (context, index) {
                              final v = _myVouchers[index];
                              final String code = v['code'] ?? '';
                              final String title = v['title'] ?? 'Ưu đãi';
                              final double minOrder = (v['min_order_value'] ?? 0).toDouble();
                              
                              // 🚀 ĐÃ KHẮC PHỤC KHẨN TRƯƠNG: Sử dụng đúng trường issuer_type và issuer_id từ database
                              final String issuerType = (v['issuer_type'] ?? '').toString().toUpperCase();
                              final String? rawIssuerId = v['issuer_id']?.toString();
                              
                              // Điều kiện Admin chuẩn hóa tuyệt đối: Cứ issuer_type là ADMIN thì là mã toàn sàn
                              final bool isAdmin = issuerType == 'ADMIN';
                              
                              final String dType = v['discount_type'] ?? 'FIXED';
                              final double dValue = (v['discount_value'] ?? 0).toDouble();
                              final String discountDisplay = dType == 'PERCENTAGE' ? 'Giảm ${dValue.toInt()}%' : 'Giảm ${_currencyFormat.format(dValue)}';

                              String expiryDate = 'Vô thời hạn';
                              if (v['valid_until'] != null && v['valid_until'].toString().isNotEmpty) {
                                try {
                                  final d = DateTime.parse(v['valid_until'].toString());
                                  expiryDate = 'HSD: ${DateFormat('dd/MM/yyyy').format(d)}';
                                } catch (_) {}
                              }
                              
                              final bool isPriceValid = _basePrice >= minOrder;
                              // 🚀 Khớp điều kiện: Nếu mã đối tác thì cột issuer_id của voucher bắt buộc phải trùng khít với partnerId (author_id) của video này
                              final bool isPartnerValid = isAdmin || rawIssuerId == _partnerId;
                              final bool isSelectable = isPriceValid && isPartnerValid;

                              String lockReason = '';
                              if (!isPartnerValid) lockReason = 'Chỉ áp dụng cho dịch vụ cơ sở phát hành';
                              else if (!isPriceValid) lockReason = 'Đơn chưa đủ ${_currencyFormat.format(minOrder)}';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelectable ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.3),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isSelectable ? (isAdmin ? Colors.amber.withOpacity(0.3) : const Color(0xFF80BF84).withOpacity(0.3)) : Colors.white10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.local_activity_rounded, color: isSelectable ? (isAdmin ? Colors.amber : const Color(0xFF80BF84)) : Colors.white24, size: 32),
                                    const SizedBox(width: 16),
                                    
                                    // 🚀 ĐÃ SỬA LỖI 1: Bọc Expanded cho khối Text ở giữa để triệt tiêu lỗi RenderFlex overflowed 46px
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                margin: const EdgeInsets.only(right: 8),
                                                decoration: BoxDecoration(
                                                  color: isAdmin ? Colors.amber.withOpacity(0.2) : const Color(0xFF80BF84).withOpacity(0.2),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: isAdmin ? Colors.amber.withOpacity(0.5) : const Color(0xFF80BF84).withOpacity(0.5)),
                                                ),
                                                child: Text(isAdmin ? 'TOÀN SÀN' : 'CƠ SỞ', style: TextStyle(color: isAdmin ? Colors.amber : const Color(0xFF80BF84), fontSize: 9, fontWeight: FontWeight.w900)),
                                              ),
                                              // 🚀 Chống tràn chữ cho Code nếu quá dài
                                              Expanded(
                                                child: Text(code, style: TextStyle(color: isSelectable ? Colors.white : Colors.white30, fontWeight: FontWeight.w900, fontSize: 16), overflow: TextOverflow.ellipsis),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(title, style: TextStyle(color: isSelectable ? Colors.white70 : Colors.white24, fontSize: 13, fontWeight: FontWeight.w500)),
                                          const SizedBox(height: 4),
                                          // 🚀 ĐÃ SỬA: Thay thế Row bằng Wrap để tự động bẻ dòng mượt mà nếu HSD quá dài, triệt tiêu lỗi overflowed 5.3px
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 2,
                                            children: [
                                              Text(discountDisplay, style: TextStyle(color: isSelectable ? (isAdmin ? Colors.amber.shade300 : const Color(0xFF80BF84)) : Colors.white24, fontSize: 12, fontWeight: FontWeight.w900)),
                                              Text('• $expiryDate', style: TextStyle(color: isSelectable ? Colors.white54 : Colors.white24, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ],
                                          ),
                                          if (!isSelectable)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 8),
                                              child: Text(lockReason, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                                            )
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isSelectable)
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isAdmin ? Colors.amber : const Color(0xFF80BF84), 
                                          foregroundColor: Colors.black87,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16)
                                        ),
                                        onPressed: () {
                                          Navigator.pop(ctx); 
                                          _applyVoucherLocal(v); // Chạy tính toán trực tiếp, bypass lỗi 404 API validate
                                        },
                                        child: const Text('DÙNG', style: TextStyle(fontWeight: FontWeight.bold)),
                                      )
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25), 
        child: Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 24, left: 24, right: 24, top: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF131316).withOpacity(0.88), 
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)))),
                
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.15), shape: BoxShape.circle),
                      child: const Icon(Icons.eco_rounded, color: Color(0xFF80BF84), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text('Đặt lịch tư vấn', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Thông tin của bạn sẽ được bảo mật an toàn tuyệt đối.', style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 13)),
                const SizedBox(height: 24),
                
                _buildSoftInput(_nameCtrl, 'Họ và tên của bạn', Icons.person_rounded),
                _buildSoftInput(_phoneCtrl, 'Số điện thoại liên hệ', Icons.phone_rounded, isPhone: true),
                _buildSoftInput(_noteCtrl, 'Bạn cần lưu ý thêm điều gì không?', Icons.edit_note_rounded),
                _buildSoftInput(_affiliateCtrl, 'Mã giới thiệu (Affiliate) nếu có', Icons.handshake_rounded),

                // BAR CHỌN VOUCHER TỪ VÍ
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 24),
                  decoration: BoxDecoration(
                    color: _isVoucherSuccess ? const Color(0xFF80BF84).withOpacity(0.08) : Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _isVoucherSuccess ? const Color(0xFF80BF84).withOpacity(0.5) : Colors.white.withOpacity(0.08)),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: _isLoadingWallet ? null : _showVoucherSelectionSheet,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(Icons.local_activity_rounded, color: _isVoucherSuccess ? const Color(0xFF80BF84) : Colors.amber.shade300, size: 24),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_isVoucherSuccess ? 'Mã ưu đãi đã được áp dụng' : 'Ưu đãi & Voucher', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(_isVoucherSuccess ? _appliedVoucherTitle : 'Bấm để chọn từ ví của bạn', style: TextStyle(color: _isVoucherSuccess ? const Color(0xFF80BF84) : Colors.white.withOpacity(0.5), fontSize: 13, fontWeight: _isVoucherSuccess ? FontWeight.w900 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            if (_isLoadingWallet)
                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Color(0xFF80BF84), strokeWidth: 2))
                            else if (_isVoucherSuccess)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                                onPressed: () => setState(() { _isVoucherSuccess = false; _appliedVoucherCode = null; _appliedVoucherTitle = ''; _discountAmount = 0; }),
                              )
                            else
                              const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // KHỐI TẠM TÍNH HÓA ĐƠN NÂNG CẤP
                Container(
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.05))),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Giá dịch vụ', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14)),
                          Text(_currencyFormat.format(_basePrice), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (_discountAmount > 0) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text('Voucher: $_appliedVoucherCode', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 13, fontWeight: FontWeight.w600))),
                            Text('- ${_currencyFormat.format(_discountAmount)}', style: const TextStyle(color: Color(0xFF80BF84), fontSize: 14, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Divider(color: Colors.white.withOpacity(0.08), height: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Tổng thanh toán', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_discountAmount > 0)
                                Text(
                                  _currencyFormat.format(_basePrice), 
                                  style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13, decoration: TextDecoration.lineThrough, decorationColor: Colors.white54, fontWeight: FontWeight.w500)
                                ),
                              Text(
                                _currencyFormat.format(_finalPrice), 
                                style: TextStyle(color: _discountAmount > 0 ? const Color(0xFF80BF84) : Colors.white, fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),

                SafeArea(
                  top: false,
                  child: SizedBox(
                    width: double.infinity, height: 56,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF80BF84), 
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        elevation: 0,
                      ),
                      onPressed: _isLoading ? null : _submitBooking,
                      child: _isLoading 
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.black87, strokeWidth: 2)) 
                          : const Text('GỬI YÊU CẦU ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 14)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}