import 'package:dio/dio.dart';
import '../../core/network/api_client.dart';
import '../models/appointment_model.dart';

class AppointmentApiService {
  static final Dio _dio = ApiClient.instance;

  static Future<List<AppointmentModel>> fetchAppointments() async {
    try {
      final response = await _dio.get('/appointments/me');
      if (response.statusCode == 200) {
        return (response.data as List).map((i) => AppointmentModel.fromJson(i)).toList();
      }
      return [];
    } catch (e) { return []; }
  }
}