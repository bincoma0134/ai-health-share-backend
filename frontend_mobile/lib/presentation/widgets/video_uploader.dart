import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../../../data/services/user_api_service.dart';

class VideoUploader extends StatefulWidget {
  final Function(String) onUploadSuccess;
  final String label;
  final String folder;
  final double height;
  final double? width;

  const VideoUploader({
    super.key,
    required this.onUploadSuccess,
    this.label = 'Nhấn để chọn Video',
    this.folder = 'media/videos',
    this.height = 200,
    this.width,
  });

  @override
  State<VideoUploader> createState() => _VideoUploaderState();
}

class _VideoUploaderState extends State<VideoUploader> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  bool _isUploadSuccess = false;
  double _progress = 0.0;

  Future<void> _pickAndUpload() async {
    // 1. Validation: Giới hạn độ dài Video ngay khi pick
    final XFile? video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );

    if (video == null) return;

    final file = File(video.path);
    
    // Kiểm tra dung lượng (Chặn > 500MB)
    final double fileSizeInMB = file.lengthSync() / (1024 * 1024);
    if (fileSizeInMB > 500) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dung lượng video vượt quá 500MB'), backgroundColor: Colors.orange));
      return;
    }

    setState(() {
      _isUploading = true;
      _isUploadSuccess = false;
      _progress = 0.0;
    });

    try {
      // 2. THUẬT TOÁN NÉN TỐI ƯU: Nén video tại Local trước khi tải lên để giảm 70-80% dung lượng
      File fileToUpload = file;
      try {
        final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          file.path,
          quality: VideoQuality.MediumQuality, // Cân bằng hoàn hảo giữa dung lượng và chất lượng
          deleteOrigin: false, // Giữ nguyên file gốc trong máy người dùng
        );
        if (mediaInfo != null && mediaInfo.file != null) {
          fileToUpload = mediaInfo.file!;
        }
      } catch (e) {
        debugPrint("Lỗi thuật toán nén (Fallback sang file gốc): $e");
      }

      // 3. Upload ngầm file đã nén với cổng stream chuyên dụng và lắng nghe tiến trình nhị phân
      final url = await UserApiService.uploadVideo(
        fileToUpload,
        widget.folder,
        onSendProgress: (int sent, int total) {
          if (mounted && total > 0) {
            setState(() {
              _progress = sent / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        if (url != null) {
          setState(() => _isUploadSuccess = true);
          widget.onUploadSuccess(url);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi tải video lên máy chủ!'), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _progress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể tải tệp: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: (_isUploading || _isUploadSuccess) ? null : _pickAndUpload,
      child: Container(
        height: widget.height,
        width: widget.width ?? double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _isUploadSuccess ? Colors.blueAccent : Colors.white24,
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Trạng thái chưa tải
            if (!_isUploadSuccess && !_isUploading)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.video_library_outlined, color: Colors.white54, size: 40),
                  const SizedBox(height: 8),
                  Text(widget.label, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  const Text('Tối đa 3 phút / 500MB', style: TextStyle(color: Colors.white30, fontSize: 10)),
                ],
              ),

            // Trạng thái thành công
            if (_isUploadSuccess && !_isUploading)
              const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: Colors.blueAccent, size: 48),
                  SizedBox(height: 8),
                  Text('Video đã đính kèm', style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),

            // Lớp phủ Loading (Giống giao diện web báo "Đang xử lý nén")
            if (_isUploading)
              Container(
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 48, height: 48,
                            child: CircularProgressIndicator(
                              value: _progress > 0 ? _progress : null, 
                              color: Colors.blueAccent, 
                              backgroundColor: Colors.white24
                            ),
                          ),
                          Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(_progress == 0.0 ? 'Đang xử lý nén video...' : 'Hệ thống đang tải lên...', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('Vui lòng không đóng cửa sổ này', style: TextStyle(color: Colors.white54, fontSize: 9), textAlign: TextAlign.center),
                      ),
                    ],
                  ),
                ),
              ),
            // Nút gỡ Video khi đã tải xong
            if (_isUploadSuccess && !_isUploading)
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _isUploadSuccess = false);
                    widget.onUploadSuccess(""); // Xóa URL
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}