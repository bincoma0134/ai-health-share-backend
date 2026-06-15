import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/user_api_service.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/app_toast.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/booking_bottom_sheet.dart';
import '../../widgets/auth_guard.dart';

class PublicProfileScreen extends StatefulWidget {
  final String username;
  const PublicProfileScreen({super.key, required this.username});

  @override
  State<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends State<PublicProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _data;
  
  bool _isFollowing = false;
  int _followersCount = 0;
  
  String _activeTab = 'services'; // services | videos
  
  // State Đặt lịch (Escrow Flow)
  Map<String, dynamic>? _selectedService;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<dynamic> _fetchedVideos = [];
  List<dynamic> _fetchedServices = [];
  List<dynamic> _fetchedVouchers = [];

  Future<void> _loadData() async {
    final profileResult = await UserApiService.fetchPublicProfile(widget.username);
    if (profileResult != null && profileResult['profile'] != null) {
      final String userId = profileResult['profile']['id'] ?? '';
      
      // Kích hoạt song song các luồng dữ liệu độc lập theo API chuẩn hóa từ Web
      final dataFutures = await Future.wait([
        UserApiService.fetchUserServices(userId),
        UserApiService.fetchUserFeeds(userId),
      ]);

      if (mounted) {
        setState(() {
          _data = profileResult;
          _fetchedServices = dataFutures[0];
          _fetchedVideos = dataFutures[1];
          _fetchedVouchers = profileResult['vouchers'] ?? [
            {
              'id': 'v1',
              'code': 'HEALTH20',
              'discount_type': 'PERCENTAGE',
              'discount_value': 20,
              'min_order_value': 500000,
              'issuer_type': 'PARTNER',
              'valid_until': '2026-12-31'
            },
            {
              'id': 'v2',
              'code': 'AIHEALTH10K',
              'discount_type': 'FIXED',
              'discount_value': 10000,
              'min_order_value': 200000,
              'issuer_type': 'ADMIN',
              'valid_until': '2026-08-30'
            }
          ];
          _isFollowing = profileResult['is_followed'] ?? false;
          _followersCount = profileResult['stats']?['followers_count'] ?? 0;
          
          final String fetchedRole = profileResult['profile']['role'] ?? 'USER';
          if (fetchedRole == 'SUPER_ADMIN' || fetchedRole == 'ADMIN') {
            _activeTab = 'activities';
          } else if (fetchedRole == 'MODERATOR') {
            _activeTab = 'liked';
          } else if (fetchedRole == 'PARTNER' || fetchedRole == 'PARTNER_ADMIN') {
            _activeTab = 'services';
          } else {
            _activeTab = 'videos';
          }
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _data = null;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleToggleFollow() async {
    if (_data == null) return;
    setState(() {
      _isFollowing = !_isFollowing;
      _followersCount += _isFollowing ? 1 : -1;
    });

    final success = await UserApiService.toggleFollow(_data!['profile']['id']);
    if (success && mounted) {
      AppToast.show(
        context: context,
        message: _isFollowing ? 'Đã thêm vào danh sách quan tâm thành công!' : 'Đã hủy quan tâm người dùng.',
        isSuccess: true,
      );
    } else if (!success && mounted) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount += _isFollowing ? 1 : -1;
      });
      AppToast.show(
        context: context,
        message: 'Vui lòng đăng nhập để thực hiện tính năng này!',
        isSuccess: false,
      );
    }
  }

  // Luồng đặt lịch cũ đã được thay thế hoàn toàn bằng BookingBottomSheet hệ thống

  String _formatCurrency(dynamic amount) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(amount ?? 0);
  }

  Color _getRoleColor(String role) {
    if (role == 'MODERATOR') return const Color(0xFF8B5CF6); 
    if (role == 'SUPER_ADMIN' || role == 'ADMIN') return Colors.amber;
    if (role == 'PARTNER' || role == 'PARTNER_ADMIN') return Colors.blue;
    return const Color(0xFF80BF84); 
  }

  IconData _getRoleIcon(String role) {
    if (role == 'MODERATOR') return Icons.shield;
    if (role == 'SUPER_ADMIN' || role == 'ADMIN') return Icons.workspace_premium;
    if (role == 'PARTNER' || role == 'PARTNER_ADMIN') return Icons.business;
    return Icons.verified_user;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFFF4F7F6), body: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))));
    if (_data == null) return const Scaffold(backgroundColor: Color(0xFFF4F7F6), body: Center(child: Text('NGƯỜI DÙNG KHÔNG TỒN TẠI', style: TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w900))));

    final profile = _data!['profile'];
    final role = profile['role'] ?? 'USER';
    final isPartner = role == 'PARTNER' || role == 'PARTNER_ADMIN';
    final primaryColor = _getRoleColor(role);
    final videos = _fetchedVideos;
    final services = _fetchedServices;

    final String? rawCover = profile['cover_url'] != null && profile['cover_url'].toString().trim().isNotEmpty ? '${profile['cover_url']}?w=800&q=70' : null;
    final bool hasCover = rawCover != null;

    final String? rawAvatar = profile['avatar_url'] != null && profile['avatar_url'].toString().trim().isNotEmpty ? '${profile['avatar_url']}?w=200&q=75' : null;
    final bool hasAvatar = rawAvatar != null;
    final String fallbackAvatar = 'https://ui-avatars.com/api/?name=${profile['full_name']}&background=${primaryColor.value.toRadixString(16).substring(2)}&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 1. LIQUID GLASS HEADER & COVER
              SliverAppBar(
                expandedHeight: 280,
                pinned: true,
                stretch: true,
                backgroundColor: Colors.white,
                elevation: 0,
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      hasCover ? Image.network(rawCover, fit: BoxFit.cover) : Container(color: primaryColor.withOpacity(0.15)),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, const Color(0xFFF4F7F6).withOpacity(0.8), const Color(0xFFF4F7F6)],
                            stops: const [0.5, 0.9, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            width: 116, height: 116,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(color: primaryColor.withOpacity(0.15), blurRadius: 32, offset: const Offset(0, 12)),
                                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 16, offset: const Offset(0, 4)),
                              ],
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : fallbackAvatar), fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: Colors.white.withOpacity(0.4),
                        child: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 18), onPressed: () => context.pop())
                      ),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: Colors.white.withOpacity(0.4),
                          child: IconButton(
                            icon: const Icon(Icons.ios_share_rounded, color: Colors.black87, size: 20), 
                            onPressed: () => AppToast.show(context: context, message: 'Đã sao chép liên kết hồ sơ!', isSuccess: true)
                          )
                        ),
                      ),
                    ),
                  )
                ],
              ),

              // 2. PREMIUM OVERLAPPING PROFILE CARD
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    children: [
                      // Tên & Huy hiệu xác thực
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(child: Text(profile['full_name'] ?? 'Vô danh', style: const TextStyle(color: const Color(0xFF1E293B), fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5, height: 1.1), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (role != 'USER') ...[
                            const SizedBox(width: 6),
                            Icon(Icons.verified_rounded, color: isPartner ? Colors.blue : primaryColor, size: 24),
                          ]
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Thẻ Xác thực Y tế (Trust Badge)
                      if (isPartner)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: primaryColor.withOpacity(0.2), width: 0.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.health_and_safety_rounded, size: 12, color: primaryColor),
                              const SizedBox(width: 4),
                              Text('Xác thực bởi VN Share', style: TextStyle(color: primaryColor, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.2)),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      
                      // Địa điểm
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 14, color: Colors.black45),
                          const SizedBox(width: 4),
                          Text(profile['physical_address'] ?? 'Đối tác Y tế Chính thức', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Nút Follow Dời lên Bio
                      InkWell(
                        onTap: () => AuthGuard.run(context, action: _handleToggleFollow),
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                          decoration: BoxDecoration(
                            color: _isFollowing ? const Color(0xFFF4F7F6) : primaryColor,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: _isFollowing ? Colors.black.withOpacity(0.1) : primaryColor),
                            boxShadow: _isFollowing ? [] : [BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_isFollowing ? Icons.check_rounded : Icons.person_add_rounded, color: _isFollowing ? Colors.black87 : Colors.white, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                _isFollowing ? 'Đã quan tâm' : 'Quan tâm', 
                                style: TextStyle(color: _isFollowing ? Colors.black87 : Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // TRUST BAR: Chỉ số uy tín (Tối giản viền mỏng)
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildPremiumStat(profile['reputation_points']?.toString() ?? '98', 'ĐIỂM UY TÍN', primaryColor, icon: Icons.shield_rounded),
                            Container(width: 1, height: 40, color: const Color(0xFFF4F7F6)),
                            _buildPremiumStat('4.8', 'ĐÁNH GIÁ (★)', Colors.amber, icon: Icons.star_rounded),
                            Container(width: 1, height: 40, color: const Color(0xFFF4F7F6)),
                            _buildPremiumStat(_followersCount.toString(), 'QUAN TÂM', const Color(0xFF64748B), icon: Icons.favorite_rounded),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Bio Text
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(profile['bio'] ?? "Cơ sở chuyên cung cấp các dịch vụ chăm sóc sức khỏe chủ động theo tiêu chuẩn chất lượng cao.", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF475569), fontSize: 13, height: 1.6, fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. STICKY TABS
              SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(children: _getTabsForRole(role, primaryColor)),
                  ),
                ),
              ),

              // 4. CONTENT AREA (SERVICES / VIDEOS)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16).copyWith(bottom: 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    
                    if (_activeTab == 'services')
                      if (services.isEmpty)
                        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.spa_rounded, size: 56, color: Colors.black12), SizedBox(height: 16), Text('Đang cập nhật dịch vụ', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800))])))
                      else
                        ...services.map((svc) {
                          final bool hasVideo = svc['video_url'] != null && svc['video_url'].toString().trim().isNotEmpty;
                          final bool hasImage = svc['image_url'] != null && svc['image_url'].toString().trim().isNotEmpty;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    AppToast.show(context: context, message: 'Tính năng xem chi tiết dịch vụ đang được cập nhật.', isSuccess: true);
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AspectRatio(
                                        aspectRatio: 16/9,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            if (hasVideo)
                                              MiniVideoPlayer(videoUrl: svc['video_url'])
                                            else if (hasImage)
                                              Image.network(svc['image_url'], fit: BoxFit.cover)
                                            else
                                              Container(color: const Color(0xFFF4F7F6), child: const Icon(Icons.image, color: Colors.black12, size: 40)),
                                            
                                            // Lớp phủ hiển thị Icon Play nếu là Video để tăng cường UX
                                            if (hasVideo)
                                              Positioned(
                                                top: 12, right: 12,
                                                child: Container(
                                                  padding: const EdgeInsets.all(8),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.4), 
                                                    shape: BoxShape.circle, 
                                                    border: Border.all(color: Colors.white.withOpacity(0.2))
                                                  ),
                                                  child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.all(20),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(svc['service_name'] ?? '', style: const TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: -0.3, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
                                                ),
                                                if (isPartner) const SizedBox(width: 8),
                                                if (isPartner) const Icon(Icons.verified_rounded, color: Colors.blue, size: 18),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(svc['description'] ?? 'Dịch vụ chăm sóc cao cấp mang lại trải nghiệm thư giãn tuyệt đối.', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 16),
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('GIÁ TRỌN GÓI', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                                                    const SizedBox(height: 2),
                                                    Text(_formatCurrency(svc['price']), style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900, fontSize: 18)),
                                                  ],
                                                ),
                                                ElevatedButton.icon(
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: primaryColor, foregroundColor: Colors.white,
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                                    elevation: 0
                                                  ),
                                                  onPressed: () {
                                                    AuthGuard.run(context, action: () {
                                                      final targetUserId = profile['id'] ?? '';
                                                      final Map<String, dynamic> adaptedVideoContext = {
                                                        'id': svc['id'] ?? svc['service_id'] ?? '',
                                                        'price': svc['price'] ?? 0.0,
                                                        'authorId': targetUserId,
                                                        'title': svc['service_name'] ?? '',
                                                        'service_name': svc['service_name'] ?? '',
                                                        'image_url': svc['image_url'],
                                                        'video_url': svc['video_url'],
                                                      };
                                                      showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: Colors.transparent, builder: (context) => BookingBottomSheet(video: adaptedVideoContext));
                                                    });
                                                  },
                                                  icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                                                  label: const Text('ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
                                                )
                                              ]
                                            )
                                          ]
                                        )
                                      )
                                    ]
                                  ),
                                ),
                              ),
                            ),
                          );
                        })
                        
                    else if (_activeTab == 'vouchers')
                      ...[
                        ..._fetchedVouchers.map((v) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE5E7EB), width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 90,
                                  decoration: BoxDecoration(
                                    color: v['issuer_type'] == 'ADMIN' ? Colors.amber : primaryColor,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      bottomLeft: Radius.circular(20),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                margin: const EdgeInsets.only(right: 8),
                                                decoration: BoxDecoration(
                                                  color: (v['issuer_type'] == 'ADMIN' ? Colors.amber : primaryColor).withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  v['issuer_type'] == 'ADMIN' ? 'TOÀN SÀN' : 'ĐỘC QUYỀN CƠ SỞ',
                                                  style: TextStyle(
                                                    color: v['issuer_type'] == 'ADMIN' ? Colors.amber[800] : primaryColor,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              'HSD: ${v['valid_until']}',
                                              style: const TextStyle(color: Colors.black45, fontSize: 10, fontWeight: FontWeight.w600),
                                              maxLines: 1,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          v['discount_type'] == 'PERCENTAGE'
                                              ? 'Giảm ${v['discount_value']}%'
                                              : 'Giảm ${_formatCurrency(v['discount_value'])}',
                                          style: const TextStyle(color: Color(0xFF1E293B), fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Đơn tối thiểu: ${_formatCurrency(v['min_order_value'])}',
                                          style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 16),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: v['issuer_type'] == 'ADMIN' ? Colors.amber : primaryColor,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    ),
                                    onPressed: () {
                                      AppToast.show(context: context, message: 'Lưu mã ưu đãi thành công!', isSuccess: true);
                                    },
                                    child: const Text('LƯU MÃ', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.3)),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (_fetchedVouchers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 40),
                            child: Center(
                              child: Column(
                                children: [
                                  Icon(Icons.confirmation_num_rounded, size: 56, color: Colors.black12),
                                  SizedBox(height: 16),
                                  Text('Hiện chưa có mã ưu đãi nào', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                      ]
                        
                    else if (_activeTab == 'videos' || _activeTab == 'liked' || _activeTab == 'saved')
                      if (videos.isEmpty)
                        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.video_library_rounded, size: 56, color: Colors.black12), SizedBox(height: 16), Text('Chưa có video chia sẻ', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800))])))
                      else
                        GridView.builder(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 16, mainAxisSpacing: 16),
                          itemCount: videos.length,
                          itemBuilder: (context, index) {
                            final v = videos[index];
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  MiniVideoPlayer(videoUrl: v['video_url']),
                                  Positioned(
                                    bottom: 0, left: 0, right: 0, 
                                    child: Container(
                                      padding: const EdgeInsets.all(14).copyWith(top: 32), 
                                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.9), Colors.transparent], stops: const [0.0, 1.0])), 
                                      child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, height: 1.3), maxLines: 2)
                                    )
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                    else 
                       const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.more_horiz_rounded, size: 56, color: Colors.black12), SizedBox(height: 16), Text('Tính năng đang phát triển', style: TextStyle(color: Colors.black45, fontWeight: FontWeight.w800))])) )
                  ]),
                ),
              )
            ],
          ),

          // 5. BOTTOM DOCK (LIQUID GLASS CTA)
          if (isPartner)
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: ClipRRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16).copyWith(bottom: MediaQuery.paddingOf(context).bottom > 0 ? MediaQuery.paddingOf(context).bottom : 16),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.85), border: Border(top: BorderSide(color: Colors.black.withOpacity(0.05)))),
                    child: Row(
                      children: [
                        // Nút Chat / Tư vấn nhanh
                        InkWell(
                          onTap: () => AppToast.show(context: context, message: 'Tính năng Chat với Đối tác đang được phát triển.', isSuccess: true),
                          child: Container(
                            width: 56, height: 56,
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE5E7EB))),
                            child: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF1E293B), size: 24),
                          )
                        ),
                        const SizedBox(width: 12),
                        // Nút Action Chính
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B), foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              elevation: 0
                            ),
                            onPressed: () => AppToast.show(context: context, message: 'Vui lòng cuộn lên và chọn một dịch vụ cụ thể để đặt lịch!', isSuccess: true),
                            child: const Text('XEM TẤT CẢ DỊCH VỤ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                          )
                        )
                      ]
                    )
                  )
                )
              )
            )
        ],
      )
    );
  }

  Widget _buildPremiumStat(String val, String label, Color color, {required IconData icon}) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 8),
        Text(val, style: const TextStyle(color: Colors.black87, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.black45, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey, Color primaryColor) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.fastOutSlowIn,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? primaryColor.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Icon(
              icon, 
              size: 16, 
              color: isActive ? primaryColor : const Color(0xFF71717A),
            ),
            const SizedBox(width: 8),
            Text(
              label.toUpperCase(), 
              style: TextStyle(
                color: isActive ? primaryColor : const Color(0xFF71717A), 
                fontSize: 11, 
                fontWeight: isActive ? FontWeight.w900 : FontWeight.bold, 
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Thuật toán gán bộ Tab động dựa trên Phân Quyền chuẩn phiên bản Web
  List<Widget> _getTabsForRole(String role, Color primaryColor) {
    List<Widget> tabs = [];
    if (role == 'SUPER_ADMIN' || role == 'ADMIN') {
      tabs = [
        _buildTabBtn('HOẠT ĐỘNG', Icons.local_activity_rounded, 'activities', primaryColor),
        _buildTabBtn('VIDEO', Icons.video_library_rounded, 'videos', primaryColor),
        _buildTabBtn('ĐÃ LƯU', Icons.bookmark_rounded, 'saved', primaryColor),
      ];
    } else if (role == 'MODERATOR') {
      tabs = [
        _buildTabBtn('ĐÃ THÍCH', Icons.favorite_rounded, 'liked', primaryColor),
        _buildTabBtn('ĐÃ LƯU', Icons.bookmark_rounded, 'saved', primaryColor),
      ];
    } else if (role == 'CREATOR') {
      tabs = [
        _buildTabBtn('VIDEO', Icons.video_library_rounded, 'videos', primaryColor),
        _buildTabBtn('CỘNG ĐỒNG', Icons.forum_rounded, 'community', primaryColor),
      ];
    } else if (role == 'PARTNER' || role == 'PARTNER_ADMIN') {
      tabs = [
        _buildTabBtn('DỊCH VỤ', Icons.local_mall_rounded, 'services', primaryColor),
        _buildTabBtn('ƯU ĐÃI', Icons.local_activity_rounded, 'vouchers', primaryColor),
        _buildTabBtn('VIDEO', Icons.video_library_rounded, 'videos', primaryColor),
        _buildTabBtn('CỘNG ĐỒNG', Icons.forum_rounded, 'community', primaryColor),
        _buildTabBtn('ĐÁNH GIÁ', Icons.star_rounded, 'reviews', primaryColor),
      ];
    } else {
      tabs = [
        _buildTabBtn('VIDEO', Icons.video_library_rounded, 'videos', primaryColor),
        _buildTabBtn('CỘNG ĐỒNG', Icons.forum_rounded, 'community', primaryColor),
        _buildTabBtn('ĐÃ THÍCH', Icons.favorite_rounded, 'liked', primaryColor),
      ];
    }
    
    // Tự động chèn khoảng cách 24px giữa các Tab để vuốt mượt mà
    return tabs.expand((widget) => [widget, const SizedBox(width: 24)]).toList()..removeLast();
  }
}