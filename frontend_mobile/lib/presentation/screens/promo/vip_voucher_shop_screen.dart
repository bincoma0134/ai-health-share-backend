import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/voucher_model.dart';
import '../../../data/services/voucher_api_service.dart';
import '../../../data/services/wallet_api_service.dart';
import '../../widgets/app_toast.dart';
import 'package:go_router/go_router.dart';

class VipVoucherShopScreen extends StatefulWidget {
  const VipVoucherShopScreen({super.key});

  @override
  State<VipVoucherShopScreen> createState() => _VipVoucherShopScreenState();
}

class _VipVoucherShopScreenState extends State<VipVoucherShopScreen> with TickerProviderStateMixin {
  final NumberFormat _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  List<VoucherModel> _vouchers = [];
  bool _isLoading = true;
  double _pointsBalance = 0.0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final vRes = await VoucherApiService.getPublicVipVouchers();
      final wRes = await WalletApiService.getWallet();
      if (mounted) {
        setState(() {
          _vouchers = vRes;
          _pointsBalance = wRes?.pointsBalance ?? 0.0;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Mini Popup Xem chi tiết
  void _showVoucherDetailsModal(VoucherModel voucher) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.black45, size: 20),
              ),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFE2C55), borderRadius: BorderRadius.circular(8)),
                child: const Text('VOUCHER VIP', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                voucher.discountType == 'PERCENTAGE' ? 'Giảm ${voucher.discountValue.toInt()}%' : 'Giảm ${_currencyFormat.format(voucher.discountValue)}',
                style: const TextStyle(color: Color(0xFF1A3A35), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
              ),
            ),
            const SizedBox(height: 24),
            _buildDetailRow('Cơ sở', voucher.partnerName ?? 'N/A'),
            const Divider(color: Colors.black12, height: 24),
            _buildDetailRow('Khung giờ cố định', voucher.fixedTimeSlot ?? 'N/A', valueColor: const Color(0xFF4C8D50)),
            const Divider(color: Colors.black12, height: 24),
            _buildDetailRow('Số lượng còn', '${voucher.totalQuantity - voucher.usedQuantity}/${voucher.totalQuantity}'),
            const Divider(color: Colors.black12, height: 24),
            _buildDetailRow('Giá', '${NumberFormat.decimalPattern('vi_VN').format(voucher.pointPrice)} Điểm', valueColor: Colors.amber.shade800),
            if (voucher.description != null && voucher.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(12)),
                child: Text(voucher.description!, style: const TextStyle(fontSize: 12, color: Colors.black54, fontStyle: FontStyle.italic)),
              ),
            ],
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF4F7F6), foregroundColor: const Color(0xFF1A3A35),
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(vertical: 12)
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      if (voucher.partnerUsername != null) GoRouter.of(context).push('/public-profile/${voucher.partnerUsername}');
                    },
                    child: const Text('Xem cơ sở', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35), foregroundColor: Colors.white,
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), padding: const EdgeInsets.symmetric(vertical: 12)
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _showCheckoutBottomSheet(voucher);
                    },
                    child: const Text('Mua ngay', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color valueColor = Colors.black87}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(fontSize: 13, color: valueColor, fontWeight: FontWeight.bold)),
      ],
    );
  }

  // BottomSheet Hóa đơn thanh toán & Animation Apple Tick
  void _showCheckoutBottomSheet(VoucherModel voucher) {
    bool isProcessing = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          final double remain = _pointsBalance - voucher.pointPrice;
          
          return Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 48, height: 5, margin: const EdgeInsets.only(bottom: 24), decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)))),
                const Text('Thanh toán Voucher VIP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF1A3A35))),
                const SizedBox(height: 24),
                
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    children: [
                      _buildDetailRow('Số dư hiện tại', '${NumberFormat.decimalPattern('vi_VN').format(_pointsBalance)} Điểm'),
                      const Divider(color: Colors.black12, height: 24),
                      _buildDetailRow('Giá Voucher', '-${NumberFormat.decimalPattern('vi_VN').format(voucher.pointPrice)} Điểm', valueColor: Colors.red),
                      const Divider(color: Colors.black12, height: 24),
                      _buildDetailRow('Số dư còn lại', '${NumberFormat.decimalPattern('vi_VN').format(remain)} Điểm', valueColor: remain < 0 ? Colors.red : const Color(0xFF4C8D50)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                SizedBox(
                  width: double.infinity, height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1A3A35), foregroundColor: Colors.white,
                      elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    ),
                    onPressed: isProcessing ? null : () async {
                      if (remain < 0) { AppToast.show(context: context, message: 'Số dư điểm không đủ!', isSuccess: false); return; }
                      
                      setModalState(() => isProcessing = true);
                      try {
                        final success = await VoucherApiService.buyVoucherWithPoints(voucher.code);
                        if (success) {
                          Navigator.pop(context); // Đóng BottomSheet thanh toán
                          _showSuccessAppleTick(voucher); // Mở popup animation
                          _loadData(); // Tải lại dữ liệu trang
                        }
                      } catch (e) {
                        AppToast.show(context: context, message: e.toString(), isSuccess: false);
                      } finally {
                        if (context.mounted) setModalState(() => isProcessing = false);
                      }
                    },
                    child: isProcessing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('XÁC NHẬN THANH TOÁN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                )
              ],
            ),
          );
        },
      )
    );
  }

  // Animation Apple Tick mềm mại
  void _showSuccessAppleTick(VoucherModel voucher) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _AppleTickAnimationDialog(),
    ).then((_) {
      // Sau khi Animation chạy xong (2 giây), bật Popup tùy chọn
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: Colors.white,
          title: const Text('Thanh toán thành công!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF1A3A35)), textAlign: TextAlign.center),
          content: Text('Bạn đã sở hữu Voucher [${voucher.code}] cho khung giờ ${voucher.fixedTimeSlot}.', style: const TextStyle(fontSize: 13, color: Colors.black54), textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Để sau', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () {
                Navigator.pop(context);
                if (voucher.partnerUsername != null) GoRouter.of(context).push('/public-profile/${voucher.partnerUsername}');
              },
              child: const Text('Sử dụng ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            )
          ],
        )
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredVouchers = _searchQuery.isEmpty 
        ? _vouchers 
        : _vouchers.where((v) => (v.partnerName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) || v.code.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF1A3A35), size: 20), onPressed: () => Navigator.pop(context)),
        title: const Text('Shop VIP Voucher', style: TextStyle(color: Color(0xFF1A3A35), fontSize: 18, fontWeight: FontWeight.w900)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(color: const Color(0xFFF4F7F6), borderRadius: BorderRadius.circular(14)),
                    child: TextField(
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Tìm cơ sở, mã voucher...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.black38),
                        prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.black38),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: const Color(0xFF1A3A35), borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    children: [
                      const Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 6),
                      Text(NumberFormat.decimalPattern('vi_VN').format(_pointsBalance), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              ],
            ),
          ),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3A35)))
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              physics: const BouncingScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 0.75
              ),
              itemCount: filteredVouchers.length,
              itemBuilder: (context, index) {
                final v = filteredVouchers[index];
                return GestureDetector(
                  onTap: () => _showVoucherDetailsModal(v),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 4))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 80, width: double.infinity,
                          decoration: const BoxDecoration(color: Color(0xFF1A3A35), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          child: Stack(
                            children: [
                              Positioned(right: -10, top: -10, child: Icon(Icons.stars_rounded, size: 70, color: Colors.white.withOpacity(0.05))),
                              Center(child: Text(v.discountType == 'PERCENTAGE' ? '-${v.discountValue.toInt()}%' : '-${_currencyFormat.format(v.discountValue)}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(v.partnerName ?? 'VIP', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.access_time_rounded, size: 12, color: Colors.black45),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(v.fixedTimeSlot ?? '', style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                child: Text('${NumberFormat.decimalPattern('vi_VN').format(v.pointPrice)} Điểm', style: TextStyle(color: Colors.amber.shade900, fontSize: 11, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Widget Animation Riêng
class _AppleTickAnimationDialog extends StatefulWidget {
  const _AppleTickAnimationDialog();
  @override State<_AppleTickAnimationDialog> createState() => _AppleTickAnimationDialogState();
}

class _AppleTickAnimationDialogState extends State<_AppleTickAnimationDialog> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _scale = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent, elevation: 0,
      child: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 120, height: 120,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 80),
          ),
        ),
      ),
    );
  }
}