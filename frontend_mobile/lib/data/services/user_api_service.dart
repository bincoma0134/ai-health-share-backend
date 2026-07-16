import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../../core/network/api_client.dart';

class UserApiService {
  static final Dio _dio = ApiClient.instance;

  // 0. Authentication (Ném lỗi trực tiếp lên UI để hiển thị Toast/Alert chính xác)
  static Future<Map<String, dynamic>?> loginEmail(String email, String password) async {
    final res = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    if (res.statusCode == 200 && res.data['status'] == 'success') return res.data;
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data['detail'] ?? 'Đăng nhập thất bại',
    );
  }

  static Future<Map<String, dynamic>?> registerEmail(String email, String password, String username, String fullName) async {
    final res = await _dio.post('/auth/register', data: {
      'email': email, 'password': password, 'username': username, 'full_name': fullName
    });
    if (res.statusCode == 200 && res.data['status'] == 'success') return res.data;
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: res.data['detail'] ?? 'Đăng ký thất bại',
    );
  }

  static Future<Map<String, dynamic>?> loginFirebase(String idToken) async {
    // BỎ CÁI CATCH ĐỂ LỖI ĐƯỢC NÉM THẲNG LÊN UI
    final res = await _dio.post('/auth/firebase', data: {'id_token': idToken});
    if (res.statusCode == 200 && res.data['status'] == 'success') return res.data;
    
    // Nếu status code khác 200 nhưng không văng lỗi, ném ra lỗi giả để bắt vào khối catch ở UI
    throw DioException(
      requestOptions: res.requestOptions,
      response: res,
      error: 'Backend không trả về status success',
    );
  }

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

  // 3b. Lấy danh sách dịch vụ đi kèm của User cụ thể theo đặc tả OpenAPI
  static Future<List<dynamic>> fetchUserServices(String userId) async {
    try {
      final res = await _dio.get('/services', queryParameters: {'user_id': userId});
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is Map && res.data['data'] != null) {
          return List<dynamic>.from(res.data['data']);
        } else if (res.data is List) {
          return List<dynamic>.from(res.data);
        }
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  // 3c. Lấy danh sách video đăng tải của User cụ thể theo đặc tả OpenAPI
  static Future<List<dynamic>> fetchUserFeeds(String userId) async {
    try {
      final res = await _dio.get('/tiktok/feeds', queryParameters: {'user_id': userId});
      if (res.statusCode == 200 && res.data != null) {
        if (res.data is Map && res.data['data'] != null) {
          return List<dynamic>.from(res.data['data']);
        } else if (res.data is List) {
          return List<dynamic>.from(res.data);
        }
      }
      return [];
    } catch (e) {
      return [];
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
      
      final res = await _dio.post(
        '/media/upload', 
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
      );
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['url'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 5b. TẢI VIDEO LÊN CLOUDFLARE R2 CHUYÊN DỤNG (Hỗ trợ theo dõi tiến trình và không nuốt lỗi)
  static Future<String?> uploadVideo(File file, String folder, {Function(int, int)? onSendProgress}) async {
    String fileName = file.path.split('/').last;
    String ext = fileName.split('.').last.toLowerCase();
    
    FormData formData = FormData.fromMap({
      "file": await MultipartFile.fromFile(
        file.path, 
        filename: fileName,
        contentType: MediaType('video', ext)
      ),
      "folder": folder,
    });
    
    final res = await _dio.post(
      '/media/upload', 
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(minutes: 10),
      ),
      onSendProgress: onSendProgress,
    );
    
    if (res.statusCode == 200 && res.data['status'] == 'success') {
      return res.data['url'];
    }
    throw Exception(res.data['detail'] ?? 'Backend không trả về trạng thái thành công');
  }

  // 6. Lấy danh sách nội dung đã lưu
  static Future<List<dynamic>> fetchSavedItems() async {
    try {
      final res = await _dio.get('/user/saves');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        return res.data['data'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}