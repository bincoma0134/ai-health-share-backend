import 'dart:ui'; // Bổ sung thư viện này để dùng ImageFilter
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart'; // Bổ sung phục vụ format giá tiền tệ VNĐ động
import 'package:go_router/go_router.dart'; // Bổ sung GoRouter
import '../../../data/models/video_model.dart'; 
import '../../../data/services/feed_api_service.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/global_cache_engine.dart';
import '../../widgets/feed_video_player.dart';
import '../../widgets/auth_bottom_sheet.dart';
import '../../widgets/booking_bottom_sheet.dart';
import '../../widgets/comment_bottom_sheet.dart';
import '../../widgets/app_toast.dart'; // Tích hợp thông báo đặc sắc của hệ thống
import '../../widgets/auth_guard.dart';
import '../../widgets/notification_notifier.dart'; // 🚀 Bổ sung thư viện quản lý State thông báo
import '../../widgets/animated_premium_like_button.dart'; // Tích hợp nút thả tim hệ hạt động
import 'package:flutter/services.dart'; // 🚀 Bổ sung HapticFeedback để tạo rung vi chạm
import 'package:visibility_detector/visibility_detector.dart'; // Giải quyết dứt điểm lỗi phát nhạc dưới nền
import '../../../core/manager/audio_focus_manager.dart';



class TikTokFeedsScreen extends StatefulWidget {
  final String? filter;
  const TikTokFeedsScreen({super.key, this.filter});

  @override
  State<TikTokFeedsScreen> createState() => _TikTokFeedsScreenState();
}


class _TikTokFeedsScreenState extends State<TikTokFeedsScreen> with AutomaticKeepAliveClientMixin {
  
  // 🚀 THUẬT TOÁN VIDEO RESUME ENGINE: Bảo lưu toàn bộ trạng thái UI và RAM khi chuyển Tab
  @override
  bool get wantKeepAlive => true;

  List<VideoModel> _videos = [];
  bool _isLoading = true;
  
  // Quản lý thời gian xem video thực tế phục vụ nhiệm vụ SValue
  final math.Random _random = math.Random();
  DateTime? _videoStartTime;
  int _currentIndex = 0;
  final _storage = const FlutterSecureStorage();
  
  // Lưu trữ danh sách ID các đối tác đã nhấn theo dõi thành công trong phiên làm việc
  final Set<String> _followedCreatorIds = {};

  // MỚI: Quản lý trạng thái và dữ liệu cho tính năng Tìm kiếm nhanh (Search Overlay)
  bool _isSearchOpen = false;
  String _searchQuery = '';
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  @override
  void didUpdateWidget(TikTokFeedsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tự động tải lại dữ liệu nếu GoRouter truyền vào một bộ lọc mới
    if (oldWidget.filter != widget.filter) {
      setState(() => _isLoading = true);
      _loadFeeds();
    }
  }

