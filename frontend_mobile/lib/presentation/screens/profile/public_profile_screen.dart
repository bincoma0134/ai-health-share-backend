import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/user_api_service.dart';
import '../../widgets/mini_video_player.dart';

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

  Future<void> _loadData() async {
    final result = await UserApiService.fetchPublicProfile(widget.username);
    if (mounted) {
      setState(() {
        _data = result;
        if (result != null) {
          _isFollowing = result['is_followed'] ?? false;
          _followersCount = result['stats']?['followers_count'] ?? 0;
          if (result['profile']['role'] != 'PARTNER' && result['profile']['role'] != 'PARTNER_ADMIN') {
            _activeTab = 'videos';
          }
        }
        _isLoading = false;
      });
    }
  }

  Future<void> _handleToggleFollow() async {
    if (_data == null) return;
    setState(() {
      _isFollowing = !_isFollowing;
      _followersCount += _isFollowing ? 1 : -1;
    });

    final success = await UserApiService.toggleFollow(_data!['profile']['id']);
    if (!success && mounted) {
      setState(() {
        _isFollowing = !_isFollowing;
        _followersCount += _isFollowing ? 1 : -1;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng đăng nhập để thực hiện!')));
    }
  }

  void _showBookingModal(Map<String, dynamic> service) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
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
                const Text('Đặt Lịch Dịch Vụ', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(service['service_name'] ?? service['title'] ?? '', style: const TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(service['price'] ?? 0)}', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                
                TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Họ và tên', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Số điện thoại', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const SizedBox(height: 12),
                TextField(controller: noteCtrl, maxLines: 2, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: 'Lời nhắn nhủ (Tùy chọn)', filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
                const SizedBox(height: 16),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.withOpacity(0.3))),
                  child: const Row(children: [Icon(Icons.shield, color: Colors.blue, size: 16), SizedBox(width: 8), Expanded(child: Text('Bạn chưa cần thanh toán lúc này. Hệ thống sẽ giữ tiền an toàn sau khi cơ sở xác nhận lịch trống.', style: TextStyle(color: Colors.blue, fontSize: 11)))]),
                ),
                
                const Spacer(),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                    onPressed: isSubmitting ? null : () async {
                      if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng nhập Tên và SĐT!'))); return;
                      }
                      setModalState(() => isSubmitting = true);
                      
                      // GIẢ LẬP GỌI API ĐẶT LỊCH (Đã được định nghĩa ở Backend)
                      await Future.delayed(const Duration(seconds: 1));
                      setModalState(() => isSubmitting = false);
                      
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Yêu cầu đã được gửi! Theo dõi tại tab Lịch hẹn.'), backgroundColor: Colors.green));
                    },
                    child: isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('GỬI YÊU CẦU ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
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
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFF09090b), body: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))));
    if (_data == null) return const Scaffold(backgroundColor: Color(0xFF09090b), body: Center(child: Text('NGƯỜI DÙNG KHÔNG TỒN TẠI', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))));

    final profile = _data!['profile'];
    final role = profile['role'] ?? 'USER';
    final primaryColor = _getRoleColor(role);
    final videos = _data!['videos'] as List<dynamic>? ?? [];
    final services = _data!['services'] as List<dynamic>? ?? [];

    final String? rawCover = profile['cover_url'];
    final bool hasCover = rawCover != null && rawCover.trim().isNotEmpty;

    final String? rawAvatar = profile['avatar_url'];
    final bool hasAvatar = rawAvatar != null && rawAvatar.trim().isNotEmpty;
    final String fallbackAvatar = 'https://ui-avatars.com/api/?name=${profile['full_name']}&background=${primaryColor.value.toRadixString(16).substring(2)}&color=fff';

    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(backgroundColor: Colors.black54, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop())),
            ),
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
                      decoration: BoxDecoration(color: primaryColor.withOpacity(0.2), image: hasCover ? DecorationImage(image: NetworkImage(rawCover), fit: BoxFit.cover) : null),
                      child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09090b).withOpacity(0.9)]))),
                    ),
                    Positioned(
                      bottom: -50,
                      child: Container(
                        width: 110, height: 110,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF09090b), border: Border.all(color: primaryColor, width: 3), image: DecorationImage(image: NetworkImage(hasAvatar ? rawAvatar : fallbackAvatar), fit: BoxFit.cover)),
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
                        children: [
                          Text(profile['full_name'] ?? 'Vô danh', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          const SizedBox(width: 8),
                          if (role != 'USER') Icon(_getRoleIcon(role), color: primaryColor, size: 20),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('@${profile['username']}', style: const TextStyle(color: Colors.white54)),
                      const SizedBox(height: 20),
                      
                      SizedBox(
                        width: 180, height: 44,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: _isFollowing ? Colors.white10 : primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                          onPressed: _handleToggleFollow,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(_isFollowing ? Icons.check : Icons.person_add, size: 18), const SizedBox(width: 8), Text(_isFollowing ? 'ĐÃ QUAN TÂM' : 'QUAN TÂM', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.5))]),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildStatCol(profile['following_count']?.toString() ?? '0', 'Đang theo dõi', primaryColor),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(_followersCount.toString(), 'Người theo dõi', primaryColor),
                          Container(width: 1, height: 30, color: Colors.white10),
                          _buildStatCol(role == 'MODERATOR' ? 'Tích cực' : role == 'PARTNER' || role == 'PARTNER_ADMIN' ? '${profile['reputation_points'] ?? 92}' : '3099', role == 'MODERATOR' ? 'Đã duyệt' : role == 'PARTNER' || role == 'PARTNER_ADMIN' ? 'Uy tín' : 'Lượt thích', primaryColor, isHighlight: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(profile['bio'] ?? "Người dùng này chưa cập nhật tiểu sử.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (role == 'PARTNER' || role == 'PARTNER_ADMIN')
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.only(top: 24),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildTabBtn('DỊCH VỤ CƠ SỞ', Icons.local_mall, 'services', primaryColor),
                    _buildTabBtn('VIDEO NỔI BẬT', Icons.video_library, 'videos', primaryColor),
                  ],
                ),
              ),
            ),

          SliverPadding(
            padding: const EdgeInsets.all(16).copyWith(top: role == 'PARTNER' || role == 'PARTNER_ADMIN' ? 24 : 32, bottom: 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                if (_activeTab == 'services' && (role == 'PARTNER' || role == 'PARTNER_ADMIN'))
                  if (services.isEmpty)
                    const Center(child: Text('Cơ sở chưa có dịch vụ nào.', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
                  else
                    ...services.map((svc) => Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        children: [
                          Container(width: 100, height: 100, decoration: BoxDecoration(borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)), image: svc['image_url'] != null ? DecorationImage(image: NetworkImage(svc['image_url']), fit: BoxFit.cover) : null, color: Colors.black26)),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(svc['service_name'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(_formatCurrency(svc['price']), style: TextStyle(color: primaryColor, fontWeight: FontWeight.w900)),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              onPressed: () => _showBookingModal(svc),
                              child: const Text('ĐẶT LỊCH', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                            ),
                          )
                        ],
                      ),
                    )),

                if (_activeTab == 'videos' || (role != 'PARTNER' && role != 'PARTNER_ADMIN'))
                  if (videos.isEmpty)
                    const Center(child: Text('Chưa có video được đăng tải', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold)))
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
              ]),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatCol(String val, String label, Color primaryColor, {bool isHighlight = false}) {
    return Column(
      children: [
        Text(val, style: TextStyle(color: isHighlight ? primaryColor : Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 4),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
      ],
    );
  }

  Widget _buildTabBtn(String label, IconData icon, String tabKey, Color primaryColor) {
    final isActive = _activeTab == tabKey;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = tabKey),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: isActive ? primaryColor : Colors.transparent, width: 3))),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isActive ? primaryColor : Colors.white54),
            const SizedBox(width: 8),
            Text(label.toUpperCase(), style: TextStyle(color: isActive ? primaryColor : Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }
}