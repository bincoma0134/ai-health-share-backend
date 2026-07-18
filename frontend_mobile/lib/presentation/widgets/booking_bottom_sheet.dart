import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import 'auth_guard.dart';
import '../widgets/app_toast.dart';
import 'shimmer_wrapper.dart';

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
  bool _isAutofilling = true; // 🚀 Mặc định khóa form và bật Shimmer khi bắt đầu mở BottomSheet
  
  // --- STATE QUẢN LÝ VOUCHER & HÓA ĐƠN ---
  String? _appliedVoucherCode;
  String _appliedVoucherTitle = ''; 
  double _discountAmount = 0.0;
  bool _isVoucherSuccess = false;

  // --- STATE VÍ VOUCHER NGƯỜI DÙNG ---
  List<dynamic> _myVouchers = [];
  bool _isLoadingWallet = false;
  bool _showMultiServiceTooltip = false; // 🚀 NÂNG CẤP UX: Quản lý hộp thoại gợi ý đa chọn

  // --- STATE DỊCH VỤ ĐỘNG (THAY THẾ GETTER TĨNH) ---
  List<dynamic> _partnerServices = [];
  bool _isLoadingServices = true;
  String? _selectedServiceId;
  List<String> _selectedServiceIds = []; // 🚀 NÂNG CẤP: Quản lý danh sách ID được chọn
  String _selectedServiceName = 'Dịch vụ đang chọn';
  double _selectedPrice = 0.0;

  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  // 🚀 LUỒNG 2: TRÍCH XUẤT GIÁ THƯƠNG MẠI GỐC & FALLBACK AN TOÀN
  double get _basePrice {
    // 1. Ưu tiên lấy giá cấu hình riêng trên chính video nội dung
    double videoPrice = (widget.video is Map) 
        ? (widget.video['price']?.toDouble() ?? 0.0) 
        : (widget.video.price?.toDouble() ?? 0.0);
        
    if (videoPrice > 0.0) return videoPrice;

    // 2. Luồng Fallback: Nếu giá video trống hoặc bằng 0, quét thông tin dịch vụ nhúng kèm để lấy giá gốc làm gốc
    if (widget.video is Map && widget.video['service'] is Map) {
      return (widget.video['service']['price'] ?? 0.0).toDouble();
    } else if (widget.video is! Map) {
      // Nếu video là Object Model, cấu trúc dữ liệu đã được map sắn qua tầng repository/model
      try {
        if (widget.video.price <= 0.0 && _videoServiceId != null) {
          // Fallback an toàn bảo vệ hệ thống không bị giá trị 0đ sai lệch
          return videoPrice;
        }
      } catch (_) {}
    }
    return videoPrice;
  }

  String get _videoAuthorId => (widget.video is Map) ? (widget.video['author_id'] ?? '') : widget.video.authorId;
  String get _videoId => (widget.video is Map) ? (widget.video['id'] ?? '') : widget.video.id;
  String? get _videoPartnerId => (widget.video is Map) ? widget.video['partner_id'] : widget.video.partnerId;
  String? get _videoServiceId => (widget.video is Map) ? widget.video['service_id'] : widget.video.serviceId;
  String? get _videoAuthorUsername => (widget.video is Map) 
      ? (widget.video['author'] is Map ? widget.video['author']['username'] : null) 
      : (widget.video.author is Map ? widget.video.author['username'] : null);
  String? get _videoVoucherCode => (widget.video is Map) ? widget.video['voucher_code'] : widget.video.voucherCode;
  
  // 🚀 ĐỊNH TUYẾN LỊCH HẸN KÉP (ASYMMETRIC ROUTING)
  String get _partnerId {
    if (_videoPartnerId != null && _videoPartnerId!.isNotEmpty) {
      return _videoPartnerId!;
    }
    return _videoAuthorId;
  }
  
  double get _finalPrice {
    double total = _basePrice - _discountAmount;
    return total < 0 ? 0 : total;
  }

  @override
  void initState() {
    super.initState();
    // 1. Chuyển đổi Getter tĩnh thành State động để khởi tạo mặc định
    _selectedServiceId = _videoServiceId;
    if (_videoServiceId != null) {
      _selectedServiceIds = [_videoServiceId!]; // 🚀 Khởi tạo danh sách mặc định
    }
    _selectedPrice = _basePrice;
    
    // Tự động quét Tên dịch vụ mặc định từ VideoModel nếu có nhúng sẵn
    if (widget.video is Map && widget.video['service'] != null && widget.video['service']['service_name'] != null) {
      _selectedServiceName = widget.video['service']['service_name'];
    } else if (widget.video is! Map) {
      try { _selectedServiceName = widget.video.service['service_name'] ?? 'Dịch vụ niêm yết'; } catch (_) { _selectedServiceName = 'Dịch vụ niêm yết'; }
    }

    _preloadUserData(); // Kích hoạt luồng Auto-fill thông tin khách hàng
    _fetchPartnerServices(); // 🚀 Tải ngầm danh sách dịch vụ cho Dropdown
    _processAutoVoucherAndFetchWallet(); 
    
    // 🚀 NÂNG CẤP UX: Kích hoạt độ trễ 1 giây để hiển thị bong bóng gợi ý
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _showMultiServiceTooltip = true);
    });
  }

  // 🚀 TẢI NGẦM DANH SÁCH DỊCH VỤ TỪ PARTNER ID LIÊN KẾT
  Future<void> _fetchPartnerServices() async {
    try {
      final res = await ApiClient.instance.get('/services?user_id=$_partnerId');
      if (mounted && res.data != null) {
        setState(() {
          if (res.data is List) {
            _partnerServices = res.data;
          } else if (res.data is Map && res.data['data'] != null) {
            _partnerServices = res.data['data'];
          }
          
          // Chốt chặn Fail-safe: Đồng bộ lại tên dịch vụ mặc định nếu tìm thấy trong list trả về
          if (_selectedServiceIds.isNotEmpty && _selectedServiceName == 'Dịch vụ niêm yết') {
            final match = _partnerServices.firstWhere((s) => s['id'] == _selectedServiceIds.first, orElse: () => null);
            if (match != null) _selectedServiceName = match['service_name'] ?? 'Dịch vụ niêm yết';
          }
        });
      }
    } catch (_) {
      // Im lặng nếu lỗi mạng, giữ nguyên giá trị mặc định lúc khởi tạo
    } finally {
      if (mounted) setState(() => _isLoadingServices = false);
    }
  }

  // 🚀 AUTO-FILL LUỒNG 4: Trích xuất danh tính ngầm định (Silent Extraction)
  Future<void> _preloadUserData() async {
    try {
      // 1. Gọi API chính xác dựa trên Source of Truth (Backend FastAPI)
      final res = await ApiClient.instance.get('/user/profile');
      final dynamic userData = res.data;

      if (userData != null) {
        // 2. Bóc tách lớp vỏ 'data' -> 'profile' theo đúng Schema của Backend
        Map<String, dynamic> data = {};
        if (userData is Map && userData.containsKey('data') && userData['data'] is Map && userData['data'].containsKey('profile')) {
          data = userData['data']['profile'];
        }

        if (mounted && data.isNotEmpty) {
          // 3. Quét thông minh (Dynamic Extraction) biến JSON định dạng Tên
          final name = data['full_name'] ?? data['fullName'] ?? data['name'] ?? '';
          if (name.toString().trim().isNotEmpty && _nameCtrl.text.isEmpty) {
            _nameCtrl.text = name.toString().trim();
          }

          // 4. Quét thông minh (Dynamic Extraction) biến JSON định dạng Số điện thoại
          final phone = data['phone'] ?? data['phone_number'] ?? data['phoneNumber'] ?? '';
          if (phone.toString().trim().isNotEmpty && _phoneCtrl.text.isEmpty) {
            _phoneCtrl.text = phone.toString().trim();
          }
        }
      }
    } catch (_) {
      // 5. Fail-safe: Im lặng bỏ qua, để trống form cho khách tự nhập nếu lỗi mạng
    } finally {
      // 6. Luôn mở khóa TextField bất kể thành công hay thất bại để trả quyền kiểm soát cho người dùng
      if (mounted) {
        setState(() => _isAutofilling = false);
      }
    }
  }

  // 🚀 LUỒNG 3: AUTO-CLAIM NGẦM & SELF-HEALING VOUCHER FLOW
  Future<void> _processAutoVoucherAndFetchWallet() async {
    final String? linkedVoucher = _videoVoucherCode;
    
    // Bước 3.1: Auto-Claim ngầm (Silent Try-Catch)
    if (linkedVoucher != null && linkedVoucher.isNotEmpty) {
      try {
        await ApiClient.instance.post('/vouchers/$linkedVoucher/claim');
      } catch (_) {
        // Im lặng bỏ qua lỗi nếu mã đã tồn tại trong ví
      }
    }

    // Luôn tải lại ví voucher mới nhất để đồng bộ Data
    await _fetchUserVoucherWallet();

    // Bước 3.2 & 3.3: Tự động áp dụng & Bắn Toast thông báo UX
    if (linkedVoucher != null && linkedVoucher.isNotEmpty && mounted) {
      try {
        // Tìm đúng voucher vừa claim trong ví để lấy thông số (Giá trị giảm, loại giảm)
        final targetVoucher = _myVouchers.firstWhere(
          (v) => (v['code'] ?? '') == linkedVoucher,
          orElse: () => null,
        );
        
        if (targetVoucher != null) {
          final double minOrder = (targetVoucher['min_order_value'] ?? 0).toDouble();
          // Bảo vệ Logic kinh doanh: Chỉ tự động áp dụng nếu đạt giá trị đơn tối thiểu
          if (_selectedPrice >= minOrder) {
            _applyVoucherLocal(targetVoucher, isAutoInjection: true);
          }
        }
      } catch (_) {}
    }
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

          // TỰ ĐỘNG CHỌN MÃ GIẢM SÂU NHẤT KHI MỞ POP-UP (Đồng bộ tuyệt đối với Website)
          if (_myVouchers.isNotEmpty) {
            dynamic bestVoucher;
            double maxDiscount = 0.0;

            for (var v in _myVouchers) {
              final String wStatus = v['wallet_status'] ?? '';
              if (wStatus != 'UNUSED') continue;

              // 🚀 CHỐT CHẶN BẢO MẬT 1: Loại bỏ ngay lập tức các mã đã quá hạn sử dụng khỏi thuật toán Auto-Apply
              bool isExpired = false;
              if (v['valid_until'] != null && v['valid_until'].toString().isNotEmpty) {
                try {
                  final expiryDate = DateTime.parse(v['valid_until'].toString());
                  if (expiryDate.isBefore(DateTime.now())) isExpired = true;
                } catch (_) {}
              }
              if (isExpired) continue;

              final String issuerType = (v['issuer_type'] ?? '').toString().toUpperCase();
              final String? rawIssuerId = v['issuer_id']?.toString();
              final bool isAdmin = issuerType == 'ADMIN';
              final bool isPartnerValid = isAdmin || rawIssuerId == _partnerId;

              final double minOrder = (v['min_order_value'] ?? 0).toDouble();
              if (_selectedPrice < minOrder || !isPartnerValid) continue;

              final String dType = v['discount_type'] ?? 'FIXED';
              final double dValue = (v['discount_value'] ?? 0).toDouble();
              final double maxDiscountAmount = (v['max_discount_amount'] ?? 0).toDouble();

              double currentDiscount = 0.0;
              if (dType == 'PERCENTAGE') {
                currentDiscount = _selectedPrice * (dValue / 100);
                if (maxDiscountAmount > 0 && currentDiscount > maxDiscountAmount) {
                  currentDiscount = maxDiscountAmount;
                }
              } else {
                currentDiscount = dValue;
              }

              if (currentDiscount > _selectedPrice) currentDiscount = _selectedPrice;

              if (currentDiscount > maxDiscount) {
                maxDiscount = currentDiscount;
                bestVoucher = v;
              }
            }

            if (bestVoucher != null) {
              _appliedVoucherCode = bestVoucher['code'];
              _appliedVoucherTitle = bestVoucher['title'] ?? 'Ưu đãi';
              _discountAmount = maxDiscount;
              _isVoucherSuccess = true;
            }
          }

          _isLoadingWallet = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingWallet = false);
    }
  }

  // 🚀 ĐÃ DỨT ĐIỂM 404: Tự động tính toán trực tiếp bằng Frontend giống hệt Web (Zero-latency)
  void _applyVoucherLocal(Map<String, dynamic> voucher, {bool isAutoInjection = false}) {
    final String code = voucher['code'] ?? '';
    final String title = voucher['title'] ?? 'Ưu đãi';
    final String type = voucher['discount_type'] ?? 'FIXED';
    final double value = (voucher['discount_value'] ?? 0).toDouble();
    final double maxDiscount = (voucher['max_discount_amount'] ?? 0).toDouble();
    
    double calculatedDiscount = 0;
    if (type == 'PERCENTAGE') {
      calculatedDiscount = _selectedPrice * (value / 100);
      if (maxDiscount > 0 && calculatedDiscount > maxDiscount) {
        calculatedDiscount = maxDiscount; 
      }
    } else {
      calculatedDiscount = value;
    }

    if (calculatedDiscount > _selectedPrice) calculatedDiscount = _selectedPrice;

    // 🚀 BƯỚC 3.2: Cập nhật UI & Đảm bảo thành tiền tối thiểu 10.000đ
    double expectedFinalPrice = _selectedPrice - calculatedDiscount;
    if (expectedFinalPrice < 10000 && _selectedPrice >= 10000) {
      calculatedDiscount = _selectedPrice - 10000;
    }

    setState(() {
      _appliedVoucherCode = code;
      _appliedVoucherTitle = title; 
      _discountAmount = calculatedDiscount;
      _isVoucherSuccess = true;
    });
    
    // 🚀 BƯỚC 3.3: THÔNG BÁO UX BỌC THÉP
    if (isAutoInjection) {
      AppToast.show(
        context: context, 
        message: 'Bạn đã nhận được 1 voucher ưu đãi và được tự động áp dụng trực tiếp cho dịch vụ này!', 
        isSuccess: true
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Áp dụng mã ưu đãi thành công!'), backgroundColor: Color(0xFF80BF84))
      );
    }
  }

  // LUỒNG GỬI ĐƠN ĐẶT LỊCH CHÍNH THỨC
  Future<void> _submitBooking() async {
    AuthGuard.run(context, action: () async {
      if (_nameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty) {
        // 🚀 ĐỒNG BỘ NÂNG CẤP UX: Thay SnackBar thô cứng bằng hệ thống AppToast kính mờ tinh tế lơ lửng trên đỉnh đầu app
        AppToast.show(
          context: context, 
          message: 'Vui lòng điền đầy đủ thông tin Họ tên và Số điện thoại để đặt lịch hẹn!', 
          isSuccess: false
        );
        return;
      }
      setState(() => _isLoading = true);
    try {
      final code = _affiliateCtrl.text.trim();
      if (code.isNotEmpty) {
        try {
          final validateRes = await ApiClient.instance.get('/affiliates/validate?code=$code');
          if (validateRes.statusCode != 200) {
            throw Exception('Mã giới thiệu không hợp lệ');
          }
        } catch (_) {
          if (mounted) {
            AppToast.show(
              context: context,
              message: 'Mã giới thiệu không hợp lệ hoặc không tồn tại!',
              isSuccess: false,
            );
            setState(() => _isLoading = false);
          }
          return;
        }
      }

      // --- LUỒNG ĐỊNH TUYẾN LỊCH HẸN KÉP (ASYMMETRIC ROUTING LOGIC) ---
      String? finalAffiliateCode = code.isNotEmpty ? code : null;
      if (_videoPartnerId != null && _videoPartnerId!.isNotEmpty && finalAffiliateCode == null) {
        finalAffiliateCode = _videoAuthorUsername ?? _videoAuthorId;
      }

      final payload = {
        'partner_id': _partnerId,
        'service_id': _selectedServiceId, // 🚀 Sử dụng ID của dịch vụ được chọn tại Dropdown
        'video_id': _videoId,
        'customer_name': _nameCtrl.text.trim(),
        'customer_phone': _phoneCtrl.text.trim(),
        'note': _noteCtrl.text.trim(),
        'total_amount': _selectedPrice.toInt(), // 🚀 Sử dụng Giá của dịch vụ được chọn tại Dropdown
        'voucher_code': _appliedVoucherCode,
        'affiliate_code': finalAffiliateCode,
      };
      
      await ApiClient.instance.post('/appointments/request', data: payload);
      if (mounted) {
        Navigator.pop(context);
        
        AppToast.show(
          context: context,
          message: '🎉 Yêu cầu đã được gửi! Vui lòng theo dõi tại tab \'Lịch hẹn\'.',
          isSuccess: true,
        );
      }
    } catch (e) {
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
    });
  }

  Widget _buildSoftInput(TextEditingController controller, String hint, IconData icon, {bool isPhone = false, bool isAutoFilledField = false}) {
    final bool shouldLock = isAutoFilledField && _isAutofilling;
    
    Widget inputWidget = Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        enabled: !shouldLock, // 🚀 Tạm khóa tương tác nếu đang quét thông tin
        keyboardType: isPhone ? TextInputType.phone : TextInputType.text,
        style: TextStyle(
          color: shouldLock ? const Color(0xFF94A3B8) : const Color(0xFF1E293B), 
          fontSize: 14, 
          fontWeight: FontWeight.w600
        ),
        decoration: InputDecoration(
          hintText: shouldLock ? 'Đang tải dữ liệu...' : hint,
          hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14, fontWeight: FontWeight.w400),
          prefixIcon: Icon(icon, color: shouldLock ? const Color(0xFFCBD5E1) : const Color(0xFF64748B), size: 18),
          filled: true,
          fillColor: shouldLock ? const Color(0xFFF8FAFC) : Colors.white, // Nền xám nhạt nếu khóa
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          disabledBorder: OutlineInputBorder( // 🚀 Định dạng viền khi bị khóa
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFF80BF84), width: 1.5),
          ),
        ),
      ),
    );

    // Bọc hiệu ứng quét sáng Shimmer nếu đây là field chờ Autofill và cờ đang bật
    if (shouldLock) {
      return ShimmerWrapper(child: inputWidget);
    }
    return inputWidget;
  }

  // 🚀 NGĂN KÉO CHỌN DỊCH VỤ ĐỘNG CỦA ĐỐI TÁC (DROPDOWN MODAL)
  void _showServiceSelectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        return StatefulBuilder( // 🚀 NÂNG CẤP: Sử dụng StatefulBuilder để cập nhật UI Modal tức thời
          builder: (BuildContext context, StateSetter setModalState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  height: MediaQuery.of(context).size.height * 0.65, 
                  padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.95),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Column(
                    children: [
                      Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(10))),
                      const Text('Chọn Dịch Vụ', style: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 16),
                      
                      Expanded(
                        child: _partnerServices.isEmpty
                            ? Center(child: Text(_isLoadingServices ? 'Đang tải dịch vụ...' : 'Cơ sở hiện chưa có dịch vụ nào', style: const TextStyle(color: Colors.black45)))
                            : ListView.builder(
                                itemCount: _partnerServices.length,
                                itemBuilder: (context, index) {
                                  final svc = _partnerServices[index];
                                  final String svcId = svc['id'] ?? '';
                                  final String svcName = svc['service_name'] ?? 'Dịch vụ';
                                  final double svcPrice = (svc['price'] ?? 0).toDouble();
                                  final bool isSelected = _selectedServiceIds.contains(svcId); // 🚀 Đổi sang kiểm tra mảng

                                  return InkWell(
                                    onTap: () {
                                      setModalState(() {
                                        // 1. Cập nhật State mảng dịch vụ
                                        if (isSelected) {
                                          if (_selectedServiceIds.length > 1) { // Bắt buộc chọn ít nhất 1
                                            _selectedServiceIds.remove(svcId);
                                          } else {
                                            AppToast.show(context: ctx, message: 'Phải chọn ít nhất 1 dịch vụ!', isSuccess: false);
                                            return;
                                          }
                                        } else {
                                          _selectedServiceIds.add(svcId);
                                        }
                                        
                                        // 2. Tính toán tổng tiền & Tên Combo
                                        _selectedPrice = 0.0;
                                        List<String> names = [];
                                        for (var s in _partnerServices) {
                                          if (_selectedServiceIds.contains(s['id'])) {
                                            _selectedPrice += (s['price'] ?? 0).toDouble();
                                            names.add(s['service_name'] ?? 'Dịch vụ');
                                          }
                                        }
                                        
                                        _selectedServiceId = _selectedServiceIds.join(',');
                                        _selectedServiceName = names.length > 1 ? 'Combo: ${names.join(', ')}' : (names.isNotEmpty ? names.first : 'Dịch vụ');
                                      });

                                      setState(() {
                                        // 3. 🚀 CHỐT CHẶN BẢO VỆ VOUCHER: Gỡ bỏ tự động nếu giá dịch vụ mới rớt chuẩn Min Order
                                        if (_isVoucherSuccess && _appliedVoucherCode != null) {
                                          final targetVoucher = _myVouchers.firstWhere(
                                            (v) => (v['code'] ?? '') == _appliedVoucherCode,
                                            orElse: () => null,
                                          );
                                          if (targetVoucher != null) {
                                            final minOrder = (targetVoucher['min_order_value'] ?? 0).toDouble();
                                            if (_selectedPrice < minOrder) {
                                              _isVoucherSuccess = false;
                                              _appliedVoucherCode = null;
                                              _appliedVoucherTitle = '';
                                              _discountAmount = 0.0;
                                              AppToast.show(
                                                context: context, 
                                                message: 'Đã gỡ Voucher do tổng dịch vụ không đạt giá trị đơn tối thiểu!', 
                                                isSuccess: false
                                              );
                                            } else {
                                              // Gọi lại để tính toán lại giá trị giảm giá
                                              _applyVoucherLocal(targetVoucher, isAutoInjection: false);
                                            }
                                          }
                                        } else {
                                          // Thử dò tìm xem có mã nào tự động ngon hơn không sau khi đổi dịch vụ
                                          _processAutoVoucherAndFetchWallet();
                                        }
                                      });
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF80BF84).withOpacity(0.1) : Colors.black.withOpacity(0.03),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: isSelected ? const Color(0xFF80BF84) : Colors.transparent, width: 1.5),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded, // 🚀 UX đổi sang Checkbox đa chọn
                                            color: isSelected ? const Color(0xFF5B9E5F) : Colors.black26
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(svcName, style: TextStyle(color: Colors.black87, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600, fontSize: 15)),
                                                const SizedBox(height: 4),
                                                Text(_currencyFormat.format(svcPrice), style: const TextStyle(color: Color(0xFF388E3C), fontSize: 13, fontWeight: FontWeight.w700)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      
                      // 🚀 NÚT XÁC NHẬN ĐÓNG MODAL
                      if (_partnerServices.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(top: 12, bottom: 24),
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF80BF84),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              elevation: 0,
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('XONG', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }
        );
      },
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
                color: Colors.white.withOpacity(0.9), // Đồng bộ sang nền sáng kính mờ
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: Colors.black.withOpacity(0.08))),
              ),
              child: Column(
                children: [
                  Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(10))),
                  const Text('Ví Voucher của bạn', style: TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: _myVouchers.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wallet_giftcard_rounded, size: 48, color: Colors.black.withOpacity(0.25)), // Đã sửa lỗi: Dùng cấu trúc opacity chuẩn cho màu đen
                                const SizedBox(height: 16),
                                const Text('Ví đang trống hoặc đang tải...', style: TextStyle(color: Colors.black45, fontSize: 14, fontWeight: FontWeight.w500)),
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
                              bool isExpired = false;
                              if (v['valid_until'] != null && v['valid_until'].toString().isNotEmpty) {
                                try {
                                  final d = DateTime.parse(v['valid_until'].toString());
                                  expiryDate = 'HSD: ${DateFormat('dd/MM/yyyy').format(d)}';
                                  // Kiểm tra chéo với thời gian thiết bị thực tế
                                  if (d.isBefore(DateTime.now())) isExpired = true;
                                } catch (_) {}
                              }
                              
                              final bool isPriceValid = _selectedPrice >= minOrder;
                              // 🚀 Khớp điều kiện: So khớp chuẩn xác với mã partnerId (authorId) thực tế trích xuất từ mô hình video
                              final bool isPartnerValid = isAdmin || rawIssuerId == _partnerId;
                              
                              // 🚀 CHỐT CHẶN BẢO MẬT 2: Bổ sung rào cản Hết hạn (isExpired) vào luồng bấm chọn
                              final bool isSelectable = isPriceValid && isPartnerValid && !isExpired;

                              String lockReason = '';
                              if (isExpired) lockReason = 'Mã ưu đãi đã hết hạn sử dụng';
                              else if (!isPartnerValid) lockReason = 'Chỉ áp dụng cho dịch vụ cơ sở phát hành';
                              else if (!isPriceValid) lockReason = 'Đơn chưa đủ ${_currencyFormat.format(minOrder)}';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: isSelectable ? Colors.black.withOpacity(0.03) : Colors.black.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: isSelectable ? (isAdmin ? Colors.amber : const Color(0xFF80BF84).withOpacity(0.4)) : Colors.transparent),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.local_activity_rounded, color: isSelectable ? (isAdmin ? Colors.amber.shade800 : const Color(0xFF5B9E5F)) : Colors.black26, size: 32),
                                    const SizedBox(width: 16),
                                    
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
                                                  color: isAdmin ? Colors.amber.withOpacity(0.15) : const Color(0xFF80BF84).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: isAdmin ? Colors.amber : const Color(0xFF80BF84)),
                                                ),
                                                child: Text(isAdmin ? 'TOÀN SÀN' : 'CƠ SỞ', style: TextStyle(color: isAdmin ? Colors.amber.shade900 : const Color(0xFF5B9E5F), fontSize: 9, fontWeight: FontWeight.w900)),
                                              ),
                                              Expanded(
                                                child: Text(code, style: TextStyle(color: isSelectable ? Colors.black87 : Colors.black38, fontWeight: FontWeight.w900, fontSize: 16), overflow: TextOverflow.ellipsis),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Text(title, style: TextStyle(color: isSelectable ? Colors.black54 : Colors.black26, fontSize: 13, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 6,
                                            runSpacing: 2,
                                            children: [
                                              Text(discountDisplay, style: TextStyle(color: isSelectable ? (isAdmin ? Colors.amber.shade900 : const Color(0xFF5B9E5F)) : Colors.black26, fontSize: 12, fontWeight: FontWeight.w900)),
                                              Text('• $expiryDate', style: TextStyle(color: isSelectable ? Colors.black45 : Colors.black26, fontSize: 11, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
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
    return Theme(
      // Ép cục bộ cửa sổ đặt lịch chuyển sang chế độ Light Theme để lấy lại cấu hình chữ đen hệ thống
      data: ThemeData.light().copyWith(
        primaryColor: const Color(0xFF80BF84),
        hintColor: Colors.black38,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            constraints: BoxConstraints(
              // Giới hạn tỷ lệ vàng: Chiều cao tối thiểu co theo nội dung, tối đa bằng 85% màn hình khi bật bàn phím
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom + 20, 
              left: 24, 
              right: 24, 
              top: 16
            ),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.88), // Đạt tỷ lệ tương phản chuẩn mực trên nền sáng Glassmorphism
              borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                color: Colors.white.withOpacity(0.6),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15), 
                  blurRadius: 30, 
                  offset: const Offset(0, -10)
                ),
                BoxShadow(
                  color: const Color(0xFF80BF84).withOpacity(0.08), 
                  blurRadius: 15, 
                  offset: const Offset(0, -2)
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.black.withOpacity(0.12), borderRadius: BorderRadius.circular(10)))),
                
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.2), shape: BoxShape.circle),
                      child: const Icon(Icons.eco_rounded, color: Color(0xFF5B9E5F), size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Text('Đặt lịch tư vấn', style: TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Thông tin của bạn sẽ được bảo mật an toàn tuyệt đối.', style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 24),
                
                _buildSoftInput(_nameCtrl, 'Họ và tên của bạn', Icons.person_rounded, isAutoFilledField: true),
                _buildSoftInput(_phoneCtrl, 'Số điện thoại liên hệ', Icons.phone_rounded, isPhone: true, isAutoFilledField: true),
                _buildSoftInput(_noteCtrl, 'Bạn cần lưu ý thêm điều gì không?', Icons.edit_note_rounded),
                _buildSoftInput(_affiliateCtrl, 'Mã giới thiệu (Affiliate) nếu có', Icons.handshake_rounded),

                // BAR CHỌN VOUCHER TỪ VÍ (Premium Ticket-Cut Effect)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isVoucherSuccess 
                          ? [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)] 
                          : [const Color(0xFFF8FAFC), const Color(0xFFF1F5F9)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _isVoucherSuccess ? const Color(0xFF80BF84).withOpacity(0.5) : const Color(0xFFE2E8F0)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      children: [
                        // Vết khoét vé bên trái
                        Positioned(
                          left: -8, top: 22,
                          child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                        ),
                        // Vết khoét vé bên phải
                        Positioned(
                          right: -8, top: 22,
                          child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isLoadingWallet ? null : _showVoucherSelectionSheet,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  Icon(Icons.local_activity_rounded, color: _isVoucherSuccess ? const Color(0xFF388E3C) : const Color(0xFF64748B), size: 22),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_isVoucherSuccess ? 'Mã ưu đãi đã áp dụng' : 'Ưu đãi & Voucher', style: const TextStyle(color: Color(0xFF1E293B), fontSize: 13, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 2),
                                        Text(_isVoucherSuccess ? _appliedVoucherCode! : 'Bấm để lựa chọn từ ví cá nhân', style: TextStyle(color: _isVoucherSuccess ? const Color(0xFF2E7D32) : const Color(0xFF64748B), fontSize: 12, fontWeight: _isVoucherSuccess ? FontWeight.w900 : FontWeight.normal), maxLines: 1, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  if (_isLoadingWallet)
                                    const SizedBox(width: 18, height: 20, child: CircularProgressIndicator(color: Color(0xFF80BF84), strokeWidth: 2))
                                  else if (_isVoucherSuccess)
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B), size: 18),
                                      onPressed: () => setState(() { _isVoucherSuccess = false; _appliedVoucherCode = null; _appliedVoucherTitle = ''; _discountAmount = 0; }),
                                    )
                                  else
                                    const Icon(Icons.chevron_right_rounded, color: Color(0xFF64748B), size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // KHỐI TẠM TÍNH HÓA ĐƠN TỰ DO (Floating Invoice Line)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Column(
                    children: [
                      // 🚀 NÚT DROPDOWN CHỌN DỊCH VỤ ĐỘNG
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          GestureDetector(
                            onTap: () {
                              if (_showMultiServiceTooltip) setState(() => _showMultiServiceTooltip = false); // Ẩn bong bóng ngay lập tức khi click
                              if (!_isLoadingServices) _showServiceSelectionSheet();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              color: Colors.transparent, // Bắt sự kiện Tap dễ dàng hơn
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center, // Neo giữa dòng để không bị lệch nếu tên dịch vụ dài
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text('Dịch vụ áp dụng', style: TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w600)),
                                            if (_isLoadingServices)
                                              const Padding(
                                                padding: EdgeInsets.only(left: 6),
                                                child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(color: Color(0xFF64748B), strokeWidth: 1.5)),
                                              )
                                            else
                                              const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF64748B), size: 18),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(_selectedServiceName, style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w800), maxLines: 2, overflow: TextOverflow.ellipsis),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Text(_currencyFormat.format(_selectedPrice), style: const TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                          // 🚀 BONG BÓNG GỢI Ý CHỌN NHIỀU (TOOLTIP)
                          if (_showMultiServiceTooltip)
                            Positioned(
                              top: -46, // 🚀 Lifted higher for Comic Tail
                              left: 0,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: _showMultiServiceTooltip ? 1.0 : 0.0,
                                child: _BouncingComicBubble(
                                  onClose: () => setState(() => _showMultiServiceTooltip = false),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_discountAmount > 0) ...[
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Text('Khấu trừ Voucher ($_appliedVoucherCode)', style: const TextStyle(color: Color(0xFF388E3C), fontSize: 13, fontWeight: FontWeight.w700))),
                            Text('- ${_currencyFormat.format(_discountAmount)}', style: const TextStyle(color: Color(0xFF388E3C), fontSize: 13, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ],
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Divider(color: Color(0xFFF1F5F9), height: 1, thickness: 1),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Tổng tiền thanh toán', style: TextStyle(color: Color(0xFF1E293B), fontSize: 14, fontWeight: FontWeight.w800)),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (_discountAmount > 0)
                                Text(
                                  _currencyFormat.format(_selectedPrice), 
                                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w500)
                                ),
                              Text(
                                _currencyFormat.format(_selectedPrice - _discountAmount < 0 ? 0 : _selectedPrice - _discountAmount), // Tính final inline 
                                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1)
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // NÚT CTA NỔI KHỐI CAO CẤP (Stadium Glow Button)
                Container(
                  width: double.infinity, 
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF80BF84), Color(0xFF4C8D50)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF80BF84).withOpacity(0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      elevation: 0,
                    ),
                    onPressed: _isLoading ? null : _submitBooking,
                    child: _isLoading 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Text('XÁC NHẬN ĐẶT LỊCH HẸN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
   ),
  );
 }
}

