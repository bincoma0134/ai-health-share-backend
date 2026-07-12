import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/admin_api_service.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/shimmer_wrapper.dart';

class ModeratorDashboardScreen extends StatefulWidget {
  const ModeratorDashboardScreen({super.key});

  @override
  State<ModeratorDashboardScreen> createState() => _ModeratorDashboardScreenState();
}

class _ModeratorDashboardScreenState extends State<ModeratorDashboardScreen> {
  bool _isLoading = true;
  String _activeTab = 'overview'; // overview, queue, history
  String _queueFilter = 'all'; // all, service, video, delete, edit
  
  Map<String, dynamic> _stats = {};
  List<dynamic> _queue = [];
  List<dynamic> _history = [];

  final Color _modPrimary = const Color(0xFF8B5CF6); // Violet
  final Color _modDanger = const Color(0xFFF43F5E); // Rose
  bool _isProcessing = false; // Biến trạng thái xử lý API

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      AdminApiService.fetchModerationStats(),
      AdminApiService.fetchModerationQueue(),
      AdminApiService.fetchModerationHistory(),
    ]);

    if (mounted) {
      setState(() {
        _stats = (results[0] as Map<String, dynamic>?) ?? {'total_processed': 0, 'approved_count': 0, 'rejected_count': 0, 'chart_data': []};
        _queue = (results[1] as List<dynamic>?) ?? [];
        _history = (results[2] as List<dynamic>?) ?? [];
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(dynamic amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount ?? 0);
  }

  // --- MODAL KIỂM DUYỆT (Review Modal) ---
  void _showModerateModal(Map<String, dynamic> item, bool isHistory) {
    final noteCtrl = TextEditingController();
    bool showRejectInput = false;
    _isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final isPendingDelete = item['status'] == 'PENDING_DELETE';
          final isPendingUpdate = item['status'] == 'PENDING_UPDATE';
          final mediaUrl = item['media_url'] ?? item['video_url'] ?? item['image_url'];
          final isVideo = mediaUrl != null && mediaUrl.toString().contains('.mp4');

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundImage: NetworkImage(item['author']?['avatar_url'] ?? 'https://ui-avatars.com/api/?name=${item['author']?['full_name']}'), radius: 16),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['author']?['full_name'] ?? 'Ẩn danh', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
                              const Text('Tác giả', style: TextStyle(color: Colors.black54, fontSize: 10)),
                            ],
                          ),
                        ],
                      ),
                      IconButton(icon: const Icon(Icons.close, color: Colors.black54), onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                ),
                
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: Colors.black,
                    child: Stack(
                      children: [
                        if (mediaUrl != null)
                          isVideo ? MiniVideoPlayer(videoUrl: mediaUrl) : Center(child: Image.network(mediaUrl, fit: BoxFit.contain)),
                        if (isPendingDelete)
                          Container(color: _modDanger.withOpacity(0.3), child: Center(child: Icon(Icons.warning, color: _modDanger, size: 80))),
                      ],
                    ),
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: Text(item['title'] ?? '', style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w900))),
                          if (item['price'] != null) Text(_formatCurrency(item['price']), style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(item['description'] ?? 'Không có mô tả', style: const TextStyle(color: Colors.black54, fontSize: 12), maxLines: 3, overflow: TextOverflow.ellipsis),
                      
                      // Bổ sung: Thông tin liên kết thương mại (Affiliate) đối chiếu từ Website
                      if (item['type'] == 'video' && (item['linked_service'] != null || item['linked_partner'] != null || item['linked_voucher'] != null || (item['affiliate_rate'] != null && item['affiliate_rate'] > 0))) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.05), border: Border.all(color: Colors.deepPurple.withOpacity(0.1)), borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('THÔNG TIN LIÊN KẾT THƯƠNG MẠI', style: TextStyle(color: Colors.deepPurple, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (item['linked_partner'] != null)
                                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Đối tác: ${item['linked_partner']['full_name']} (@${item['linked_partner']['username']})', style: const TextStyle(color: Colors.black87, fontSize: 12))),
                              if (item['linked_service'] != null)
                                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Dịch vụ: ${item['linked_service']['service_name']} - ${_formatCurrency(item['linked_service']['price'])}', style: const TextStyle(color: Colors.black87, fontSize: 12))),
                              if (item['linked_voucher'] != null)
                                Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Voucher: ${item['linked_voucher']['code']}', style: const TextStyle(color: Colors.black87, fontSize: 12))),
                              if (item['affiliate_rate'] != null && item['affiliate_rate'] > 0)
                                Text('Hoa hồng: ${item['affiliate_rate']}%', style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        )
                      ],

                      if (isHistory && item['moderation_note'] != null && item['moderation_note'].toString().isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1), border: Border.all(color: Colors.amber.withOpacity(0.3)), borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('GHI CHÚ KIỂM DUYỆT CỦA BẠN', style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(item['moderation_note'], style: const TextStyle(color: Colors.black87, fontStyle: FontStyle.italic)),
                            ],
                          ),
                        )
                      ],

                      if (showRejectInput && !isHistory) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: noteCtrl,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(hintText: 'Nhập lý do từ chối (Bắt buộc)...', hintStyle: const TextStyle(color: Colors.black38), filled: true, fillColor: _modDanger.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _modDanger.withOpacity(0.5)))),
                        ),
                      ],
                    ],
                  ),
                ),

                if (!isHistory)
                  Padding(
                    padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
                    child: isPendingDelete 
                      ? Row(
                          children: [
                            Expanded(child: _buildActionButton('DUYỆT XÓA', _modDanger, _isProcessing, () => _handleAction(item, 'DELETED', noteCtrl.text, setModalState))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildActionButton('TỪ CHỐI XÓA', Colors.grey.shade300, _isProcessing, () => _handleAction(item, 'APPROVED', noteCtrl.text, setModalState), textColor: Colors.black87)),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: showRejectInput 
                                ? _buildActionButton('XÁC NHẬN TỪ CHỐI', _modDanger, _isProcessing, () => _handleAction(item, 'REJECTED', noteCtrl.text, setModalState))
                                : _buildActionButton('YÊU CẦU ĐIỀU CHỈNH', _modDanger.withOpacity(0.1), _isProcessing, () => setModalState(() => showRejectInput = true), textColor: _modDanger),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: _buildActionButton(isPendingUpdate ? 'DUYỆT BẢN SỬA' : 'PHÊ DUYỆT', _modPrimary, _isProcessing, () => _handleAction(item, 'APPROVED', '', setModalState), disabled: showRejectInput)),
                          ],
                        ),
                  )
              ],
            ),
          );
        }
      )
    );
  }

  Future<void> _handleAction(Map<String, dynamic> item, String action, String note, Function setModalState) async {
    if (action == 'REJECTED' && note.trim().isEmpty) {
      AppToast.show(context: context, message: 'Vui lòng nhập lý do từ chối!', isSuccess: false);
      return;
    }
    setModalState(() => _isProcessing = true);
    final success = await AdminApiService.moderateItem(item['type'], item['id'], action, note);
    if (success && mounted) {
      Navigator.pop(context);
      _loadAllData();
      AppToast.show(context: context, message: 'Đã $action thành công!', isSuccess: true);
    } else {
      setModalState(() => _isProcessing = false);
      AppToast.show(context: context, message: 'Lỗi xử lý!', isSuccess: false);
    }
  }

  Widget _buildActionButton(String label, Color color, bool isProcessing, VoidCallback onTap, {Color? textColor, bool disabled = false}) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: color, foregroundColor: textColor ?? Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        onPressed: (isProcessing || disabled) ? null : onTap,
        child: isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : Text(label, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA), // Light Mode Background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.05),
        title: Row(
          children: [
            Icon(Icons.shield, color: _modPrimary),
            const SizedBox(width: 8),
            const Text('Moderator Workspace', style: TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.black87), onPressed: _loadAllData),
        ],
      ),
      body: Column(
        children: [
          // THANH ĐIỀU HƯỚNG TABS
          Container(
            color: Colors.white,
            width: double.infinity,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _buildTab('overview', 'Tổng quan', Icons.dashboard),
                  _buildTab('queue', 'Hàng đợi (${_queue.length})', Icons.access_time),
                  _buildTab('history', 'Lịch sử', Icons.history),
                ],
              ),
            ),
          ),
          
          // NỘI DUNG TABS
          Expanded(
            child: _isLoading 
              ? ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: 5,
                  itemBuilder: (context, index) => ShimmerWrapper(
                    child: Container(
                      height: 100,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black12),
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: _modPrimary,
                  onRefresh: _loadAllData,
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
      case 'queue': return _buildQueueTab();
      case 'history': return _buildHistoryTab();
      default: return const SizedBox();
    }
  }

  // ==========================================
  // TAB 1: TỔNG QUAN
  // ==========================================
  Widget _buildOverviewTab() {
    int total = _stats['total_processed'] ?? 0;
    int approved = _stats['approved_count'] ?? 0;
    int rate = total > 0 ? ((approved / total) * 100).round() : 0;

    List<FlSpot> duyetSpots = [];
    List<FlSpot> tuChoiSpots = [];
    final chartData = _stats['chart_data'] as List<dynamic>? ?? [];
    for (int i = 0; i < chartData.length; i++) {
      duyetSpots.add(FlSpot(i.toDouble(), (chartData[i]['Duyệt'] ?? 0).toDouble()));
      tuChoiSpots.add(FlSpot(i.toDouble(), (chartData[i]['Từ chối'] ?? 0).toDouble()));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildMetricCard('Tồn đọng', '${_queue.length}', Icons.access_time, Colors.amber)),
            const SizedBox(width: 12),
            Expanded(child: _buildMetricCard('Đã xử lý', '$total', Icons.check_circle, Colors.green)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_modPrimary, _modPrimary.withOpacity(0.7)]), 
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: _modPrimary.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TỶ LỆ PHÊ DUYỆT (TRÊN TỔNG)', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
              Text('$rate%', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        
        const SizedBox(height: 32),
        const Text('BIỂU ĐỒ KIỂM DUYỆT (7 NGÀY)', style: TextStyle(color: Colors.black87, fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 1)),
        const SizedBox(height: 16),
        
        Container(
          height: 250,
          padding: const EdgeInsets.only(right: 16, top: 16),
          decoration: BoxDecoration(
            color: Colors.white, 
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: chartData.isEmpty ? const Center(child: Text('Chưa có dữ liệu', style: TextStyle(color: Colors.black54))) : LineChart(
            LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.black12, strokeWidth: 1, dashArray: [4, 4])),
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (val, meta) {
                  if (val.toInt() >= 0 && val.toInt() < chartData.length) return Text(chartData[val.toInt()]['date'], style: const TextStyle(color: Colors.black54, fontSize: 10));
                  return const SizedBox();
                })),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(spots: duyetSpots, isCurved: true, color: _modPrimary, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: _modPrimary.withOpacity(0.1))),
                LineChartBarData(spots: tuChoiSpots, isCurved: true, color: _modDanger, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: _modDanger.withOpacity(0.1))),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 2: HÀNG ĐỢI XỬ LÝ (QUEUE)
  // ==========================================
  Widget _buildQueueTab() {
    final filtered = _queue.where((q) {
      if (_queueFilter == 'service') return q['type'] == 'service';
      if (_queueFilter == 'video') return q['type'] == 'video';
      if (_queueFilter == 'voucher') return q['type'] == 'voucher';
      if (_queueFilter == 'delete') return q['status'] == 'PENDING_DELETE';
      if (_queueFilter == 'edit') return q['status'] == 'PENDING_UPDATE';
      return true;
    }).toList();

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              {'id': 'all', 'label': 'Tất cả'}, {'id': 'service', 'label': 'Dịch vụ'}, 
              {'id': 'video', 'label': 'Video'}, {'id': 'voucher', 'label': 'Voucher'},
              {'id': 'delete', 'label': 'Gỡ bỏ'}, {'id': 'edit', 'label': 'Cập nhật'}
            ].map((f) {
              final isActive = _queueFilter == f['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(f['label']!, style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
                  selected: isActive,
                  onSelected: (_) => setState(() => _queueFilter = f['id']!),
                  selectedColor: _modPrimary,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isActive ? _modPrimary : Colors.black12)),
                  showCheckmark: false,
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        
        if (filtered.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Text('Không có mục nào trong hàng đợi.', style: TextStyle(color: Colors.black54))))
        else
          ...filtered.map((item) => GestureDetector(
            onTap: () => _showModerateModal(item, false),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, 
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
              ),
              child: Row(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(color: item['type'] == 'voucher' ? Colors.deepPurple.withOpacity(0.1) : Colors.black12, borderRadius: BorderRadius.circular(12), image: item['image_url'] != null ? DecorationImage(image: NetworkImage(item['image_url']), fit: BoxFit.cover) : null),
                    child: item['type'] == 'voucher' 
                        ? const Icon(Icons.local_activity, color: Colors.deepPurple) 
                        : ((item['image_url'] == null && item['video_url'] != null) ? const Icon(Icons.play_circle, color: Colors.white) : null),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item['title'] ?? '', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text('Tác giả: ${item['author']?['full_name'] ?? 'Ẩn danh'}', style: const TextStyle(color: Colors.black54, fontSize: 10)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: item['status'].toString().contains('DELETE') ? _modDanger.withOpacity(0.1) : Colors.amber.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(item['status'].toString().split('_').last, style: TextStyle(color: item['status'].toString().contains('DELETE') ? _modDanger : Colors.amber.shade700, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                  )
                ],
              ),
            ),
          ))
      ],
    );
  }

  // ==========================================
  // TAB 3: LỊCH SỬ XỬ LÝ
  // ==========================================
  Widget _buildHistoryTab() {
    if (_history.isEmpty) return const Center(child: Text('Chưa có lịch sử xử lý.', style: TextStyle(color: Colors.black54)));

    return Column(
      children: _history.map((item) => GestureDetector(
        onTap: () => _showModerateModal(item, true),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white, 
            border: Border(left: BorderSide(color: item['status'] == 'APPROVED' ? Colors.green : _modDanger, width: 4)), 
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(child: Text(item['title'] ?? '', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Text(item['status'], style: TextStyle(color: item['status'] == 'APPROVED' ? Colors.green : _modDanger, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: 8),
              Text(item['moderation_note'] ?? 'Không có ghi chú', style: const TextStyle(color: Colors.black54, fontSize: 12, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      )).toList(),
    );
  }

  // --- WIDGET HỖ TRỢ ---
  Widget _buildTab(String key, String title, IconData icon) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? _modPrimary : Colors.white, 
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isActive ? _modPrimary : Colors.black12),
          boxShadow: isActive ? [BoxShadow(color: _modPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))] : [],
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? Colors.white : Colors.black54),
            const SizedBox(width: 8),
            Text(title.toUpperCase(), style: TextStyle(color: isActive ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(color: Colors.black87, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.black54, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}