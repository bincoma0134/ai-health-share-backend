import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/user_api_service.dart';
import '../../widgets/mini_video_player.dart';
import '../../widgets/app_toast.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/booking_bottom_sheet.dart';

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
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFFFAFAFA), body: Center(child: CircularProgressIndicator(color: Color(0xFF3B82F6))));
    if (_data == null) return const Scaffold(backgroundColor: Color(0xFFFAFAFA), body: Center(child: Text('NGƯỜI DÙNG KHÔNG TỒN TẠI', style: TextStyle(color: Color(0xFF18181B), fontSize: 18, fontWeight: FontWeight.w900))));

    final profile = _data!['profile'];
    final role = profile['role'] ?? 'USER';
    final primaryColor = _getRoleColor(role);
    final videos = _fetchedVideos;
    final services = _fetchedServices;

    // Tích hợp tham số nén ảnh trực tiếp trên CDN để tăng tốc độ tải
    final String? rawCover = profile['cover_url'] != null && profile['cover_url'].toString().trim().isNotEmpty 
        ? '${profile['cover_url']}?w=800&q=70' 
        : null;
    final bool hasCover = rawCover != null;

    final String? rawAvatar = profile['avatar_url'] != null && profile['avatar_url'].toString().trim().isNotEmpty
        ? '${profile['avatar_url']}?w=200&q=75'
        : null;
    final bool hasAvatar = rawAvatar != null;
    final String fallbackAvatar = 'https://ui-avatars.com/api/?name=${profile['full_name']}&background=${primaryColor.value.toRadixString(16).substring(2)}&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(backgroundColor: Colors.white70, child: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)), onPressed: () => context.pop())),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: Colors.white70, 
                  child: IconButton(
                    icon: const Icon(Icons.share_rounded, color: Color(0xFF18181B), size: 20), 
                    onPressed: () {
                      AppToast.show(
                        context: context,
                        message: 'Đã sao chép liên kết hồ sơ vào bộ nhớ tạm!',
                        isSuccess: true,
                      );
                    }
                  )
                ),
              )
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      height: 180, width: double.infinity,
                      decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), image: hasCover ? DecorationImage(image: NetworkImage(rawCover), fit: BoxFit.cover) : null),
                      child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFFFAFAFA).withOpacity(0.8)]))),
                    ),
                    Positioned(
                      bottom: -50,
                      child: Container(
                        width: 110, height: 110,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFAFAFA), border: Border.all(color: primaryColor, width: 3), image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : fallbackAvatar), fit: BoxFit.cover)),
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 60),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              profile['full_name'] ?? 'Vô danh', 
                              style: const TextStyle(color: Color(0xFF18181B), fontSize: 24, fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (role != 'USER') ...[
                            const SizedBox(width: 8),
                            Icon(_getRoleIcon(role), color: primaryColor, size: 20),
                          ]
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('@${profile['username']}', style: const TextStyle(color: Color(0xFF71717A))),
                      const SizedBox(height: 20),
                      
                      SizedBox(
                        width: 180, height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _isFollowing ? const Color(0xFFD4D4D8) : primaryColor, foregroundColor: _isFollowing ? const Color(0xFF18181B) : Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
                          onPressed: _handleToggleFollow,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isFollowing ? Icons.check : Icons.person_add, size: 18), const SizedBox(width: 8), Text(_isFollowing ? 'ĐÃ QUAN TÂM' : 'QUAN TÂM', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5))]),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(profile['following_count']?.toString() ?? '0', 'Đang theo dõi', primaryColor),
                          Container(width: 1, height: 30, color: const Color(0xFFD4D4D8)),
                          _buildStatCol(_followersCount.toString(), 'Người theo dõi', primaryColor),
                          Container(width: 1, height: 30, color: const Color(0xFFD4D4D8)),
                          _buildStatCol(
                            (role == 'SUPER_ADMIN' || role == 'ADMIN') ? '100%' : role == 'MODERATOR' ? 'Tích cực' : (role == 'PARTNER' || role == 'PARTNER_ADMIN') ? '${profile['reputation_points'] ?? 92}' : (profile['likes_count']?.toString() ?? '0'), 
                            (role == 'SUPER_ADMIN' || role == 'ADMIN') ? 'Hệ thống' : role == 'MODERATOR' ? 'Đã duyệt' : (role == 'PARTNER' || role == 'PARTNER_ADMIN') ? 'Uy tín' : 'Lượt thích', 
                            primaryColor, 
                            isHighlight: true
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(profile['bio'] ?? "Người dùng này chưa cập nhật tiểu sử.", textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF27272A), fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.only(top: 24),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: _getTabsForRole(role, primaryColor),
                ),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(16).copyWith(top: 24, bottom: 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // TAB 1: DỊCH VỤ
                if (_activeTab == 'services')
                  if (services.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.local_mall_outlined, size: 48, color: Color(0xFFA1A1AA)), SizedBox(height: 16), Text('Chưa có dịch vụ nào.', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold))])) )
                  else
                    ...services.map((svc) => Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFD4D4D8))),
                      child: Row(
                        children: [
                          Container(width: 100, height: 100, decoration: BoxDecoration(borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)), image: svc['image_url'] != null ? DecorationImage(image: NetworkImage(svc['image_url']), fit: BoxFit.cover) : null, color: const Color(0xFFD4D4D8))),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(svc['service_name'] ?? '', style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(_formatCurrency(svc['price']), style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
                              onPressed: () {
                                // Ánh xạ dữ liệu dịch vụ sang cấu trúc tương thích với BookingBottomSheet
                                final targetUserId = profile['id'] ?? '';
                                final Map<String, dynamic> adaptedVideoContext = {
                                  'id': svc['id'] ?? svc['service_id'] ?? '',
                                  'price': svc['price'] ?? 0.0,
                                  'authorId': targetUserId,
                                  'title': svc['service_name'] ?? '',
                                  'service_name': svc['service_name'] ?? '',
                                  'image_url': svc['image_url'],
                                };
                                
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.transparent,
                                  builder: (context) => BookingBottomSheet(video: adaptedVideoContext),
                                );
                              },
                              child: const Text('ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                            ),
                          )
                        ],
                      ),
                    ))
                // TAB 2: VIDEOS / LIKED / SAVED
                else if (_activeTab == 'videos' || _activeTab == 'liked' || _activeTab == 'saved')
                  if (videos.isEmpty)
                    Padding(padding: const EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(_activeTab == 'videos' ? Icons.video_library_outlined : _activeTab == 'liked' ? Icons.favorite_outline : Icons.bookmark_outline, size: 48, color: Color(0xFFA1A1AA)), const SizedBox(height: 16), Text(_activeTab == 'videos' ? 'Chưa có video được đăng tải' : 'Danh sách trống', style: const TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold))])) )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 9/16, crossAxisSpacing: 12, mainAxisSpacing: 12),
                      itemCount: videos.length,
                      itemBuilder: (context, index) {
                        final v = videos[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              MiniVideoPlayer(videoUrl: v['video_url']),
                              Positioned(bottom: 0, left: 0, right: 0, child: Container(padding: const EdgeInsets.all(8), decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])), child: Text(v['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold), maxLines: 2))),
                            ],
                          ),
                        );
                      },
                    )
                // TAB 3: EMPTY STATES KHÁC (Đợi API tích hợp sau)
                else if (_activeTab == 'community')
                   const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.forum_outlined, size: 48, color: Color(0xFFA1A1AA)), SizedBox(height: 16), Text('Chưa có bài viết nào trên cộng đồng.', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold))])) )
                else if (_activeTab == 'reviews')
                   const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.star_outline, size: 48, color: Color(0xFFA1A1AA)), SizedBox(height: 16), Text('Chưa có đánh giá nào.', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold))])) )
                else if (_activeTab == 'activities')
                   const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: Column(children: [Icon(Icons.local_activity_outlined, size: 48, color: Color(0xFFA1A1AA)), SizedBox(height: 16), Text('Chưa có hoạt động nào.', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.bold))])) )
              ]),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCol(String val, String label, Color primaryColor, {bool isHighlight = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            val, 
            style: TextStyle(color: isHighlight ? primaryColor : const Color(0xFF18181B), fontSize: 20, fontWeight: FontWeight.w900),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(), 
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
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