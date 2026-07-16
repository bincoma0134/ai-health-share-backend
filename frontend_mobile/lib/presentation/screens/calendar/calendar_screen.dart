import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Đã bổ sung: Phục vụ tương tác hệ thống Clipboard sao chép một chạm
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/services/calendar_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth_bottom_sheet.dart';
import '../../widgets/auth_guard.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/notification_notifier.dart'; // 🚀 Bổ sung thư viện quản lý State thông báo
import 'package:go_router/go_router.dart'; // 🚀 BẢN VÁ: Khai thông hàm extension .push() cho context

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> with WidgetsBindingObserver {
  List<AppointmentModel> _appointments = [];
  bool _isLoading = true;
  
  String _userRole = 'USER';
  String _searchQuery = ''; // Kính lúp tìm kiếm local dữ liệu lịch hẹn
  bool _isSearching = false; // 🚀 Biến trạng thái bật/tắt thanh tìm kiếm Inline chuẩn UX
  String? _avatarUrl; // 🚀 Lưu trữ URL ảnh đại diện động bóc tách từ API hệ thống
  String _customerFullName = ''; // Phục vụ hiển thị kí tự viết tắt khi ảnh lỗi
  final _searchController = TextEditingController(); // Quản lý dữ liệu text nhập vào thanh tìm kiếm
  final Map<String, TextEditingController> _checkInControllers = {}; // Lưu trữ controller nhập mã độc lập theo ID4

  // 4 TAB TIẾN TRÌNH LIFECYCLE ĐẲNG CẤP THEO YÊU CẦU
  String _activeTab = 'waiting'; // waiting | payment | upcoming | history

  // Trạng thái cấu hình chế độ hiển thị lịch trình cử chỉ thông minh
  bool _isMonthView = false;

  // Cấu hình chế độ xem chuyên biệt cho Đối tác: timeline (Trục thời gian) hoặc analytics (Biểu đồ Thống kê)
  String _partnerViewMode = 'timeline';

  bool get _isMyClient => _userRole == 'PARTNER' || _userRole == 'PARTNER_ADMIN';
  
  DateTime _selectedDate = DateTime.now(); // 🚀 Chuyển thành biến động để cập nhật khi chọn tháng
  DateTime _focusedDate = DateTime.now(); // Ghi nhận ngày đang được nhấn lọc local trên UI mới
  List<DateTime> _currentWeekDays = List.generate(7, (i) => 
    DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1)).add(Duration(days: i))
  );

  // Hàm bổ trợ tính toán lại dải 7 ngày trong tuần dựa trên tháng/năm mới được chọn
  void _updateWeekDaysBasedOnDate(DateTime targetDate) {
    setState(() {
      _selectedDate = targetDate;
      _focusedDate = targetDate; // Đồng bộ tiêu điểm về ngày được chọn
      
      // Tính toán ngày đầu tuần của tuần chứa ngày targetDate
      final int weekdayOffset = targetDate.weekday - 1;
      final DateTime startOfWeek = DateTime(targetDate.year, targetDate.month, targetDate.day).subtract(Duration(days: weekdayOffset));
      
      _currentWeekDays = List.generate(7, (i) => 
        startOfWeek.add(Duration(days: i))
      );
    });
  }

  // Hàm bổ trợ kiểm tra xem ngày cụ thể có chứa lịch hẹn cần chú ý hay không để vẽ dấu chấm đỏ
  bool _hasActiveNotificationDot(DateTime day) {
    return _appointments.any((a) {
      if (a.startTime == null || a.startTime!.isEmpty) return false;
      try {
        final parsedDate = DateTime.parse(a.startTime!);
        final bool isSameDay = parsedDate.day == day.day && 
                               parsedDate.month == day.month && 
                               parsedDate.year == day.year;
        if (!isSameDay) return false;
        
        final String s = a.status.toUpperCase();
        return s == 'WAITING_PARTNER' || s == 'PENDING_PAYMENT' || s == 'CONFIRMED' || s == 'SERVED';
      } catch (_) {
        return false;
      }
    });
  }

  // Hàm bổ trợ dịch chuyển chu kỳ thời gian (Tuần hoặc Tháng) khi người dùng vuốt sang ngang
  void _handleHorizontalSwipeNavigation(bool isNext) {
    setState(() {
      if (_isMonthView) {
        // 1. Nếu đang ở chế độ MỞ RỘNG (MONTH VIEW): Tăng/Giảm 1 tháng chuẩn xác
        final int nextMonth = isNext ? _selectedDate.month + 1 : _selectedDate.month - 1;
        final DateTime newMonthDate = DateTime(_selectedDate.year, nextMonth, 1);
        
        _selectedDate = newMonthDate;
        // Đồng bộ tiêu điểm focusedDate về ngày đầu tiên hoặc ngày tương ứng của tháng mới
        int targetDay = _focusedDate.day;
        final int lastDayOfNewMonth = DateTime(newMonthDate.year, newMonthDate.month + 1, 0).day;
        if (targetDay > lastDayOfNewMonth) targetDay = lastDayOfNewMonth;
        
        _focusedDate = DateTime(newMonthDate.year, newMonthDate.month, targetDay);
        
        // Tính toán lại dải tuần tương ứng với ngày tiêu điểm mới để khi thu gọn không bị lệch vị trí
        final int weekdayOffset = _focusedDate.weekday - 1;
        final DateTime startOfWeek = DateTime(_focusedDate.year, _focusedDate.month, _focusedDate.day).subtract(Duration(days: weekdayOffset));
        _currentWeekDays = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
      } else {
        // 2. Nếu đang ở chế độ RÚT GỌN (WEEK VIEW): Tịnh tiến tăng/giảm 7 ngày
        final int offsetDays = isNext ? 7 : -7;
        _focusedDate = _focusedDate.add(Duration(days: offsetDays));
        _currentWeekDays = List.generate(7, (i) => _currentWeekDays[i].add(Duration(days: offsetDays)));
        
        // Nếu ngày tiêu điểm vượt khỏi tháng đang hiển thị, tự động đồng bộ lại nhãn tên tháng trên Header
        if (_focusedDate.month != _selectedDate.month || _focusedDate.year != _selectedDate.year) {
          _selectedDate = DateTime(_focusedDate.year, _focusedDate.month, 1);
        }
      }
    });
  }

  // Hàm tạo danh sách tất cả các ngày hiển thị trong lưới tháng (bao gồm cả ô trống bù đầu/cuối tuần)
  List<DateTime?> _generateMonthGridDays(DateTime monthDate) {
    final DateTime firstDayOfMonth = DateTime(monthDate.year, monthDate.month, 1);
    final DateTime lastDayOfMonth = DateTime(monthDate.year, monthDate.month + 1, 0);
    
    final int prefixEmptyCells = firstDayOfMonth.weekday - 1;
    final List<DateTime?> gridCells = [];
    
    // Thêm các ô trống đại diện cho các ngày thuộc tháng trước
    for (int i = 0; i < prefixEmptyCells; i++) {
      gridCells.add(null);
    }
    
    // Thêm toàn bộ các ngày thực tế của tháng hiện tại
    for (int i = 1; i <= lastDayOfMonth.day; i++) {
      gridCells.add(DateTime(monthDate.year, monthDate.month, i));
    }
    
    return gridCells;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Lắng nghe App Lifecycle
    _loadData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 🚀 ĐỒNG BỘ LOGIC: Tự động tải lại lịch hẹn ngay khi khách quay về từ cổng thanh toán PayOS
      _loadData();
    }
  }

  bool _isFetchingLock = false;
  Future<void> _loadData() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    
    if (!mounted) {
      _isFetchingLock = false;
      return;
    }
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
          if (profile != null) {
            _userRole = profile['role'] ?? 'USER';
            _avatarUrl = profile['avatar_url']; // Đấu nối chính xác trường dữ liệu từ API
            _customerFullName = profile['full_name'] ?? '';
          }
          _appointments = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("❌ LỖI TẢI TIẾN TRÌNH LỊCH HẸN: $e");
    } finally {
      _isFetchingLock = false;
    }
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ', decimalDigits: 0).format(price);
  }

  // Thuật toán ma thuật đồng bộ 1:1 từ Website: Tính toán toàn bộ mảng Metric, KPIs doanh thu Escrow và biểu đồ cho Đối tác
  Map<String, dynamic> _calculatePartnerMetrics() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int todayCount = 0;
    int pendingCheckInCount = 0;
    int pendingPaymentCount = 0;
    int cancelledTotal = 0;
    double weeklyRev = 0.0;
    int totalCompleted = 0;

    // Thiết lập mảng danh sách 7 ngày qua phục vụ trục hoành biểu đồ cột
    final List<DateTime> last7DaysDates = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final List<String> last7DaysLabels = last7DaysDates.map((d) => DateFormat('dd/MM').format(d)).toList();
    final Map<String, double> revByDay = {for (var label in last7DaysLabels) label: 0.0};

    for (var a in _appointments) {
      if (a.startTime == null || a.startTime!.isEmpty) continue;
      try {
        final startObj = DateTime.parse(a.startTime!);
        final startDay = DateTime(startObj.year, startObj.month, startObj.day);
        final String dateLabel = DateFormat('dd/MM').format(startObj);
        final String s = a.status.toUpperCase();

        // 1. Thống kê Lịch hôm nay & Chờ Check-in
        if (startDay.isAtSameMomentAs(today)) {
          todayCount++;
          if (s == 'CONFIRMED') pendingCheckInCount++;
        }

        // 2. Thống kê Chờ thanh toán & Đơn đã hủy tổng thể
        if (s == 'PENDING_PAYMENT') pendingPaymentCount++;
        if (s == 'CANCELLED') cancelledTotal++;

        // 3. Phân tách doanh thu Escrow bọc thép bảo vệ quyền lợi Đối tác khi áp Voucher sàn (ADMIN)
        if (s == 'COMPLETED' || s == 'SERVED') {
          totalCompleted++;
          
          double originalTotal = a.totalAmount;
          double discountAmount = 0.0;
          String? fundedBy;

          if (a.voucherInfo.isNotEmpty) {
            fundedBy = a.voucherInfo['issuer_type'];
            
            // Tính toán mức giảm trừ tương tự giao diện
            double basePrice = (a.serviceInfo['price'] ?? a.totalAmount ?? 0).toDouble();
            if (a.voucherInfo['discount_value'] != null) {
              double discountValue = (a.voucherInfo['discount_value'] ?? 0).toDouble();
              if (a.voucherInfo['discount_type'] == 'PERCENTAGE') {
                discountAmount = (basePrice * discountValue) / 100.0;
                if (a.voucherInfo['max_discount_amount'] != null) {
                  double maxDiscount = (a.voucherInfo['max_discount_amount'] ?? 0).toDouble();
                  if (discountAmount > maxDiscount) discountAmount = maxDiscount;
                }
              } else {
                discountAmount = discountValue;
              }
            }
          }

          // Công thức Escrow Toán học đồng bộ Backend: Đối tác nhận 70% doanh thu
          // Nếu Đối tác phát hành mã -> Chịu phần discount. Nếu Sàn phát hành -> Sàn chịu.
          double revenueBase = (fundedBy == 'PARTNER') ? (originalTotal - discountAmount) : originalTotal;
          if (revenueBase < 0) revenueBase = 0;
          double actualPartnerRevenue = revenueBase * 0.70;

          if (revByDay.containsKey(dateLabel)) {
            revByDay[dateLabel] = revByDay[dateLabel]! + actualPartnerRevenue;
            weeklyRev += actualPartnerRevenue;
          }
        }
      } catch (_) {}
    }

    final double aov = totalCompleted > 0 ? weeklyRev / totalCompleted : 0.0;

    return {
      'todayCount': todayCount,
      'pendingCheckInCount': pendingCheckInCount,
      'pendingPaymentCount': pendingPaymentCount,
      'cancelledTotal': cancelledTotal,
      'weeklyRev': weeklyRev,
      'totalCompleted': totalCompleted,
      'aov': aov,
      'labels': last7DaysLabels,
      'chartData': last7DaysLabels.map((l) => revByDay[l]!).toList(),
    };
  }

  // Mở BottomSheet kết nối hiển thị danh sách lịch hẹn bóc tách chi tiết theo từng chỉ số Metric đầu thẻ
  void _openMetricDetailsBottomSheet(String type, String title) {
    final now = DateTime.now();
    final todayStr = DateTime(now.year, now.month, now.day);

    final List<AppointmentModel> filteredList = _appointments.where((a) {
      if (a.startTime == null || a.startTime!.isEmpty) return false;
      try {
        final startObj = DateTime.parse(a.startTime!);
        final startDay = DateTime(startObj.year, startObj.month, startObj.day);
        final s = a.status.toUpperCase();

        if (type == 'today') return startDay.isAtSameMomentAs(todayStr);
        if (type == 'checkin') return s == 'CONFIRMED';
        if (type == 'payment') return s == 'PENDING_PAYMENT';
        if (type == 'cancelled') return s == 'CANCELLED';
      } catch (_) {}
      return false;
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
              Text('Tổng cộng: ${filteredList.length} lịch hẹn', style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: filteredList.isEmpty
                    ? const Center(child: Text('Không có dữ liệu hiển thị.', style: TextStyle(color: Colors.black38, fontSize: 13, fontWeight: FontWeight.bold)))
                    : ListView.builder(
                        itemCount: filteredList.length,
                        physics: const BouncingScrollPhysics(),
                        itemBuilder: (context, idx) {
                          final item = filteredList[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F7F6),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.customerName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text(item.serviceInfo['service_name'] ?? 'Dịch vụ y tế', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                      const SizedBox(height: 2),
                                      Text(
                                        item.startTime != null ? DateFormat('HH:mm - dd/MM/yyyy').format(DateTime.parse(item.startTime!)) : '',
                                        style: const TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(_formatPrice(item.totalAmount), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4C8D50))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Color _getStatusThemeColor(String status) {
    switch (status.toUpperCase()) {
      case 'WAITING_PARTNER': 
        return const Color(0xFFF59E0B); // Màu vàng hổ phách chờ duyệt
      case 'PENDING_PAYMENT': 
        return const Color(0xFFFF5E3A); // Màu cam hồng chủ đạo chờ ký gửi PayOS
      case 'CONFIRMED':
      case 'SERVED': 
        return const Color(0xFF3B82F6); // Màu xanh lam bảo chứng (brand-trust) chuẩn Escrow
      case 'COMPLETED':
        return const Color(0xFF80BF84); // Màu xanh y tế hoàn thành giải ngân (brand-primary)
      default: 
        return const Color(0xFF9CA3AF); // Màu xám cho lịch hẹn đã hủy (Cancelled)
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => _buildRequireLogin(),
      builder: (context, token, userId) {
        if (_isLoading) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: ShimmerWrapper(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Skeleton Header Tháng & Avatar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(height: 30, width: 150, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(8))),
                        Container(height: 32, width: 32, decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Skeleton 4 Tabs Tiến Trình
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(4, (index) => Container(height: 30, width: 75, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(12)))),
                    ),
                    const SizedBox(height: 24),
                    // Skeleton Lưới Lịch 7 Ngày
                    Container(height: 100, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(24))),
                    const SizedBox(height: 24),
                    // Skeleton Danh Sách Card Lịch Hẹn
                    Expanded(
                      child: ListView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 4,
                        itemBuilder: (context, index) => Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          height: 130,
                          decoration: BoxDecoration(color: const Color(0xFFE2ECEB), borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
        }

        return Scaffold(
      backgroundColor: Colors.white, // Ép cứng nền sáng phẳng (Light Mode Only) theo bản vẽ thiết kế mới
      body: Column(
        children: [
          // 1. FIXED HEADER
          _buildPremiumHeaderDock(),

          // 2. PHÂN DIỆN RẼ NHÁNH: Nếu là ĐỐI TÁC, nhúng thêm khối hiển thị quản trị nâng cao dạng cuộn ngang phóng khoáng
          if (_isMyClient) ...[
            _buildPartnerTopMetricsBar(),
            _buildPartnerViewModeToggler(),
          ],

          // 3. ĐIỀU PHỐI NỘI DUNG THEO VIEW MODE VÀ ROLE SYSTEM
          Expanded(
            child: _isMyClient && _partnerViewMode == 'analytics'
                ? SingleChildScrollView(physics: const BouncingScrollPhysics(), child: _buildPartnerAnalyticsView())
                : Column(
                    children: [
                      _buildMatrixWeekStrip(),
                      Expanded(child: _buildAppointmentsTimeline()),
                    ],
                  ),
          ),
        ],
      ),
    );
      },
    );
  }

  // Khối dựng dải cuộn ngang 4 nút thống kê chỉ số (Top Metrics Bar) thông thoáng chuẩn phong cách cao cấp của Web
  Widget _buildPartnerTopMetricsBar() {
    final m = _calculatePartnerMetrics();

    return SizedBox(
      height: 72,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        children: [
          _buildMetricItemCard('Lịch hôm nay', '${m['todayCount']}', const Color(0xFF3B82F6), () => _openMetricDetailsBottomSheet('today', 'Lịch đặt hẹn hôm nay')),
          const SizedBox(width: 10),
          _buildMetricItemCard('Chờ Check-in', '${m['pendingCheckInCount']}', const Color(0xFF10B981), () => _openMetricDetailsBottomSheet('checkin', 'Danh sách khách chờ Check-in')),
          const SizedBox(width: 10),
          _buildMetricItemCard('Chờ thanh toán', '${m['pendingPaymentCount']}', const Color(0xFFF59E0B), () => _openMetricDetailsBottomSheet('payment', 'Đơn đặt lịch chờ thanh toán bảo chứng')),
          const SizedBox(width: 10),
          _buildMetricItemCard('Đơn đã hủy', '${m['cancelledTotal']}', const Color(0xFFEF4444), () => _openMetricDetailsBottomSheet('cancelled', 'Lịch trình cuộc hẹn đã hủy')),
        ],
      ),
    );
  }

  Widget _buildMetricItemCard(String title, String value, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title, 
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black38),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Container(width: 12, height: 2.5, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              value, 
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color),
            ),
          ],
        ),
      ),
    );
  }

  // Thanh gạt chuyển đổi chế độ xem Dashboard tinh gọn khoảng cách biên triệt tiêu khoảng trống thừa
  Widget _buildPartnerViewModeToggler() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            _buildTogglerButton('Trục thời gian', 'timeline'),
            _buildTogglerButton('Biểu đồ Thống kê', 'analytics'),
          ],
        ),
      ),
    );
  }

  Widget _buildTogglerButton(String label, String modeKey) {
    final bool isActive = _partnerViewMode == modeKey;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _partnerViewMode = modeKey),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? Colors.black87 : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(color: isActive ? Colors.white : Colors.black45, fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // Khối dựng giao diện phân tích tài chính Analytics View sử dụng fl_chart native mượt mà
  Widget _buildPartnerAnalyticsView() {
    final m = _calculatePartnerMetrics();
    final List<String> labels = m['labels'] as List<String>;
    final List<double> chartValues = m['chartData'] as List<double>;
    final double weeklyRevValue = (m['weeklyRev'] ?? 0.0).toDouble();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI Thẻ lơ lửng Doanh thu tổng hợp 7 ngày qua
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF4C8D50), Color(0xFF80BF84)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: const Color(0xFF4C8D50).withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TỔNG DOANH THU (7 NGÀY QUA)', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(_formatPrice(weeklyRevValue), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final double aovValue = (m['aov'] ?? 0.0).toDouble();
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('AOV: ${_formatPrice(aovValue)}', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold)),
                        Text('Đã xong: ${m['totalCompleted']} đơn phục vụ', style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    );
                  }
                )
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 1. BIỂU ĐỒ CỘT NATIVE: Dòng tiền doanh thu 7 ngày qua
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, color: Color(0xFF4C8D50), size: 18),
                    SizedBox(width: 8),
                    Text('Biến động dòng tiền 7 ngày', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 180,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: chartValues.map((v) => v).fold(100000.0, (prev, element) => element > prev ? element : prev) * 1.15,
                      barTouchData: BarTouchData(enabled: true),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (double value, TitleMeta meta) {
                              int idx = value.toInt();
                              if (idx >= 0 && idx < labels.length) {
                                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(labels[idx], style: const TextStyle(color: Colors.black38, fontSize: 10, fontWeight: FontWeight.bold)));
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      barGroups: List.generate(chartValues.length, (index) {
                        return BarChartGroupData(
                          x: index,
                          barRods: [
                            BarChartRodData(
                              toY: chartValues[index],
                              color: const Color(0xFF80BF84),
                              width: 14,
                              borderRadius: BorderRadius.circular(4),
                            )
                          ],
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. BIỂU ĐỒ DONUT TRÒN: Tỉ lệ cơ cấu phễu trạng thái cuộc hẹn
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded, color: Color(0xFF3B82F6), size: 18),
                    SizedBox(width: 8),
                    Text('Cơ cấu tỉ lệ trạng thái đơn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    SizedBox(
                      width: 130,
                      height: 130,
                      child: PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 35,
                          sections: [
                            PieChartSectionData(value: (m['totalCompleted'] as int).toDouble(), color: const Color(0xFF10B981), radius: 18, showTitle: false),
                            PieChartSectionData(value: (m['pendingCheckInCount'] as int).toDouble(), color: const Color(0xFF3B82F6), radius: 18, showTitle: false),
                            PieChartSectionData(value: (m['pendingPaymentCount'] as int).toDouble(), color: const Color(0xFFF59E0B), radius: 18, showTitle: false),
                            PieChartSectionData(value: (m['cancelledTotal'] as int).toDouble(), color: const Color(0xFFEF4444), radius: 18, showTitle: false),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendRow('Đã phục vụ xong', '${m['totalCompleted']}', const Color(0xFF10B981)),
                          _buildLegendRow('Chờ khách đến', '${m['pendingCheckInCount']}', const Color(0xFF3B82F6)),
                          _buildLegendRow('Chờ thanh toán', '${m['pendingPaymentCount']}', const Color(0xFFF59E0B)),
                          _buildLegendRow('Lịch hẹn đã hủy', '${m['cancelledTotal']}', const Color(0xFFEF4444)),
                        ],
                      ),
                    )
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildLegendRow(String title, String count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(count, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildPremiumHeaderDock() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 10, 20, 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/');
                      }
                    },
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<int>(
                    offset: const Offset(0, 40),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    color: Colors.white,
                    elevation: 3,
                    onSelected: (int selectedMonth) {
                      final newDate = DateTime(_selectedDate.year, selectedMonth, 1);
                      _updateWeekDaysBasedOnDate(newDate);
                    },
                    itemBuilder: (BuildContext context) {
                      return List.generate(12, (index) {
                        final monthNumber = index + 1;
                        final dummyDate = DateTime(_selectedDate.year, monthNumber, 1);
                        final isCurrentMonth = monthNumber == _selectedDate.month;

                        return PopupMenuItem<int>(
                          value: monthNumber,
                          child: Text(
                            DateFormat('MMMM').format(dummyDate),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isCurrentMonth ? FontWeight.bold : FontWeight.normal,
                              color: isCurrentMonth ? const Color(0xFF80BF84) : Colors.black87,
                            ),
                          ),
                        );
                      });
                    },
                    child: Row(
                      children: [
                        Text(
                          DateFormat('MMMM').format(_selectedDate),
                          style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54, size: 22),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => _updateWeekDaysBasedOnDate(DateTime.now()),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF80BF84).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.3), width: 1),
                      ),
                      child: const Text(
                        'Today',
                        style: TextStyle(
                          color: Color(0xFF4C8D50),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListenableBuilder(
                    listenable: NotificationNotifier.instance,
                    builder: (context, child) {
                      final unread = NotificationNotifier.instance.unreadCount;
                      return IconButton(
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.notifications_none_rounded, color: Colors.black87, size: 22),
                            if (unread > 0)
                              Positioned(
                                right: -2,
                                top: -2,
                                child: Container(
                                  width: 9,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFE2C55),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onPressed: () => context.push('/notifications'),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      );
                    },
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFF4F7F6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? Image.network(
                              _avatarUrl!,
                              fit: BoxFit.cover,
                              cacheWidth: 120,
                              cacheHeight: 120,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(
                                  child: SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF80BF84)),
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) => Center(
                                child: Text(
                                  _customerFullName.isNotEmpty ? _customerFullName.substring(0, 1).toUpperCase() : 'U',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4C8D50)),
                                ),
                              ),
                            )
                          : Center(
                              child: Text(
                                _customerFullName.isNotEmpty ? _customerFullName.substring(0, 1).toUpperCase() : 'U',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF4C8D50)),
                              ),
                            ),
                    ),
                  ),
                ],
              )
            ],
          ),
          const SizedBox(height: 16),
          
          // Thanh tìm kiếm được đẩy xuống dưới
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            firstCurve: Curves.easeInOut,
            secondCurve: Curves.easeInOut,
            crossFadeState: _isSearching ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: GestureDetector(
              onTap: () => setState(() => _isSearching = true),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F7F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black.withOpacity(0.05)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded, color: Colors.black45, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _isMyClient ? 'Tìm tên khách hàng, dịch vụ...' : 'Tìm tên dịch vụ, cơ sở đặt lịch...',
                      style: const TextStyle(fontSize: 13, color: Colors.black38),
                    ),
                  ],
                ),
              ),
            ),
            secondChild: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF4F7F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.5)),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: _isMyClient ? 'Tìm tên khách hàng, dịch vụ...' : 'Tìm tên dịch vụ, cơ sở đặt lịch...',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                  prefixIcon: const Icon(Icons.search_rounded, color: const Color(0xFF80BF84), size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 11),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.clear_rounded, color: Colors.black45, size: 18),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _isSearching = false;
                      });
                    },
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7F6), 
              borderRadius: BorderRadius.circular(16)
            ),
            child: Row(
              children: [
                _buildCapsuleTab(_isMyClient ? 'Yêu cầu mới' : 'Đang chờ', 'waiting'),
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
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF80BF84) : Colors.transparent, // Đã chuyển sang màu xanh y tế chủ đạo (brand-primary)
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.black45,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMatrixWeekStrip() {
    final List<String> weekdays = ['W', 'T', 'F', 'S', 'S', 'M', 'T'];

    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Phát hiện cử chỉ kéo vuốt dọc: Vận tốc dương là kéo xuống (Expand), vận tốc âm là kéo lên (Collapse)
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! > 100) {
            setState(() => _isMonthView = true);
          } else if (details.primaryVelocity! < -100) {
            setState(() => _isMonthView = false);
          }
        }
      },
      onHorizontalDragEnd: (details) {
        // Phát hiện cử chỉ vuốt ngang: Vận tốc âm là vuốt từ phải sang trái (Next), vận tốc dương là vuốt từ trái sang phải (Prev)
        if (details.primaryVelocity != null) {
          if (details.primaryVelocity! < -120) {
            _handleHorizontalSwipeNavigation(true); // Tiến sang tuần/tháng tiếp theo
          } else if (details.primaryVelocity! > 120) {
            _handleHorizontalSwipeNavigation(false); // Lùi về tuần/tháng trước đó
          }
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.fastOutSlowIn,
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // Áp dụng AnimatedSwitcher kết hợp SlideTransition nâng cấp với Curve siêu mềm mịn để triệt tiêu độ khựng
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutQuart,
              switchOutCurve: Curves.easeInQuad,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0.0), // Trượt ngang nhẹ nhàng tinh tế phối hợp mượt mà
                    end: Offset.zero,
                  ).animate(animation),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeInOut,
                    ),
                    child: child,
                  ),
                );
              },
              child: !_isMonthView
                  ? // CHẾ ĐỘ XEM TUẦN (WEEK VIEW) ĐÃ TÍCH HỢP DẤU CHẤM ĐỎ THÔNG BÁO TIẾN TRÌNH LỊCH HẸN
                    Row(
                      key: ValueKey<String>('week_${_currentWeekDays.first.toIso8601String()}'),
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(7, (index) {
                        final day = _currentWeekDays[index];
                        final isFocused = day.day == _focusedDate.day && day.month == _focusedDate.month && day.year == _focusedDate.year;
                        final isToday = day.day == DateTime.now().day && day.month == DateTime.now().month && day.year == DateTime.now().year;
                        final showRedDot = _hasActiveNotificationDot(day);
                        
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _focusedDate = day;
                                if (day.month != _selectedDate.month || day.year != _selectedDate.year) {
                                  _selectedDate = DateTime(day.year, day.month, 1);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              color: Colors.transparent,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    weekdays[index], 
                                    style: TextStyle(
                                      color: isFocused ? Colors.black87 : Colors.black26, 
                                      fontSize: 11, 
                                      fontWeight: FontWeight.bold
                                    )
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: isFocused ? const Color(0xFF80BF84) : Colors.transparent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: isFocused ? Colors.white : (isToday ? const Color(0xFF80BF84) : Colors.black87),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // Container xếp chồng hiển thị dấu chấm trạng thái linh hoạt
                                  SizedBox(
                                    height: 4,
                                    child: isFocused
                                        ? Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle))
                                        : (showRedDot 
                                            ? Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle))
                                            : const SizedBox.shrink()),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    )
                  : // CHẾ ĐỘ XEM THÁNG TOÀN DIỆN (FULL MONTH GRID VIEW) TÍCH HỢP ĐỦ LUỒNG CHẤM ĐỎ VÀ SO KHỚP FOCUS
                    Column(
                      key: ValueKey<String>('month_${_selectedDate.year}_${_selectedDate.month}'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Hàng hiển thị nhãn ký tự thứ trong tuần của lưới tháng
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: weekdays.map((w) => Expanded(
                            child: Text(
                              w,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.black26, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final gridDays = _generateMonthGridDays(_selectedDate);
                            return GridView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 7,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 0,
                                childAspectRatio: 1.0,
                        ),
                              itemCount: gridDays.length,
                              itemBuilder: (context, idx) {
                                final day = gridDays[idx];
                                if (day == null) return const SizedBox.shrink();

                                final isFocused = day.day == _focusedDate.day && day.month == _focusedDate.month && day.year == _focusedDate.year;
                                final isToday = day.day == DateTime.now().day && day.month == DateTime.now().month && day.year == DateTime.now().year;
                                final showRedDot = _hasActiveNotificationDot(day);

                                return GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _focusedDate = day;
                                      final int weekdayOffset = day.weekday - 1;
                                      final DateTime startOfWeek = DateTime(day.year, day.month, day.day).subtract(Duration(days: weekdayOffset));
                                      _currentWeekDays = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));
                                    });
                                  },
                                  child: Container(
                                    color: Colors.transparent,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          width: 28,
                                          height: 28,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: isFocused ? const Color(0xFF80BF84) : Colors.transparent,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '${day.day}',
                                            style: TextStyle(
                                              color: isFocused ? Colors.white : (isToday ? const Color(0xFF80BF84) : Colors.black87),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        SizedBox(
                                          height: 4,
                                          child: isFocused
                                              ? Container(width: 4, height: 4, decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle))
                                              : (showRedDot 
                                                  ? Container(width: 4, height: 4, decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle))
                                                  : const SizedBox.shrink()),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            // Thanh Handle kéo dẹt tinh tế hỗ trợ người dùng nhận diện chỉ báo vuốt lên/xuống trực quan
            Center(
              child: Container(
                width: 36, 
                height: 4, 
                decoration: BoxDecoration(
                  color: Colors.black12, 
                  borderRadius: BorderRadius.circular(2)
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildAppointmentsTimeline() {
    final filteredList = _appointments.where((a) {
      final s = a.status.toUpperCase();
      
      // 1. Khớp tab phân cấp trạng thái
      bool matchesTab = false;
      if (_activeTab == 'waiting') matchesTab = (s == 'WAITING_PARTNER');
      if (_activeTab == 'payment') matchesTab = (s == 'PENDING_PAYMENT');
      if (_activeTab == 'upcoming') matchesTab = (s == 'CONFIRMED' || s == 'SERVED');
      if (_activeTab == 'history') matchesTab = (s == 'COMPLETED' || s == 'CANCELLED');

      // 2. Khớp bộ lọc chu kỳ lịch ngày được chọn từ Strip
      bool matchesDate = false;
      if (a.startTime != null && a.startTime!.isNotEmpty) {
        try {
          final parsedDate = DateTime.parse(a.startTime!);
          matchesDate = parsedDate.day == _focusedDate.day && 
                        parsedDate.month == _focusedDate.month && 
                        parsedDate.year == _focusedDate.year;
        } catch (_) {
          matchesDate = true; // Bẫy lọc an toàn nếu chuỗi format lỗi
        }
      } else {
        matchesDate = true; // Nếu chưa có thời gian bắt đầu thì hiển thị ở mọi ngày trong tab Đang chờ
      }

      final bool matchesTimeline = matchesTab && matchesDate;

      // 3. Khớp bộ lọc tìm kiếm cục bộ (Local Search) nếu có
      if (matchesTimeline && _searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final serviceName = (a.serviceInfo['service_name'] ?? '').toString().toLowerCase();
        final customerName = a.customerName.toLowerCase();
        return serviceName.contains(q) || customerName.contains(q);
      }
      return matchesTimeline;
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

    // Thống kê số lượng ngắn gọn ở đầu list đồng bộ giao diện mẫu [Sun 1 events and 2 tasks]
    final String focusedDayStr = DateFormat('EEE, dd MMM yyyy').format(_focusedDate);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_focusedDate.day} ${_focusedDate.day == DateTime.now().day ? "Today" : DateFormat('EEEE').format(_focusedDate)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${filteredList.length} lịch đặt hẹn y tế',
                    style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: const Text('Xem tất cả', style: TextStyle(color: Color(0xFF4C8D50), fontSize: 11, fontWeight: FontWeight.bold)), // Chuyển sang tone xanh đậm mượt mà
              )
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            // Đã đồng bộ toán học: 90px (thanh Nav) + 16px (Padding cơ sở) + Safe Area + 24px (Không gian thừa để nút không bị sát viền)
            padding: EdgeInsets.only(
              left: 16, 
              right: 16, 
              top: 2, 
              bottom: 130 + MediaQuery.paddingOf(context).bottom
            ), 
            physics: const BouncingScrollPhysics(),
            itemCount: filteredList.length,
            itemBuilder: (context, index) {
              final appt = filteredList[index];
              final themeColor = _getStatusThemeColor(appt.status);

              // Tách chuỗi thời gian AM/PM đẹp mắt
              String timeStartStr = "Chờ xếp";
              String timeEndStr = "lịch";
              if (appt.startTime != null && appt.startTime!.isNotEmpty) {
                try {
                  final parsedStart = DateTime.parse(appt.startTime!);
                  timeStartStr = DateFormat('hh:mm a').format(parsedStart);
                  if (appt.endTime != null && appt.endTime!.isNotEmpty) {
                    timeEndStr = DateFormat('hh:mm a').format(DateTime.parse(appt.endTime!));
                  }
                } catch (_) {}
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 12, offset: const Offset(0, 4))
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dải màu indicator mượt mà bên lề trái thay thế viền thô cũ
                      Container(width: 5, height: 110, color: themeColor),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      appt.serviceInfo['service_name'] ?? 'Trị liệu chuyên sâu',
                                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.more_vert_rounded, color: Colors.black38, size: 18),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(color: themeColor, shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$timeStartStr - $timeEndStr',
                                    style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(Icons.person_outline_rounded, color: Colors.black26, size: 14),
                                  const SizedBox(width: 6),
                                  Text(
                                    _isMyClient ? 'Khách: ${appt.customerName}' : 'Cơ sở: ${appt.partnerInfo['full_name'] ?? "VN Share"}',
                                    style: const TextStyle(color: Colors.black45, fontSize: 12),
                                  ),
                                ],
                              ),
                              
                              // Khu vực bóc tách hóa đơn voucher đồng bộ logic Web áp dụng mô hình toán học bọc thép
                              const SizedBox(height: 6),
                              Builder(
                                builder: (context) {
                                  final double totalAmount = appt.totalAmount;
                                  final double originalPrice = (appt.serviceInfo['price'] ?? appt.totalAmount ?? 0).toDouble();
                                  final Map<String, dynamic> v = appt.voucherInfo;
                                  
                                  double calculatedDiscount = 0.0;
                                  if (v.isNotEmpty && v['discount_value'] != null) {
                                    final double discountValue = (v['discount_value'] ?? 0).toDouble();
                                    if (v['discount_type'] == 'PERCENTAGE') {
                                      calculatedDiscount = (originalPrice * discountValue) / 100.0;
                                      if (v['max_discount_amount'] != null) {
                                        final double maxDiscount = (v['max_discount_amount'] ?? 0).toDouble();
                                        if (calculatedDiscount > maxDiscount) {
                                          calculatedDiscount = maxDiscount;
                                        }
                                      }
                                    } else {
                                      calculatedDiscount = discountValue;
                                    }
                                  }

                                  final bool hasActiveVoucher = calculatedDiscount > 0;
                                  
                                  // Tính toán giá trị thực trả cuối cùng
                                  double finalPrice = originalPrice - calculatedDiscount;
                                  if (finalPrice < 0) finalPrice = 0;

                                  return Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(Icons.credit_card_rounded, color: Colors.black26, size: 14),
                                          const SizedBox(width: 6),
                                          Text(
                                            _formatPrice(finalPrice), // Đã sửa: In đậm số tiền khách thực trả
                                            style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12),
                                          ),
                                          if (hasActiveVoucher) ...[
                                            const SizedBox(width: 6),
                                            Text(
                                              _formatPrice(originalPrice), // Đã sửa: Gạch ngang số tiền gốc
                                              style: const TextStyle(color: Colors.black26, fontSize: 11, decoration: TextDecoration.lineThrough),
                                            ),
                                          ]
                                        ],
                                      ),
                                      if (v.isNotEmpty && v['code'] != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                                          child: Text(v['code'].toString(), style: const TextStyle(color: Color(0xFF3B82F6), fontSize: 9, fontWeight: FontWeight.bold)), // Tag Voucher xanh lam bảo chứng khớp với Web
                                        )
                                    ],
                                  );
                                }
                              ),

                              // Tuyến hành động bo tròn (Action Buttons Pill)
                              if (appt.status.toUpperCase() == 'WAITING_PARTNER' && !_isMyClient) ...[
                                const SizedBox(height: 12),
                                _buildActionWidgetButton('Hủy yêu cầu đặt lịch', Colors.red.shade50, Colors.red, () => _handleCancel(appt.id)),
                              ],
                              
                              // ĐỒNG BỘ LOGIC WEB: Nút hành động dành riêng cho Đối tác
                              if (appt.status.toUpperCase() == 'WAITING_PARTNER' && _isMyClient) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _buildActionWidgetButton('Từ chối', Colors.red.shade50, Colors.red, () => _handlePartnerReject(appt.id))),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildActionWidgetButton('Duyệt & Chọn giờ', const Color(0xFFEAF8EE), const Color(0xFF22C55E), () => _handlePartnerAccept(appt.id, appt.startTime))),
                                  ],
                                ),
                              ],

                              if (appt.status.toUpperCase() == 'PENDING_PAYMENT' && !_isMyClient) ...[
                                const SizedBox(height: 12),
                                _buildActionWidgetButton('Xem hóa đơn & Thanh toán', const Color(0xFF3B82F6).withOpacity(0.08), const Color(0xFF3B82F6), () => _handlePayment(appt.id)), // Đổi sang tone xanh lam an toàn bảo chứng Escrow
                              ],
                              if (appt.status.toUpperCase() == 'CONFIRMED' && _isMyClient) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 34,
                                        child: TextField(
                                          controller: _checkInControllers.putIfAbsent(appt.id, () => TextEditingController()),
                                          keyboardType: TextInputType.number,
                                          maxLength: 6,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 2),
                                          decoration: InputDecoration(
                                            hintText: 'MÃ 6 SỐ KHÁCH ĐƯA',
                                            counterText: '',
                                            hintStyle: const TextStyle(fontSize: 10, letterSpacing: 0, color: Colors.black26, fontWeight: FontWeight.normal),
                                            contentPadding: const EdgeInsets.symmetric(vertical: 6),
                                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF80BF84), // Chuyển nút xác nhận của đối tác sang màu xanh y tế chủ đạo của app
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        minimumSize: const Size(90, 34),
                                        padding: EdgeInsets.zero,
                                      ),
                                      onPressed: () => _handlePartnerCheckIn(appt.id),
                                      child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              ],
                              if (appt.status.toUpperCase() == 'CONFIRMED' && appt.checkInCode != null && !_isMyClient) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(color: const Color(0xFF4C8D50).withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
                                  child: Center(
                                    child: Text('MÃ XÁC NHẬN TẠI QUẦY: ${appt.checkInCode}', style: const TextStyle(color: Color(0xFF4C8D50), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                                  ),
                                )
                              ],
                              if (appt.status.toUpperCase() == 'SERVED' && !_isMyClient) ...[
                                const SizedBox(height: 12),
                                _buildActionWidgetButton('Xác nhận hài lòng & Giải ngân', const Color(0xFF4C8D50).withOpacity(0.08), const Color(0xFF4C8D50), () => _handleUserConfirm(appt.id)),
                              ],
                              
                              // Thêm 2 nút tương tác nhanh Gọi điện / Nhắn tin tiện dụng như bản Web
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF4F7F6)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  GestureDetector(
                                    onTap: () => AppToast.show(context: context, message: 'Tính năng chat đang được đồng bộ.', isSuccess: true),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.message_outlined, size: 14, color: Colors.black38),
                                        SizedBox(width: 6),
                                        Text('Nhắn tin', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () async {
                                      final phone = _isMyClient ? appt.customerPhone : (appt.partnerInfo['phone'] ?? "0901234567");
                                      final url = 'tel:$phone';
                                      if (await canLaunchUrl(Uri.parse(url))) {
                                        await launchUrl(Uri.parse(url));
                                      }
                                    },
                                    child: const Row(
                                      children: [
                                        Icon(Icons.phone_enabled_outlined, size: 14, color: Colors.black38),
                                        SizedBox(width: 6),
                                        Text('Gọi điện', style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildActionWidgetButton(String label, Color bgColor, Color textColor, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
        ),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.1)),
      ),
    );
  }

  Widget _buildRequireLogin() {
    return Scaffold(
      backgroundColor: Colors.white, // Ép cứng nền trắng sáng đồng bộ hệ thống
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E3A), // Đổi sang màu cam hồng chủ đạo của thiết kế mới
            foregroundColor: Colors.white, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          onPressed: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AuthBottomSheet(onSuccess: () async { await AuthNotifier.instance.refresh(); _loadData(); })),
          child: const Text('Đăng nhập để xem Lịch hẹn', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  Future<void> _handleCancel(String id) async {
    // 🚀 Tìm thực thể lịch hẹn cục bộ để kiểm tra trạng thái và thông tin khóa Voucher
    final appt = _appointments.firstWhere((a) => a.id == id, orElse: () => _appointments.first);
    final bool isPendingPayment = appt.status.toUpperCase() == 'PENDING_PAYMENT';
    final bool hasVoucher = appt.voucherInfo.isNotEmpty && appt.voucherInfo['code'] != null;

    // Hiển thị Custom Dialog bẫy cảnh báo mất quyền lợi Voucher đồng bộ 1:1 với bản Website
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
              SizedBox(width: 8),
              Text('Hủy yêu cầu đặt lịch?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isPendingPayment
                    ? 'Cơ sở đã xác nhận lịch hẹn của bạn. Nếu hủy lúc này, Voucher đã áp dụng sẽ bị HỦY BỎ và không thể hoàn lại theo chính sách sàn. Bạn chắc chắn chứ?'
                    : 'Thao tác này không thể hoàn tác. Yêu cầu đặt hẹn của bạn sẽ bị hủy và mã ưu đãi (nếu có) sẽ được hoàn trả lại vào ví voucher.',
                style: const TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
              ),
              if (hasVoucher && isPendingPayment) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.shade100),
                  ),
                  child: Text(
                    '⚠️ Thất thoát mã ưu đãi: [${appt.voucherInfo['code']}] sẽ bị vô hiệu hóa.',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                )
              ]
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Không, Giữ lại', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                Navigator.pop(dialogContext); // Đóng Dialog bằng context riêng
                final success = await CalendarApiService.cancelAppointment(id);
                if (success) {
                  if (mounted) {
                    AppToast.show(
                      context: context, // An toàn: Trỏ về context gốc của màn hình đang hiển thị
                      message: isPendingPayment 
                          ? '🎉 Đã hủy lịch hẹn! Voucher đã áp dụng bị hủy bỏ theo chính sách.' 
                          : '🎉 Đã hủy yêu cầu thành công! Voucher đã được trả lại ví.', 
                      isSuccess: true
                    );
                  }
                  _loadData(); // Lệnh F5 ngầm sẽ được chạy mượt mà
                } else {
                  if (mounted) AppToast.show(context: context, message: '❌ Hủy lịch hẹn thất bại. Vui lòng thử lại!', isSuccess: false);
                }
              },
              child: const Text('Vâng, Hủy lịch', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
  // ĐỒNG BỘ LOGIC WEB: Đối tác duyệt lịch phải thiết lập khung giờ thực tế
  Future<void> _handlePartnerAccept(String id, String? startTimeString) async {
    final TimeOfDay? startTime = await showTimePicker(
      context: context, 
      initialTime: const TimeOfDay(hour: 9, minute: 0),
      helpText: 'CHỌN GIỜ BẮT ĐẦU PHỤC VỤ',
    );
    if (startTime == null || !mounted) return;

    final TimeOfDay? endTime = await showTimePicker(
      context: context, 
      initialTime: TimeOfDay(hour: startTime.hour + 1, minute: startTime.minute),
      helpText: 'CHỌN GIỜ KẾT THÚC DỰ KIẾN',
    );
    if (endTime == null || !mounted) return;

    // Chuẩn hóa ISO 8601 bằng cách bóc tách chuỗi ngày thực tế từ startTime
    String baseDate = DateTime.now().toIso8601String().split('T')[0];
    if (startTimeString != null && startTimeString.isNotEmpty) {
      if (startTimeString.contains('T')) {
        baseDate = startTimeString.split('T')[0];
      } else {
        baseDate = startTimeString;
      }
    }
    
    final DateTime parsed = DateTime.parse(baseDate);
    final String startIso = DateTime(parsed.year, parsed.month, parsed.day, startTime.hour, startTime.minute).toIso8601String();
    final String endIso = DateTime(parsed.year, parsed.month, parsed.day, endTime.hour, endTime.minute).toIso8601String();

    try {
      await ApiClient.instance.patch('/appointments/$id/respond', data: {
        'action': 'ACCEPT',
        'start_time': startIso,
        'end_time': endIso,
      });
      if (mounted) AppToast.show(context: context, message: '🎉 Đã duyệt lịch hẹn và chốt giờ thành công!', isSuccess: true);
      _loadData();
    } catch (e) {
      if (mounted) AppToast.show(context: context, message: '❌ Lỗi khi duyệt lịch.', isSuccess: false);
    }
  }

  // ĐỒNG BỘ LOGIC WEB: Đối tác từ chối bắt buộc phải có lý do minh bạch
  Future<void> _handlePartnerReject(String id) async {
    final TextEditingController reasonCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Từ chối yêu cầu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            hintText: 'Nhập lý do từ chối (bắt buộc)...',
            hintStyle: TextStyle(fontSize: 13),
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (reasonCtrl.text.trim().isEmpty) {
                AppToast.show(context: context, message: 'Vui lòng nhập lý do!', isSuccess: false);
                return;
              }
              Navigator.pop(dialogContext); // Đóng Dialog an toàn
              try {
                await ApiClient.instance.patch('/appointments/$id/respond', data: {
                  'action': 'REJECT',
                  'reason': reasonCtrl.text.trim(),
                });
                if (mounted) AppToast.show(context: context, message: 'Đã từ chối lịch hẹn.', isSuccess: true);
                _loadData();
              } catch (e) {
                if (mounted) AppToast.show(context: context, message: '❌ Lỗi khi từ chối.', isSuccess: false);
              }
            },
            child: const Text('Từ chối', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _handlePayment(String id) async {
    // 🚀 ĐỒNG BỘ HOÀN HẢO LOGIC WEB: Gọi API Preview hóa đơn minh bạch trước khi chuyển hướng cổng thanh toán
    final preview = await CalendarApiService.fetchPaymentPreview(id);
    if (preview == null) {
      AppToast.show(context: context, message: '❌ Không thể khởi tạo chi tiết hóa đơn.', isSuccess: false);
      return;
    }

    if (!mounted) return;
    
    // Đã chuyển đổi sang Dialog lơ lửng giữa màn hình để triệt tiêu hoàn toàn lỗi che khuất bởi Bottom Navigation nổi
    showDialog(
      context: context,
      builder: (dialogContext) {
        final orig = (preview['original_amount'] ?? 0).toDouble();
        final disc = (preview['discount_amount'] ?? 0).toDouble();
        final finalPrice = (preview['final_amount'] ?? 0).toDouble();
        final code = preview['applied_voucher_code'] ?? 'Không áp dụng';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Xác Nhận Hóa Đơn Đặt Lịch', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.black45),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [const Text('Giá dịch vụ niêm yết:'), Text(_formatPrice(orig))],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Voucher ưu đãi giảm:'), 
                    Text('- ${_formatPrice(disc)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                  ],
                ),
                Text('Mã tự động áp dụng: $code', style: const TextStyle(fontSize: 10, color: Colors.black38, fontStyle: FontStyle.italic)),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tổng thanh toán ký gửi:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(_formatPrice(finalPrice), style: const TextStyle(color: Color(0xFF4C8D50), fontSize: 18, fontWeight: FontWeight.w900))
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A1E),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                    Navigator.pop(dialogContext); // Đóng hóa đơn tạm tính
                    
                    BuildContext? loadContext;
                    
                    // 1. Hiển thị Overlay Loading chờ khởi tạo PayOS
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (loadCtx) {
                        loadContext = loadCtx; // Khóa định danh chính xác context của Dialog Loading
                        return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
                      },
                    );
                    
                    try {
                      // 2. Gọi trực tiếp API tạo thanh toán
                      final res = await ApiClient.instance.post('/appointments/$id/pay');
                      
                      // Giải phóng màn hình chờ bằng đúng định danh cô lập
                      if (loadContext != null && Navigator.canPop(loadContext!)) {
                        Navigator.pop(loadContext!);
                      }
                      
                      if (res.statusCode == 200 && res.data != null) {
                        // Bọc lót ép kiểu dữ liệu an toàn để tránh lỗi Type Cast Exception hệ thống
                        final Map<String, dynamic> responseData = res.data is Map ? res.data : {};
                        
                        if (responseData['status'] == 'success') {
                          final inAppData = responseData['in_app_data'];
                          
                          if (inAppData != null && inAppData['qr_code'] != null) {
                            // 3. THÀNH CÔNG: Hiển thị In-App QR Box lơ lửng
                            if (!mounted) return;
                            _showQrPaymentDialog(id, inAppData);
                          } else if (responseData['checkout_url'] != null) {
                            // 4. FALLBACK AN TOÀN: Mở Browser nếu thiếu dữ liệu QR
                            launchUrl(Uri.parse(responseData['checkout_url']), mode: LaunchMode.externalApplication);
                          }
                        } else {
                          if (mounted) AppToast.show(context: context, message: '❌ Lỗi khởi tạo thanh toán', isSuccess: false);
                        }
                      } else {
                        if (mounted) AppToast.show(context: context, message: '❌ Lỗi từ máy chủ thanh toán', isSuccess: false);
                      }
                    } catch (e) {
                      // Bẫy lỗi giải phóng an toàn khi xảy ra sự cố sập mạng hoặc timeout
                      if (loadContext != null && Navigator.canPop(loadContext!)) {
                        Navigator.pop(loadContext!);
                      }
                      if (mounted) AppToast.show(context: context, message: '❌ Lỗi kết nối hệ thống PayOS', isSuccess: false);
                    }
                  },
                    child: const Text('XÁC NHẬN CHUYỂN KHOẢN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  void _showQrPaymentDialog(String appointmentId, Map<String, dynamic> inAppData) {
    bool isChecking = false;
    Timer? pollingTimer;
    
    // Tìm thông tin đối tác ứng với lịch hẹn để lấy avatar/tên bồi đắp cho Premium Header
    final currentAppt = _appointments.firstWhere((a) => a.id == appointmentId, orElse: () => _appointments.first);
    final String partnerName = currentAppt.partnerInfo['full_name'] ?? 'VN Share';
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (qrContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            
            // 🚀 BỌC THÉP LIFECYCLE: Khởi tạo Polling chạy ngầm mỗi 3 giây để bắt lệnh Webhook tự động ngay trong app (Zero-touch verification)
            pollingTimer ??= Timer.periodic(const Duration(seconds: 3), (timer) async {
              if (!mounted || isChecking) return;
              try {
                final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
                if (res.statusCode == 200 && res.data['status'] == 'success') {
                  timer.cancel(); // Hủy lặp ngay lập tức khi phát hiện tiền vào
                  if (Navigator.canPop(qrContext)) Navigator.pop(qrContext);
                  if (mounted) AppToast.show(context: context, message: '🎉 Thanh toán hoàn tất bảo chứng tự động!', isSuccess: true);
                  _loadData();
                }
              } catch (_) {}
            });

            return WillPopScope(
              onWillPop: () async {
                pollingTimer?.cancel();
                return true;
              },
              child: Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              backgroundColor: Colors.white,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- SECTION 1: PREMIUM PAYMENT HEADER & CLOSE DOCK ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF3B82F6), // Màu xanh bảo chứng Escrow chuẩn Apple Pay
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'BẢO CHỨNG THANH TOÁN',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black38,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 22, color: Colors.black38),
                              onPressed: () {
                                pollingTimer?.cancel();
                                Navigator.pop(qrContext);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Column(
                            children: [
                              Text(
                                partnerName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87, letterSpacing: -0.3),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Cổng ký gửi an toàn thực hiện qua PayOS',
                                style: TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        
                        // --- SECTION 3: DYNAMIC VIETQR CARD (LIQUID GLASS STYLE) ---
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFF4F7F6), width: 1.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                )
                              ],
                            ),
                            child: Image.network(
                              'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(inAppData['qr_code'] ?? '')}',
                              width: 190,
                              height: 190,
                              fit: BoxFit.contain,
                              loadingBuilder: (ctx, child, progress) => progress == null 
                                  ? child 
                                  : const SizedBox(width: 190, height: 190, child: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)))),
                              errorBuilder: (ctx, err, stack) => const SizedBox(
                                width: 190, 
                                height: 190, 
                                child: Center(child: Icon(Icons.qr_code_scanner_rounded, size: 48, color: Colors.black12))
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // --- SECTION 3.2: CLICK-TO-COPY ACCOUNT DETAILS PILL ---
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7F6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Column(
                            children: [
                              _buildCopyableRow('Tài khoản ký gửi PayOS', inAppData['account_number']?.toString() ?? '', isMono: true),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(height: 1, color: Colors.black12),
                              ),
                              _buildCopyableRow('Số tiền chuyển khoản', _formatPrice((inAppData['amount'] ?? 0).toDouble()), customValueColor: const Color(0xFF4C8D50)),
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Divider(height: 1, color: Colors.black12),
                              ),
                              _buildCopyableRow('Nội dung bắt buộc', inAppData['description']?.toString() ?? '', customValueColor: const Color(0xFF3B82F6)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // --- SECTION 4 & 5: STATUS INDICATOR & COUNTDOWN TIMELINE ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFFF59E0B)),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Đang chờ giao dịch...',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade700),
                                ),
                              ],
                            ),
                            const Row(
                              children: [
                                Icon(Icons.access_time_rounded, size: 14, color: Colors.black26),
                                const SizedBox(width: 4),
                                Text(
                                  '14:52',
                                  style: TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        
                        // --- SECTION 5.2: TRUST ACTION BUTTON ---
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981), // Thiết kế Mint Green cao cấp chuẩn Apple Hub
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: isChecking ? null : () async {
                              setState(() => isChecking = true);
                              try {
                                final res = await ApiClient.instance.get('/appointments/payment/verify?orderCode=${inAppData['order_code']}');
                                if (res.statusCode == 200 && res.data['status'] == 'success') {
                                  pollingTimer?.cancel();
                                  Navigator.pop(qrContext); // Giải phóng hộp thoại QR an toàn
                                  if (mounted) AppToast.show(context: context, message: '🎉 Thanh toán hoàn tất bảo chứng!', isSuccess: true);
                                  _loadData(); // Tải mới danh sách thời gian thực
                                } else {
                                  if (mounted) AppToast.show(context: context, message: '⏳ Chưa ghi nhận dòng tiền đến PayOS. Giao dịch đang được quét ngầm!', isSuccess: false);
                                  setState(() => isChecking = false);
                                }
                              } catch (e) {
                                if (mounted) AppToast.show(context: context, message: '❌ Lỗi đường truyền xác thực.', isSuccess: false);
                                setState(() => isChecking = false);
                              }
                            },
                            child: isChecking 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('TÔI ĐÃ CHUYỂN KHOẢN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // --- SECTION 6: SECURITY TRUST INDICATORS ---
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_outlined, size: 12, color: Colors.black26),
                            SizedBox(width: 4),
                            Text(
                              'Giao dịch mã hóa SSL bọc thép bảo vệ quyền lợi 100%',
                              style: TextStyle(fontSize: 10, color: Colors.black26, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),);
          },
        );
      },
    );
  }

  // Hàm bổ trợ dựng dòng thông tin copyable cao cấp tinh sảo
  Widget _buildCopyableRow(String title, String value, {bool isMono = false, Color? customValueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start, // Giúp căn lề trên khi text xuống dòng
      children: [
        Text(title, style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500)),
        const SizedBox(width: 12), // Tạo khoảng cách để tránh text dính vào title
        Expanded(
          child: GestureDetector(
            onTap: () {
              ServicesBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
                'flutter/platform',
                const JSONMessageCodec().encodeMessage({
                  'method': 'Clipboard.setData',
                  'args': {'text': value}
                }),
                null,
              );
              AppToast.show(context: context, message: '🎉 Đã sao chép: $value', isSuccess: true);
            },
            child: Container(
              color: Colors.transparent,
              alignment: Alignment.centerRight, // Căn lề phải cho giá trị
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: customValueColor ?? Colors.black87,
                        fontFamily: isMono ? 'monospace' : null,
                        fontFeatures: isMono ? const [FontFeature.tabularFigures()] : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy_rounded, size: 12, color: Colors.black26),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _handlePartnerCheckIn(String id) async {
    final code = _checkInControllers[id]?.text ?? '';
    if (code.length != 6) {
      AppToast.show(context: context, message: '⚠️ Vui lòng nhập đúng mã 6 số của khách hàng', isSuccess: false);
      return;
    }

    final res = await CalendarApiService.partnerCheckIn(id, code);
    if (res != null) {
      if(mounted) AppToast.show(context: context, message: '🎉 Check-in hoàn tất! Trạng thái đã chuyển sang SERVED.', isSuccess: true);
      _checkInControllers[id]?.clear();
      _loadData();
    } else {
      if(mounted) AppToast.show(context: context, message: '❌ Mã xác thực không chính xác hoặc đã hết hạn.', isSuccess: false);
    }
  }

  // ĐỒNG BỘ LOGIC WEB: Khách hàng xác nhận giải ngân kèm đánh giá chất lượng
  Future<void> _handleUserConfirm(String id) async {
    bool isSatisfied = true;
    final TextEditingController feedbackCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (statefulContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Xác nhận & Đánh giá', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bạn có hài lòng với chất lượng dịch vụ y tế vừa nhận không?', style: TextStyle(fontSize: 13), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ChoiceChip(
                        label: const Text('Hài lòng 💖'),
                        selected: isSatisfied,
                        onSelected: (val) => setDialogState(() => isSatisfied = true),
                        selectedColor: const Color(0xFF80BF84).withOpacity(0.3),
                      ),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Chưa tốt 💔'),
                        selected: !isSatisfied,
                        onSelected: (val) => setDialogState(() => isSatisfied = false),
                        selectedColor: Colors.red.withOpacity(0.2),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: feedbackCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Để lại góp ý cho Cơ sở (không bắt buộc)...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C8D50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    Navigator.pop(dialogContext); // Đóng Dialog an toàn
                    // 🚀 BỌC THÉP ENDPOINT 404/405: Đồng bộ hóa lệnh giải ngân thông qua Service đã được bảo chứng thay vì tự gọi thủ công sai URL
                    final bool isSuccess = await CalendarApiService.confirmCompletion(id);
                    if (isSuccess) {
                      if (mounted) AppToast.show(context: context, message: '🎉 Cảm ơn bạn! Đã ký xác nhận và giải ngân tiền cho Cơ sở.', isSuccess: true);
                      _loadData();
                    } else {
                      if (mounted) AppToast.show(context: context, message: '❌ Lỗi hệ thống, chưa thể xác nhận.', isSuccess: false);
                    }
                  },
                  child: const Text('Gửi xác nhận', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // Gỡ lắng nghe
    _searchController.dispose();
    for (var controller in _checkInControllers.values) {
      controller.dispose();
    }
    _checkInControllers.clear(); // 🚀 BỌC THÉP RAM: Hủy hoàn toàn các tham chiếu con trỏ Controller ra khỏi bộ nhớ Heap
    super.dispose();
  }
}