import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'auth_guard.dart';
import '../../core/network/video_cache_engine.dart';
import '../../core/manager/audio_focus_manager.dart';

// 🚀 THUẬT TOÁN CONTROLLER POOL (LRU CACHE) + DISK CACHE
// Quản lý tối đa 5 VideoPlayerController đồng thời để tái sử dụng, 
// chống tràn RAM và ngăn crash Codec phần cứng.
class FeedVideoPool {
  static final Map<String, VideoPlayerController> _pool = {};
  static final List<String> _lru = [];
  static const int maxPoolSize = 8; // 🚀 TĂNG POOL SIZE: Tạo vùng đệm an toàn lớn hơn Window Cache (5), triệt tiêu lỗi tranh chấp
  
  // 🚀 BỌC THÉP TRẠNG THÁI: Hàm kiểm tra vòng đời của Controller
  static bool isControllerAlive(String url) {
    return _pool.containsKey(url);
  }

  // 🚀 CÔNG TẮC TỔNG TOÀN CỤC: Khóa cứng âm lượng toàn bộ Pool khi Studio Đăng tải mở/đóng thành công
  static bool isGlobalMutedForUpload = false;

  static Future<VideoPlayerController> getController(String url) async {
    // Tái sử dụng Controller nếu đã tồn tại trong Pool
    if (_pool.containsKey(url)) {
      _lru.remove(url);
      _lru.add(url); // Đẩy lên vị trí sử dụng gần nhất
      return _pool[url]!;
    }

    // Nếu Pool đầy, giải phóng Controller cũ nhất (Least Recently Used)
    if (_pool.length >= maxPoolSize) {
      final oldestUrl = _lru.removeAt(0);
      _pool[oldestUrl]?.dispose();
      _pool.remove(oldestUrl);
    }

    // 🚀 LÕI VIDEO CACHE: Lấy URL tối ưu (File nội bộ nếu đã Cache, hoặc Network gốc)
    final optimalUrl = await VideoCacheEngine.getOptimalUrl(url);

    // Khởi tạo Controller dựa trên nguồn File hoặc Network kèm theo cấu hình trộn kênh âm thanh đồng bộ với Website
    // 🚀 HOTFIX: Nhận diện đường dẫn tuyệt đối (bắt đầu bằng '/' hoặc 'file://') và khởi tạo File an toàn
    final controller = optimalUrl.startsWith('/') || optimalUrl.startsWith('file://')
        ? VideoPlayerController.file(
            File(optimalUrl.replaceFirst('file://', '')),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(optimalUrl),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
          );
 
    _pool[url] = controller;
    _lru.add(url);
    return controller;
  }
}

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isActive; 
  final VoidCallback? onDoubleTap; 
  final int videoIndex;   // MỚI: Vị trí của video này trong danh sách
  final int currentIndex; // MỚI: Vị trí video người dùng đang thực sự xem

  const FeedVideoPlayer({
    super.key, 
    required this.videoUrl, 
    required this.isActive,
    this.onDoubleTap,
    required this.videoIndex,
    required this.currentIndex,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

// Bổ sung AutomaticKeepAliveClientMixin để chống khai tử Video
class _FeedVideoPlayerState extends State<FeedVideoPlayer> with WidgetsBindingObserver, TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  
  // 🚀 THUẬT TOÁN WINDOW CACHE: BẢO LƯU RAM CHỐNG TRÀN BỘ NHỚ
  // Chỉ giữ sống Video trong phạm vi Cửa sổ: N-2, N-1, N, N+1, N+2 (khoảng cách <= 2)
  @override
  bool get wantKeepAlive => (widget.videoIndex - widget.currentIndex).abs() <= 2;

  VideoPlayerController? _controller; // Cho phép Null trong lúc chờ Disk Cache Engine phản hồi
  bool _isInitialized = false;
  bool _isUserPaused = false; 
  
  // MỚI: Biến theo dõi tiến độ video chạy động theo thời gian thực (0.0 -> 1.0)
  double _progress = 0.0;
  
  // --- TIKTOK MULTI-HEART STATE ---
  final List<Map<String, dynamic>> _hearts = [];
  int _heartCounter = 0;
  Offset _lastTapPosition = Offset.zero;


  // Tách hàm Lắng nghe riêng để dễ dàng gỡ bỏ chống rò rỉ bộ nhớ (Memory Leak)
  void _videoListener() {
    if (!FeedVideoPool.isControllerAlive(widget.videoUrl)) return; // 🚀 GUARD: Chặn truy cập vùng nhớ chết
    if (mounted && _controller != null && _controller!.value.isInitialized && _controller!.value.duration.inMilliseconds > 0) {
      final double currentPos = _controller!.value.position.inMilliseconds.toDouble();
      final double totalDuration = _controller!.value.duration.inMilliseconds.toDouble();
      setState(() {
        _progress = (currentPos / totalDuration).clamp(0.0, 1.0);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🚀 TÍCH HỢP KIẾN TRÚC ĐẲNG CẤP: Lắng nghe trọng tài âm thanh tập trung
    AudioFocusManager.instance.addListener(_onAudioFocusChanged);

    // Lấy Controller từ Pool (Hỗ trợ Async Disk Cache)
    FeedVideoPool.getController(widget.videoUrl).then((controller) {
      if (!mounted) return;
      // 🚀 CHỐT CHẶN RACE CONDITION: Kiểm tra xem trong lúc chờ Async, Controller này có bị Pool khai tử ngầm chưa
      if (!FeedVideoPool.isControllerAlive(widget.videoUrl)) return;
      
      _controller = controller;
      _controller!.addListener(_videoListener);

      if (!_controller!.value.isInitialized) {
        _controller!.initialize().then((_) {
          if (mounted) {
            setState(() => _isInitialized = true);
            _controller!.setLooping(true);
            if (widget.isActive) _controller!.play();
          }
        });
      } else {
        setState(() => _isInitialized = true);
        if (widget.isActive) _controller!.play();
      }
    });
  }

  // CHỈ GIỮ LẠI 1 HÀM didUpdateWidget DUY NHẤT Ở ĐÂY
  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Đánh giá lại trạng thái bảo lưu bộ nhớ khi luồng vuốt thay đổi (Window Cache)
    if (oldWidget.currentIndex != widget.currentIndex) {
      updateKeepAlive();
    }

    // 🚀 TỰ ĐỘNG KHÔI PHỤC (AUTO-RESUME ENGINE): Nếu quay lại video này nhưng Controller đã bị dọn dẹp mất
    if (widget.isActive && (!FeedVideoPool.isControllerAlive(widget.videoUrl) || _controller == null)) {
      setState(() {
        _isInitialized = false;
        _controller = null;
      });
      FeedVideoPool.getController(widget.videoUrl).then((controller) {
        if (!mounted || !FeedVideoPool.isControllerAlive(widget.videoUrl)) return;
        _controller = controller;
        _controller!.addListener(_videoListener);
        if (!_controller!.value.isInitialized) {
          _controller!.initialize().then((_) {
            if (mounted) {
              setState(() => _isInitialized = true);
              _controller!.setLooping(true);
              if (widget.isActive && !_isUserPaused && AudioFocusManager.instance.shouldFeedsPlay) {
                _controller!.play();
              }
            }
          });
        } else {
          setState(() => _isInitialized = true);
          if (widget.isActive && !_isUserPaused && AudioFocusManager.instance.shouldFeedsPlay) {
            _controller!.play();
          }
        }
      });
      return; // Thoát luồng didUpdate cũ để nhường chỗ cho luồng nạp mới
    }

    if (_isInitialized && _controller != null && FeedVideoPool.isControllerAlive(widget.videoUrl)) {
      // 🚀 ĐỒNG BỘ: Check qua AudioFocusManager thay vì cờ tĩnh toàn cục
      if (widget.isActive && !_isUserPaused && AudioFocusManager.instance.shouldFeedsPlay) {
        _controller!.play();
      } else {
        _controller!.pause();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller!.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive && !_isUserPaused) {
        _controller!.play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_videoListener);
    
    // 🚀 GỠ THỤ THỂ: Tránh rò rỉ bộ nhớ RAM hệ thống
    AudioFocusManager.instance.removeListener(_onAudioFocusChanged);
    
    // KHÔNG GỌI _controller.dispose() Ở ĐÂY.
    // Việc giải phóng tài nguyên hiện tại do lớp FeedVideoPool tự động quản lý.
    
    super.dispose();
  }

  void _onAudioFocusChanged() {
    if (!mounted || _controller == null || !_isInitialized) return;
    
    // Nếu trọng tài ra lệnh tắt luồng Feeds, ép pause vật lý ngay lập tức
    if (!AudioFocusManager.instance.shouldFeedsPlay) {
      _controller!.pause();
    } else if (widget.isActive && !_isUserPaused) {
      _controller!.play();
    }
  }

  void _togglePlayPause() {
    if (!_isInitialized || _controller == null || !FeedVideoPool.isControllerAlive(widget.videoUrl)) return;
    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        _isUserPaused = true;
      } else {
        _controller!.play();
        _isUserPaused = false;
      }
    });
  }

  void _handleDoubleTap() {
    AuthGuard.run(context, action: () {
      // Kích hoạt phản hồi xúc giác nhẹ (Haptic Feedback) chuẩn trải nghiệm TikTok
      HapticFeedback.lightImpact();

      if (widget.onDoubleTap != null) {
        widget.onDoubleTap!();
      }
      
      final int id = ++_heartCounter;
    setState(() {
      _hearts.add({'id': id, 'position': _lastTapPosition});
    });
    
    // Tự hủy tim khỏi bộ nhớ sau 1 giây (Tiết kiệm RAM)
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) {
          setState(() => _hearts.removeWhere((h) => h['id'] == id));
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // BẮT BUỘC phải gọi để kích hoạt thuật toán KeepAlive
    
    // 🚀 BẪY LỖI NỘI TẠI (LIFECYCLE VALUE GUARD): Chặn đứng việc render nếu Controller đã chết hoặc lỗi
    if (!_isInitialized || _controller == null || !FeedVideoPool.isControllerAlive(widget.videoUrl)) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
    }

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        if (!FeedVideoPool.isControllerAlive(widget.videoUrl) || _controller == null) return;
        
        if (info.visibleFraction < 0.7) {
          if (_isInitialized && _controller!.value.isPlaying) {
            _controller!.pause();
          }
        } else if (info.visibleFraction >= 0.7 && widget.isActive) {
          if (!_isUserPaused && AudioFocusManager.instance.shouldFeedsPlay) {
            _controller!.play();
          } else {
            _controller!.pause();
          }
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, 
        onTapDown: (details) => _lastTapPosition = details.localPosition, // Bắt Tọa Độ
        onTap: _togglePlayPause,
        onDoubleTap: _handleDoubleTap, 
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Lớp Video
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            ),
            
            // Lớp Phủ Nút Play (Single Tap) đã được nâng cấp UI
            AnimatedOpacity(
              opacity: _isUserPaused ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.white.withOpacity(0.3))),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 64),
              ),
            ),
            
            // Lớp báo hiệu Đang Đệm (Buffering Indicator) chống giật
            if (_controller!.value.isBuffering)
               const CircularProgressIndicator(color: Color(0xFF80BF84), strokeWidth: 3),

            // MỚI: Thanh tiến trình video (Progress Bar) - Chuyển sang Tone màu sáng (Nền tối nhẹ, chạy màu thương hiệu xanh đậm)
            Positioned(
              bottom: 96,
              left: 0,
              right: 0,
              child: Opacity(
                opacity: 0.8,
                child: Container(
                  height: 2,
                  width: double.infinity,
                  color: Colors.black12, // Máng chạy màu tối nhạt tương phản nền sáng
                  child: Stack(
                    children: [
                      FractionallySizedBox(
                        widthFactor: _progress,
                        child: Container(
                          height: 2,
                          color: const Color(0xFF5e9662), // Màu xanh đậm thương hiệu nổi bật trên Light Mode
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Lớp Phủ Tim Nổi Đa Điểm TikTok (Multi-Tap Dynamic Position)

            // MỚI: Lớp phủ Báo lỗi luồng phát mạng (Network / Stream Error Overlay) - Chuyển sang Tone màu Sáng toàn diện
            if (_controller!.value.hasError)
              Container(
                color: const Color(0xFFFAFAFA), // Nền xám trắng Light Mode sạch sẽ
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded, color: Colors.black38, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Lỗi tải video. Vui lòng kiểm tra kết nối.',
                        style: TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isInitialized = false;
                          });
                          _controller!.initialize().then((_) {
                            if (mounted) {
                              setState(() => _isInitialized = true);
                              _controller!.play();
                            }
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF80BF84),
                          foregroundColor: Colors.black87, // Đổi text nút sang đậm màu
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18, color: Colors.black87),
                        label: const Text('Thử lại'),
                      ),
                    ],
                  ),
                ),
              ),

            // Lớp Phủ Tim Nổi Đa Điểm TikTok (Multi-Tap Dynamic Position)
            ..._hearts.map((heart) {
              return Positioned(
                left: heart['position'].dx - 50, // Căn giữa ngón tay
                top: heart['position'].dy - 50,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(heart['id']),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutBack, // Hiệu ứng nảy Spring
                  builder: (context, value, child) {
                    // Logic mượt: Nảy lên -> Giữ nguyên -> Mờ đi
                    final opacity = value < 0.1 ? (value * 10) : (value > 0.7 ? (1 - value) * 3.33 : 1.0);
                    final scale = 0.5 + (value * 0.7); // Phóng to dần
                    final dy = -(value * 120); // Bay bổng lên trên 120px

                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, dy),
                        child: Transform.scale(
                          scale: scale,
                          child: Transform.rotate(
                            angle: (heart['id'] % 2 == 0 ? 0.2 : -0.2), // Xoay nghiêng trái/phải ngẫu nhiên
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(Icons.favorite, color: Colors.pinkAccent.withOpacity(0.4), size: 110),
                                const Icon(Icons.favorite, color: Colors.red, size: 90),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}