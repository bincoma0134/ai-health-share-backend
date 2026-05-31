import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../data/services/admin_api_service.dart';

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
            decoration: const BoxDecoration(color: Color(0xFF121214), borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Xử lý Giải Ngân', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.pop(context)),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Khối thông tin
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.pinkAccent.withOpacity(0.3))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('SỐ TIỀN CẦN CHUYỂN', style: TextStyle(color: Colors.pinkAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                      Text(_formatCurrency(withdrawal['amount']), style: const TextStyle(color: Colors.pinkAccent, fontSize: 32, fontWeight: FontWeight.w900)),
                      const Divider(color: Colors.white10, height: 24),
                      Text('Đối tác: ${withdrawal['users']?['full_name']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('Email: ${withdrawal['users']?['email']}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Bank Info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('THÔNG TIN NGÂN HÀNG', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text(withdrawal['payout_info'].toString(), style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13)),
                    ],
                  ),
                ),
                
                if (withdrawal['status'] == 'PENDING') ...[
                  const SizedBox(height: 24),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(hintText: 'Nhập mã giao dịch hoặc lý do từ chối...', hintStyle: const TextStyle(color: Colors.white30), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.transparent, foregroundColor: Colors.pinkAccent, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.pinkAccent))),
                          onPressed: isProcessing ? null : () async {
                            if (noteCtrl.text.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập lý do từ chối!')));
                              return;
                            }
                            setModalState(() => isProcessing = true);
                            final ok = await AdminApiService.processWithdrawal(withdrawal['id'], 'REJECTED', noteCtrl.text);
                            if (ok && mounted) {
                              Navigator.pop(context);
                              _loadDashboardData();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã từ chối lệnh!'), backgroundColor: Colors.pinkAccent));
                            }
                          },
                          child: const Text('TỪ CHỐI', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: isProcessing ? null : () async {
                            setModalState(() => isProcessing = true);
                            final ok = await AdminApiService.processWithdrawal(withdrawal['id'], 'COMPLETED', noteCtrl.text);
                            if (ok && mounted) {
                              Navigator.pop(context);
                              _loadDashboardData();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã duyệt thành công!'), backgroundColor: Colors.green));
                            }
                          },
                          child: isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Text('ĐÃ CHUYỂN TIỀN', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  const Spacer(),
                  Center(child: Text('Lệnh này đã được xử lý (${withdrawal['status']})', style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold))),
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
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090b),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.amber),
            SizedBox(width: 8),
            Text('Super Admin Center', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadDashboardData),
        ],
      ),
      body: Column(
        children: [
          // THANH ĐIỀU HƯỚNG TABS NGANG
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildTab('overview', 'Tổng quan', Icons.bar_chart),
                _buildTab('finance', 'Tài chính', Icons.account_balance_wallet),
                _buildTab('partners', 'Đối tác', Icons.business),
                _buildTab('audit', 'Giám sát', Icons.security),
              ],
            ),
          ),
          
          // NỘI DUNG TABS
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator(color: Colors.amber))
              : RefreshIndicator(
                  color: Colors.amber,
                  onRefresh: _loadDashboardData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16).copyWith(bottom: 40),
                    child: _buildActiveTabContent(),
                  ),
                ),
          )
        ],
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
  // TAB 1: TỔNG QUAN (OVERVIEW)
  // ==========================================
  Widget _buildOverviewTab() {
    // Xử lý dữ liệu biểu đồ
    List<FlSpot> gmvSpots = [];
    List<FlSpot> revSpots = [];
    final chartData = _stats['chart_data'] as List<dynamic>? ?? [];
    
    for (int i = 0; i < chartData.length; i++) {
      gmvSpots.add(FlSpot(i.toDouble(), (chartData[i]['GMV'] ?? 0).toDouble()));
      revSpots.add(FlSpot(i.toDouble(), (chartData[i]['Doanh thu'] ?? 0).toDouble()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 3 Thẻ Chỉ số Tài chính Lớn
        _buildBigMetricCard('TỔNG GIAO DỊCH (GMV)', _stats['gmv'], Colors.amber, Icons.trending_up),
        const SizedBox(height: 16),
        _buildBigMetricCard('DOANH THU NỀN TẢNG', _stats['platform_revenue'], Colors.green, Icons.attach_money),
        const SizedBox(height: 16),
        _buildBigMetricCard('QUỸ TẠM GIỮ (ESCROW)', _stats['escrow_holding'], Colors.blue, Icons.account_balance),
        
        const SizedBox(height: 24),
        
        // 4 Thẻ Chỉ số Nhỏ
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Người dùng', _stats['total_users'].toString(), Icons.people, Colors.white54)),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Đối tác', _stats['total_partners'].toString(), Icons.business, Colors.white54)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Uptime', '99.9%', Icons.check_circle, Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Lệnh chờ', _stats['pending_withdrawals'].toString(), Icons.warning, Colors.amber)),
          ],
        ),

        const SizedBox(height: 32),
        const Text('BIỂU ĐỒ DÒNG TIỀN (7 NGÀY)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 16),
        
        // Biểu đồ Vùng (Area Chart)
        Container(
          height: 250,
          padding: const EdgeInsets.only(right: 16, top: 16),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)),
          child: chartData.isEmpty ? const Center(child: Text('Chưa có dữ liệu')) : LineChart(
            LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white10, strokeWidth: 1, dashArray: [4, 4])),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (val, meta) {
                  if (val.toInt() >= 0 && val.toInt() < chartData.length) {
                    return Text(chartData[val.toInt()]['date'], style: const TextStyle(color: Colors.white54, fontSize: 10));
                  }
                  return const SizedBox();
                })),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (val, meta) {
                  if (val == 0) return const SizedBox();
                  String text = val >= 1000000 ? '${(val/1000000).toStringAsFixed(0)}M' : '${(val/1000).toStringAsFixed(0)}K';
                  return Text(text, style: const TextStyle(color: Colors.white54, fontSize: 10));
                })),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(spots: gmvSpots, isCurved: true, color: Colors.amber, barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.amber.withOpacity(0.1))),
                LineChartBarData(spots: revSpots, isCurved: true, color: Colors.green, barWidth: 3, isStrokeCapRound: true, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.green.withOpacity(0.1))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: TÀI CHÍNH (FINANCE)
  // ==========================================
  Widget _buildFinanceTab() {
    final filteredWithdrawals = _withdrawals.where((w) => _withdrawalFilter == 'ALL' || w['status'] == _withdrawalFilter).toList();

    return Column(
      children: [
        // Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['ALL', 'PENDING', 'COMPLETED', 'REJECTED'].map((filter) {
              final isActive = _withdrawalFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter == 'ALL' ? 'Tất cả' : filter, style: TextStyle(color: isActive ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  selected: isActive,
                  onSelected: (_) => setState(() => _withdrawalFilter = filter),
                  selectedColor: Colors.amber,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        
        // List
        if (filteredWithdrawals.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Không có lệnh giải ngân nào.', style: TextStyle(color: Colors.white54))))
        else
          ...filteredWithdrawals.map((w) => GestureDetector(
            onTap: () => _showProcessWithdrawalModal(w),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20), border: Border.all(color: w['status'] == 'PENDING' ? Colors.amber.withOpacity(0.5) : Colors.white10)),
              child: Row(
                children: [
                  CircleAvatar(backgroundColor: Colors.white10, child: Text(w['users']?['full_name']?.substring(0,1) ?? 'U', style: const TextStyle(color: Colors.white))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w['users']?['full_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text(_formatCurrency(w['amount']), style: const TextStyle(color: Colors.pinkAccent, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: w['status'] == 'COMPLETED' ? Colors.green.withOpacity(0.2) : w['status'] == 'REJECTED' ? Colors.pinkAccent.withOpacity(0.2) : Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                        child: Text(w['status'], style: TextStyle(color: w['status'] == 'COMPLETED' ? Colors.green : w['status'] == 'REJECTED' ? Colors.pinkAccent : Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 8),
                      const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
                    ],
                  )
                ],
              ),
            ),
          ))
      ],
    );
  }

  // ==========================================
  // TAB 3: ĐỐI TÁC (PARTNERS)
  // ==========================================
  Widget _buildPartnersTab() {
    final filteredPartners = _partners.where((p) => _partnerFilter == 'ALL' || p['role'] == _partnerFilter).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['ALL', 'PARTNER_ADMIN', 'CREATOR', 'MODERATOR'].map((filter) {
              final isActive = _partnerFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(filter == 'ALL' ? 'Tất cả' : filter.replaceAll('_ADMIN', ''), style: TextStyle(color: isActive ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  selected: isActive,
                  onSelected: (_) => setState(() => _partnerFilter = filter),
                  selectedColor: Colors.amber,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),

        if (filteredPartners.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Không có tài khoản nào.', style: TextStyle(color: Colors.white54))))
        else
          ...filteredPartners.map((p) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                CircleAvatar(backgroundImage: p['avatar_url'] != null ? NetworkImage(p['avatar_url']) : null, backgroundColor: Colors.white10, child: p['avatar_url'] == null ? Text(p['full_name']?.substring(0,1) ?? 'U', style: const TextStyle(color: Colors.white)) : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['full_name'] ?? 'Vô danh', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text(p['email'] ?? '', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                  child: Text(p['role'].replaceAll('_ADMIN', ''), style: const TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ),
              ],
            ),
          ))
      ],
    );
  }

  // ==========================================
  // TAB 4: GIÁM SÁT (AUDIT)
  // ==========================================
  Widget _buildAuditTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TRẠNG THÁI HẠ TẦNG', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildSmallMetricCard('Độ trễ API', '42ms', Icons.network_ping, Colors.green)),
            const SizedBox(width: 12),
            Expanded(child: _buildSmallMetricCard('Database', 'Active', Icons.storage, Colors.green)),
          ],
        ),
        const SizedBox(height: 32),
        const Text('NHẬT KÝ HỆ THỐNG MỚI NHẤT', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 16),
        
        ..._withdrawals.take(5).map((w) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.02), borderRadius: BorderRadius.circular(12), border: Border(left: BorderSide(color: w['status'] == 'PENDING' ? Colors.amber : Colors.green, width: 3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Yêu cầu giải ngân từ ${w['users']?['full_name']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              Text('Số tiền: ${_formatCurrency(w['amount'])} - Trạng thái: ${w['status']}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
            ],
          ),
        )),
      ],
    );
  }

  // --- COMPONENT HỖ TRỢ UI ---
  Widget _buildTab(String key, String title, IconData icon) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isActive ? Colors.amber : Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.black : Colors.white54),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: TextStyle(color: isActive ? Colors.black : Colors.white54, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildBigMetricCard(String title, dynamic value, Color color, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [color.withOpacity(0.2), Colors.transparent], begin: Alignment.topLeft, end: Alignment.bottomRight), border: Border.all(color: color.withOpacity(0.3)), borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color, size: 16), const SizedBox(width: 8), Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          Text(_formatCurrency(value), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Widget _buildSmallMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}