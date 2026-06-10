import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/services/calendar_api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth_bottom_sheet.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _storage = const FlutterSecureStorage();
  List<AppointmentModel> _appointments = [];
  bool _isLoading = true;
  bool _isAuthenticated = false;
  
  String _userRole = 'USER';

  // 4 TAB TIẾN TRÌNH LIFECYCLE ĐẲNG CẤP THEO YÊU CẦU
  String _activeTab = 'waiting'; // waiting | payment | upcoming | history
  
  final DateTime _selectedDate = DateTime.now();
  final List<DateTime> _currentWeekDays = List.generate(7, (i) => 
    DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(Duration(days: i))
  );

  @override
  void initState() {
    super.initState();
    _checkAuthAndLoad();
  }

  Future<void> _checkAuthAndLoad() async {
    final token = await _storage.read(key: 'ai-health-token');
    if (token == null || token.isEmpty) {
      setState(() { _isAuthenticated = false; _isLoading = false; });
    } else {
      setState(() => _isAuthenticated = true);
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final results = await Future.wait([
        CalendarApiService.fetchUserProfile(),
        CalendarApiService.fetchAppointments(),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final data = results[1] as List<AppointmentModel>;

      if (mounted) {
        setState(() {
          if (profile != null) _userRole = profile['role'] ?? 'USER';
          _appointments = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("❌ LỖI TẢI TIẾN TRÌNH LỊCH HẸN: $e");
    }
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0).format(price);
  }

  Color _getStatusThemeColor(String status) {
    switch (status.toUpperCase()) {
      case 'WAITING_PARTNER': return const Color(0xFFF59E0B); // Hổ phách
      case 'PENDING_PAYMENT': return const Color(0xFFEF4444); // Đỏ bảo chứng
      case 'CONFIRMED':
      case 'SERVED': return const Color(0xFF4C8D50); // Xanh VN Share
      default: return const Color(0xFF6B7280); // Xám lịch sử
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) return _buildRequireLogin();
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFFF4F7F6), body: Center(child: CircularProgressIndicator(color: Color(0xFF4C8D50))));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Column(
        children: [
          // 1. FIXED HEADER
          _buildPremiumHeaderDock(),

          // 2. MATRIX WEEK STRIP
          _buildMatrixWeekStrip(),

          // 3. APPOINTMENTS TIMELINE LIST
          Expanded(
            child: _buildAppointmentsTimeline(),
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeaderDock() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 10, 20, 20),
      decoration: const BoxDecoration(
        color: Color(0xFF1E3A1E),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Calendar', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 22), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22), onPressed: _loadData),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.15), borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                _buildCapsuleTab('Đang chờ', 'waiting'),
                _buildCapsuleTab('Thanh toán', 'payment'),
                _buildCapsuleTab('Sắp tới', 'upcoming'),
                _buildCapsuleTab('Lịch sử', 'history'),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildCapsuleTab(String label, String tabKey) {
    final isActive = _activeTab == tabKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tabKey),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? const Color(0xFF1E3A1E) : Colors.white60,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixWeekStrip() {
    final List<String> weekdays = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    final String currentMonthName = DateFormat('MMMM, yyyy').format(_selectedDate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: const Color(0xFFF4F7F6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(currentMonthName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.3)),
              const Row(
                children: [
                  Icon(Icons.chevron_left_rounded, color: Colors.black38, size: 20),
                  SizedBox(width: 16),
                  Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 20),
                ],
              )
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final day = _currentWeekDays[index];
              final isToday = day.day == DateTime.now().day && day.month == DateTime.now().month;
              
              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(weekdays[index], style: const TextStyle(color: Colors.black26, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isToday ? const Color(0xFF1E3A1E) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          color: isToday ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    )
                  ],
                ),
              );
            }),
          )
        ],
      ),
    );
  }

  Widget _buildAppointmentsTimeline() {
    final filteredList = _appointments.where((a) {
      final s = a.status.toUpperCase();
      if (_activeTab == 'waiting') return s == 'WAITING_PARTNER';
      if (_activeTab == 'payment') return s == 'PENDING_PAYMENT';
      if (_activeTab == 'upcoming') return s == 'CONFIRMED' || s == 'SERVED';
      if (_activeTab == 'history') return s == 'COMPLETED' || s == 'CANCELLED';
      return false;
    }).toList();

    if (filteredList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_rounded, size: 36, color: Colors.grey.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text('Không có lịch hẹn nào ở mục này.', style: TextStyle(color: Colors.black38, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      physics: const BouncingScrollPhysics(),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final appt = filteredList[index];
        final themeColor = _getStatusThemeColor(appt.status);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.015), blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: IntrinsicHeight( // 🚀 GIẢI PHÁP ĐỈNH CAO: Tự động đo và kéo dãn thanh màu trái bám khít nội dung text phải
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: themeColor,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                appt.serviceInfo['service_name'] ?? 'Dịch vụ trị liệu y tế', 
                                style: const TextStyle(color: Colors.black87, fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: -0.2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            
                            // 🚀 ĐẤU NỐI TOÁN HỌC HÓA ĐƠN HOÀN CHỈNH THÔNG SUỐT NHƯ WEB (VÁ LỖI CŨ)
                            Builder(
                              builder: (context) {
                                final double totalAmount = appt.totalAmount;
                                final double originalPrice = (appt.serviceInfo['price'] ?? totalAmount).toDouble();
                                final Map<String, dynamic> v = appt.voucherInfo;

                                if ((v.isNotEmpty && v['discount_value'] != null) || totalAmount < originalPrice) {
                                  final String voucherCode = v['code']?.toString() ?? "ƯU ĐÃI";
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        _formatPrice(originalPrice),
                                        style: const TextStyle(color: Colors.black38, fontSize: 10, decoration: TextDecoration.lineThrough, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                            margin: const EdgeInsets.only(right: 4),
                                            decoration: BoxDecoration(color: const Color(0xFF4C8D50).withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                                            child: Text(voucherCode, style: const TextStyle(color: Color(0xFF4C8D50), fontSize: 8, fontWeight: FontWeight.bold)),
                                          ),
                                          Text(_formatPrice(totalAmount), style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 13)),
                                        ],
                                      ),
                                    ],
                                  );
                                }
                                return Text(_formatPrice(totalAmount), style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 13));
                              }
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Khách hàng: ${appt.customerName} • SĐT: ${appt.customerPhone}',
                          style: const TextStyle(color: Colors.black38, fontSize: 11, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        
                        if (appt.note.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('📝 Lời nhắn: ${appt.note}', style: const TextStyle(color: Colors.black45, fontSize: 11, fontStyle: FontStyle.italic), maxLines: 2, overflow: TextOverflow.ellipsis),
                        ],
                        
                        // HỆ THỐNG PHÂN PHỐI NÚT BẤM HÀNH ĐỘNG NATIVE
                        if (appt.status.toUpperCase() == 'WAITING_PARTNER') ...[
                          const SizedBox(height: 10),
                          _buildActionWidgetButton('HỦY YÊU CẦU ĐẶT LỊCH', Colors.red.shade50, Colors.red, () => _handleCancel(appt.id)),
                        ],
                        
                        if (appt.status.toUpperCase() == 'PENDING_PAYMENT') ...[
                          const SizedBox(height: 10),
                          _buildActionWidgetButton('NẠP TIỀN KÝ GỬI BẢO CHỨNG (PAYOS)', const Color(0xFF1E3A1E).withOpacity(0.08), const Color(0xFF1E3A1E), () => _handlePayment(appt.id)),
                        ],
                        
                        if (appt.status.toUpperCase() == 'CONFIRMED' && appt.checkInCode != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFF4C8D50).withOpacity(0.08), borderRadius: BorderRadius.circular(10)),
                            child: Center(
                              child: Text('MÃ CHECK-IN: ${appt.checkInCode}', style: const TextStyle(color: Color(0xFF4C8D50), fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
                            ),
                          )
                        ],
                        
                        if (appt.status.toUpperCase() == 'SERVED') ...[
                          const SizedBox(height: 10),
                          _buildActionWidgetButton('XÁC NHẬN HÀI LÒNG (GIẢI NGÂN)', const Color(0xFF4C8D50).withOpacity(0.12), const Color(0xFF4C8D50), () => _handleUserConfirm(appt.id)),
                        ],
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionWidgetButton(String label, Color bgColor, Color textColor, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.3)),
      ),
    );
  }

  Widget _buildRequireLogin() {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A1E), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
          onPressed: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AuthBottomSheet(onSuccess: _checkAuthAndLoad)),
          child: const Text('Đăng nhập để xem Lịch hẹn', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Future<void> _handleCancel(String id) async {
    await CalendarApiService.cancelAppointment(id);
    _loadData();
  }
  Future<void> _handlePayment(String id) async {
    final url = await CalendarApiService.getPaymentUrl(id);
    if (url != null) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
  Future<void> _handleUserConfirm(String id) async {
    await CalendarApiService.confirmCompletion(id);
    AppToast.show(context: context, message: '🎉 Đã ký xác nhận giải ngân thành công!', isSuccess: true);
    _loadData();
  }
}