// 🚀 WIDGET ĐỘC LẬP: BONG BÓNG TRUYỆN TRANH (COMIC BUBBLE)
class _BouncingComicBubble extends StatefulWidget {
  final VoidCallback onClose;
  const _BouncingComicBubble({required this.onClose});

  @override
  State<_BouncingComicBubble> createState() => _BouncingComicBubbleState();
}

class _BouncingComicBubbleState extends State<_BouncingComicBubble> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _animation = Tween<double>(begin: 0, end: -8).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _animation.value),
          child: child,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B), // Nền đậm thanh lịch
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.25), blurRadius: 12, spreadRadius: 0, offset: const Offset(0, 2)), // 🚀 Ánh sáng Glow nhẹ nhàng, tự nhiên hơn
                BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Trải nghiệm cùng bạn bè? Chọn thêm dịch vụ nhé!', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: widget.onClose,
                  child: const Icon(Icons.close_rounded, color: Colors.white70, size: 16),
                ),
              ],
            ),
          ),
          // 🚀 Đuôi bong bóng truyện tranh (Comic Tail)
          Container(
            margin: const EdgeInsets.only(left: 32),
            child: CustomPaint(
              size: const Size(16, 8),
              painter: _ComicTailPainter(),
            ),
          )
        ],
      ),
    );
  }
}

class _ComicTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width / 2, size.height);
    path.lineTo(size.width, 0);
    path.close();
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}