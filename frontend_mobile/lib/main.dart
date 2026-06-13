import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // Bổ sung thư viện
import 'core/router/app_router.dart';

void main() async { // Đổi thành hàm async
  WidgetsFlutterBinding.ensureInitialized();
  
  // BẮT BUỘC: Khởi tạo Firebase trước khi chạy App
  await Firebase.initializeApp();
  
  runApp(const VNShareApp());
}

class VNShareApp extends StatelessWidget {
  const VNShareApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'AI Health Share',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF80BF84)), // Lấy mã màu xanh lá từ UI Web
        useMaterial3: true,
      ),
      routerConfig: appRouter,
      debugShowCheckedModeBanner: false,
    );
  }
}