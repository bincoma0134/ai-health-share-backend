import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/partner_api_service.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  bool _isLoading = true;
  String _activeTab = 'escrow'; // escrow | appointments | wallet | withdrawals
  
  List<dynamic> _bookings = [];
  List<dynamic> _appointments = [];
  List<dynamic> _withdrawals = [];
  
  double _balance = 0;
  double _totalEarned = 0;

  // Forms
  Map<String, String> _checkInCodes = {};
  Map<String, Map<String, String>> _respondForms = {};
  final _bankCtrl = TextEditingController();
  final _accNumCtrl = TextEditingController();
  final _accNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  final Color _bizPrimary = const Color(0xFF80BF84); // Xanh ngọc
  final Color _bizSecondary = const Color(0xFF0F172A); // Slate 900

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      PartnerApiService.fetchBookings(),
      PartnerApiService.fetchAppointments(),
      PartnerApiService.fetchWithdrawals(),
    ]);

    if (mounted) {
      setState(() {
        _bookings = results[0];
        _appointments = results[1];
        _withdrawals = results[2];

        // Tính toán ví y hệt Web
        double earned = 0;
        double withdrawn = 0;
        for (var b in _bookings) {
          if (b['service_status'] == 'COMPLETED') earned += (double.tryParse(b['partner_revenue']?.toString() ?? '0') ?? 0);
        }
        for (var w in _withdrawals) {
          if (w['status'] == 'APPROVED' || w['status'] == 'PENDING') withdrawn += (double.tryParse(w['amount']?.toString() ?? '0') ?? 0);
        }
        
        _totalEarned = earned;
        _balance = (earned - withdrawn) > 0 ? (earned - withdrawn) : 0;
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(dynamic amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount ?? 0);
  }

  String _formatDate(String? isoDate) {
    if (isoDate == null) return 'N/A';
    return DateFormat('dd/MM HH:mm').format(DateTime.parse(isoDate).toLocal());
  }

  // --- LOGIC GIAO DỊCH ---
  Future<void> _handleCheckIn(String apptId) async {
    final code = _checkInCodes[apptId] ?? '';
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập đúng 6 số Check-in!')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang xác thực...')));
    final success = await PartnerApiService.checkInAppointment(apptId, code);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check-in khách thành công!'), backgroundColor: Colors.green));
      _loadAllData();
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Mã sai hoặc lỗi mạng!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleCompleteBooking(String bookingId) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang giải ngân...')));
    final success = await PartnerApiService.completeBooking(bookingId);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Giải ngân tiền về ví thành công!'), backgroundColor: Colors.green));
      _loadAllData();
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi: Khách chưa check-in hoặc sự cố hệ thống!'), backgroundColor: Colors.red));
    }
  }

  Future<void> _handleWithdraw() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount < 50000 || amount > _balance) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Số tiền không hợp lệ!')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang tạo lệnh rút...')));
    final success = await PartnerApiService.requestWithdrawal({
      'amount': amount,
      'bank_name': _bankCtrl.text,
      'account_number': _accNumCtrl.text,
      'account_name': _accNameCtrl.text,
    });
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi yêu cầu rút tiền!'), backgroundColor: Colors.green));
      _amountCtrl.clear();
      _loadAllData();
      setState(() => _activeTab = 'withdrawals');
    }
  }

  // --- LOGIC LỊCH HẸN ---
  Future<void> _pickDateTime(String id, String field) async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    
    final finalDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      _respondForms[id] = _respondForms[id] ?? {};
      _respondForms[id]![field] = finalDateTime.toIso8601String();
    });
  }

  Future<void> _handleRespondAppt(String id, String action) async {
    final form = _respondForms[id] ?? {};
    Map<String, dynamic> payload = {'action': action};
    
    if (action == 'ACCEPT') {
      if (form['start'] == null || form['end'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng chọn thời gian Bắt đầu và Kết thúc!')));
        return;
      }
      payload['start_time'] = form['start'];
      payload['end_time'] = form['end'];
    } else {
      if (form['reason'] == null || form['reason']!.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập lý do từ chối!')));
        return;
      }
      payload['reason'] = form['reason'];
    }

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đang phản hồi...')));
    final success = await PartnerApiService.respondAppointment(id, payload);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã ${action == 'ACCEPT' ? 'Chấp nhận' : 'Từ chối'} lịch hẹn!'), backgroundColor: Colors.green));
      _loadAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingAppts = _appointments.where((a) => a['status'] == 'WAITING_PARTNER').toList();
    final validBookings = _bookings.where((b) => b['payment_status'] == 'PAID' || b['service_status'] == 'COMPLETED').toList();

    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090b),
        elevation: 0,
        leading: BackButton(color: _bizPrimary),
        title: Row(
          children: [
            Icon(Icons.shield, color: _bizPrimary, size: 20),
            const SizedBox(width: 8),
            const Text('Partner Workspace', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadAllData)],
      ),
      body: Column(
        children: [
          // MENU TABS NGANG
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildTabBtn('escrow', 'Escrow', Icons.wallet),
                _buildTabBtn('appointments', 'Lịch hẹn ${pendingAppts.isNotEmpty ? '(${pendingAppts.length})' : ''}', Icons.calendar_today),
                _buildTabBtn('wallet', 'Rút tiền', Icons.credit_card),
                _buildTabBtn('withdrawals', 'Lịch sử', Icons.history),
              ],
            ),
          ),
          
          Expanded(
            child: _isLoading 
              ? Center(child: CircularProgressIndicator(color: _bizPrimary))
              : RefreshIndicator(
                  color: _bizPrimary,
                  onRefresh: _loadAllData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16).copyWith(bottom: 40),
                    child: _buildActiveTabContent(validBookings, pendingAppts),
                  ),
                ),
          )
        ],
      ),
    );
  }

  Widget _buildActiveTabContent(List<dynamic> validBookings, List<dynamic> pendingAppts) {
    switch (_activeTab) {
      case 'escrow': return _buildEscrowTab(validBookings);
      case 'appointments': return _buildAppointmentsTab(pendingAppts);
      case 'wallet': return _buildWalletTab();
      case 'withdrawals': return _buildWithdrawalsTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // TAB 1: ESCROW (DÒNG TIỀN BẢO CHỨNG)
  // ==========================================
  Widget _buildEscrowTab(List<dynamic> validBookings) {
    double pendingEscrow = 0;
    for (var b in validBookings) {
      if (b['service_status'] != 'COMPLETED') pendingEscrow += (double.tryParse(b['total_amount']?.toString() ?? '0') ?? 0) * 0.7;
    }

    return Column(
      children: [
        // Các chỉ số
        Row(
          children: [
            Expanded(child: _buildMetricCard('Neo Giữ (70%)', _formatCurrency(pendingEscrow), Icons.lock_clock, Colors.amber)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard('Thực Nhận', _formatCurrency(_totalEarned), Icons.trending_up, _bizPrimary)),
          ],
        ),
        const SizedBox(height: 24),
        
        // Danh sách Đơn
        if (validBookings.isEmpty) const Center(child: Text('Chưa có giao dịch bảo chứng.', style: TextStyle(color: Colors.white54)))
        else ...validBookings.map((b) {
          final appt = _appointments.firstWhere((a) => a['booking_id'] == b['id'], orElse: () => null);
          final isCompleted = b['service_status'] == 'COMPLETED';
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.white10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('#${b['id'].toString().substring(0, 8)}', style: const TextStyle(color: Colors.white54, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: const Text('ĐÃ THANH TOÁN', style: TextStyle(color: Colors.blue, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Doanh thu dự kiến: ${isCompleted ? _formatCurrency(b['partner_revenue']) : _formatCurrency((double.tryParse(b['total_amount'].toString()) ?? 0) * 0.7)}', style: TextStyle(color: isCompleted ? _bizPrimary : Colors.amber, fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 12),
                
                // Trạng thái thao tác
                if (isCompleted)
                  const Row(children: [Icon(Icons.check_circle, color: Colors.green, size: 16), SizedBox(width: 8), Text('Đã giải ngân về ví', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))])
                else if (appt != null && appt['status'] == 'CONFIRMED')
                  Row(
                    children: [
                      Expanded(child: TextField(
                        maxLength: 6,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                        decoration: InputDecoration(counterText: '', hintText: 'Mã 6 số', hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                        onChanged: (v) => _checkInCodes[appt['id']] = v,
                      )),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _handleCheckIn(appt['id']),
                        child: const Text('CHECK-IN', style: TextStyle(fontWeight: FontWeight.w900)),
                      )
                    ],
                  )
                else if (appt != null && appt['status'] == 'SERVED')
                  SizedBox(
                    width: double.infinity, height: 44,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: () => _handleCompleteBooking(b['id']),
                      child: const Text('HOÀN THÀNH & RÚT TIỀN', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  )
                else
                  const Text('Khách chưa thanh toán hoặc đang chờ xếp lịch.', style: TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic))
              ],
            ),
          );
        }).toList()
      ],
    );
  }

  // ==========================================
  // TAB 2: DUYỆT LỊCH HẸN
  // ==========================================
  Widget _buildAppointmentsTab(List<dynamic> pendingAppts) {
    if (pendingAppts.isEmpty) return const Center(child: Text('Không có lịch hẹn chờ duyệt.', style: TextStyle(color: Colors.white54)));

    return Column(
      children: pendingAppts.map((appt) {
        final form = _respondForms[appt['id']] ?? {};
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber.withOpacity(0.3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: const Text('YÊU CẦU MỚI', style: TextStyle(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
              const SizedBox(height: 12),
              Text(appt['services']?['service_name'] ?? 'Dịch vụ Cơ sở', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text('Khách: ${appt['customer_name'] ?? 'Ẩn danh'}', style: const TextStyle(color: Colors.white70)),
              Text('SĐT: ${appt['customer_phone'] ?? 'Không có'}', style: const TextStyle(color: Colors.white70)),
              if (appt['note'] != null && appt['note'].toString().isNotEmpty)
                Container(margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: Text('"${appt['note']}"', style: const TextStyle(color: Colors.white54, fontStyle: FontStyle.italic, fontSize: 12))),
              
              const Divider(height: 32, color: Colors.white10),
              
              // Form Chấp nhận
              const Text('CHỐT LỊCH (CHẤP NHẬN)', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: GestureDetector(
                    onTap: () => _pickDateTime(appt['id'], 'start'),
                    child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: Text(form['start'] != null ? _formatDate(form['start']) : 'Chọn Bắt đầu', style: TextStyle(color: form['start'] != null ? Colors.white : Colors.white30, fontSize: 12))),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GestureDetector(
                    onTap: () => _pickDateTime(appt['id'], 'end'),
                    child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)), child: Text(form['end'] != null ? _formatDate(form['end']) : 'Chọn Kết thúc', style: TextStyle(color: form['end'] != null ? Colors.white : Colors.white30, fontSize: 12))),
                  )),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: () => _handleRespondAppt(appt['id'], 'ACCEPT'), child: const Text('GỬI BÁO GIÁ & CHỐT LỊCH', style: TextStyle(fontWeight: FontWeight.w900)))),
              
              const SizedBox(height: 16),
              
              // Form Từ chối
              const Text('TỪ CHỐI TIẾP NHẬN', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              TextField(
                onChanged: (v) => setState(() { _respondForms[appt['id']] = _respondForms[appt['id']] ?? {}; _respondForms[appt['id']]!['reason'] = v; }),
                style: const TextStyle(color: Colors.white, fontSize: 12), decoration: InputDecoration(hintText: 'Nhập lý do từ chối...', hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.2), foregroundColor: Colors.redAccent), onPressed: () => _handleRespondAppt(appt['id'], 'REJECT'), child: const Text('HỦY YÊU CẦU', style: TextStyle(fontWeight: FontWeight.w900)))),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==========================================
  // TAB 3: VÍ NỘI BỘ VÀ RÚT TIỀN
  // ==========================================
  Widget _buildWalletTab() {
    return Column(
      children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F172A), Colors.black]), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SỐ DƯ HIỆN TẠI', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text(_formatCurrency(_balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TẠO LỆNH RÚT TIỀN', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              _buildTextField('Ngân hàng thụ hưởng', _bankCtrl, 'VD: Vietcombank...'),
              const SizedBox(height: 12),
              _buildTextField('Số tài khoản', _accNumCtrl, 'Nhập số tài khoản...', isNumber: true),
              const SizedBox(height: 12),
              _buildTextField('Tên chủ thẻ', _accNameCtrl, 'NGUYEN VAN A'),
              const SizedBox(height: 12),
              _buildTextField('Số tiền cần rút', _amountCtrl, 'Tối thiểu 50.000đ', isNumber: true, textColor: _bizPrimary),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                  onPressed: _handleWithdraw,
                  child: const Text('GỬI YÊU CẦU RÚT TIỀN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              )
            ],
          ),
        )
      ],
    );
  }

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool isNumber = false, Color textColor = Colors.white}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
          decoration: InputDecoration(hintText: hint, hintStyle: const TextStyle(color: Colors.white24), filled: true, fillColor: Colors.black, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: LỊCH SỬ RÚT TIỀN
  // ==========================================
  Widget _buildWithdrawalsTab() {
    if (_withdrawals.isEmpty) return const Center(child: Text('Bạn chưa có lệnh rút tiền nào.', style: TextStyle(color: Colors.white54)));

    return Column(
      children: _withdrawals.map((w) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_formatCurrency(w['amount']), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: w['status'] == 'COMPLETED' ? Colors.green.withOpacity(0.2) : w['status'] == 'REJECTED' ? Colors.red.withOpacity(0.2) : Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(6)), child: Text(w['status'], style: TextStyle(color: w['status'] == 'COMPLETED' ? Colors.green : w['status'] == 'REJECTED' ? Colors.redAccent : Colors.amber, fontSize: 8, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
              ],
            ),
            const SizedBox(height: 8),
            Text('${w['payout_info']?['bank_name']} - ${w['payout_info']?['account_number']}', style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(_formatDate(w['created_at']), style: const TextStyle(color: Colors.white30, fontSize: 10)),
            if (w['admin_note'] != null && w['admin_note'].toString().isNotEmpty)
               Padding(padding: const EdgeInsets.only(top: 8), child: Text('Ghi chú: ${w['admin_note']}', style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontStyle: FontStyle.italic)))
          ],
        ),
      )).toList(),
    );
  }

  // --- WIDGET HỖ TRỢ ---
  Widget _buildTabBtn(String key, String title, IconData icon) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isActive ? Colors.white : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.black : Colors.white54),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: TextStyle(color: isActive ? Colors.black : Colors.white54, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}