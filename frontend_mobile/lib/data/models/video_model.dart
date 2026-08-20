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
  final Map<String, dynamic>? linkedPartner; // 🚀 PHASE 08: Lưu nguyên vẹn Metadata Đối tác liên kết

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
    this.linkedPartner,
  });

  // Getter trích xuất nhãn phân loại động từ title
  String get categoryTag {
    if (title.isNotEmpty) return title;
    return 'Xu hướng làm đẹp';
  }

  // 🚀 GETTER HỖ TRỢ HIỂN THỊ VIỀN AVATAR & BADGE CHO TÁC GIẢ VIDEO
  bool get isAuthorPremium {
    return author['is_premium'] == true || author['is_premium'] == 'true';
  }

  String get authorTier {
    return (author['premium_tier'] ?? 'STANDARD').toString().toUpperCase();
  }

  // 🚀 GETTER HỖ TRỢ HIỂN THỊ VIỀN AVATAR & BADGE CHO ĐỐI TÁC LIÊN KẾT
  bool get isLinkedPartnerPremium {
    if (linkedPartner == null) return false;
    return linkedPartner!['is_premium'] == true || linkedPartner!['is_premium'] == 'true';
  }

  String get linkedPartnerTier {
    if (linkedPartner == null) return 'STANDARD';
    return (linkedPartner!['premium_tier'] ?? 'STANDARD').toString().toUpperCase();
  }

  factory VideoModel.fromJson(Map<String, dynamic> json) {
    // Giải nén an toàn linked_partner map
    Map<String, dynamic>? linkedPartnerMap;
    if (json['linked_partner'] is Map<String, dynamic>) {
      linkedPartnerMap = json['linked_partner'];
    } else if (json['linked_partner'] is Map) {
      linkedPartnerMap = Map<String, dynamic>.from(json['linked_partner']);
    }

    // Giải nén an toàn author map
    Map<String, dynamic> authorMap = {};
    if (json['author'] is Map<String, dynamic>) {
      authorMap = json['author'];
    } else if (json['author'] is Map) {
      authorMap = Map<String, dynamic>.from(json['author']);
    }

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
      author: authorMap,
      partnerId: json['partner_id'],
      serviceId: json['service_id'],
      voucherCode: json['voucher_code'],
      feedType: json['feed_type'],
      affiliateRate: json['affiliate_rate'] != null ? (json['affiliate_rate'] as num).toDouble() : null,
      partnerUsername: linkedPartnerMap != null ? linkedPartnerMap['username'] : null,
      linkedPartner: linkedPartnerMap,
    );
  }
}