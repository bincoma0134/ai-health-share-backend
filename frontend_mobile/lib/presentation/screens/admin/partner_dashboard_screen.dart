import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/partner_tier_theme.dart';
import '../../../data/services/calendar_api_service.dart';
import '../../../data/services/partner_api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/partner_tier/partner_tier_badge.dart';

class PartnerDashboardScreen extends StatefulWidget {
  const PartnerDashboardScreen({super.key});

  @override
  State<PartnerDashboardScreen> createState() => _PartnerDashboardScreenState();
}

class _PartnerDashboardScreenState extends State<PartnerDashboardScreen> {
  bool _isLoading = true;
  String _activeTab = 'escrow'; // escrow | appointments | wallet | withdrawals
  
  // 🚀 PHASE 08: State Quản Lý Cấp Bậc Đối Tác (Source of Truth)
  bool _isPremium = false;
  String _premiumTier = 'STANDARD';
  
  List<dynamic> _bookings = [];
  List<dynamic> _appointments = [];
  List<dynamic> _withdrawals = [];
  List<dynamic> _vouchers = [];
  List<dynamic> _affiliateQueue = [];
  List<dynamic> _affiliateMetrics = [];
  
  double _balance = 0;
  double _totalEarned = 0;

  PartnerTierTheme get _tierTheme => PartnerTierTheme.fromTier(_isPremium, _premiumTier);

  // Forms
  Map<String, String> _checkInCodes = {};
  Map<String, Map<String, String>> _respondForms = {};
  final _bankCtrl = TextEditingController();
  final _accNumCtrl = TextEditingController();
  final _accNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();

  final Color _bizPrimary = const Color(0xFF48C9B0); // Xanh ngọc SaaS
  final Color _bizSecondary = const Color(0xFF1A3A35); // Xanh đen đậm
  final Color _bgLight = const Color(0xFFF7FBF9);
  final Color _textMain = const Color(0xFF1A3A35);
  final Color _textSub = const Color(0xFF617D79);
  final Color _borderColor = const Color(0xFFE2ECEB);

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      print('[DEBUG-PARTNER-WORKSPACE] Bắt đầu đồng bộ dữ liệu quản trị cơ sở...');
      final results = await Future.wait([
        PartnerApiService.fetchBookings(),
        PartnerApiService.fetchAppointments(),
        PartnerApiService.fetchWithdrawals(),
        PartnerApiService.fetchVouchers(),
        PartnerApiService.fetchAffiliateQueue(),
        PartnerApiService.fetchAffiliateMetrics(),
        CalendarApiService.fetchUserProfile(),
      ]);

