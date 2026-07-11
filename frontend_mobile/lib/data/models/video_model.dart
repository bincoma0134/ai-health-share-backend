class VideoModel {
  final String id;
  final String authorId;
  final String title;
  final String content;
  final double price;
  final String videoUrl;
  int likesCount;
  int savesCount;
  int commentsCount;
  bool isLiked;
  bool isSaved;
  final Map<String, dynamic> author;
  final String? partnerId;
  final String? serviceId;
  final String? voucherCode;
  final String? feedType;
  final double? affiliateRate;
  final String? partnerUsername; // 🚀 Bổ sung biến hứng Username của đối tác liên kết

  VideoModel({
    required this.id,
    required this.authorId,
    required this.title,
    required this.content,
    required this.price,
    required this.videoUrl,
    required this.likesCount,
    required this.savesCount,
    required this.commentsCount,
    required this.isLiked,
    required this.isSaved,
    required this.author,
    this.partnerId,
    this.serviceId,
    this.voucherCode,
    this.feedType,
    this.affiliateRate,
    this.partnerUsername,
  });

  // Giải pháp 1: Getter trích xuất nhãn phân loại động từ dữ liệu thực tế (title) để tránh hardcode trên UI
  String get categoryTag {
    if (title.isNotEmpty) return title;
    // Fallback an toàn nếu chuỗi title từ database trống
    return 'Xu hướng làm đẹp';
  }

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id'] ?? '',
      authorId: json['author_id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      videoUrl: json['video_url'] ?? '',
      likesCount: json['likes_count'] ?? 0,
      savesCount: json['saves_count'] ?? 0,
      commentsCount: json['comments_count'] ?? 0,
      isLiked: json['is_liked'] ?? false,
      isSaved: json['is_saved'] ?? false,
      author: json['author'] is Map<String, dynamic> ? json['author'] : {},
      partnerId: json['partner_id'],
      serviceId: json['service_id'],
      voucherCode: json['voucher_code'],
      feedType: json['feed_type'],
      affiliateRate: json['affiliate_rate'] != null ? (json['affiliate_rate'] as num).toDouble() : null,
      // 🚀 Giải nén an toàn object linked_partner do Backend trả về
      partnerUsername: json['linked_partner'] != null ? json['linked_partner']['username'] : null,
    );
  }
}