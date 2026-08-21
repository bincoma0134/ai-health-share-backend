import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/partner_tier_theme.dart';
import '../../../data/services/partner_api_service.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/partner_tier/partner_tier_badge.dart';

class PartnerAiContextScreen extends StatefulWidget {
  final String currentContext;

  const PartnerAiContextScreen({
    super.key,
    required this.currentContext,
  });

  @override
  State<PartnerAiContextScreen> createState() => _PartnerAiContextScreenState();
}

class _PartnerAiContextScreenState extends State<PartnerAiContextScreen> {
  late TextEditingController _contextController;
  bool _isSaving = false;
  bool _isLoadingTier = true;

  bool _isPremium = false;
  String _premiumTier = 'STANDARD';
  int _maxCharLimit = 2000;

  @override
  void initState() {
    super.initState();
    _contextController = TextEditingController(text: widget.currentContext);
    _contextController.addListener(() => setState(() {}));
    _fetchTierStatus();
  }

  Future<void> _fetchTierStatus() async {
    try {
      final status = await PartnerApiService.fetchPremiumStatus();
      if (status != null && mounted) {
        setState(() {
          _isPremium = status['is_premium'] == true;
          _premiumTier = (status['premium_tier'] ?? 'STANDARD').toString().toUpperCase();
          if (_isPremium) {
            if (_premiumTier == 'DIAMOND') {
              _maxCharLimit = 10000;
            } else if (_premiumTier == 'PRO') {
              _maxCharLimit = 5000;
            }
          }
          _isLoadingTier = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('[DEBUG-AI-CONTEXT-TIER-ERR] $e');
    }
    if (mounted) setState(() => _isLoadingTier = false);
  }

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _saveContext() async {
    final text = _contextController.text.trim();

    if (text.length > _maxCharLimit) {
      AppToast.show(
        context: context, 
        message: 'Nội dung vượt quá giới hạn ${_maxCharLimit.toString()} ký tự của gói hiện tại!', 
        isSuccess: false
      );
      return;
    }

    setState(() => _isSaving = true);
    print('[DEBUG-AI-CONTEXT-SAVE] Đang lưu định hướng AI (${text.length}/$_maxCharLimit ký tự) | Tier: $_premiumTier');

    try {
      final res = await ApiClient.instance.put(
        '/partner/ai-context',
        data: {'partner_ai_context': text},
      );

      if (res.statusCode == 200 && res.data['status'] == 'success') {
        if (mounted) {
          AppToast.show(context: context, message: 'Đã cập nhật định hướng AI thành công!', isSuccess: true);
          Navigator.pop(context, true);
        }
      } else {
        final String err = res.data?['detail'] ?? 'Lỗi cập nhật. Vui lòng thử lại!';
        if (mounted) AppToast.show(context: context, message: err, isSuccess: false);
      }
    } catch (e) {
      debugPrint('[DEBUG-AI-CONTEXT-SAVE-EXCEPTION] $e');
      if (mounted) {
        AppToast.show(context: context, message: 'Lỗi đường truyền hoặc vượt quá hạn mức gói!', isSuccess: false);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = PartnerTierTheme.fromTier(_isPremium, _premiumTier);
    final int currentLength = _contextController.text.length;
    final double usageRatio = (currentLength / _maxCharLimit).clamp(0.0, 1.0);
    final bool isOverLimit = currentLength > _maxCharLimit;

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAF8), // Apple Wellness Light
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF14302B), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Định Hướng AI Cơ Sở',
              style: TextStyle(color: Color(0xFF14302B), fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
            const SizedBox(width: 8),
            PartnerTierBadge(isPremium: _isPremium, premiumTier: _premiumTier, isCompact: true),
          ],
        ),
        centerTitle: true,
      ),
      body: _isLoadingTier
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2E6F65)))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🚀 BANNER ĐẶC QUYỀN HỘI VIÊN ĐƯỢC THIẾT KẾ THEO CHUẨN TIER
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _isPremium ? theme.badgeBgColor : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _isPremium ? theme.primaryColor.withValues(alpha: 0.35) : const Color(0xFFE2ECE9),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isPremium ? theme.primaryColor : const Color(0xFF14302B)).withValues(alpha: 0.05),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.primaryColor.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(theme.icon, color: theme.primaryColor, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPremium ? 'Hạn Mức Ngữ Cảnh ${theme.label.toUpperCase()}' : 'Hạn Mức Tiêu Chuẩn',
                                    style: TextStyle(
                                      color: _isPremium ? theme.textColor : const Color(0xFF14302B),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Khả dụng: ${_maxCharLimit.toString()} ký tự sâu',
                                    style: TextStyle(color: const Color(0xFF6B8782), fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                            if (!_isPremium || _premiumTier == 'PRO')
                              TextButton(
                                onPressed: () => context.push('/partner/membership').then((_) => _fetchTierStatus()),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  backgroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.4)),
                                  ),
                                ),
                                child: Text(
                                  _isPremium ? 'Nâng VIP 10k' : 'Mở rộng 10k',
                                  style: TextStyle(color: theme.primaryColor, fontSize: 11, fontWeight: FontWeight.w800),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFEAEFEF)),
                        const SizedBox(height: 12),
                        const Text(
                          'AI sẽ kết hợp toàn bộ tri thức này cùng danh mục Dịch vụ và Voucher để trở thành Trợ lý 24/7 tư vấn chuẩn y khoa cho khách hàng.',
                          style: TextStyle(color: Color(0xFF5A7570), fontSize: 12.5, height: 1.45, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Thanh tiến trình đo đạc dung lượng ngữ cảnh
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Nội dung tài liệu chuyên sâu',
                        style: TextStyle(color: Color(0xFF14302B), fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                      Text(
                        '$currentLength / $_maxCharLimit ký tự',
                        style: TextStyle(
                          color: isOverLimit ? Colors.redAccent : (usageRatio > 0.85 ? Colors.amber.shade800 : const Color(0xFF6B8782)),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usageRatio,
                      minHeight: 5,
                      backgroundColor: const Color(0xFFE2ECE9),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isOverLimit ? Colors.redAccent : theme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Khung nhập liệu Frosted Glass
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isOverLimit ? Colors.redAccent : const Color(0xFFE2ECE9),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF14302B).withValues(alpha: 0.03),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _contextController,
                      maxLines: 15,
                      style: const TextStyle(color: Color(0xFF14302B), fontSize: 14, height: 1.55, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Nhập đầy đủ thông tin chuyên sâu của cơ sở: phác đồ điều trị, lưu ý trước khi thăm khám, phong cách tư vấn, hướng dẫn đỗ xe, cam kết bảo mật y tế...',
                        hintStyle: TextStyle(color: const Color(0xFF14302B).withValues(alpha: 0.35), fontSize: 13, height: 1.4),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 24.0, right: 24.0, bottom: 20.0),
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isPremium
                    ? theme.gradientBorderColors
                    : const [Color(0xFF14302B), Color(0xFF234E46)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: (_isPremium ? theme.primaryColor : const Color(0xFF14302B)).withValues(alpha: 0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: _isSaving ? null : _saveContext,
              child: _isSaving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.save_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'LƯU ĐỊNH HƯỚNG AI',
                          style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}