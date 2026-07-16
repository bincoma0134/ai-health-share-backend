import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../data/services/user_api_service.dart';

class ImageUploader extends StatefulWidget {
  final Function(String) onUploadSuccess;
  final String label;
  final String folder;
  final double height;

  const ImageUploader({
    super.key,
    required this.onUploadSuccess,
    this.label = 'Nhấn để chọn Ảnh',
    this.folder = 'media/images',
    this.height = 160,
  });

  @override
  State<ImageUploader> createState() => _ImageUploaderState();
}

class _ImageUploaderState extends State<ImageUploader> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  File? _selectedFile;

  Future<void> _pickAndUpload() async {
    // 1. Validation Client-side: Ép chất lượng và kích thước ngay lúc chọn
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1920,
    );

    if (image == null) return;

    final file = File(image.path);
    
    // Kiểm tra dung lượng (VD: Giới hạn 10MB)
    final double fileSizeInMB = file.lengthSync() / (1024 * 1024);
    if (fileSizeInMB > 10) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dung lượng ảnh quá lớn (Tối đa 10MB)'), backgroundColor: Colors.orange));
      return;
    }

    setState(() {
      _selectedFile = file;
      _isUploading = true;
    });

    // 2. Upload ngầm (Asynchronous)
    final url = await UserApiService.uploadMedia(file, widget.folder);

    if (mounted) {
      setState(() {
        _isUploading = false;
      });

      if (url != null) {
        widget.onUploadSuccess(url);
      } else {
        _selectedFile = null; // Reset nếu lỗi
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi đường truyền khi tải ảnh!'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _isUploading ? null : _pickAndUpload,
      child: Container(
        height: widget.height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _selectedFile != null ? Colors.blueAccent : Colors.white24,
            width: 2,
          ),
          image: _selectedFile != null
              ? DecorationImage(image: FileImage(_selectedFile!), fit: BoxFit.cover)
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Trạng thái chưa có ảnh
            if (_selectedFile == null && !_isUploading)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_upload_outlined, color: Colors.white54, size: 40),
                  const SizedBox(height: 8),
                  Text(widget.label, style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  const Text('Tự động nén để tối ưu', style: TextStyle(color: Colors.white30, fontSize: 10)),
                ],
              ),
              
            // Lớp phủ khi đang Upload
            if (_isUploading)
              Container(
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(14)),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.blueAccent),
                      SizedBox(height: 12),
                      Text('Đang tải lên...', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                ),
              ),
              
            // Nút xóa ảnh khi đã upload xong
            if (_selectedFile != null && !_isUploading)
              Positioned(
                top: 8, right: 8,
                child: GestureDetector(
                  onTap: () {
                    setState(() => _selectedFile = null);
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
 