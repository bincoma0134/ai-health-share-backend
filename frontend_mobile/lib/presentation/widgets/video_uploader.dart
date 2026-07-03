import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // 🚀 HOTFIX: Thêm thư viện để kích hoạt hàm chạy đa luồng compute()
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import '../../../data/services/user_api_service.dart';
import 'package:video_player/video_player.dart';
import 'feed_video_player.dart'; // 🚀 HOTFIX 1: Thêm import để định nghĩa lớp điều khiển tĩnh FeedVideoPool

// 🚀 WORKER ISOLATE: Hàm tĩnh phải nằm ngoài hoàn toàn cấu trúc Class để chạy đa luồng Isolate chuẩn xác
Future<Map<String, double>> _isolateExtractMetadata(String path) async {
  final MediaInfo mediaInfoData = await VideoCompress.getMediaInfo(path);
  final double duration = (mediaInfoData.duration ?? 0) / 1000;
  final double size = (mediaInfoData.filesize ?? File(path).lengthSync()) / (1024 * 1024);
  return {'duration': duration, 'size': size};
}

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
  final ImagePicker _picker = _pickerInstance ?? ImagePicker();
  static final ImagePicker _pickerInstance = ImagePicker();
  bool _isUploading = false;
  bool _isUploadSuccess = false;
  double _progress = 0.0;

  Future<void> _pickAndUpload() async {
    final XFile? video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;

    // Kích hoạt trạng thái tải, giao diện vẫn nhận click tương tác bình thường
    setState(() {
      _isUploading = true;
      _progress = 0.0;
    });

    // Ép luồng Feeds chính tạm thời dừng mọi hoạt động phát tiếng
    FeedVideoPool.isGlobalMutedForUpload = true;

    try {
      // 🚀 KHẮC PHỤC TRIỆT ĐỂ TREO UI: Ủy thác tác vụ quét file nặng cho Worker Thread phụ qua compute()
      final Map<String, double> metadata = await compute(_isolateExtractMetadata, video.path);
      final double durationInSeconds = metadata['duration'] ?? 0;
      final double fileSizeInMB = metadata['size'] ?? 0;

      if (durationInSeconds > 180 || fileSizeInMB > 500) {
        setState(() {
          _isUploading = false;
        });
        FeedVideoPool.isGlobalMutedForUpload = false; // Trả tự do cho âm thanh Feeds
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(durationInSeconds > 180 
                ? 'Từ chối: Video dài ${durationInSeconds.toInt()} giây (Vượt quá giới hạn 3 phút)!' 
                : 'Từ chối: Dung lượng file đạt ${fileSizeInMB.toInt()}MB (Vượt quá giới hạn 500MB)!'), 
              backgroundColor: Colors.redAccent
            ),
          );
        }
        return; 
      }
    } catch (e) {
      setState(() => _isUploading = false);
      FeedVideoPool.isGlobalMutedForUpload = false;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Không thể đọc cấu trúc tệp video!'), backgroundColor: Colors.redAccent));
      return;
    }

    try {
      // 2. THUẬT TOÁN NÉN TỐI ƯU: Ánh xạ chuẩn xác tệp vật lý từ đường dẫn cục bộ (video.path)
      final File localFile = File(video.path);
      File fileToUpload = localFile;
      try {
        final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
          localFile.path,
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
                    // 🚀 ĐỒNG BỘ: Trả tự do cho âm thanh Feeds khi gỡ tệp từ Widget con
                    FeedVideoPool.isGlobalMutedForUpload = false;
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