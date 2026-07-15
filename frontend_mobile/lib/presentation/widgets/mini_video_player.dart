import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart'; // Màng lọc kiểm soát hiển thị thông minh
import '../../core/network/video_cache_engine.dart';

class MiniVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final bool isMuted; 
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
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    // 🚀 BƯỚC 1: Xóa Eager Initialization. Controller sẽ được Lazy Init bởi VisibilityDetector
  }

  Future<void> _initializePlayer() async {
    if (_isInitializing || _controller != null) return;
    _isInitializing = true;
    
    try {
      final optimalUrl = await VideoCacheEngine.getOptimalUrl(widget.videoUrl);

      final controller = optimalUrl.startsWith('/') || optimalUrl.startsWith('file://')
          ? VideoPlayerController.file(
              File(optimalUrl.replaceFirst('file://', '')),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(optimalUrl),
              videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true, allowBackgroundPlayback: false),
            );

      await controller.initialize();
      
      if (!mounted) {
        controller.dispose();
        return;
      }

      _controller = controller;
      setState(() {
        _isInitialized = true;
        _hasError = false;
      });
      
      await _controller!.setVolume(widget.isMuted ? 0.0 : 1.0); 
      
      final isTrimMode = widget.trimStartPercent != null && widget.trimEndPercent != null && widget.onProgressUpdate != null;
      await _controller!.setLooping(!isTrimMode);
      
      if (isTrimMode) {
        _controller!.addListener(_videoTrimListener);
        final totalMs = _controller!.value.duration.inMilliseconds;
        final startMs = (totalMs * widget.trimStartPercent!).toInt();
        _controller!.seekTo(Duration(milliseconds: startMs));
      }
    } catch (e) {
      debugPrint("Lỗi nạp luồng phát nhanh Video: $e");
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _disposePlayer() {
    if (_controller == null) return;
    try {
      _controller!.removeListener(_videoTrimListener);
    } catch (_) {}
    
    _controller!.pause();
    _controller!.dispose();
    _controller = null;
    
    if (mounted) {
      setState(() {
        _isInitialized = false;
      });
    }
  }

  void _videoTrimListener() {
    if (!mounted || !_isInitialized || _controller == null || widget.trimStartPercent == null || widget.trimEndPercent == null || widget.onProgressUpdate == null) return;
    
    final totalMs = _controller!.value.duration.inMilliseconds;
    if (totalMs <= 0) return;

    final currentMs = _controller!.value.position.inMilliseconds;
    final startMs = (totalMs * widget.trimStartPercent!).toInt();
    final endMs = (totalMs * widget.trimEndPercent!).toInt();

    final trimDuration = endMs - startMs;
    if (trimDuration > 0) {
      final elapsedInTrim = (currentMs - startMs).clamp(0, trimDuration);
      widget.onProgressUpdate!(elapsedInTrim / trimDuration);
    }

    if (currentMs >= endMs || currentMs < startMs) {
      _controller!.seekTo(Duration(milliseconds: startMs));
      _controller!.play();
    }
  }

  @override
  void didUpdateWidget(covariant MiniVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isInitialized && _controller != null) {
      if (oldWidget.isMuted != widget.isMuted) {
        _controller!.setVolume(widget.isMuted ? 0.0 : 1.0);
      }
      if (widget.trimStartPercent != null && widget.trimEndPercent != null) {
        if (oldWidget.trimStartPercent != widget.trimStartPercent || oldWidget.trimEndPercent != widget.trimEndPercent) {
          final totalMs = _controller!.value.duration.inMilliseconds;
          final startMs = (totalMs * widget.trimStartPercent!).toInt();
          _controller!.seekTo(Duration(milliseconds: startMs));
          _controller!.play();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('mini_video_${widget.videoUrl}_${identityHashCode(this)}'),
      onVisibilityChanged: (visibilityInfo) {
        if (!mounted) return;
        final double visiblePercentage = visibilityInfo.visibleFraction * 100;
        
        // 🚀 BƯỚC 2: Giải phóng 100% tài nguyên RAM khi trượt khỏi màn hình
        if (visiblePercentage < 15) {
          _disposePlayer();
        } else {
          // Khởi tạo lại khi cuộn trúng tiêu điểm
          if (_controller == null && !_isInitializing) {
            _initializePlayer();
          }
        }
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (_hasError) {
      return Container(
        color: const Color(0xFFF1F5F9),
        child: const Center(child: Icon(Icons.broken_image_rounded, color: Colors.black26, size: 28)),
      );
    }

    if (!_isInitialized || _controller == null) {
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

    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.size.width,
              height: _controller!.value.size.height,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                  });
                },
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
        ),
        
        if (!_controller!.value.isPlaying)
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
            ),
          ),
      ],
    );
  }
}