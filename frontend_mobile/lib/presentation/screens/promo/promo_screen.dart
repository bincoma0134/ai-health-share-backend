import 'package:flutter/material.dart';

class PromoScreen extends StatelessWidget {
  const PromoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF09090b),
      body: Center(child: Text('Khuyến mãi (Sắp ra mắt)', style: TextStyle(color: Colors.white))),
    );
  }
}