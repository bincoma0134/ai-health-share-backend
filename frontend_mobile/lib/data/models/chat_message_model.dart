class ChatMessageModel {
  final String id;
  final String role; // 'user' hoặc 'bot'
  final String content;
  final DateTime timestamp;

  ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
  });

  // 1. Ánh xạ chuẩn với Groq LLM (Chỉ cần role và content)
  Map<String, dynamic> toApiJson() => {
    'role': role == 'bot' ? 'assistant' : 'user', 
    'content': content,
  };

  // 2. Mã hóa để lưu vào Local Storage điện thoại (Lưu toàn bộ thông tin)
  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
  };

  // 3. Giải mã từ Local Storage khi mở App
  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] ?? '',
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
    );
  }
}