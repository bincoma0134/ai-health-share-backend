import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../../core/network/api_client.dart';

class UserApiService {
  static final Dio _dio = ApiClient.instance;

  // 1. Lấy hồ sơ cá nhân
  static Future<Map<String, dynamic>?> fetchPrivateProfile() async {
    try {
      final res = await _dio.get('/user/profile');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['data'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 2. Cập nhật thông tin (Tên, Bio, Avatar...)
  static Future<bool> updateProfile(Map<String, dynamic> data) async {
    try {
      final res = await _dio.patch('/user/profile', data: data);
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // 3. Lấy Hồ sơ công khai (Public Profile)
  static Future<Map<String, dynamic>?> fetchPublicProfile(String username) async {
    try {
      final res = await _dio.get('/user/public/$username');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['data'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 4. Nút Quan tâm / Hủy quan tâm
  static Future<bool> toggleFollow(String targetId) async {
    try {
      final res = await _dio.post('/user/follow/$targetId');
      return res.statusCode == 200 && res.data['status'] == 'success';
    } catch (e) {
      return false;
    }
  }

  // 5. TẢI MEDIA LÊN CLOUDFLARE R2 (Đã fix lỗi 500)
  static Future<String?> uploadMedia(File file, String folder) async {
    try {
      String fileName = file.path.split('/').last;
      String ext = fileName.split('.').last.toLowerCase();
      String mimeType = 'application';
      String mimeSubtype = 'octet-stream';
      
      if (['jpg', 'jpeg', 'png', 'webp', 'gif'].contains(ext)) {
        mimeType = 'image';
        mimeSubtype = ext == 'jpg' ? 'jpeg' : ext;
      } else if (['mp4', 'mov', 'avi'].contains(ext)) {
        mimeType = 'video';
        mimeSubtype = ext;
      }

      FormData formData = FormData.fromMap({
        "file": await MultipartFile.fromFile(
          file.path, 
          filename: fileName,
          contentType: MediaType(mimeType, mimeSubtype) // Bọc thép định dạng S3
        ),
        "folder": folder, // Điều hướng thư mục lưu trữ Backend
      });
      
      final res = await _dio.post('/media/upload', data: formData);
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}