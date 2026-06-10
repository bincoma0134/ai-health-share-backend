class ChatMessageModel {
  final String id;
  final String role; // 'user' hoặc 'bot'
  final String content;
  final DateTime timestamp;
  
  // 🚀 BỔ SUNG: CÁC TRƯỜNG DỮ LIỆU CAO CẤP ĐỂ BIẾN THÀNH ACTIONABLE CHAT BUBBLE
  final String? widgetType;     // 'booking_suggestion' | 'voucher_gift' | 'text'
  final Map<String, dynamic>? widgetData; // Chứa thông tin partner_id, giá, voucher_code...

  ChatMessageModel({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.widgetType = 'text',
    this.widgetData,
  });

  Map<String, dynamic> toApiJson() => {
    'role': role == 'bot' ? 'assistant' : 'user', 
    'content': content,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'widget_type': widgetType,
    'widget_data': widgetData,
  };

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] ?? '',
      role: json['role'] ?? 'user',
      content: json['content'] ?? '',
      timestamp: json['timestamp'] != null ? DateTime.parse(json['timestamp']) : DateTime.now(),
      widgetType: json['widget_type'] ?? 'text',
      widgetData: json['widget_data'],
    );
  }
}