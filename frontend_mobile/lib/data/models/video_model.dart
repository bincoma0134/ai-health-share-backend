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
      author: json['author'] ?? {},
    );
  }
}