import 'package:flutter/material.dart';

class AppTheme {
  static const Color zinc950 = Color(0xFF09090B); // .dark .leaflet-container
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);
  static const Color zinc300 = Color(0xFFD4D4D8);
  static const Color zinc50  = Color(0xFFFAFAFA);
  static const Color blue500 = Color(0xFF3B82F6); // primary

  static ThemeData get darkTheme {
    return ThemeData.dark().copyWith(
      scaffoldBackgroundColor: zinc950,
      cardColor: zinc900,
      colorScheme: const ColorScheme.dark(
        primary: blue500,
        surface: zinc900,
      ),
    );
  }
}