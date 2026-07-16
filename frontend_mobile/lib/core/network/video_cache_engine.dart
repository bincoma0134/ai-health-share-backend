import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoCacheEngine {
  // Khởi tạo Cache Manager chuyên biệt cho Video
  // - Giới hạn dung lượng để tránh phình App trên Android tầm trung
  // - Thuật toán dọn rác LRU tự động xóa file cũ nhất khi đầy
  static final CacheManager _videoCacheManager = CacheManager(
    Config(
      'VNShareVideoCache',
      stalePeriod: const Duration(days: 7),
      maxNrOfCacheObjects: 100, // Tương đương khoảng ~200-300MB cho video ngắn
    ),
  );

  /// Truy xuất nguồn Video tối ưu nhất
  /// Trả về URI của File ổ cứng (file://) nếu đã Cache, ngược lại trả về Network URL gốc và tải ngầm
  static Future<String> getOptimalUrl(String url) async {
    try {
      // 1. Kiểm tra nhanh trong bộ nhớ đệm vật lý (Disk Cache)
      final fileInfo = await _videoCacheManager.getFileFromCache(url);
      if (fileInfo != null && await fileInfo.file.exists()) {
        // HIT: Phát ngay từ ổ cứng với độ trễ gần như 0ms
        return fileInfo.file.path; // 🚀 HOTFIX: Trả về đường dẫn vật lý tuyệt đối (Absolute Path) thay vì URI dễ gây lỗi parser
      }
      
      // 2. MISS: Trả về URL mạng để UI không bị block, ĐỒNG THỜI nạp ngầm vào Disk Cache
      // 🚀 HOTFIX: Bọc bẫy lỗi để luồng tải Video nền không làm khóa (Deadlock) cơ sở dữ liệu Cache của luồng tải Ảnh
      _videoCacheManager.downloadFile(url).then((_) {}).catchError((_) {});
      return url;
    } catch (e) {
      // Fallback an toàn, luôn đảm bảo Video chạy được kể cả khi Disk I/O lỗi
      return url;
    }
  }
}