      if (mounted) {
        setState(() {
          _bookings = (results[0] as List<dynamic>?) ?? [];
          _appointments = (results[1] as List<dynamic>?) ?? [];
          _withdrawals = (results[2] as List<dynamic>?) ?? [];
          _vouchers = (results[3] as List<dynamic>?) ?? [];
          _affiliateQueue = (results[4] as List<dynamic>?) ?? [];
          _affiliateMetrics = (results[5] as List<dynamic>?) ?? [];

          final profile = results[6] as Map<String, dynamic>?;
          if (profile != null) {
            _isPremium = profile['is_premium'] == true || profile['is_premium'] == 'true';
            _premiumTier = (profile['premium_tier'] ?? 'STANDARD').toString().toUpperCase();
            print('[DEBUG-PARTNER-WORKSPACE-TIER] Tier: $_premiumTier | IsPremium: $_isPremium | PrimaryColor: ${_tierTheme.primaryColor}');
          }

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
    } catch (e) {
      print('[ERROR-PARTNER-WORKSPACE] Lỗi tải dữ liệu workspace: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
      AppToast.show(context: context, message: 'Vui lòng nhập đúng 6 số Check-in!', isSuccess: false);
      return;
    }
    AppToast.show(context: context, message: 'Đang xác thực Check-in...', isSuccess: true, duration: const Duration(seconds: 1));
    final success = await PartnerApiService.checkInAppointment(apptId, code);
    if (success && mounted) {
      AppToast.show(context: context, message: 'Check-in khách thành công!', isSuccess: true);
      _loadAllData();
    } else if (mounted) {
      AppToast.show(context: context, message: 'Mã sai hoặc lỗi mạng!', isSuccess: false);
    }
  }

  Future<void> _handleCompleteBooking(String bookingId) async {
    AppToast.show(context: context, message: 'Đang xử lý giải ngân...', isSuccess: true, duration: const Duration(seconds: 1));
    final success = await PartnerApiService.completeBooking(bookingId);
    if (success && mounted) {
      AppToast.show(context: context, message: 'Giải ngân tiền về ví thành công!', isSuccess: true);
      _loadAllData();
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi: Khách chưa check-in hoặc sự cố!', isSuccess: false);
    }
  }

  Future<void> _handleWithdraw() async {
    final amount = double.tryParse(_amountCtrl.text) ?? 0;
    if (amount < 50000 || amount > _balance) {
      AppToast.show(context: context, message: 'Số tiền không hợp lệ!', isSuccess: false);
      return;
    }
    AppToast.show(context: context, message: 'Đang tạo lệnh rút tiền...', isSuccess: true, duration: const Duration(seconds: 1));
    
    // 🚀 ĐỒNG BỘ CHỮ KÝ HÀM: Đóng gói an toàn duy nhất 1 Map chứa 4 trường dữ liệu ngân hàng chuẩn xác theo đặc tả của PartnerApiService
    final success = await PartnerApiService.requestWithdrawal({
      'amount': amount,
      'bank_name': _bankCtrl.text.trim(),
      'account_number': _accNumCtrl.text.trim(),
      'account_name': _accNameCtrl.text.trim().toUpperCase(),
    });
    if (success && mounted) {
      AppToast.show(context: context, message: 'Đã gửi yêu cầu rút tiền!', isSuccess: true);
      _amountCtrl.clear();
      _loadAllData();
      setState(() => _activeTab = 'withdrawals');
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi gửi yêu cầu rút tiền!', isSuccess: false);
    }
  }

  // --- LOGIC LỊCH HẸN ---
  Future<void> _handleRespondAppt(String id, String action) async {
    final form = _respondForms[id] ?? {};
    Map<String, dynamic> payload = {'action': action};
    
    if (action == 'REJECT') {
      if (form['reason'] == null || form['reason']!.isEmpty) {
        AppToast.show(context: context, message: 'Vui lòng nhập lý do từ chối!', isSuccess: false);
        return;
      }
      payload['reason'] = form['reason'];
    }

    AppToast.show(context: context, message: 'Đang xử lý phản hồi...', isSuccess: true, duration: const Duration(seconds: 1));
    final success = await PartnerApiService.respondAppointment(id, payload);
    if (success && mounted) {
      AppToast.show(context: context, message: 'Đã ${action == 'ACCEPT' ? 'Chấp nhận' : 'Từ chối'} lịch hẹn!', isSuccess: true);
      _loadAllData();
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi khi gửi phản hồi!', isSuccess: false);
    }
  }

  // --- LOGIC AFFILIATE ---
  Future<void> _handleAffiliateAction(String id, String action, {String? note}) async {
    AppToast.show(context: context, message: 'Đang xử lý...', isSuccess: true, duration: const Duration(seconds: 1));
    final success = await PartnerApiService.actionAffiliate(id, action, adminNote: note);
    if (success && mounted) {
      AppToast.show(context: context, message: 'Đã xử lý hồ sơ Affiliate!', isSuccess: true);
      _loadAllData();
    } else if (mounted) {
      AppToast.show(context: context, message: 'Lỗi xử lý, vui lòng thử lại!', isSuccess: false);
    }
  }

  void _showRejectAffiliateDialog(String id) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Từ chối Affiliate', style: TextStyle(fontWeight: FontWeight.w900)),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(hintText: 'Nhập lý do từ chối (bắt buộc)...', filled: true, fillColor: Color(0xFFF7FBF9), border: OutlineInputBorder(borderSide: BorderSide.none)),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () {
              if (noteCtrl.text.trim().isEmpty) {
                AppToast.show(context: context, message: 'Vui lòng nhập lý do!', isSuccess: false);
                return;
              }
              Navigator.pop(ctx);
              _handleAffiliateAction(id, 'REJECTED', note: noteCtrl.text.trim());
            },
            child: const Text('Từ chối'),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingAppts = _appointments.where((a) => a['status'] == 'WAITING_PARTNER').toList();
    final validBookings = _bookings.where((b) => b['payment_status'] == 'PAID' || b['service_status'] == 'COMPLETED').toList();

    return Scaffold(
      backgroundColor: _bgLight,
      appBar: AppBar(
        backgroundColor: _bgLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: _textMain),
        title: Row(
          children: [
            Icon(
              _isPremium ? _tierTheme.icon : Icons.shield_rounded, 
              color: _isPremium ? _tierTheme.primaryColor : _bizPrimary, 
              size: 22
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Partner Workspace', 
                style: TextStyle(color: _textMain, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isPremium) ...[
              const SizedBox(width: 8),
              PartnerTierBadge(isPremium: _isPremium, premiumTier: _premiumTier, isCompact: true),
            ],
          ],
        ),
        actions: [IconButton(icon: Icon(Icons.refresh_rounded, color: _textMain), onPressed: _loadAllData)],
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
                _buildTabBtn('vouchers', 'Ưu đãi', Icons.discount_rounded),
                _buildTabBtn('affiliate_queue', 'Duyệt Affiliate ${_affiliateQueue.isNotEmpty ? '(${_affiliateQueue.length})' : ''}', Icons.group_add_rounded),
                _buildTabBtn('affiliate_metrics', 'Hiệu suất Affiliate', Icons.analytics_rounded),
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
      case 'vouchers': return _buildVouchersTab();
      case 'affiliate_queue': return _buildAffiliateQueueTab();
      case 'affiliate_metrics': return _buildAffiliateMetricsTab();
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
            Expanded(child: _buildMetricCard('Neo Giữ (70%)', _formatCurrency(pendingEscrow), Icons.lock_clock_rounded, Colors.amber.shade600)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard('Thực Nhận', _formatCurrency(_totalEarned), Icons.trending_up_rounded, _bizPrimary)),
          ],
        ),
        const SizedBox(height: 24),
        
        // Danh sách Đơn
        if (validBookings.isEmpty) Center(child: Text('Chưa có giao dịch bảo chứng.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500)))
        else ...validBookings.map((b) {
          final appt = _appointments.firstWhere((a) => a['booking_id'] == b['id'], orElse: () => null);
          final isCompleted = b['service_status'] == 'COMPLETED';
          
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white, 
              borderRadius: BorderRadius.circular(24), 
              border: Border.all(color: _borderColor),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('#${b['id'].toString().substring(0, 8).toUpperCase()}', style: TextStyle(color: _textSub, fontFamily: 'monospace', fontWeight: FontWeight.bold, letterSpacing: 1)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)), child: Text('ĐÃ THANH TOÁN', style: TextStyle(color: Colors.blue.shade700, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Doanh thu dự kiến:', style: TextStyle(color: _textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(isCompleted ? _formatCurrency(b['partner_revenue']) : '~${_formatCurrency((double.tryParse(b['total_amount'].toString()) ?? 0) * 0.7)}', style: TextStyle(color: isCompleted ? _textMain : Colors.amber.shade700, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 16),
                
                // Trạng thái thao tác
                if (isCompleted)
                  Row(children: [const Icon(Icons.check_circle_rounded, color: Color(0xFF48C9B0), size: 18), const SizedBox(width: 8), Text('Đã giải ngân về ví', style: TextStyle(color: _textMain, fontWeight: FontWeight.bold, fontSize: 13))])
                else if (appt != null && appt['status'] == 'CONFIRMED')
                  Row(
                    children: [
                      Expanded(child: TextField(
                        maxLength: 6,
                        style: TextStyle(color: _textMain, fontWeight: FontWeight.w800, letterSpacing: 4, fontSize: 16),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(counterText: '', hintText: 'MÃ 6 SỐ', hintStyle: TextStyle(color: _borderColor, letterSpacing: 1), filled: true, fillColor: _bgLight, contentPadding: const EdgeInsets.symmetric(vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
                        onChanged: (v) => _checkInCodes[appt['id']] = v,
                      )),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _bizSecondary, foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: () => _handleCheckIn(appt['id']),
                        child: const Text('CHECK-IN', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      )
                    ],
                  )
                else if (appt != null && appt['status'] == 'SERVED')
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                      onPressed: () => _handleCompleteBooking(b['id']),
                      child: const Text('HOÀN THÀNH & RÚT TIỀN', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                    ),
                  )
                else
                  Text('Khách chưa thanh toán hoặc đang chờ xếp lịch.', style: TextStyle(color: _textSub, fontSize: 13, fontStyle: FontStyle.italic))
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
    if (pendingAppts.isEmpty) return Center(child: Text('Không có lịch hẹn chờ duyệt.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500)));

    return Column(
      children: pendingAppts.map((appt) {
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(24), 
            border: Border.all(color: _borderColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)), child: Text('YÊU CẦU MỚI', style: TextStyle(color: Colors.amber.shade700, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
              const SizedBox(height: 16),
              Text(appt['services']?['service_name'] ?? 'Dịch vụ Cơ sở', style: TextStyle(color: _textMain, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
              const SizedBox(height: 12),
              
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: _bgLight, borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [Icon(Icons.person_outline_rounded, size: 16, color: _textSub), const SizedBox(width: 8), Text('Khách: ${appt['customer_name'] ?? 'Ẩn danh'}', style: TextStyle(color: _textMain, fontWeight: FontWeight.w600, fontSize: 13))]),
                    const SizedBox(height: 6),
                    Row(children: [Icon(Icons.phone_outlined, size: 16, color: _textSub), const SizedBox(width: 8), Text('SĐT: ${appt['customer_phone'] ?? 'Không có'}', style: TextStyle(color: _textMain, fontWeight: FontWeight.w600, fontSize: 13))]),
                  ]
                )
              ),

              if (appt['note'] != null && appt['note'].toString().isNotEmpty)
                Container(margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)), child: Text('"${appt['note']}"', style: TextStyle(color: Colors.blue.shade800, fontStyle: FontStyle.italic, fontSize: 13))),
              
              if (appt['preferred_time'] != null || appt['guest_count'] != null)
                Container(
                  margin: const EdgeInsets.only(top: 12), padding: const EdgeInsets.all(12), 
                  decoration: BoxDecoration(color: _bgLight, borderRadius: BorderRadius.circular(12)), 
                  child: Row(
                    children: [
                      if (appt['preferred_time'] != null) ...[
                        Icon(Icons.access_time_rounded, size: 16, color: _textSub), const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            String displayTime = appt['preferred_time'].toString();
                            try {
                              final parsed = DateTime.parse(displayTime).toLocal();
                              displayTime = DateFormat('HH:mm - dd/MM').format(parsed);
                            } catch (_) {}
                            return Text('Mong muốn: $displayTime', style: TextStyle(color: _textMain, fontWeight: FontWeight.w800, fontSize: 13));
                          }
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (appt['guest_count'] != null) ...[
                        Icon(Icons.people_alt_rounded, size: 16, color: _textSub), const SizedBox(width: 6),
                        Text('${appt['guest_count']} người', style: TextStyle(color: _textMain, fontWeight: FontWeight.w800, fontSize: 13)),
                      ],
                    ]
                  )
                ),

              const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(height: 1, color: Color(0xFFE2ECEB))),
              
              // Nút Chấp nhận tĩnh (Không cần chọn giờ)
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => _handleRespondAppt(appt['id'], 'ACCEPT'), child: const Text('DUYỆT YÊU CẦU & CHỐT LỊCH', style: TextStyle(fontWeight: FontWeight.w900)))),
              
              const SizedBox(height: 24),
              
              // Form Từ chối
              const Text('TỪ CHỐI TIẾP NHẬN', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 12),
              TextField(
                onChanged: (v) => setState(() { _respondForms[appt['id']] = _respondForms[appt['id']] ?? {}; _respondForms[appt['id']]!['reason'] = v; }),
                style: TextStyle(color: _textMain, fontSize: 13, fontWeight: FontWeight.w500), decoration: InputDecoration(hintText: 'Nhập lý do từ chối...', hintStyle: TextStyle(color: _textSub), filled: true, fillColor: _bgLight, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2ECEB))), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE2ECEB))), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.redAccent))),
              ),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 48, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.redAccent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), onPressed: () => _handleRespondAppt(appt['id'], 'REJECT'), child: const Text('HỦY YÊU CẦU', style: TextStyle(fontWeight: FontWeight.w900)))),
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
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1A3A35), Color(0xFF2C554D)]), borderRadius: BorderRadius.circular(32), boxShadow: [BoxShadow(color: const Color(0xFF1A3A35).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SỐ DƯ HIỆN TẠI', style: TextStyle(color: Color(0xFFB0C4C1), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1)),
              const SizedBox(height: 12),
              Text(_formatCurrency(_balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TẠO LỆNH RÚT TIỀN', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900)),
              const SizedBox(height: 24),
              _buildTextField('Ngân hàng thụ hưởng', _bankCtrl, 'VD: Vietcombank...'),
              const SizedBox(height: 16),
              _buildTextField('Số tài khoản', _accNumCtrl, 'Nhập số tài khoản...', isNumber: true),
              const SizedBox(height: 16),
              _buildTextField('Tên chủ thẻ', _accNameCtrl, 'NGUYEN VAN A'),
              const SizedBox(height: 16),
              _buildTextField('Số tiền cần rút', _amountCtrl, 'Tối thiểu 50.000đ', isNumber: true, textColor: _bizPrimary),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _bizSecondary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
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

  Widget _buildTextField(String label, TextEditingController controller, String hint, {bool isNumber = false, Color? textColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: TextStyle(color: _textSub, fontSize: 11, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: TextStyle(color: textColor ?? _textMain, fontWeight: FontWeight.bold, fontSize: 15),
          decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: _borderColor), filled: true, fillColor: _bgLight, contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: LỊCH SỬ RÚT TIỀN
  // ==========================================
  Widget _buildWithdrawalsTab() {
    if (_withdrawals.isEmpty) return Center(child: Text('Bạn chưa có lệnh rút tiền nào.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500)));

    return Column(
      children: _withdrawals.map((w) {
        // 🚀 BỌC THÉP GIẢI MÃ (Lỗ hổng 2): Giải mã chuỗi JSON String thô từ database Postgres để tránh lỗi sập giao diện Type Cast Exception
        Map<String, dynamic> payoutInfo = {};
        if (w['payout_info'] is String) {
          try {
            payoutInfo = jsonDecode(w['payout_info'] as String) as Map<String, dynamic>;
          } catch (_) {}
        } else if (w['payout_info'] is Map) {
          payoutInfo = w['payout_info'] as Map<String, dynamic>;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatCurrency(w['amount']), style: TextStyle(color: _textMain, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: w['status'] == 'COMPLETED' ? Colors.green.shade50 : w['status'] == 'REJECTED' ? Colors.red.shade50 : Colors.amber.shade50, borderRadius: BorderRadius.circular(8)), child: Text(w['status'], style: TextStyle(color: w['status'] == 'COMPLETED' ? Colors.green.shade700 : w['status'] == 'REJECTED' ? Colors.redAccent : Colors.amber.shade700, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                ],
              ),
              const SizedBox(height: 12),
              Text('${payoutInfo['bank_name'] ?? 'N/A'} - ${payoutInfo['account_number'] ?? 'N/A'}', style: TextStyle(color: _textSub, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(_formatDate(w['created_at']), style: TextStyle(color: _borderColor, fontSize: 11, fontWeight: FontWeight.w500)),
              if (w['admin_note'] != null && w['admin_note'].toString().isNotEmpty)
               Padding(padding: const EdgeInsets.only(top: 12), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)), child: Text('Ghi chú: ${w['admin_note']}', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontStyle: FontStyle.italic, fontWeight: FontWeight.w500))))
          ],
        ),
      );
    }).toList());
  }


  // ==========================================
  // TAB 5: QUẢN LÝ ƯU ĐÃI (VOUCHERS)
  // ==========================================
  void _showCreateVoucherModal() {
    final codeCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final minOrderCtrl = TextEditingController();
    final maxDiscountCtrl = TextEditingController();
    final pointPriceCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    
    String type = 'PERCENTAGE';
    bool isVip = false;
    String selectedSlot = '08:00 - 10:00';
    DateTime validUntil = DateTime.now().add(const Duration(days: 7));
    bool isSubmitting = false;

    final List<String> timeSlots = [
      '08:00 - 10:00',
      '10:00 - 12:00',
      '13:00 - 15:00',
      '15:00 - 17:00',
      '18:00 - 20:00',
      '20:00 - 22:00',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Color(0xFFF7FBF9), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tạo Mã Ưu Đãi', style: TextStyle(color: _textMain, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    IconButton(
                      icon: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Color(0xFFE2ECEB), shape: BoxShape.circle), child: Icon(Icons.close_rounded, color: _textSub, size: 18)), 
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    )
                  ]
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🚀 PHASE 08: CÔNG TẮC PHÁT HÀNH VOUCHER VIP KÈM QUẢN TRỊ HẠN MỨC CẤP BẬC
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isVip 
                                ? const Color(0xFF1A3A35) 
                                : (!_isPremium ? const Color(0xFFF8FAFC) : Colors.white),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isVip 
                                  ? const Color(0xFF1A3A35) 
                                  : (!_isPremium ? const Color(0xFFE2E8F0) : _borderColor),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Icon(
                                          !_isPremium ? Icons.lock_outline_rounded : Icons.stars_rounded, 
                                          color: isVip 
                                              ? const Color(0xFFFCD34D) 
                                              : (!_isPremium ? Colors.grey : _tierTheme.primaryColor), 
                                          size: 22
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Text(
                                                    'Phát hành Voucher VIP',
                                                    style: TextStyle(
                                                      color: isVip 
                                                          ? Colors.white 
                                                          : (!_isPremium ? Colors.grey.shade700 : _textMain), 
                                                      fontSize: 13, 
                                                      fontWeight: FontWeight.w800
                                                    ),
                                                  ),
                                                  if (!_isPremium) ...[
                                                    const SizedBox(width: 6),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFFEF3C7), 
                                                        borderRadius: BorderRadius.circular(4)
                                                      ),
                                                      child: const Text(
                                                        'PRO / DIAMOND', 
                                                        style: TextStyle(color: Color(0xFFD97706), fontSize: 8, fontWeight: FontWeight.w900)
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                !_isPremium 
                                                    ? 'Mở khóa đặc quyền khi nâng cấp gói đối tác'
                                                    : (_premiumTier == 'PRO' 
                                                        ? 'Hạn mức: Tối đa 5 mã VIP/tuần' 
                                                        : 'Đặc quyền VIP Diamond: Không giới hạn'),
                                                style: TextStyle(
                                                  color: isVip 
                                                      ? Colors.white70 
                                                      : (!_isPremium ? Colors.grey : _tierTheme.primaryColor), 
                                                  fontSize: 11,
                                                  fontWeight: isVip ? FontWeight.normal : FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Switch(
                                    value: isVip,
                                    activeThumbColor: const Color(0xFF48C9B0),
                                    activeTrackColor: Colors.white24,
                                    onChanged: !_isPremium ? null : (val) {
                                      setModalState(() => isVip = val);
                                    },
                                  ),
                                ],
                              ),
                              if (!_isPremium) ...[
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  height: 34,
                                  child: TextButton.icon(
                                    style: TextButton.styleFrom(
                                      backgroundColor: const Color(0xFFFFF0F3),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    icon: const Icon(Icons.workspace_premium_rounded, size: 14, color: Color(0xFFE63956)),
                                    label: const Text(
                                      'Nâng cấp gói Đối tác ngay', 
                                      style: TextStyle(color: Color(0xFFE63956), fontSize: 11, fontWeight: FontWeight.w800)
                                    ),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      context.push('/partner/membership');
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        _buildModalTextField('Mã Voucher (VD: VIPSPA50)', codeCtrl, isUpperCase: true),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => type = 'PERCENTAGE'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(color: type == 'PERCENTAGE' ? _bizPrimary.withOpacity(0.1) : Colors.white, border: Border.all(color: type == 'PERCENTAGE' ? _bizPrimary : _borderColor), borderRadius: BorderRadius.circular(14)),
                                  alignment: Alignment.center,
                                  child: Text('Phần trăm (%)', style: TextStyle(color: type == 'PERCENTAGE' ? _bizPrimary : _textSub, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setModalState(() => type = 'FIXED_AMOUNT'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(color: type == 'FIXED_AMOUNT' ? _bizPrimary.withOpacity(0.1) : Colors.white, border: Border.all(color: type == 'FIXED_AMOUNT' ? _bizPrimary : _borderColor), borderRadius: BorderRadius.circular(14)),
                                  alignment: Alignment.center,
                                  child: Text('Tiền mặt (VNĐ)', style: TextStyle(color: type == 'FIXED_AMOUNT' ? _bizPrimary : _textSub, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildModalTextField(type == 'PERCENTAGE' ? 'Giảm (%)' : 'Giảm (VNĐ)', valueCtrl, isNumber: true)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildModalTextField('Số lượng phát hành', qtyCtrl, isNumber: true)),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(child: _buildModalTextField('Đơn tối thiểu (VNĐ)', minOrderCtrl, isNumber: true)),
                            const SizedBox(width: 12),
                            Expanded(child: _buildModalTextField('Giảm tối đa (Tùy chọn)', maxDiscountCtrl, isNumber: true, isEnabled: type == 'PERCENTAGE')),
                          ],
                        ),
                        
                        // 🚀 CÁC TRƯỜNG CẤU HÌNH BỔ SUNG KHI BẬT VIP VOUCHER
                        if (isVip) ...[
                          const SizedBox(height: 16),
                          _buildModalTextField('Giá mua bằng Điểm (VD: 10000)', pointPriceCtrl, isNumber: true),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _borderColor)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: selectedSlot,
                                items: timeSlots.map((slot) => DropdownMenuItem(
                                  value: slot,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFF48C9B0)),
                                      const SizedBox(width: 8),
                                      Text('Khung giờ cố định: $slot', style: TextStyle(color: _textMain, fontSize: 13, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                )).toList(),
                                onChanged: (val) {
                                  if (val != null) setModalState(() => selectedSlot = val);
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildModalTextField('Mô tả đặc quyền VIP (Tùy chọn)', descCtrl),
                        ],

                        const SizedBox(height: 16),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: _borderColor)),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            title: Text('Hạn sử dụng', style: TextStyle(color: _textSub, fontSize: 13, fontWeight: FontWeight.w600)),
                            subtitle: Text(DateFormat('dd/MM/yyyy').format(validUntil), style: TextStyle(color: _textMain, fontSize: 15, fontWeight: FontWeight.bold)),
                            trailing: Icon(Icons.calendar_month_rounded, color: _bizPrimary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            onTap: () async {
                              final date = await showDatePicker(context: context, initialDate: validUntil, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                              if (date != null) {
                                setModalState(() => validUntil = DateTime(date.year, date.month, date.day, 23, 59, 59));
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 20),
                      ]
                    )
                  )
                ),
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _bizSecondary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isSubmitting ? null : () async {
                      if (codeCtrl.text.isEmpty || valueCtrl.text.isEmpty || qtyCtrl.text.isEmpty) {
                        AppToast.show(context: context, message: 'Vui lòng điền đủ thông tin cơ bản!', isSuccess: false);
                        return;
                      }
                      if (isVip && (double.tryParse(pointPriceCtrl.text) ?? 0) <= 0) {
                        AppToast.show(context: context, message: 'Voucher VIP bắt buộc phải có giá Điểm > 0!', isSuccess: false);
                        return;
                      }

                      setModalState(() => isSubmitting = true);
                      
                      // 🚀 ĐÓNG GÓI PAYLOAD CHUẨN PHASE 3
                      final payload = {
                        'code': codeCtrl.text.toUpperCase(),
                        'issuer_type': 'PARTNER',
                        'discount_type': type,
                        'discount_value': double.tryParse(valueCtrl.text) ?? 0,
                        'max_discount_amount': maxDiscountCtrl.text.isEmpty ? null : double.tryParse(maxDiscountCtrl.text),
                        'min_order_value': double.tryParse(minOrderCtrl.text) ?? 0,
                        'applicable_services': [],
                        'total_quantity': int.tryParse(qtyCtrl.text) ?? 0,
                        'valid_from': DateTime.now().toUtc().toIso8601String(),
                        'valid_until': validUntil.toUtc().toIso8601String(),
                        'is_vip': isVip,
                        'point_price': isVip ? (double.tryParse(pointPriceCtrl.text) ?? 0.0) : 0.0,
                        'fixed_time_slot': isVip ? selectedSlot : null,
                        'description': descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                      };
                      
                      try {
                        print('[DEBUG-PARTNER-VOUCHER] Gửi payload tạo Voucher: $payload');
                        final success = await PartnerApiService.createVoucher(payload);
                        if (success && mounted) {
                          Navigator.pop(context);
                          _loadAllData();
                          AppToast.show(context: context, message: isVip ? 'Đã tạo Voucher VIP! Đang chờ duyệt.' : 'Đã tạo mã ưu đãi thành công!', isSuccess: true);
                        }
                      } catch (e) {
                        print('[ERROR-PARTNER-VOUCHER] Lỗi tạo Voucher: $e');
                        setModalState(() => isSubmitting = false);
                        if (mounted) {
                          AppToast.show(
                            context: context, 
                            message: e.toString().replaceAll('Exception: ', ''), 
                            isSuccess: false,
                            duration: const Duration(seconds: 4)
                          );
                        }
                      }
                    },
                    child: isSubmitting ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(isVip ? 'GỬI DUYỆT VOUCHER VIP' : 'TẠO MÃ ƯU ĐÃI', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      )
    );
  }

  Widget _buildModalTextField(String label, TextEditingController controller, {bool isNumber = false, bool isUpperCase = false, bool isEnabled = true}) {
    return TextField(
      controller: controller,
      enabled: isEnabled,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      textCapitalization: isUpperCase ? TextCapitalization.characters : TextCapitalization.none,
      style: TextStyle(color: isEnabled ? _textMain : _textSub, fontWeight: FontWeight.bold, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textSub, fontSize: 14),
        filled: true, 
        fillColor: isEnabled ? Colors.white : _bgLight, 
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _bizPrimary, width: 1.5)),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: _borderColor)),
      ),
    );
  }

  Widget _buildVouchersTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Mã Ưu Đãi', style: TextStyle(color: _textMain, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 4),
                Text('Quản lý các chương trình khuyến mãi', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
              onPressed: _showCreateVoucherModal,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tạo mới', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            )
          ],
        ),
        const SizedBox(height: 24),
        if (_vouchers.isEmpty) 
          Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('Bạn chưa có mã ưu đãi nào đang hoạt động.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500))))
        else 
          ..._vouchers.map((v) {
            final isPercentage = v['discount_type'] == 'PERCENTAGE';
            final discountText = isPercentage ? '${v['discount_value']}%' : _formatCurrency(v['discount_value']);
            final isVip = v['is_vip'] == true;
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(24), 
                border: Border.all(color: isVip ? const Color(0xFF1A3A35) : _borderColor, width: isVip ? 1.5 : 1.0), 
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isVip ? const Color(0xFF1A3A35) : _bgLight, 
                      borderRadius: BorderRadius.circular(16)
                    ),
                    child: Column(
                      children: [
                        Icon(isVip ? Icons.stars_rounded : Icons.local_activity_rounded, color: isVip ? const Color(0xFFFCD34D) : _bizPrimary, size: 28),
                        const SizedBox(height: 8),
                        Text(discountText, style: TextStyle(color: isVip ? Colors.white : _textMain, fontWeight: FontWeight.w900, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(v['code']?.toString().toUpperCase() ?? '', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1)),
                                if (isVip) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: const Color(0xFF1A3A35), borderRadius: BorderRadius.circular(6)),
                                    child: const Text('VIP', style: TextStyle(color: Color(0xFFFCD34D), fontSize: 9, fontWeight: FontWeight.w900)),
                                  ),
                                ],
                              ],
                            ),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: v['status'] == 'APPROVED' ? Colors.green.shade50 : v['status'] == 'REJECTED' ? Colors.red.shade50 : Colors.amber.shade50, borderRadius: BorderRadius.circular(8)), child: Text(v['status'] ?? 'PENDING', style: TextStyle(color: v['status'] == 'APPROVED' ? Colors.green.shade700 : v['status'] == 'REJECTED' ? Colors.redAccent : Colors.amber.shade700, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (isVip && v['point_price'] != null)
                          Text('Giá: ${NumberFormat.decimalPattern('vi_VN').format(v['point_price'])} điểm • Khung: ${v['fixed_time_slot'] ?? 'N/A'}', style: TextStyle(color: _bizPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
                        Text('Đã dùng: ${v['used_quantity'] ?? 0}/${v['total_quantity'] ?? 0}', style: TextStyle(color: _textSub, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text('HSD: ${_formatDate(v['valid_until'])}', style: TextStyle(color: _borderColor, fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  // ==========================================
  // TAB 6: DUYỆT AFFILIATE (QUEUE)
  // ==========================================
  Widget _buildAffiliateQueueTab() {
    int pendingCount = _affiliateQueue.length;
    int approvedCount = _affiliateMetrics.length;
    int totalConversions = 0;
    
    for (var m in _affiliateMetrics) {
      totalConversions += (int.tryParse(m['total_conversions']?.toString() ?? '0') ?? 0);
    }

    // XỬ LÝ DỮ LIỆU BIỂU ĐỒ 7 NGÀY QUA
    final now = DateTime.now();
    List<Map<String, dynamic>> chartData = [];
    int maxChartCount = 0;
    
    for (int i = 6; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
      final displayDate = DateFormat('dd/MM').format(targetDate);
      
      int count = 0;
      for (var b in _bookings) {
        if (b['payment_status'] == 'PAID' || b['service_status'] == 'COMPLETED') {
          final createdAt = b['created_at'];
          if (createdAt != null) {
            try {
              final bDate = DateTime.parse(createdAt.toString()).toLocal();
              if (DateFormat('yyyy-MM-dd').format(bDate) == dateStr) count++;
            } catch (_) {}
          }
        }
      }
      if (count > maxChartCount) maxChartCount = count;
      chartData.add({'label': displayDate, 'count': count});
    }
    if (maxChartCount == 0) maxChartCount = 1; // Tránh chia cho 0 khi render chiều cao

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THỐNG KÊ AFFILIATE TỔNG QUAN VỚI WATERMARK
        Row(
          children: [
            Expanded(child: _buildAffiliateStatCard('Chờ duyệt', pendingCount.toString(), Icons.hourglass_empty_rounded, Colors.amber.shade700)),
            const SizedBox(width: 12),
            Expanded(child: _buildAffiliateStatCard('Đang HĐ', approvedCount.toString(), Icons.check_circle_outline_rounded, _bizPrimary)),
            const SizedBox(width: 12),
            Expanded(child: _buildAffiliateStatCard('Đơn chốt', totalConversions.toString(), Icons.local_mall_outlined, Colors.blue.shade600)),
          ],
        ),
        const SizedBox(height: 24),

        // BIỂU ĐỒ BAR CHART 7 NGÀY
        Text('Hiệu suất chốt đơn (7 ngày qua)', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _borderColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: chartData.map((d) {
              final double heightRatio = (d['count'] as int) / maxChartCount;
              final isToday = d['label'] == DateFormat('dd/MM').format(now);
              
              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(d['count'] > 0 ? '${d['count']}' : '', style: TextStyle(color: isToday ? _bizPrimary : _textSub, fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Container(
                    width: 28,
                    height: (90 * heightRatio) + 4, // Chiều cao min = 4px
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isToday 
                          ? [_bizPrimary, _bizPrimary.withOpacity(0.5)] 
                          : [Colors.blue.shade200, Colors.blue.shade50]
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(d['label'], style: TextStyle(color: isToday ? _textMain : _textSub, fontSize: 10, fontWeight: isToday ? FontWeight.w900 : FontWeight.w600)),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),
        
        Text('Danh sách ứng tuyển', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 16),
        
        if (_affiliateQueue.isEmpty) 
          Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('Không có Creator nào đang ứng tuyển.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500))))
        else
          ..._affiliateQueue.map((req) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor)),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(radius: 24, backgroundImage: req['avatar_url'] != null ? NetworkImage(req['avatar_url']) : null, child: req['avatar_url'] == null ? const Icon(Icons.person) : null),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(req['full_name'] ?? 'Creator', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w800)),
                          Text('@${req['username']}', style: TextStyle(color: _textSub, fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      )
                    ),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)), child: Text('CHỜ DUYỆT', style: TextStyle(color: Colors.amber.shade700, fontSize: 9, fontWeight: FontWeight.w900))),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade50, foregroundColor: Colors.redAccent, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => _showRejectAffiliateDialog(req['partnership_id']), child: const Text('TỪ CHỐI', style: TextStyle(fontWeight: FontWeight.bold)))),
                    const SizedBox(width: 12),
                    Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: _bizPrimary, foregroundColor: Colors.white, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: () => _handleAffiliateAction(req['partnership_id'], 'APPROVED'), child: const Text('PHÊ DUYỆT', style: TextStyle(fontWeight: FontWeight.bold)))),
                  ],
                )
              ],
            ),
          )).toList(),
      ],
    );
  }

  Widget _buildAffiliateStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Stack(
        children: [
          // Watermark Icon chìm ở góc dưới cùng bên phải
          Positioned(
            right: -8,
            bottom: -8,
            child: Icon(icon, size: 54, color: color.withOpacity(0.15)),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 24, fontWeight: FontWeight.w900, height: 1)),
                const SizedBox(height: 6),
                Text(title.toUpperCase(), style: TextStyle(color: _textMain, fontSize: 10, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 7: HIỆU SUẤT AFFILIATE (METRICS)
  // ==========================================
  Widget _buildAffiliateMetricsTab() {
    double totalGMV = 0;
    double totalCommission = 0;
    int totalConversions = 0;

    for (var m in _affiliateMetrics) {
      totalGMV += (double.tryParse(m['total_revenue_generated']?.toString() ?? '0') ?? 0);
      totalCommission += (double.tryParse(m['total_commission_earned']?.toString() ?? '0') ?? 0);
      totalConversions += (int.tryParse(m['total_conversions']?.toString() ?? '0') ?? 0);
    }

    // Tiện ích format gọn để số tiền lớn không làm vỡ UI Card
    String shortFormat(double amount) {
      if (amount >= 1000000000) return '${(amount / 1000000000).toStringAsFixed(1)}Tỷ';
      if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(1)}Tr';
      if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
      return amount.toStringAsFixed(0);
    }

    // XỬ LÝ DỮ LIỆU BIỂU ĐỒ 7 NGÀY QUA (CHỈ ĐẾM ĐƠN AFFILIATE)
    final now = DateTime.now();
    List<Map<String, dynamic>> chartData = [];
    int maxChartCount = 0;

    for (int i = 6; i >= 0; i--) {
      final targetDate = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(targetDate);
      final displayDate = DateFormat('dd/MM').format(targetDate);

      int count = 0;
      for (var b in _bookings) {
        if (b['payment_status'] == 'PAID' || b['service_status'] == 'COMPLETED') {
          // Chỉ lấy các đơn có ghi nhận chia sẻ hoa hồng cho Affiliate
          final affiliateRev = double.tryParse(b['affiliate_revenue']?.toString() ?? '0') ?? 0;
          if (affiliateRev > 0) {
            final createdAt = b['created_at'];
            if (createdAt != null) {
              try {
                final bDate = DateTime.parse(createdAt.toString()).toLocal();
                if (DateFormat('yyyy-MM-dd').format(bDate) == dateStr) count++;
              } catch (_) {}
            }
          }
        }
      }
      if (count > maxChartCount) maxChartCount = count;
      chartData.add({'label': displayDate, 'count': count});
    }
    if (maxChartCount == 0) maxChartCount = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // THỐNG KÊ TỔNG QUAN
        Row(
          children: [
            Expanded(child: _buildAffiliateStatCard('Tổng GMV', shortFormat(totalGMV), Icons.account_balance_wallet_outlined, _bizPrimary)),
            const SizedBox(width: 12),
            Expanded(child: _buildAffiliateStatCard('Hoa hồng', shortFormat(totalCommission), Icons.monetization_on_outlined, Colors.amber.shade700)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildAffiliateStatCard('Tổng Đơn', totalConversions.toString(), Icons.local_mall_outlined, Colors.blue.shade600)),
            const SizedBox(width: 12),
            Expanded(child: _buildAffiliateStatCard('Đang HĐ', _affiliateMetrics.length.toString(), Icons.group_outlined, _bizSecondary)),
          ],
        ),
        const SizedBox(height: 24),

        // BIỂU ĐỒ BAR CHART 7 NGÀY
        Text('Đơn Affiliate chốt (7 ngày qua)', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 16),
        Container(
          height: 180,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _borderColor),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: chartData.map((d) {
              final double heightRatio = (d['count'] as int) / maxChartCount;
              final isToday = d['label'] == DateFormat('dd/MM').format(now);

              return Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(d['count'] > 0 ? '${d['count']}' : '', style: TextStyle(color: isToday ? Colors.amber.shade700 : _textSub, fontSize: 11, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Container(
                    width: 28,
                    height: (90 * heightRatio) + 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isToday 
                          ? [Colors.amber.shade500, Colors.amber.shade200] 
                          : [Colors.grey.shade300, Colors.grey.shade100]
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(d['label'], style: TextStyle(color: isToday ? _textMain : _textSub, fontSize: 10, fontWeight: isToday ? FontWeight.w900 : FontWeight.w600)),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        Text('Danh sách Affiliate', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 16),
        
        if (_affiliateMetrics.isEmpty) 
          Center(child: Padding(padding: const EdgeInsets.only(top: 40), child: Text('Chưa có Affiliate nào đang hoạt động.', style: TextStyle(color: _textSub, fontWeight: FontWeight.w500))))
        else
          ..._affiliateMetrics.map((m) => Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: _borderColor)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(m['creator_full_name'] ?? 'Creator', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                    Text('@${m['creator_username']}', style: TextStyle(color: _bizPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Đơn thành công', style: TextStyle(color: _textSub, fontSize: 11)), const SizedBox(height: 4), Text('${m['total_conversions'] ?? 0} Đơn', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900))]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Lượt Click link', style: TextStyle(color: _textSub, fontSize: 11)), const SizedBox(height: 4), Text('${m['total_clicks'] ?? 0}', style: TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.w900))]),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: _bgLight, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('GMV Mang Lại', style: TextStyle(color: _textSub, fontSize: 11)), const SizedBox(height: 4), Text(_formatCurrency(m['total_revenue_generated']), style: TextStyle(color: _bizPrimary, fontSize: 15, fontWeight: FontWeight.w900))])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text('Hoa Hồng Đã Trả', style: TextStyle(color: _textSub, fontSize: 11)), const SizedBox(height: 4), Text(_formatCurrency(m['total_commission_earned']), style: TextStyle(color: Colors.amber.shade700, fontSize: 15, fontWeight: FontWeight.w900))])),
                    ],
                  ),
                )
              ],
            ),
          )).toList(),
      ],
    );
  }

  // --- WIDGET HỖ TRỢ ---
  Widget _buildTabBtn(String key, String title, IconData icon) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(color: isActive ? _bizSecondary : Colors.transparent, borderRadius: BorderRadius.circular(24)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : _textSub),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: TextStyle(color: isActive ? Colors.white : _textSub, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), border: Border.all(color: _borderColor), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 16),
          Text(value, style: TextStyle(color: _textMain, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
          const SizedBox(height: 4),
          Text(title.toUpperCase(), style: TextStyle(color: _textSub, fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}