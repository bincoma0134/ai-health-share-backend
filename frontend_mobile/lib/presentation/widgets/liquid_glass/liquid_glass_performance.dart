// frontend_mobile/lib/widgets/liquid_glass/liquid_glass_performance.dart

enum LiquidGlassTier { ultra, high, medium, batterySaver }

class LiquidGlassPerformance {
  // Khởi tạo an toàn ở mức Medium để đảm bảo 60fps trên đa số thiết bị Android tầm trung.
  // Ở mức Medium, Shader khúc xạ sẽ tắt, chỉ giữ lại hiệu ứng Blur và Tint Color.
  static LiquidGlassTier currentTier = LiquidGlassTier.medium;  

  static bool get shouldRenderShader => 
      currentTier == LiquidGlassTier.ultra || currentTier == LiquidGlassTier.high;

  static bool get shouldRenderBlur => 
      currentTier != LiquidGlassTier.batterySaver;
}