  bool _isFetchingLock = false;
  Future<void> _loadFeeds() async {
    if (_isFetchingLock) return;
    _isFetchingLock = true;
    try {
      // 1. Đọc trực tiếp UserID từ bộ nhớ RAM siêu tốc (AuthNotifier)
      final String? userId = AuthNotifier.instance.userId;

      // Xử lý bộ lọc từ Router truyền vào
      final Map<String, dynamic> queryParams = {'limit': 50};
      if (userId != null) queryParams['user_id'] = userId;
      if (widget.filter != null) queryParams['filter'] = widget.filter;

      // 2. Gọi API truyền kèm user_id và filter để Backend trả đúng dữ liệu
      final response = await ApiClient.instance.get(
        '/tiktok/feeds',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] ?? response.data;
        var fetchedVideos = data.map((json) => VideoModel.fromJson(json)).toList();
        
        // Thuật toán Random: Xáo trộn danh sách để mỗi lần mở app là một luồng Feed mới lạ
        fetchedVideos.shuffle(); 
        
        setState(() {
          _videos = fetchedVideos;
          _isLoading = false;
        });
        
        // Kích hoạt Preload ngay sau khi có dữ liệu
        if (_videos.isNotEmpty) {
          _preloadNextVideos(0);
        }
      }
    } catch (e) {
      // Fallback an toàn
      final feeds = await FeedApiService.fetchFeeds();
      setState(() {
        _videos = feeds;
        _isLoading = false;
      });
      
      // Kích hoạt Preload ngay sau khi có dữ liệu Fallback
      if (_videos.isNotEmpty) {
        _preloadNextVideos(0);
      }
    } finally {
      _isFetchingLock = false;
    }
  }

  // 🚀 THUẬT TOÁN SMART PRELOAD
  // Khởi tạo trước luồng mạng (Network stream) cho video kế tiếp (N+1, N+2)
  // để đảm bảo phát ngay lập tức khi cuộn mà không cần chờ tải Frame đầu tiên.
  void _preloadNextVideos(int index) {
    for (int i = 1; i <= 2; i++) {
      final nextIndex = index + i;
      if (nextIndex < _videos.length) {
        final url = _videos[nextIndex].videoUrl;
        // Bắt đầu quá trình nạp Byte thầm lặng qua FeedVideoPool (Đã nâng cấp Async cho Disk Cache)
        FeedVideoPool.getController(url).then((controller) {
          if (!controller.value.isInitialized) {
            controller.initialize();
          }
        });
      }
    }
  }

  // Bẫy Logic Khách
  Future<void> _handleAuthGuard(VoidCallback action) async {
    await AuthGuard.run(context, action: action);
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
      useRootNavigator: true, // Hiển thị đè hoàn toàn lên Bottom Navigation Bar
      backgroundColor: Colors.transparent,
      builder: (context) => BookingBottomSheet(video: video),
    );
  }

  void _showCommentBottomSheet(int index) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true, // Hiển thị đè hoàn toàn lên Bottom Navigation Bar
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
  @override
  void dispose() {
    // 🚀 ĐỒNG BỘ HÓA GIẢI PHÓNG: Tránh rò rỉ tài nguyên bằng cách ngắt trực tiếp tiêu điểm qua Trọng tài tập trung
    try {
      AudioFocusManager.instance.requestMode(AppAudioMode.mutedAll);
    } catch (_) {}
    super.dispose();
  }

  Widget build(BuildContext context) {
    super.build(context); // BẮT BUỘC: Khởi động cơ chế KeepAlive Engine
    
    // Chuyển nền nạp trang mặc định của Hệ thống Feeds từ Đen sang Sáng trắng toàn cục
    if (_isLoading) return const Scaffold(backgroundColor: Color(0xFFFAFAFA), body: Center(child: CircularProgressIndicator(color: Color(0xFF80BF84))));
    if (_videos.isEmpty) return const Scaffold(backgroundColor: Color(0xFFFAFAFA), body: Center(child: Text('Không có video nào', style: TextStyle(color: Colors.black87))));

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: PageView.builder(
        key: const PageStorageKey<String>('feed_video_position'), // 🚀 THUẬT TOÁN FEED POSITION ENGINE: Lưu giữ vị trí video hiện tại
        controller: _pageController, // Gán bộ điều khiển để hỗ trợ dịch chuyển index video khi chọn kết quả tìm kiếm
        scrollDirection: Axis.vertical,
        // Hiệu ứng lướt mượt, có độ nảy (Bounce) ở 2 đầu chuẩn UI/UX của iOS và TikTok
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()), 
        // 🚀 THUẬT TOÁN PRELOAD: Tự động khởi tạo ngầm 1 video trước và 1 video sau vào RAM
        allowImplicitScrolling: true, 
        itemCount: _videos.length,
        onPageChanged: (index) async {
          // Tính toán thời gian xem tích lũy của video vừa xem trước khi chuyển trang
          if (_videoStartTime != null) {
            final int secondsWatched = DateTime.now().difference(_videoStartTime!).inSeconds;
            if (secondsWatched > 0) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final int currentTotal = prefs.getInt('tiktok_watch_seconds_tally') ?? 0;
                await prefs.setInt('tiktok_watch_seconds_tally', currentTotal + secondsWatched);
                debugPrint('⏱️ Đã tích lũy thêm: $secondsWatched giây xem video (Tổng: ${currentTotal + secondsWatched}/180s)');
              } catch (_) {}
            }
          }
          // Reset mốc thời gian bắt đầu cho video mới
          _videoStartTime = DateTime.now();
          setState(() => _currentIndex = index);
          
          // Kích hoạt nạp trước luồng video cho các trang tiếp theo
          _preloadNextVideos(index);
        },
        itemBuilder: (context, index) {
          final video = _videos[index];
          return Stack(
            children: [
              VisibilityDetector(
                key: Key('feed_video_${video.id}_$index'),
                onVisibilityChanged: (visibilityInfo) {
                  // Trả về luồng xử lý nhẹ để tối ưu tài nguyên tầng danh sách cha
                  if (visibilityInfo.visibleFraction < 0.1 && index == _currentIndex) {
                    FeedVideoPool.getController(video.videoUrl).then((c) => c.pause());
                  }
                },
                child: FeedVideoPlayer(
                  videoUrl: video.videoUrl,
                  isActive: index == _currentIndex,
                  videoIndex: index,            // Truyền vị trí để tính toán khoảng cách
                  currentIndex: _currentIndex,  // Truyền vị trí đang xem để so sánh
                  onDoubleTap: () {
                    // Chuẩn TikTok: Double Tap chỉ để thả tim (Like), nếu đã tim rồi thì không thu hồi (Unlike)
                    if (!video.isLiked) {
                      _toggleInteraction(index, 'like');
                    }
                  },
                ),
              ),
              
             
              // BỌC IGNORE POINTER ĐỂ LỚP ĐỔ BÓNG KHÔNG CHẶN SỰ KIỆN CHẠM (Sửa lỗi hắt sáng: Chuyển dải mờ sang đen phủ mịn để tăng tương phản chữ trắng)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter, 
                      end: Alignment.bottomCenter, 
                      colors: [
                        Colors.transparent, 
                        Colors.black.withOpacity(0.55), // Bóng tối chuẩn mịn màng giúp đọc caption chữ trắng dễ chịu, bám khối chắc chắn
                      ],
                      stops: const [0.6, 1.0], // Thiết lập điểm dừng thông minh, chỉ tập trung phủ tối ở 40% phần đáy màn hình nhằm giữ độ căng cho video nền
                    )
                  )
                ),
              ),

              // TOP NAVIGATION BAR: Chuyển đổi Icon sang tone đen mờ sành điệu, bao bọc kính sáng mờ
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Nút Quay lại
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.6), // Kính mờ trắng sáng mịn màng
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black12, width: 0.5),
                          ),
                          child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black87, size: 20),
                        ),
                      ),
                      
                      // Cụm nút bên phải: Tìm kiếm & Thông báo
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () => setState(() => _isSearchOpen = true),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.6),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.black12, width: 0.5),
                              ),
                              child: const Icon(Icons.search_rounded, color: Colors.black87, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12), // Khoảng cách giữa 2 nút
                          
                          // 🚀 NÚT THÔNG BÁO MỚI ĐƯỢC CHÈN VÀO ĐÂY ĐỒNG BỘ CHẤT LIỆU KÍNH
                          ListenableBuilder(
                            listenable: NotificationNotifier.instance,
                            builder: (context, child) {
                              final unread = NotificationNotifier.instance.unreadCount;
                              return GestureDetector(
                                onTap: () => context.push('/notifications'),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.6),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.black12, width: 0.5),
                                  ),
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      const Icon(Icons.notifications_none_rounded, color: Colors.black87, size: 20),
                                      if (unread > 0)
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFE2C55), // Dùng màu đỏ hồng để Badge cảnh báo nổi bật hơn
                                              shape: BoxShape.circle,
                                              border: Border.all(color: Colors.white, width: 1.5), // Viền trắng bóc tách khối
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              Positioned(
                bottom: 110, left: 16, right: 80, // Định vị trên đỉnh thanh Navigation Hub (90px + 20px Spacing) để tránh đè lấp
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LABEL DANH MỤC PHÂN LOẠI ĐỘNG (Áp dụng giải pháp 1 - Map từ Model)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        video.categoryTag,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tên hiển thị có thể Click để truy cập Profile - Trả về màu Trắng viền đổ bóng đen sậm chống chìm
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Sửa lỗi 404: Truyền 'username' thay vì 'id' để khớp với GoRouter
                        final String targetUsername = video.author['username'].toString(); 
                        context.push('/public-profile/$targetUsername');
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Flexible(
                            child: Text(
                              video.author['full_name'] ?? video.author['username'] ?? 'Người dùng', 
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17, shadows: [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 1))]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis, // Tự động cắt thành "..." nếu Tên quá dài
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                '@${video.author['username'] ?? 'user'}', 
                                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w500, fontSize: 13, shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1))]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis, // Bảo vệ cả Username không bị tràn
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // THẺ ĐẶT LỊCH THƯƠNG MẠI MỚI: Tái cấu trúc sang Hệ kính sáng Light Mode mượt mà quyến rũ
                    if (video.price > 0) ...[
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => _handleAuthGuard(() => _showBookingBottomSheet(video)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF80BF84).withOpacity(0.15), // Hạ độ phủ đục xanh mờ tinh tế hơn
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.4), width: 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 14), // Trả về màu icon trắng sáng tương phản cao
                                  const SizedBox(width: 6),
                                  Text(
                                    '${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(video.price)} • ĐẶT LỊCH NGAY',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.3), // Chữ màu trắng tinh khiết nổi bật trên nền kính
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // Caption thông minh: Tự động tính toán số dòng và hiển thị nút "Xem thêm"
                    ExpandableCaption(text: video.content),
                  ],
                ),
              ),

              
              // ================= CỤM TƯƠNG TÁC BÊN PHẢI PIXEL-PERFECT (TIKTOK ALGORITHM) =================
              Positioned(
                bottom: 110, // Đồng bộ trục Y để không bị che khuất bởi thanh điều hướng nổi của MainHub
                right: 12,   // Khoảng cách an toàn tuyệt đối từ biên màn hình vào tâm icon
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 0. Nút Tùy chọn mở rộng (...) - Trả về màu trắng phối bóng đổ đen nổi bật
                    GestureDetector(
                      onTap: () => _showCommentBottomSheet(index),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Icon(Icons.more_horiz_rounded, color: Colors.white, size: 30, shadows: [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1.5))]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // 1. Cụm Avatar Tác Giả Pixel-Perfect (Tách luồng sự kiện Avatar vs Nút Follow)
                    SizedBox(
                      width: 50,
                      height: 60,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.topCenter,
                        children: [
                          // Vùng bấm 1: Chạm vào Avatar điều hướng sang trang Public Profile cá nhân
                          GestureDetector(
                            onTap: () {
                              final String targetUsername = video.author['username'].toString();
                              context.push('/public-profile/$targetUsername');
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.4),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                backgroundColor: const Color(0xFF161616),
                                backgroundImage: GlobalCacheProvider.create(
                                  video.author['avatar_url'] ?? 'https://via.placeholder.com/150',
                                  maxWidth: 150, // 🚀 Tối ưu RAM: Ép giải mã ở kích thước nhỏ
                                  maxHeight: 150,
                                ),
                              ),
                            ),
                          ),
                          // Vùng bấm 2: Chạm chính xác vào nút dấu "+" với Quản lý trạng thái và Hoạt họa mượt mà
                          if (!_followedCreatorIds.contains(video.authorId))
                            Positioned(
                              bottom: -2,
                              child: GestureDetector(
                                onTap: () async {
                                  await _handleAuthGuard(() async {
                                    final targetId = video.authorId;
                                    final String creatorName = video.author['full_name'] ?? video.author['username'] ?? 'Đối tác';
                                    
                                    // 1. Cập nhật Optimistic UI: Đưa vào danh sách đã theo dõi để đổi trạng thái tức thì
                                    setState(() {
                                      _followedCreatorIds.add(targetId);
                                    });

                                    // 2. Kích hoạt thông báo AppToast kính mờ đặc sắc từ trên đỉnh màn hình
                                    AppToast.show(
                                      context: context,
                                      message: 'Đã theo dõi thành công chuyên gia $creatorName',
                                      isSuccess: true,
                                    );

                                    try {
                                      // 3. Chạy ngầm lệnh gọi API đồng bộ lên cơ sở dữ liệu hệ thống
                                      await ApiClient.instance.post('/user/follow/$targetId');
                                    } catch (e) {
                                      // Hoàn tác (Rollback) thầm lặng nếu API xảy ra lỗi kết nối
                                      setState(() {
                                        _followedCreatorIds.remove(targetId);
                                      });
                                      AppToast.show(
                                        context: context,
                                        message: 'Kết nối máy chủ thất bại. Vui lòng thử lại!',
                                        isSuccess: false,
                                      );
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOutBack,
                                  width: 21,
                                  height: 21,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF80BF84),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 1.5),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 3,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.add, 
                                      color: Colors.white, 
                                      size: 13,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14), // Spacing nén chặt lại theo chuẩn UI hiện đại
                    
                    // 2. Nút Thả Tim Động (Premium Particle Animation)
                    AnimatedPremiumLikeButton(
                      isLiked: video.isLiked,
                      likeCount: video.likesCount.toString(),
                      onTap: () => _toggleInteraction(index, 'like'),
                    ),
                    const SizedBox(height: 14),
                    
                    // 3. Nút Bình Luận - Trả về màu Trắng thanh thoát
                    _buildInteractButton(
                      Icons.mode_comment_rounded, 
                      video.commentsCount.toString(), 
                      () => _showCommentBottomSheet(index),
                      color: Colors.white,
                    ),
                    const SizedBox(height: 14),
                    
                    // 4. Nút Lưu Trữ - Trả về màu Trắng/Màu Vàng hổ phách
                    _buildInteractButton(
                      Icons.bookmark_rounded, 
                      video.savesCount.toString(), 
                      () => _toggleInteraction(index, 'save'),
                      color: video.isSaved ? const Color(0xFFFAC612) : Colors.white,
                    ),
                    const SizedBox(height: 14),
                    
                    // 5. Nút Chia Sẻ - Trả về màu Trắng tinh khôi
                    _buildInteractButton(
                      Icons.share_rounded, 
                      'Chia sẻ', 
                      () {
                        Share.share(
                          'Xem nội dung video bổ ích này từ AI Health Share: ${video.videoUrl}\nTiêu đề: ${video.title}',
                          subject: 'Chia sẻ video chăm sóc sức khỏe',
                        );
                      },
                      color: Colors.white,
                    ),
                    const SizedBox(height: 14),
                    // 6. Đĩa nhạc quay (Music Disc) chuẩn mẫu giao diện ở đáy góc phải
                    const _MusicDiscAnimated(),
                  ],
                ),
              ),

              // MỚI: LỚP PHỦ TÌM KIẾM NHANH (SEARCH OVERLAY WIDGET) TÁCH BIỆT KHÔNG LIÊN QUAN ĐẾN TAB EXPLORE
              if (_isSearchOpen)
                Positioned.fill(
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), // Sửa lỗi chính tả Lens của bộ lọc mờ
                      child: Container(
                        color: Colors.black.withOpacity(0.6),
                        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 12, left: 16, right: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hàng đầu tiên: Thanh Input và nút Hủy đóng
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: Colors.white24, width: 1),
                                    ),
                                    child: TextField(
                                      autofocus: true, // Tự động bung bàn phím hệ thống ngay khi chạm mở nút FIND
                                      style: const TextStyle(color: Colors.white, fontSize: 15),
                                      decoration: const InputDecoration(
                                        hintText: 'Tìm tiêu đề video hoặc tên chuyên gia...',
                                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                                        prefixIcon: Icon(Icons.search_rounded, color: Colors.white54, size: 20),
                                        border: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(vertical: 11),
                                      ),
                                      onChanged: (value) {
                                        setState(() {
                                          _searchQuery = value.trim().toLowerCase();
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isSearchOpen = false;
                                      _searchQuery = '';
                                    });
                                  },
                                  child: const Text('Hủy', style: TextStyle(color: Color(0xFF80BF84), fontSize: 15, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            // Thống kê số lượng bản ghi tìm thấy dựa trên Client Lọc (Giải pháp 1)
                            if (_searchQuery.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 12),
                                child: Text(
                                  'Kết quả phù hợp (${_videos.where((v) => v.title.toLowerCase().contains(_searchQuery) || (v.author['full_name']?.toString() ?? '').toLowerCase().contains(_searchQuery)).length})',
                                  style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500),
                                ),
                              ),
                            // Danh sách cuộn kết quả tìm kiếm nhanh mượt mà
                            Expanded(
                              child: _searchQuery.isEmpty
                                  ? const Center(child: Text('Nhập từ khóa để tìm kiếm nội dung nhanh...', style: TextStyle(color: Colors.white30, fontSize: 14)))
                                  : ListView(
                                      physics: const BouncingScrollPhysics(),
                                      children: _videos.asMap().entries.where((entry) {
                                        final video = entry.value;
                                        final name = (video.author['full_name']?.toString() ?? '').toLowerCase();
                                        return video.title.toLowerCase().contains(_searchQuery) || name.contains(_searchQuery);
                                      }).map((entry) {
                                        final index = entry.key;
                                        final video = entry.value;
                                        return Container(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.06),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                            leading: CircleAvatar(
                                              backgroundImage: GlobalCacheProvider.create(
                                                video.author['avatar_url'] ?? 'https://via.placeholder.com/150',
                                                maxWidth: 120, // 🚀 Tối ưu RAM: Ép giải mã kích thước nhỏ cho Overlay
                                                maxHeight: 120,
                                              ),
                                            ),
                                            title: Text(video.title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            subtitle: Text('@${video.author['username'] ?? 'user'} • ${video.categoryTag}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                            trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white24, size: 14),
                                            onTap: () {
                                              setState(() {
                                                _isSearchOpen = false;
                                                _searchQuery = '';
                                              });
                                              // Nhảy mượt tới video được tìm thấy trong luồng feeds chính
                                              _pageController.jumpToPage(index);
                                            },
                                          ),
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
      behavior: HitTestBehavior.opaque, // Khắc phục lỗi khó bấm icon
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          children: [
            // Đổ bóng đa tầng đen sậm (Layered Dark Drop Shadow) giúp Icon Trắng nổi rõ bần bật trên mọi phân cảnh video
            Icon(
              icon, 
              color: color, 
              size: 36,
              shadows: [
                Shadow(color: Colors.black.withOpacity(0.5), blurRadius: 6, offset: const Offset(0, 2)),
                Shadow(color: Colors.black.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            const SizedBox(height: 3),
            // Định dạng font chữ số lượng màu trắng kèm đổ bóng đen chân bám chắc chắn
            Text(
              text, 
              style: TextStyle(
                color: color == Colors.white ? Colors.white : color, 
                fontWeight: FontWeight.w700, 
                fontSize: 12, 
                letterSpacing: -0.2,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 4, offset: const Offset(0, 1.5))
                ]
              )
            ),
          ],
        ),
      ),
    );
  }
}

// ================= WIDGET XỬ LÝ NÚT "XEM THÊM" CHO MÔ TẢ DÀI =================
class ExpandableCaption extends StatefulWidget {
  final String text;
  const ExpandableCaption({super.key, required this.text});

  @override
  State<ExpandableCaption> createState() => _ExpandableCaptionState();
}

class _ExpandableCaptionState extends State<ExpandableCaption> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded), // Nhấn vào chữ để bung rộng/thu gọn
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.text,
            maxLines: _isExpanded ? null : 2, // Mặc định khóa 2 dòng
            overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white, // Trả về màu trắng tinh khiết chuẩn UI video ngắn
              fontSize: 14, 
              fontWeight: FontWeight.w400, 
              height: 1.4, 
              letterSpacing: 0.2, 
              shadows: [Shadow(color: Colors.black87, blurRadius: 6, offset: Offset(1, 1))] // Đổ bóng đen bảo vệ chữ
            ),
          ),
          // Nếu chưa mở rộng VÀ độ dài ký tự lớn hơn 60 (tương đương 2 dòng), hiện nút "Xem thêm"
          if (!_isExpanded && widget.text.length > 60)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Xem thêm', 
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14, shadows: [Shadow(color: Colors.black87, blurRadius: 4, offset: Offset(1, 1))])
              ),
            ),
        ],
      ),
    );

  }
}

// Widget đĩa nhạc tự quay mượt mà chuẩn phong cách UI TikTok mẫu
class _MusicDiscAnimated extends StatefulWidget {
  const _MusicDiscAnimated();

  @override
  State<_MusicDiscAnimated> createState() => _MusicDiscAnimatedState();
}

class _MusicDiscAnimatedState extends State<_MusicDiscAnimated> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [Colors.black87, Colors.black54, Colors.black87],
          ),
          border: Border.all(color: Colors.white30, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: Icon(Icons.music_note_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}