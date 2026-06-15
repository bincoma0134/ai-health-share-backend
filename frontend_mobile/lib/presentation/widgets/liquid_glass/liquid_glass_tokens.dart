// frontend_mobile/lib/widgets/liquid_glass/liquid_glass_tokens.dart

import 'package:flutter/material.dart';

class LiquidGlassTokens {
  // Blur Scale (Sigma) - Tăng mạnh để tạo độ sâu chuẩn Apple Glass
  static const double blurLight = 16.0;
  static const double blurMedium = 30.0;
  static const double blurHeavy = 50.0;

  // Tint & Alpha - Giảm Opacity để lộ hiệu ứng Blur xịn xò dưới nền
  static const Color tintMint = Color(0xFFE8F5E9); // Mint Green Wellness Tone
  static const double tintSubtle = 0.05;
  static const double tintBase = 0.15;
  static const double tintDense = 0.35;

  // Highlight
  static const double highlightSoft = 0.2;
  static const double highlightCrisp = 0.4;

  // Radius (Converted to Squircle conceptually)
  static const double radiusSm = 16.0;
  static const double radiusMd = 24.0;
  static const double radiusLg = 36.0;
  static const double radiusPill = 999.0;
}