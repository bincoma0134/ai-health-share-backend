class CommentModel {
  final String id;
  final String content;
  final String? parentId;
  final String createdAt;
  final Map<String, dynamic> user;

  CommentModel({
    required this.id,
    required this.content,
    this.parentId,
    required this.createdAt,
    required this.user,
  });

  factory CommentModel.fromJson(Map<String, dynamic> json) {
    return CommentModel(
      id: json['id'] ?? '',
      content: json['content'] ?? '',
      parentId: json['parent_id'],
      createdAt: json['created_at'] ?? '',
      user: json['users'] ?? {}, 
    );
  }
}