import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../data/services/creator_api_service.dart';
import '../../widgets/mini_video_player.dart';

class CreatorDashboardScreen extends StatefulWidget {
  const CreatorDashboardScreen({super.key});

  @override
  State<CreatorDashboardScreen> createState() => _CreatorDashboardScreenState();
}

class _CreatorDashboardScreenState extends State<CreatorDashboardScreen> {
  bool _isLoading = true;
  
  Map<String, dynamic> _stats = {'total_videos': 0, 'total_posts': 0, 'total_likes': 0, 'approval_rate': 0};
  List<dynamic> _recentVideos = [];
  List<dynamic> _recentPosts = [];

  final Color _crtPrimary = const Color(0xFFF43F5E); // Rose-500
  final Color _crtSecondary = const Color(0xFFE11D48); // Rose-600

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      CreatorApiService.fetchStats(),
      CreatorApiService.fetchContent(),
    ]);

    if (mounted) {
      setState(() {
        if (results[0] != null) _stats = results[0]!;
        if (results[1] != null) {
          final videos = results[1]!['videos'] as List<dynamic>? ?? [];
          final posts = results[1]!['community_posts'] as List<dynamic>? ?? [];
          
          // Lấy 5 item mới nhất
          _recentVideos = videos.take(5).toList();
          _recentPosts = posts.take(5).toList();
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09090b),
        elevation: 0,
        leading: BackButton(color: _crtPrimary),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: _crtPrimary, size: 20),
            const SizedBox(width: 8),
            const Text('Trung tâm Sáng tạo', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: Colors.white), onPressed: _loadDashboardData)],
      ),
      body: _isLoading 
        ? Center(child: CircularProgressIndicator(color: _crtPrimary))
        : RefreshIndicator(
            color: _crtPrimary,
            onRefresh: _loadDashboardData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16).copyWith(bottom: 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LỜI CHÀO & NÚT TẠO MỚI
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Hiệu suất Kênh', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
                          Text('Đánh giá chất lượng và tăng trưởng.', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                        ],
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: _crtPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => context.pop(), // Quay về trang Profile để đăng bài
                        icon: const Icon(Icons.add_box, size: 16),
                        label: const Text('Tạo mới', style: TextStyle(fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 4 KHỐI THỐNG KÊ (GRID)
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.4,
                    children: [
                      _buildStatCard('Video Đã Đăng', _stats['total_videos'].toString(), Icons.video_library, Colors.pink),
                      _buildStatCard('Bài Cộng Đồng', _stats['total_posts'].toString(), Icons.article, Colors.purple),
                      _buildStatCard('Tổng Lượt Thích', _stats['total_likes'].toString(), Icons.favorite, Colors.redAccent),
                      _buildStatCard('Uy tín Kênh', '${_stats['approval_rate']}%', Icons.shield, Colors.amber),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // BIỂU ĐỒ HIỆU SUẤT (MOCK UI TỐI ƯU)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.white.withOpacity(0.1))),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.trending_up, color: Colors.pinkAccent, size: 16),
                            SizedBox(width: 8),
                            Text('TƯƠNG TÁC 7 NGÀY QUA', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildMockBarChart(),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // DANH SÁCH VIDEO MỚI NHẤT
                  const Text('Video Gần Đây', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  if (_recentVideos.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có video nào.', style: TextStyle(color: Colors.white54)))
                  else
                    ..._recentVideos.map((v) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Container(
                            width: 50, height: 70,
                            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                MiniVideoPlayer(videoUrl: v['video_url']),
                                const Center(child: Icon(Icons.play_arrow, color: Colors.white, size: 20)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v['title'] ?? 'Video', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.favorite, color: Colors.pinkAccent, size: 12),
                                    const SizedBox(width: 4),
                                    Text('${v['likes_count'] ?? 0}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                    const SizedBox(width: 12),
                                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: v['status'] == 'APPROVED' ? Colors.green.withOpacity(0.2) : Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), child: Text(v['status'].toString().split('_').last, style: TextStyle(color: v['status'] == 'APPROVED' ? Colors.green : Colors.amber, fontSize: 8, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    )),
                    
                  const SizedBox(height: 12),
                  // DANH SÁCH BÀI ĐĂNG MỚI NHẤT
                  const Text('Bài Đăng Gần Đây', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  if (_recentPosts.isEmpty)
                    const Padding(padding: EdgeInsets.all(16), child: Text('Chưa có bài đăng nào.', style: TextStyle(color: Colors.white54)))
                  else
                    ..._recentPosts.map((p) => Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.article, color: Colors.pinkAccent)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p['content'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(p['created_at']).toLocal()), style: const TextStyle(color: Colors.white30, fontSize: 10)),
                              ],
                            ),
                          )
                        ],
                      ),
                    )),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const Spacer(),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(title.toUpperCase(), style: const TextStyle(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // Khối giả lập Bar Chart đẹp mắt bằng code thuần
  Widget _buildMockBarChart() {
    final List<double> values = [0.4, 0.7, 0.3, 0.9, 0.6, 0.8, 1.0];
    final List<String> days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (index) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 16, height: 120 * values[index],
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_crtPrimary, _crtPrimary.withOpacity(0.1)]),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 8),
            Text(days[index], style: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        );
      }),
    );
  }
}