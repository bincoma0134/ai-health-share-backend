import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// 🚀 LÕI GLOBAL CACHE ENGINE
// Quản lý lưu trữ tĩnh (Hình ảnh) qua Memory và Disk (Ổ cứng)
class GlobalCacheEngine {
  static const String key = 'VNShareImageCache';
  
  static final CacheManager manager = CacheManager(
    Config(
      key,
      stalePeriod: const Duration(days: 7), // Lưu ổ cứng tối đa 7 ngày
      maxNrOfCacheObjects: 200, // Tối đa 200 file (~100MB) để chống đầy bộ nhớ Android
    ),
  );

  // 🚀 XẢ MEMORY CACHE (RAM): Gọi khi hệ điều hành báo động đỏ
  static void clearMemoryCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  // 🚀 XẢ DISK CACHE (Ổ CỨNG): Dọn rác thủ công (nếu cần gọi khi Logout)
  static Future<void> clearDiskCache() async {
    await manager.emptyCache();
  }
}

// 🚀 WIDGET ĐẠI DIỆN: Tự động quản lý luồng tải ảnh an toàn, chống giật UI
class GlobalCacheImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const GlobalCacheImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 🚀 HOTFIX: Tiền xử lý Absolute URL cho đường dẫn tương đối từ DB
    final String absoluteUrl = imageUrl.startsWith('/') 
        ? 'https://ai-health-share-backend.onrender.com$imageUrl' 
        : imageUrl;

    // 🚀 HOTFIX: Làm sạch URL trước khi gọi mạng và tạo Cache Key tuyệt đối an toàn cho File System OS
    final safeUrl = Uri.encodeFull(absoluteUrl);
    final safeCacheKey = base64UrlEncode(utf8.encode(absoluteUrl));

    return CachedNetworkImage(
      imageUrl: safeUrl,
      cacheKey: safeCacheKey,
      cacheManager: GlobalCacheEngine.manager,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth ?? memCacheHeight, // 🚀 HOTFIX: Chỉ ép giải mã theo 1 chiều để bảo toàn Tỷ lệ gốc (Aspect Ratio)
      // memCacheHeight: Bỏ trống hoàn toàn để Skia/Impeller tự động tính toán chiều còn lại, chống crash Native
      placeholder: (context, url) => Container(color: const Color(0xFFF4F7F6)), // Khung xương mịn màng
      errorWidget: (context, url, error) => Container(color: const Color(0xFFF4F7F6), child: const Icon(Icons.broken_image_rounded, color: Colors.black12)),
    );
  }
}

// 🚀 PROVIDER ĐẠI DIỆN: Dành riêng thay thế cho CircleAvatar / DecorationImage
class GlobalCacheProvider {
  static CachedNetworkImageProvider create(String url, {int? maxWidth, int? maxHeight}) {
    // 🚀 HOTFIX: Tiền xử lý Absolute URL cho đường dẫn tương đối từ DB
    final String absoluteUrl = url.startsWith('/') 
        ? 'https://ai-health-share-backend.onrender.com$url' 
        : url;

    // 🚀 HOTFIX: Đồng bộ mã hóa URL và Cache Key cho tầng Provider
    final safeUrl = Uri.encodeFull(absoluteUrl);
    final safeCacheKey = base64UrlEncode(utf8.encode(absoluteUrl));

    return CachedNetworkImageProvider(
      safeUrl,
      cacheKey: safeCacheKey,
      cacheManager: GlobalCacheEngine.manager,
      maxWidth: maxWidth ?? maxHeight, // 🚀 HOTFIX: Tương tự, chỉ ép 1 chiều duy nhất
      // maxHeight: Bỏ trống để tránh phá vỡ tỷ lệ cấu trúc byte của ảnh
    );
  }
}