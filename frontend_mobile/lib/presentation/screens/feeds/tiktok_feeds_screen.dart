import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../data/models/video_model.dart';
import '../../../data/services/feed_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/feed_video_player.dart';
import '../../widgets/auth_bottom_sheet.dart';
import '../../widgets/booking_bottom_sheet.dart';
import '../../widgets/comment_bottom_sheet.dart';

class TikTokFeedsScreen extends StatefulWidget {
  const TikTokFeedsScreen({super.key});

  @override
  State<TikTokFeedsScreen> createState() => _TikTokFeedsScreenState();
}

class _TikTokFeedsScreenState extends State<TikTokFeedsScreen> {
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  Future<void> _loadFeeds() async {
    final feeds = await FeedApiService.fetchFeeds();
    setState(() {
      _videos = feeds;
      _isLoading = false;
    });
  }

  // Bẫy Logic Khách
  Future<void> _handleAuthGuard(Function action) async {
    final token = await _storage.read(key: 'ai-health-token');
    if (token == null || token.isEmpty) {
      _showAuthBottomSheet();
    } else {
      action(); 
    }
  }

  // Gọi API Tương tác (Like / Save)
  Future<void> _toggleInteraction(int index, String action) async {
    await _handleAuthGuard(() async {
      final video = _videos[index];
      
      // Optimistic UI: Cập nhật giao diện ngay lập tức
      setState(() {
        if (action == 'like') {
          video.isLiked = !video.isLiked;
          video.likesCount += video.isLiked ? 1 : -1;
        } else if (action == 'save') {
          video.isSaved = !video.isSaved;
          video.savesCount += video.isSaved ? 1 : -1;
        }
      });

      // Chạy ngầm API
      try {
        await ApiClient.instance.post('/tiktok/feeds/${video.id}/$action');
      } catch (e) {
        // Nếu lỗi, âm thầm hoàn tác trạng thái
        setState(() {
          if (action == 'like') {
            video.isLiked = !video.isLiked;
            video.likesCount += video.isLiked ? 1 : -1;
          } else if (action == 'save') {
            video.isSaved = !video.isSaved;
            video.savesCount += video.isSaved ? 1 : -1;
          }
        });
      }
    });
  }

  void _showAuthBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AuthBottomSheet(onSuccess: _loadFeeds),
    );
  }

  void _showBookingBottomSheet(VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => BookingBottomSheet(video: video),
    );
  }

  void _showCommentBottomSheet(int index) {
    // Không bọc bằng _handleAuthGuard để khách vãng lai vẫn được ĐỌC bình luận
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentBottomSheet(
        videoId: _videos[index].id,
        onAuthRequired: _showAuthBottomSheet, // Yêu cầu đăng nhập khi gõ phím
        onCommentAdded: () {
          setState(() {
            _videos[index].commentsCount += 1; // Cập nhật số lượng ngoài màn hình
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator(color: Colors.green)));
    if (_videos.isEmpty) return const Scaffold(backgroundColor: Colors.black, body: Center(child: Text('Không có video nào', style: TextStyle(color: Colors.white))));

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: _videos.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          final video = _videos[index];
          return Stack(
            children: [
              FeedVideoPlayer(
                videoUrl: video.videoUrl, 
                isActive: index == _currentIndex,
                onDoubleTap: () {
                  // Chuẩn TikTok: Double Tap chỉ để thả tim (Like), nếu đã tim rồi thì không thu hồi (Unlike)
                  if (!video.isLiked) {
                    _toggleInteraction(index, 'like');
                  }
                },
              ),
              
              // BỌC IGNORE POINTER ĐỂ LỚP ĐỔ BÓNG KHÔNG CHẶN SỰ KIỆN CHẠM
              IgnorePointer(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, 
                      end: Alignment.bottomCenter, 
                      colors: [Colors.transparent, Colors.black54]
                    )
                  )
                ),
              ),

              // Đẩy cao lên 110px để tránh hoàn toàn cụm Navigation nổi
              Positioned(
                bottom: 110, left: 16, right: 80,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('@${video.author['username'] ?? 'user'}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(video.content, style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    if (video.price > 0)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF80BF84), foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: () => _handleAuthGuard(() => _showBookingBottomSheet(video)),
                        child: const Text('ĐẶT LỊCH NGAY', style: TextStyle(fontWeight: FontWeight.w900)),
                      )
                  ],
                ),
              ),

              // Đồng bộ trục Y với cụm Đặt lịch
              Positioned(
                bottom: 110, right: 12,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    CircleAvatar(radius: 24, backgroundImage: NetworkImage(video.author['avatar_url'] ?? 'https://via.placeholder.com/150')),
                    const SizedBox(height: 20),
                    
                    // Nút Like
                    _buildInteractButton(
                      video.isLiked ? Icons.favorite : Icons.favorite_border, 
                      video.likesCount.toString(), 
                      () => _toggleInteraction(index, 'like'),
                      color: video.isLiked ? Colors.red : Colors.white
                    ),
                    const SizedBox(height: 20),
                    
                    // Nút Comment
                    _buildInteractButton(
                      Icons.comment, 
                      video.commentsCount.toString(), 
                      () => _showCommentBottomSheet(index),
                    ),
                    const SizedBox(height: 20),
                    
                    // Nút Save
                    _buildInteractButton(
                      video.isSaved ? Icons.bookmark : Icons.bookmark_border, 
                      video.savesCount.toString(), 
                      () => _toggleInteraction(index, 'save'),
                      color: video.isSaved ? Colors.orangeAccent : Colors.white
                    ),
                    const SizedBox(height: 20),
                    
                    _buildInteractButton(Icons.share, 'Chia sẻ', () {}),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInteractButton(IconData icon, String text, VoidCallback onTap, {Color color = Colors.white}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}