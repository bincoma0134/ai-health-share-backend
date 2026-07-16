import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/network/api_client.dart';
import '../models/service_model.dart';
import '../models/partner_map_model.dart'; // Import Model bản đồ đối tác
import 'dart:convert';

class ExploreApiService {
  static final Dio _dio = ApiClient.instance;

  // --- GIỮ LẠI LUỒNG TẢI DỊCH VỤ CŨ NẾU CẦN ---
  static Future<List<ServiceModel>> fetchServices() async {
    try {
      final response = await _dio.get('/services');
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> data = response.data['data'];
        return data.map((json) => ServiceModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TẢI DỊCH VỤ KHÁM PHÁ: $e');
      return [];
    }
  }

  // --- 🚀 BỔ SUNG: LUỒNG TRUY VẤN SỐ DƯ ĐIỂM SVALUE THỰC TẾ TỪ DATABASE MỚI ---
  static Future<int?> fetchSValueBalance() async {
    try {
      final response = await _dio.get('/user/profile'); 
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final data = response.data['data'] ?? {};
        final profile = data['profile'] ?? {};
        if (profile['svalue_balance'] != null) {
          return int.tryParse(profile['svalue_balance'].toString());
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ LỖI TRUY VẤN VÍ ĐIỂM SVALUE: $e');
      return null;
    }
  }

  // --- 🚀 BỔ SUNG: ĐỒNG BỘ HOÀN THÀNH NHIỆM VỤ LÊN DATABASE BIẾN ĐỘNG SVALUE ---
  static Future<bool> completeSValueTask(String actionType, int points, {String? referenceId}) async {
    try {
      final response = await _dio.post(
        '/user/svalue/task',
        data: {
          'action_type': actionType,
          'points_changed': points,
          'reference_id': referenceId,
        },
      );
      return response.statusCode == 200 && response.data['status'] == 'success';
    } catch (e) {
      debugPrint('❌ LỖI ĐỒNG BỘ NHIỆM VỤ SVALUE: $e');
      return false;
    }
  }

  // --- 🚀 BỔ SUNG: LUỒNG ĐỔ DATA THẬT CHUẨN XANHSM ---
  // --- BỔ SUNG ĐƯỜNG ỐNG NẠP DANH SÁCH DỊCH VỤ LẺ ĐỒNG BỘ WEBSITE ---
  static Future<List<dynamic>> fetchAllServices() async {
    try {
      // Nhúng trực tiếp đường dẫn gốc R2/Render của Backend tương tự như cách Website thực thi
      final response = await _dio.get('https://ai-health-share-backend.onrender.com/services');
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> decodedData = response.data is String ? json.decode(response.data) : response.data;
        if (decodedData['status'] == 'success' || decodedData['data'] != null) {
          return List<dynamic>.from(decodedData['data'] ?? []);
        }
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi tầng mạng ExploreApiService.fetchAllServices: $e");
      return [];
    }
  }

  static Future<List<PartnerMapModel>> fetchExplorePartners() async {
    try {
      // Gọi qua ApiClient tận dụng đường ống mạng nội bộ adb reverse hoặc Live URL
      final response = await _dio.get('/map/partners');
      
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final List<dynamic> data = response.data['data'] ?? [];
        // Khởi tạo mảng dữ liệu có kiểu định nghĩa an toàn thông qua hàm Factory của Model
        return data.map((json) => PartnerMapModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('❌ LỖI TRUY VẤN ĐỐI TÁC KHÁM PHÁ (EXPLORE SERVICE): $e');
      return [];
    }
  }
}