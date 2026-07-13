import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart'; // Màng lọc kiểm soát hiển thị thông minh
import '../../core/network/video_cache_engine.dart';

class MiniVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isMuted; 
  // 🚀 MỚI: Các tham số cấu hình Trim dạng Tùy chọn (Nullable) để tương thích ngược 100% với các màn hình khác
  final double? trimStartPercent;   
  final double? trimEndPercent;     
  final ValueChanged<double>? onProgressUpdate; 

  const MiniVideoPlayer({
    super.key, 
    required this.videoUrl, 
    this.isMuted = true,
    this.trimStartPercent,
    this.trimEndPercent,
    this.onProgressUpdate,
  });

  @override
  State<MiniVideoPlayer> createState() => _MiniVideoPlayerState();
}

class _MiniVideoPlayerState extends State<MiniVideoPlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    // 🚀 TÍCH HỢP CACHE ENGINE: Truy xuất File từ ổ cứng nếu có để khởi động 0ms
    final optimalUrl = await VideoCacheEngine.getOptimalUrl(widget.videoUrl);

    // CẤU HÌNH TĂNG TỐC 1: Sử dụng VideoPlayerOptions để kiểm soát tài nguyên chạy ngầm của hệ điều hành
    // 🚀 HOTFIX: Đồng bộ cơ chế phân tích đường dẫn an toàn từ Engine chính
    _controller = optimalUrl.startsWith('/') || optimalUrl.startsWith('file://')
        ? VideoPlayerController.file(
            File(optimalUrl.replaceFirst('file://', '')),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(optimalUrl),
            videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
          );

    try {
      // Kích hoạt nạp luồng không đồng bộ với cấu hình khởi tạo trước
      await _controller.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        await _controller.setVolume(widget.isMuted ? 0.0 : 1.0); 
        
        // Luồng Trim thì tự quản lý vòng lặp khép kín, luồng cũ giữ looping mặc định của hệ điều hành
        final isTrimMode = widget.trimStartPercent != null && widget.trimEndPercent != null && widget.onProgressUpdate != null;
        await _controller.setLooping(!isTrimMode);
        
        if (isTrimMode) {
          _controller.addListener(_videoTrimListener);
          final totalMs = _controller.value.duration.inMilliseconds;
          final startMs = (totalMs * widget.trimStartPercent!).toInt();
          _controller.seekTo(Duration(milliseconds: startMs));
        }
      }
    } catch (e) {
      debugPrint("Lỗi nạp luồng phát nhanh Video: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    }
  }

  void _videoTrimListener() {
    if (!mounted || !_isInitialized || widget.trimStartPercent == null || widget.trimEndPercent == null || widget.onProgressUpdate == null) return;
    
    final totalMs = _controller.value.duration.inMilliseconds;
    if (totalMs <= 0) return;

    final currentMs = _controller.value.position.inMilliseconds;
    final startMs = (totalMs * widget.trimStartPercent!).toInt();
    final endMs = (totalMs * widget.trimEndPercent!).toInt();

    // 1. Tính toán tỷ lệ phần trăm tiến trình tương đối chạy trong dải Slider biên
    final trimDuration = endMs - startMs;
    if (trimDuration > 0) {
      final elapsedInTrim = (currentMs - startMs).clamp(0, trimDuration);
      widget.onProgressUpdate!(elapsedInTrim / trimDuration);
    }

    // 2. Logic ép vòng lặp khép kín tại biên cuối (YouTube Short Style)
    if (currentMs >= endMs || currentMs < startMs) {
      _controller.seekTo(Duration(milliseconds: startMs));
      _controller.play();
    }
  }

  @override
  void didUpdateWidget(covariant MiniVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInitialized) {
      if (oldWidget.isMuted != widget.isMuted) {
        _controller.setVolume(widget.isMuted ? 0.0 : 1.0);
      }
      // Đưa đầu phát về vị trí biên mới nếu màn hình cha cập nhật thanh trượt kéo biên
      if (widget.trimStartPercent != null && widget.trimEndPercent != null) {
        if (oldWidget.trimStartPercent != widget.trimStartPercent || oldWidget.trimEndPercent != widget.trimEndPercent) {
          final totalMs = _controller.value.duration.inMilliseconds;
          final startMs = (totalMs * widget.trimStartPercent!).toInt();
          _controller.seekTo(Duration(milliseconds: startMs));
          _controller.play();
        }
      }
    }
  }

  @override
  void dispose() {
    // Luôn an toàn gỡ listener để tránh rò rỉ bộ nhớ
    try {
      _controller.removeListener(_videoTrimListener);
    } catch (_) {}
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 28)),
      );
    }

    if (!_isInitialized) {
      return Container(
        color: const Color(0xFFF8FAFC),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: const Color(0xFF80BF84).withOpacity(0.4),
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }

    // Bọc VisibilityDetector thiết lập màng bảo vệ tự động đóng ngắt luồng giải mã video tiết kiệm tài nguyên
    return VisibilityDetector(
      key: Key('mini_video_${widget.videoUrl}_${identityHashCode(this)}'),
      onVisibilityChanged: (visibilityInfo) {
        if (!mounted || !_isInitialized) return;
        final double visiblePercentage = visibilityInfo.visibleFraction * 100;
        
        // Thuật toán: Nếu tỷ lệ hiển thị dưới 15% diện tích màn hình, lập tức đóng ngắt luồng CPU để bảo vệ RAM
        if (visiblePercentage < 15) {
          if (_controller.value.isPlaying) {
            _controller.pause();
          }
        }
      },
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller.value.size.width,
                height: _controller.value.size.height,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _controller.value.isPlaying ? _controller.pause() : _controller.play();
                    });
                  },
                  child: VideoPlayer(_controller),
                ),
              ),
            ),
          ),
          
          if (!_controller.value.isPlaying)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
              ),
            ),
        ],
      ),
    );
  }
}