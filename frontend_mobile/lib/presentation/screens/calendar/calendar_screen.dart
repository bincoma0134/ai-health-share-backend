import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../data/models/appointment_model.dart';
import '../../../data/services/calendar_api_service.dart';
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
  
  // Phân quyền
  String _userRole = 'USER';
  bool get isMyClient => _userRole == 'PARTNER_ADMIN';

  // State cho USER
  String _activeTab = 'upcoming'; // waiting, payment, upcoming, history

  // State cho PARTNER
  String _partnerViewMode = 'timeline'; // timeline, analytics
  Map<String, String> _checkInCodes = {};

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
    setState(() => _isLoading = true);
    
    // Tải song song Profile (để lấy Role) và Lịch hẹn
    final results = await Future.wait([
      CalendarApiService.fetchUserProfile(),
      CalendarApiService.fetchAppointments(),
    ]);

    final profile = results[0] as Map<String, dynamic>?;
    final data = results[1] as List<AppointmentModel>;

    setState(() {
      if (profile != null) _userRole = profile['role'] ?? 'USER';
      _appointments = data;
      _isLoading = false;
    });
  }

  // --- HÀM RÚT GỌN ĐỊNH DẠNG ---
  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(price);
  }

  // ==========================================
  // XÂY DỰNG GIAO DIỆN CHÍNH
  // ==========================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Lịch hẹn của tôi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        actions: [
          if (isMyClient) 
            IconButton(icon: const Icon(Icons.analytics, color: Color(0xFF80BF84)), onPressed: () => setState(() => _partnerViewMode = _partnerViewMode == 'timeline' ? 'analytics' : 'timeline')),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (!_isAuthenticated) return _buildRequireLogin();
    if (_isLoading) return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
    
    return isMyClient ? _buildPartnerDashboard() : _buildUserView();
  }

  // ==========================================
  // 1. GIAO DIỆN USER (Tab Ngang)
  // ==========================================
  Widget _buildUserView() {
    final filteredList = _appointments.where((a) {
      final s = a.status;
      if (_activeTab == 'waiting') return s == 'WAITING_PARTNER';
      if (_activeTab == 'payment') return s == 'PENDING_PAYMENT';
      if (_activeTab == 'upcoming') return s == 'CONFIRMED' || s == 'SERVED';
      if (_activeTab == 'history') return s == 'COMPLETED' || s == 'CANCELLED';
      return false;
    }).toList();

    return Column(
      children: [
        // Thanh Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _buildTabBtn('Đang chờ', 'waiting'),
              _buildTabBtn('Thanh toán', 'payment'),
              _buildTabBtn('Sắp tới', 'upcoming'),
              _buildTabBtn('Lịch sử', 'history'),
            ],
          ),
        ),
        
        // Danh sách Lịch
        Expanded(
          child: filteredList.isEmpty 
            ? const Center(child: Text('Không có lịch hẹn nào ở mục này.', style: TextStyle(color: Colors.white54)))
            : ListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 16, bottom: 120),
                itemCount: filteredList.length,
                itemBuilder: (context, index) {
                  final appt = filteredList[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF121214), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white.withOpacity(0.05))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(appt.status.replaceFirst('_', ' '), style: const TextStyle(color: Color(0xFF80BF84), fontSize: 10, fontWeight: FontWeight.bold)),
                            Text(_formatPrice(appt.totalAmount), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(appt.serviceInfo['service_name'] ?? 'Liệu trình tùy chỉnh', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        
                        // Action Buttons based on Status
                        if (appt.status == 'WAITING_PARTNER')
                          _buildActionBtn('Hủy yêu cầu', Colors.redAccent, () => _handleCancel(appt.id)),
                        if (appt.status == 'PENDING_PAYMENT')
                          _buildActionBtn('Thanh toán qua PayOS', Colors.blueAccent, () => _handlePayment(appt.id)),
                        if (appt.status == 'CONFIRMED' && appt.checkInCode != null)
                          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF80BF84).withOpacity(0.1), borderRadius: BorderRadius.circular(12)), child: Center(child: Text('MÃ CHECK-IN: ${appt.checkInCode}', style: const TextStyle(color: Color(0xFF80BF84), fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 2)))),
                        if (appt.status == 'SERVED')
                          _buildActionBtn('Xác nhận hoàn thành', const Color(0xFF80BF84), () => _handleUserConfirm(appt.id), isDarkText: true),
                      ],
                    ),
                  );
                },
              ),
        )
      ],
    );
  }

  Widget _buildTabBtn(String label, String tabKey) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(color: isActive ? Colors.white : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: isActive ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }

  // ==========================================
  // 2. GIAO DIỆN PARTNER (Lưới lịch & Thống kê)
  // ==========================================
  Widget _buildPartnerDashboard() {
    if (_partnerViewMode == 'analytics') {
      return _buildAnalyticsView();
    }

    // Lưới Timeline Google Calendar Style
    final hours = List.generate(16, (i) => i + 6); // 6 AM - 9 PM
    
    return Column(
      children: [
        // Header 4 Metrics nhỏ
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildMiniMetric('Hôm nay', _appointments.where((a) => a.startTime != null && DateTime.parse(a.startTime!).day == DateTime.now().day).length.toString(), Colors.white),
              _buildMiniMetric('Chờ Check-in', _appointments.where((a) => a.status == 'CONFIRMED').length.toString(), Colors.greenAccent),
              _buildMiniMetric('Chờ thanh toán', _appointments.where((a) => a.status == 'PENDING_PAYMENT').length.toString(), Colors.blueAccent),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // Lưới trục thời gian
        Expanded(
          child: Container(
            color: const Color(0xFF0a0a0c),
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cột giờ
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: hours.map((h) => Container(
                        height: 80, 
                        alignment: Alignment.topCenter, 
                        child: Text('${h}h', style: const TextStyle(color: Colors.white54, fontSize: 12))
                      )).toList(),
                    ),
                  ),
                  
                  // Lưới sự kiện (Chỉ mô phỏng 1 ngày hiện tại trên Mobile để dễ nhìn)
                  Expanded(
                    child: Stack(
                      children: [
                        // Kẻ ngang
                        Column(
                          children: hours.map((h) => Container(
                            height: 80,
                            decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05)))),
                          )).toList(),
                        ),
                        
                        // Thẻ sự kiện hôm nay
                        ..._appointments.where((a) => a.startTime != null && ['CONFIRMED', 'SERVED', 'COMPLETED'].contains(a.status)).map((appt) {
                          final start = DateTime.parse(appt.startTime!);
                          final end = appt.endTime != null ? DateTime.parse(appt.endTime!) : start.add(const Duration(hours: 1));
                          
                          // Thuật toán tọa độ
                          final topOffset = ((start.hour - 6) * 80) + ((start.minute / 60) * 80);
                          final height = ((end.difference(start).inMinutes) / 60) * 80;
                          
                          if (start.day != DateTime.now().day) return const SizedBox(); // Chỉ vẽ hôm nay

                          return Positioned(
                            top: topOffset.toDouble(),
                            left: 10,
                            right: 10,
                            height: height.toDouble() < 40 ? 40 : height.toDouble(),
                            child: GestureDetector(
                              onTap: () => _showPartnerApptDetails(appt),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: appt.status == 'CONFIRMED' ? Colors.greenAccent.shade700 : Colors.blueGrey.shade800,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black, width: 2)
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(appt.customerName, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 1),
                                    Text(appt.serviceInfo['service_name'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 10), maxLines: 1),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Giao diện Biểu đồ Doanh thu Partner
  Widget _buildAnalyticsView() {
    double totalRev = 0;
    for (var a in _appointments) {
      if (a.status == 'COMPLETED' || a.status == 'SERVED') totalRev += a.totalAmount;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF2e7d32)]), borderRadius: BorderRadius.circular(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TỔNG DOANH THU ĐÃ PHỤC VỤ', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 2)),
                const SizedBox(height: 8),
                Text(_formatPrice(totalRev), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('Trạng thái lịch hẹn', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 40,
                sections: [
                  PieChartSectionData(value: _appointments.where((a) => a.status == 'COMPLETED').length.toDouble(), color: const Color(0xFF80BF84), title: 'Xong', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(value: _appointments.where((a) => a.status == 'CONFIRMED').length.toDouble(), color: Colors.blueAccent, title: 'Chờ đến', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                  PieChartSectionData(value: _appointments.where((a) => a.status == 'CANCELLED').length.toDouble(), color: Colors.redAccent, title: 'Đã hủy', radius: 40, titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                ]
              )
            ),
          )
        ],
      ),
    );
  }

  // ==========================================
  // HÀM XỬ LÝ LOGIC (CHUNG)
  // ==========================================
  void _showPartnerApptDetails(AppointmentModel appt) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: 400,
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Khách: ${appt.customerName}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            Text('SĐT: ${appt.customerPhone}', style: const TextStyle(color: Colors.white70)),
            const Divider(color: Colors.white24, height: 32),
            Text('Dịch vụ: ${appt.serviceInfo['service_name']}', style: const TextStyle(color: Colors.white)),
            Text('Giá: ${_formatPrice(appt.totalAmount)}', style: const TextStyle(color: Color(0xFF80BF84), fontWeight: FontWeight.bold, fontSize: 18)),
            const Spacer(),
            if (appt.status == 'CONFIRMED') ...[
              TextField(
                onChanged: (val) => _checkInCodes[appt.id] = val,
                decoration: const InputDecoration(labelText: 'Nhập mã Check-in của khách', border: OutlineInputBorder(), filled: true, fillColor: Colors.white10),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, letterSpacing: 4, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildActionBtn('Hoàn tất Check-in', const Color(0xFF80BF84), () => _handlePartnerCheckIn(appt.id), isDarkText: true),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildRequireLogin() {
    return Center(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black),
        onPressed: () => showModalBottomSheet(context: context, useRootNavigator: true, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => AuthBottomSheet(onSuccess: _checkAuthAndLoad)),
        child: const Text('Đăng nhập để xem Lịch hẹn', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildMiniMetric(String title, String value, Color color) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          children: [
            Text(title.toUpperCase(), style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBtn(String label, Color color, VoidCallback onTap, {bool isDarkText = false}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: isDarkText ? Colors.black : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        onPressed: onTap,
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // CÁC HÀM GỌI API (Đã định nghĩa từ trước)
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
    _loadData();
  }
  Future<void> _handlePartnerCheckIn(String id) async {
    final code = _checkInCodes[id];
    if (code == null || code.isEmpty) return;
    // Gọi API Check-in ở đây (sử dụng API Client tương tự Web)
    // Sau đó gọi lại _loadData();
    Navigator.pop(context);
  }
}