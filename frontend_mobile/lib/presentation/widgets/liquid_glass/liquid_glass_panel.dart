// frontend_mobile/lib/widgets/liquid_glass/liquid_glass_panel.dart

import 'package:flutter/material.dart';
import 'liquid_glass_surface.dart';
import 'liquid_glass_tokens.dart';

class LiquidGlassPanel extends StatelessWidget {
  final Widget child;
  
  const LiquidGlassPanel({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return LiquidGlassSurface(
      blur: LiquidGlassTokens.blurHeavy,
      tintOpacity: LiquidGlassTokens.tintDense, 
      borderRadius: LiquidGlassTokens.radiusLg,
      enableShader: true,
      child: child,
    );
  }
}