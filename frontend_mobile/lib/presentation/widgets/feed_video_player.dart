import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

class FeedVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isActive; 
  final VoidCallback? onDoubleTap; // 1. Thêm Callback đón lệnh Double Tap

  const FeedVideoPlayer({
    super.key, 
    required this.videoUrl, 
    required this.isActive,
    this.onDoubleTap,
  });

  @override
  State<FeedVideoPlayer> createState() => _FeedVideoPlayerState();
}

class _FeedVideoPlayerState extends State<FeedVideoPlayer> with WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isUserPaused = false; 
  
  bool _showHeart = false; // 2. Cờ hiệu điều khiển Animation Tim nổ

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _isInitialized = true);
          _controller.setLooping(true);
          if (widget.isActive) _controller.play();
        }
      });
  }

  @override
  void didUpdateWidget(covariant FeedVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInitialized) {
      if (widget.isActive && !_isUserPaused) {
        _controller.play();
      } else {
        _controller.pause();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (widget.isActive && !_isUserPaused) {
        _controller.play();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose(); 
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isUserPaused = true;
      } else {
        _controller.play();
        _isUserPaused = false;
      }
    });
  }

  // 3. Logic xử lý Double Tap
  void _handleDoubleTap() {
    if (widget.onDoubleTap != null) {
      widget.onDoubleTap!();
    }
    
    // Bật hiệu ứng tim nổ trong 500 mili-giây
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)));
    }

    return VisibilityDetector(
      key: Key(widget.videoUrl),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 0) {
          _controller.pause();
        } else if (info.visibleFraction == 1.0 && widget.isActive && !_isUserPaused) {
          _controller.play();
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // QUAN TRỌNG: Ép bắt toàn bộ vùng chạm trên màn hình
        onTap: _togglePlayPause,
        onDoubleTap: _handleDoubleTap, // Đăng ký sự kiện Double Tap
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Lớp Video
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
            
            // Lớp Phủ Nút Play (Single Tap)
            AnimatedOpacity(
              opacity: _isUserPaused ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.5), shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow, color: Colors.white, size: 64),
              ),
            ),

            // Lớp Phủ Tim Nổi (Double Tap)
            AnimatedScale(
              scale: _showHeart ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.elasticOut,
              child: AnimatedOpacity(
                opacity: _showHeart ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: const Icon(Icons.favorite, color: Colors.red, size: 100),
              ),
            ),
          ],
        ),
      ),
    );
  }
}