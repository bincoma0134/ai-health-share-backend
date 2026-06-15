#include <flutter/runtime_effect.glsl>

// Uniforms from Flutter
uniform vec2 uResolution;
uniform vec2 uMouse;
uniform float uEffectSize; // Controls the size of the lens effect (0.1 to 2.0 recommended)
uniform float uBlurIntensity;
uniform float uDispersionStrength; // Add chromatic dispersion control
uniform float uTime; // Đã thêm biến uTime để đồng bộ index 7 từ Flutter
uniform sampler2D uTexture;

// Output
out vec4 fragColor;

void main() {
    // Get fragment coordinates
    vec2 fragCoord = FlutterFragCoord();

    // Normalized pixel coordinates (from 0 to 1)
    vec2 uv = fragCoord / uResolution.xy;

    // Khôi phục 100% thuật toán tính khoảng cách và định hình thấu kính nguyên bản từ Repo mẫu
    vec2 center = uMouse.xy / uResolution.xy;
    vec2 m2 = (uv - center);

    float effectRadius = uEffectSize * 0.5;
    float sizeMultiplier = 1.0 / (effectRadius * effectRadius);
    // Tự động triệt tiêu tỉ lệ khung hình nếu widget quá dài (ví dụ: Thanh điều hướng Nav Bar)
    // Giúp giọt chất lỏng lấp đầy toàn bộ bề rộng mà không bị ép dẹt thành oval
    float aspectRatio = uResolution.x / uResolution.y;
    float correctedX = aspectRatio > 2.0 ? (m2.x * 1.5) : (m2.x * aspectRatio); 
    float roundedBox = pow(abs(correctedX), 4.0) + pow(abs(m2.y), 4.0);

    // Calculate different zones of the effect
    float baseIntensity = 100.0 * sizeMultiplier;
    float rb1 = clamp((1.0 - roundedBox * baseIntensity) * 8.0, 0.0, 1.0); // main lens
    float rb2 = clamp((0.95 - roundedBox * baseIntensity * 0.95) * 16.0, 0.0, 1.0) -
                clamp(pow(0.9 - roundedBox * baseIntensity * 0.95, 1.0) * 16.0, 0.0, 1.0); // borders
    float rb3 = clamp((1.5 - roundedBox * baseIntensity * 1.1) * 2.0, 0.0, 1.0) -
                clamp(pow(1.0 - roundedBox * baseIntensity * 1.1, 1.0) * 2.0, 0.0, 1.0); // shadow

    fragColor = vec4(0.0);

    if (rb1 + rb2 > 0.0) {
        // Lens distortion effect
        float distortionStrength = 50.0 * sizeMultiplier;
        vec2 lens = ((uv - 0.5) * (1.0 - roundedBox * distortionStrength) + 0.5);

        // Enhanced chromatic dispersion calculation
        vec2 dir = normalize(m2);
        float dispersionScale = uDispersionStrength * 0.05;

        // Create edge mask based on distance from center
        float dispersionMask = smoothstep(0.3, 0.7, roundedBox * baseIntensity);

        // Apply mask to dispersion offsets
        vec2 redOffset = dir * dispersionScale * 2.0 * dispersionMask;
        vec2 greenOffset = dir * dispersionScale * 1.0 * dispersionMask;
        vec2 blueOffset = dir * dispersionScale * -1.5 * dispersionMask;

        vec4 colorResult = vec4(0.0);

        // Enhanced single sample with directional offsets
        // Blur sampling has been explicitly delegated to Flutter's BackdropFilter to guarantee 60fps
        colorResult.r = texture(uTexture, lens + redOffset).r;
        colorResult.g = texture(uTexture, lens + greenOffset).g;
        colorResult.b = texture(uTexture, lens + blueOffset).b;
        colorResult.a = 1.0;

        // Add lighting effects
        float gradient = clamp((clamp(m2.y, 0.0, 0.2) + 0.1) / 2.0, 0.0, 1.0) +
                        clamp((clamp(-m2.y, -1000.0, 0.2) * rb3 + 0.1) / 2.0, 0.0, 1.0);

        // Combine all effects
        fragColor = mix(
            texture(uTexture, uv),
            colorResult,
            rb1
        );
        fragColor = clamp(fragColor + vec4(rb2 * 0.3) + vec4(gradient * 0.2), 0.0, 1.0);

    } else {
        fragColor = texture(uTexture, uv);
    }
}