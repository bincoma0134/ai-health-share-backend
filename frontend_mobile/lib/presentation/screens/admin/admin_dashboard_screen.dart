import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../data/services/admin_api_service.dart';
import '../../widgets/shimmer_wrapper.dart';
import '../../widgets/app_toast.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _isLoading = true;
  String _activeTab = 'overview'; // overview, finance, partners, audit
  
  Map<String, dynamic> _stats = {};
  List<dynamic> _withdrawals = [];
  List<dynamic> _partners = [];
  
  // State Tài chính
  String _withdrawalFilter = 'ALL';
  // State Đối tác
  String _partnerFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AdminApiService.fetchDashboardStats(),
      AdminApiService.fetchWithdrawals(),
      AdminApiService.fetchPartners(),
    ]);

    if (mounted) {
      setState(() {
        _stats = (results[0] as Map<String, dynamic>?) ?? {};
        _withdrawals = (results[1] as List<dynamic>?) ?? [];
        _partners = (results[2] as List<dynamic>?) ?? [];
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(dynamic amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount ?? 0);
  }

  // --- MODAL XỬ LÝ RÚT TIỀN ---
  void _showProcessWithdrawalModal(Map<String, dynamic> withdrawal) {
    final noteCtrl = TextEditingController();
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.85,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Xử lý Giải Ngân', style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Color(0xFF64748B)), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Khối thông tin
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFC7D2FE))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SỐ TIỀN CẦN CHUYỂN', style: TextStyle(color: Color(0xFF4F46E5), fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(_formatCurrency(withdrawal['amount']), style: const TextStyle(color: Color(0xFF4338CA), fontSize: 32, fontWeight: FontWeight.w900)),
                      const Divider(color: Color(0xFFC7D2FE), height: 24),
                      Text('Đối tác: ${withdrawal['users']?['full_name']}', style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
                      Text('Email: ${withdrawal['users']?['email']}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Bank Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE2E8F0))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('THÔNG TIN NGÂN HÀNG', style: TextStyle(color: Color(0xFFB45309), fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(withdrawal['payout_info'].toString(), style: const TextStyle(color: Color(0xFF334155), fontFamily: 'monospace', fontSize: 13)),
                    ],
                  ),
                ),
                
                if (withdrawal['status'] == 'PENDING') ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Color(0xFF1E293B)),
                    decoration: InputDecoration(hintText: 'Nhập mã giao dịch hoặc lý do từ chối...', hintStyle: const TextStyle(color: Color(0xFF94A3B8)), filled: true, fillColor: const Color(0xFFF8FAFC), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Color(0xFFE2E8F0)))),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xFFEF4444), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFCA5A5))), elevation: 0),
                          onPressed: isProcessing ? null : () async {
                            if (noteCtrl.text.isEmpty) {
                              AppToast.show(context: context, message: 'Vui lòng nhập lý do từ chối!', isSuccess: false);
                              return;
                            }
                            setModalState(() => isProcessing = true);
                            final ok = await AdminApiService.processWithdrawal(withdrawal['id'], 'REJECTED', noteCtrl.text);
                            if (ok && mounted) {
                              Navigator.pop(context);
                              _loadDashboardData();
                              AppToast.show(context: context, message: 'Đã từ chối lệnh rút tiền!', isSuccess: true);
                            }
                          },
                          child: const Text('TỪ CHỐI', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                          onPressed: isProcessing ? null : () async {
                            setModalState(() => isProcessing = true);
                            final ok = await AdminApiService.processWithdrawal(withdrawal['id'], 'COMPLETED', noteCtrl.text);
                            if (ok && mounted) {
                              Navigator.pop(context);
                              _loadDashboardData();
                              AppToast.show(context: context, message: 'Đã duyệt giải ngân thành công!', isSuccess: true);
                            }
                          },
                          child: isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('ĐÃ CHUYỂN TIỀN', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Spacer(),
                  Center(child: Text('Lệnh này đã được xử lý (${withdrawal['status']})', style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.bold))),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        title: const Row(
          children: [
            Icon(Icons.shield_rounded, color: Color(0xFFF59E0B)),
            SizedBox(width: 10),
            Text('Super Admin Center', style: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: _loadDashboardData),
        ],
      ),
      body: Column(
        children: [
          // THANH ĐIỀU HƯỚNG TABS SANG TRỌNG
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildTab('overview', 'Tổng quan', Icons.insights_rounded),
                  _buildTab('finance', 'Tài chính', Icons.account_balance_wallet_rounded),
                  _buildTab('partners', 'Đối tác', Icons.business_rounded),
                  _buildTab('audit', 'Giám sát', Icons.security_rounded),
                ],
              ),
            ),
          ),
          
          // NỘI DUNG TABS
          Expanded(
            child: _isLoading 
              ? _buildShimmerLoading()
              : RefreshIndicator(
                  color: const Color(0xFF6366F1),
                  onRefresh: _loadDashboardData,
                  // Loại bỏ lớp bao SingleChildScrollView để các Tab tự quyết định cơ chế Scroll lazy-load
                  child: _buildActiveTabContent(),
                ),
          )
        ],
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return ShimmerWrapper(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Container(height: 110, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
            const SizedBox(height: 12),
            Container(height: 110, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
            const SizedBox(height: 12),
            Container(height: 110, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24))),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Container(height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)))),
                const SizedBox(width: 12),
                Expanded(child: Container(height: 90, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)))),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 'overview': return _buildOverviewTab();
      case 'finance': return _buildFinanceTab();
      case 'partners': return _buildPartnersTab();
      case 'audit': return _buildAuditTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // TAB 1: TỔNG QUAN (SANG TRỌNG)
  // ==========================================
  Widget _buildOverviewTab() {
    List<FlSpot> gmvSpots = [];
    List<FlSpot> revSpots = [];
    final chartData = _stats['chart_data'] as List<dynamic>? ?? [];
    
    for (int i = 0; i < chartData.length; i++) {
      gmvSpots.add(FlSpot(i.toDouble(), (chartData[i]['GMV'] ?? 0).toDouble()));
      revSpots.add(FlSpot(i.toDouble(), (chartData[i]['Doanh thu'] ?? 0).toDouble()));
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16).copyWith(bottom: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBigMetricCard('TỔNG GIAO DỊCH (GMV)', _stats['gmv'], const Color(0xFF6366F1), Icons.trending_up_rounded),
        const SizedBox(height: 12),
        _buildBigMetricCard('DOANH THU NỀN TẢNG', _stats['platform_revenue'], const Color(0xFF10B981), Icons.attach_money_rounded),
        const SizedBox(height: 12),
        _buildBigMetricCard('QUỸ TẠM GIỮ (ESCROW)', _stats['escrow_holding'], const Color(0xFFF59E0B), Icons.account_balance_rounded),
        
        const SizedBox(height: 20),
        
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Người dùng', _stats['total_users'].toString(), Icons.people_rounded, const Color(0xFF0F172A))),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Đối tác', _stats['total_partners'].toString(), Icons.storefront_rounded, const Color(0xFF0F172A))),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Uptime', '99.9%', Icons.check_circle_rounded, const Color(0xFF10B981))),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Lệnh chờ', _stats['pending_withdrawals'].toString(), Icons.priority_high_rounded, const Color(0xFFEF4444))),
          ],
        ),

        const SizedBox(height: 32),
        const Text('HIỆU SUẤT TĂNG TRƯỞNG (7 NGÀY)', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 16),
        
        Container(
          height: 260,
          padding: const EdgeInsets.only(right: 16, top: 24, bottom: 8),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
          child: chartData.isEmpty ? const Center(child: Text('Đang khởi tạo dữ liệu...')) : LineChart(
            LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: const Color(0xFFF1F5F9), strokeWidth: 1)),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28, getTitlesWidget: (val, meta) {
                  if (val.toInt() >= 0 && val.toInt() < chartData.length) {
                    return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(chartData[val.toInt()]['date'], style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w600)));
                  }
                  return const SizedBox();
                })),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 45, getTitlesWidget: (val, meta) {
                  if (val == 0) return const SizedBox();
                  String text = val >= 1000000 ? '${(val/1000000).toStringAsFixed(0)}M' : '${(val/1000).toStringAsFixed(0)}K';
                  return Text(text, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.w600));
                })),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(spots: gmvSpots, isCurved: true, color: const Color(0xFF6366F1), barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: const Color(0xFF6366F1).withOpacity(0.05))),
                LineChartBarData(spots: revSpots, isCurved: true, color: const Color(0xFF10B981), barWidth: 4, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: const Color(0xFF10B981).withOpacity(0.05))),
              ],
            ),
          ),
        ),
      ],
    ),
    );
  }

  // ==========================================
  // TAB 2: TÀI CHÍNH (TỐI ƯU HOÁ MEMORY)
  // ==========================================
  Widget _buildFinanceTab() {
    final filteredWithdrawals = _withdrawals.where((w) => _withdrawalFilter == 'ALL' || w['status'] == _withdrawalFilter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'PENDING', 'COMPLETED', 'REJECTED'].map((filter) {
                final isActive = _withdrawalFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter == 'ALL' ? 'Tất cả' : filter, style: TextStyle(color: isActive ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w700, fontSize: 11)),
                    selected: isActive,
                    onSelected: (_) => setState(() => _withdrawalFilter = filter),
                    selectedColor: const Color(0xFF0F172A),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100), side: BorderSide(color: isActive ? Colors.transparent : const Color(0xFFE2E8F0))),
                    showCheckmark: false,
                    elevation: 0,
                    pressElevation: 0,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        Expanded(
          child: filteredWithdrawals.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('Không có dữ liệu giao dịch.', style: TextStyle(color: Color(0xFF94A3B8), fontWeight: FontWeight.w600))))])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 60),
                itemCount: filteredWithdrawals.length,
                itemBuilder: (context, index) {
                  final w = filteredWithdrawals[index];
                  return GestureDetector(
                    onTap: () => _showProcessWithdrawalModal(w),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: w['status'] == 'PENDING' ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))]),
                      child: Row(
                        children: [
                          Container(width: 48, height: 48, decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(12)), child: Center(child: Text(w['users']?['full_name']?.substring(0,1) ?? 'U', style: const TextStyle(color: Color(0xFF475569), fontWeight: FontWeight.w900, fontSize: 18)))),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(w['users']?['full_name'] ?? 'Chưa cập nhật', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(_formatCurrency(w['amount']), style: const TextStyle(color: Color(0xFF4F46E5), fontWeight: FontWeight.w900, fontSize: 16)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildStatusBadge(w['status']),
                              const SizedBox(height: 8),
                              const Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFCBD5E1), size: 12),
                            ],
                          )
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

  // ==========================================
  // TAB 3: ĐỐI TÁC (TỐI ƯU HIỆU NĂNG DANH SÁCH)
  // ==========================================
  Widget _buildPartnersTab() {
    final filteredPartners = _partners.where((p) => _partnerFilter == 'ALL' || p['role'] == _partnerFilter).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['ALL', 'PARTNER_ADMIN', 'CREATOR', 'MODERATOR'].map((filter) {
                final isActive = _partnerFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter == 'ALL' ? 'Tất cả' : filter.replaceAll('_ADMIN', ''), style: TextStyle(color: isActive ? Colors.white : const Color(0xFF475569), fontWeight: FontWeight.w700, fontSize: 11)),
                    selected: isActive,
                    onSelected: (_) => setState(() => _partnerFilter = filter),
                    selectedColor: const Color(0xFF0F172A),
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100), side: BorderSide(color: isActive ? Colors.transparent : const Color(0xFFE2E8F0))),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: filteredPartners.isEmpty
            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('Không có tài khoản nào được tìm thấy.', style: TextStyle(color: Color(0xFF94A3B8)))))])
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16).copyWith(bottom: 60),
                itemCount: filteredPartners.length,
                itemBuilder: (context, index) {
                  final p = filteredPartners[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE2E8F0))),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 24, backgroundImage: p['avatar_url'] != null ? NetworkImage(p['avatar_url']) : null, backgroundColor: const Color(0xFFF1F5F9), child: p['avatar_url'] == null ? Text(p['full_name']?.substring(0,1) ?? 'U', style: const TextStyle(color: Color(0xFF475569))) : null),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['full_name'] ?? 'Vô danh', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 14)),
                              Text(p['email'] ?? '', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                          child: Text(p['role'].replaceAll('_ADMIN', ''), style: const TextStyle(color: Color(0xFF475569), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                        ),
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 4: GIÁM SÁT (AUDIT)
  // ==========================================
  Widget _buildAuditTab() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16).copyWith(bottom: 60),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PHÂN TÍCH HỆ THỐNG', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Độ trễ API', '42ms', Icons.bolt_rounded, const Color(0xFF10B981))),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Database', 'Active', Icons.dns_rounded, const Color(0xFF10B981))),
          ],
        ),
        const SizedBox(height: 32),
        const Text('NHẬT KÝ HOẠT ĐỘNG GẦN ĐÂY', style: TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        const SizedBox(height: 16),
        
        ..._withdrawals.take(8).map((w) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border(left: BorderSide(color: w['status'] == 'PENDING' ? const Color(0xFFF59E0B) : const Color(0xFF10B981), width: 4))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Xử lý giải ngân: ${w['users']?['full_name']}', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Giá trị: ${_formatCurrency(w['amount'])}', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600)),
                  Text(w['status'], style: TextStyle(color: w['status'] == 'COMPLETED' ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        )),
      ],
    ),
    );
  }

  // --- COMPONENT HỖ TRỢ UI CAO CẤP ---
  Widget _buildTab(String key, String title, IconData icon) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: isActive ? const Color(0xFF0F172A) : Colors.transparent, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: isActive ? Colors.white : const Color(0xFF64748B), fontWeight: FontWeight.w700, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildBigMetricCard(String title, dynamic value, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: const Color(0xFF0F172A).withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4))]),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 24)),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text(_formatCurrency(value), style: const TextStyle(color: Color(0xFF0F172A), fontSize: 24, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(value, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color bg = const Color(0xFFF1F5F9);
    Color text = const Color(0xFF475569);
    
    if (status == 'COMPLETED') {
      bg = const Color(0xFFD1FAE5);
      text = const Color(0xFF065F46);
    } else if (status == 'PENDING') {
      bg = const Color(0xFFFEF3C7);
      text = const Color(0xFF92400E);
    } else if (status == 'REJECTED') {
      bg = const Color(0xFFFEE2E2);
      text = const Color(0xFF991B1B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(status, style: TextStyle(color: text, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
    );
  }
}