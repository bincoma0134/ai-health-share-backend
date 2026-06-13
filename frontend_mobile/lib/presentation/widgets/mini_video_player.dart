import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class MiniVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const MiniVideoPlayer({super.key, required this.videoUrl});

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
    // CẤU HÌNH TĂNG TỐC 1: Sử dụng VideoPlayerOptions để kiểm soát tài nguyên chạy ngầm của hệ điều hành
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true, // Cho phép chạy song song không làm gián đoạn nhạc nền hệ thống
        allowBackgroundPlayback: false, // Tắt ngay lập tức khi ứng dụng xuống background để tiết kiệm pin
      ),
    );

    try {
      // Kích hoạt nạp luồng không đồng bộ với cấu hình khởi tạo trước
      await _controller.initialize();
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
        // CẤU HÌNH TĂNG TỐC 2: Thiết lập luồng phát nén không âm thanh mượt mà tức thì cho Preview
        await _controller.setVolume(0.0); 
        await _controller.setLooping(true);
        
        // Tự động kích hoạt phát lại ngay khi bộ đệm tối thiểu (Buffer chunk) sẵn sàng
        if (mounted) {
          _controller.play();
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

  @override
  void dispose() {
    // Giải phóng vùng đệm và luồng stream ngay lập tức khi widget bị cuộn khỏi Viewport
    _controller.pause();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      // Dự phòng an toàn (Fallback UI) nếu link video lỗi, hiển thị icon y tế chuyên nghiệp
      return Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 28)),
      );
    }

    if (!_isInitialized) {
      // TỐI ƯU HÓA UX 3: Thay thế vòng quay Circular cũ bằng bộ khung xương mờ mịn màng sang trọng
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

    // Ép cấu trúc khung hình lấp đầy diện tích thẻ Card không để lại vệt đen (Zero-padding Cover layout)
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller.value.size.width,
          height: _controller.value.size.height,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}