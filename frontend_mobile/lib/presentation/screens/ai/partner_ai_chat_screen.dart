import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../widgets/app_toast.dart';

class PartnerAIChatScreen extends StatefulWidget {
  final String partnerId;
  final String? partnerName; // Tên cơ sở đối tác truyền qua Route (nếu có)

  const PartnerAIChatScreen({
    super.key,
    required this.partnerId,
    this.partnerName,
  });

  @override
  State<PartnerAIChatScreen> createState() => _PartnerAIChatScreenState();
}

class _PartnerAIChatScreenState extends State<PartnerAIChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List<dynamic> _chatHistory = [];
  bool _isLoadingHistory = true;
  bool _isSending = false;

  // Variables for Ghost Bubble Suggestions
  final List<String> _suggestedQuestions = [
    'Tất cả các dịch vụ', 'Các ưu đãi hiện tại?', 'Xin chào! Tư vấn giúp tôi',
    'Địa chỉ cơ sở ở đâu?', 'Số điện thoại liên hệ', 'Kênh liên hệ khác',
    'Đặt lịch tại đâu?', 'Quy định thanh toán', 'Chính sách bảo đảm'
  ];
  int _suggestionStep = 0;
  bool _showSuggestions = true;

  // Khai báo màu xanh thương hiệu độc quyền của Partner làm chủ đạo
  final Color _partnerColor = const Color(0xFF80BF84);
  final Color _darkBgColor = const Color(0xFF1A3A35);

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  // 🔄 LOGIC: Tải toàn bộ lịch sử chat cũ của cặp User - Partner này từ Backend
  Future<void> _loadChatHistory() async {
    try {
      final response = await ApiClient.instance.get(
        '/ai_support/conversations/${widget.partnerId}/history',
      );
      if (response.statusCode == 200 && response.data['status'] == 'success') {
        setState(() {
          _chatHistory = response.data['data'] ?? [];
          _isLoadingHistory = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isLoadingHistory = false);
      AppToast.show(context: context, message: 'Không thể tải lịch sử cuộc trò chuyện!', isSuccess: false);
    }
  }

  // 🚀 LOGIC: Gửi tin nhắn lên Prompt Fusion Engine của Backend
  Future<void> _sendMessage() async {
    final String text = _messageController.text.trim();
    if (text.isEmpty || _isSending) return;

    _messageController.clear();
    
    // Optimistic UI: Hiển thị ngay tin nhắn của người dùng lên màn hình để tạo cảm giác mượt mà
    setState(() {
      _chatHistory.add({
        'sender_role': 'USER',
        'message_content': text,
        'created_at': DateTime.now().toIso8601String(),
      });
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final response = await ApiClient.instance.post(
        '/ai_support/chat',
        data: {
          'partner_id': widget.partnerId,
          'message': text,
        },
      );

      if (response.statusCode == 200 && response.data['status'] == 'success') {
        final String botReply = response.data['data']['reply'] ?? '';
        setState(() {
          _chatHistory.add({
            'sender_role': 'AI',
            'message_content': botReply,
            'created_at': DateTime.now().toIso8601String(),
          });
          _isSending = false;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isSending = false);
      AppToast.show(context: context, message: 'Yêu cầu kết nối AI thất bại!', isSuccess: false);
    }
  }

  // Tự động cuộn xuống đáy khi có tin nhắn mới xuất hiện
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA), // Premium Light Background
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black.withOpacity(0.05),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _darkBgColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  backgroundColor: _partnerColor.withOpacity(0.15),
                  radius: 20,
                  child: Icon(Icons.support_agent_rounded, color: _partnerColor, size: 22),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981), // Trạng thái Online
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partnerName ?? 'Trợ lý AI Cơ Sở',
                    style: TextStyle(color: _darkBgColor, fontSize: 16, fontWeight: FontWeight.w900),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: Colors.amber, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Tư vấn tự động 24/7',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. KHU VỰC HIỂN THỊ TIN NHẮN VÀ GỢI Ý (STACK LAYER)
          Expanded(
            child: Stack(
              children: [
                // Layer Dưới: Lịch sử Chat
                Positioned.fill(
                  child: _isLoadingHistory
                      ? Center(child: CircularProgressIndicator(color: _partnerColor))
                      : _chatHistory.isEmpty
                          ? Center(
                              child: SingleChildScrollView(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(24),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(color: _partnerColor.withOpacity(0.15), blurRadius: 30, spreadRadius: 10),
                                        ],
                                      ),
                                      child: Icon(Icons.auto_awesome_mosaic_rounded, size: 48, color: _partnerColor),
                                    ),
                                    const SizedBox(height: 24),
                                    Text(
                                      'Xin chào! 👋',
                                      style: TextStyle(color: _darkBgColor, fontSize: 22, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 8),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 40),
                                      child: Text(
                                        'Trợ lý AI đã sẵn sàng giải đáp mọi thắc mắc về dịch vụ, bảng giá và ưu đãi của cơ sở.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: _darkBgColor.withOpacity(0.6), fontSize: 13, height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              itemCount: _chatHistory.length + (_isSending ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _chatHistory.length) return _buildLoadingBubble();
                                final msg = _chatHistory[index];
                                final bool isMe = msg['sender_role'] == 'USER';
                                return _buildChatBubble(
                                  content: msg['message_content'] ?? '',
                                  isMe: isMe,
                                  timeStr: msg['created_at'] != null
                                      ? DateFormat('HH:mm').format(DateTime.parse(msg['created_at']))
                                      : '',
                                );
                              },
                            ),
                ),
                
                // Layer Trên: Cụm Câu hỏi gợi ý Floating (Ghost Bubbles) theo Tâm lý Userflow
                if (_showSuggestions)
                  Builder(
                    builder: (context) {
                      // Tính toán Step dựa trên số lượng tin nhắn USER đã gửi
                      int userMsgCount = _chatHistory.where((m) => m['sender_role'] == 'USER').length;
                      int autoStep = 0;
                      if (userMsgCount == 1) autoStep = 1; // Sau câu 1 -> Hiện bộ 2
                      else if (userMsgCount >= 2) autoStep = 2; // Sau câu 2 trở đi -> Hiện bộ 3 (giữ nguyên)
                      
                      // Ưu tiên step người dùng tự ấn (nếu có), nếu không dùng autoStep
                      int currentStep = _suggestionStep > autoStep ? _suggestionStep : autoStep;

                      return Positioned(
                        bottom: 0,
                        right: 0,
                        left: 0,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Thanh công cụ Refresh & Close siêu nhỏ gọn
                            Padding(
                              padding: const EdgeInsets.only(right: 16, bottom: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _suggestionStep = (currentStep + 1) % 3),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.6), borderRadius: BorderRadius.circular(12)),
                                      child: Row(
                                        children: [
                                          Icon(Icons.refresh_rounded, size: 12, color: _darkBgColor),
                                          const SizedBox(width: 4),
                                          Text('Đổi chủ đề', style: TextStyle(fontSize: 10, color: _darkBgColor, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  GestureDetector(
                                    onTap: () => setState(() => _showSuggestions = false),
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), shape: BoxShape.circle),
                                      child: const Icon(Icons.close_rounded, size: 12, color: Colors.black54),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 3 Câu hỏi mồi xếp lợp (Stacked) tạo chiều sâu 3D
                            ..._suggestedQuestions.skip(currentStep * 3).take(3).toList().asMap().entries.map((entry) {
                              int idx = entry.key; // 0 (top), 1 (mid), 2 (bottom)
                              String text = entry.value;
                              double scale = 1.0 - (2 - idx) * 0.04; // Thu nhỏ dần về phía trên
                              double opacity = 1.0 - (2 - idx) * 0.2; // Mờ dần về phía trên

                              return Transform.scale(
                                scale: scale,
                                alignment: Alignment.centerRight,
                                child: Opacity(
                                  opacity: opacity,
                                  child: GestureDetector(
                                    onTap: () {
                                      _messageController.text = text;
                                      _sendMessage();
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 8, right: 16),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.95), // Giả Glassmorphism
                                        borderRadius: BorderRadius.circular(20).copyWith(bottomRight: const Radius.circular(4)),
                                        border: Border.all(color: _partnerColor.withOpacity(0.3)),
                                        boxShadow: [
                                          BoxShadow(color: _partnerColor.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                                        ],
                                      ),
                                      child: Text(
                                        text,
                                        style: TextStyle(color: _darkBgColor, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    }
                  )
              ],
            ),
          ),

          // 2. THANH NHẬP LIỆU FLOAT (INPUT PANEL)
          Container(
            margin: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom : 24, // Tạo khoảng lơ lửng so với đáy
            ),
            padding: const EdgeInsets.all(8), // Tăng padding tổng thể
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: _partnerColor.withOpacity(0.1)),
              boxShadow: [
                BoxShadow(
                  color: _partnerColor.withOpacity(0.25), // Glow xanh nhẹ, mềm mại
                  blurRadius: 24,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), // Tăng chiều cao trường nhập liệu
                    child: TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(color: _darkBgColor, fontSize: 14, fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: 'Bạn cần tư vấn gì?',
                        hintStyle: TextStyle(color: Colors.black38, fontSize: 14),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 2, right: 2),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [_partnerColor, const Color(0xFF63A067)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _partnerColor.withOpacity(0.4),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Widget thiết kế Bong bóng chat chuẩn UI/UX phân cấp thị giác
  Widget _buildChatBubble({required String content, required bool isMe, required String timeStr}) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? _partnerColor : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
          border: isMe ? null : Border.all(color: const Color(0xFFE2ECEB), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isMe ? 0.06 : 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                color: isMe ? Colors.white : _darkBgColor,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                timeStr,
                style: TextStyle(
                  color: isMe ? Colors.white.withOpacity(0.6) : Colors.grey,
                  fontSize: 9,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget hiển thị bong bóng chờ AI đang xử lý/suy nghĩ tin nhắn
  Widget _buildLoadingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
        ),
        child: SizedBox(
          width: 24,
          height: 12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (index) {
              return Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: _partnerColor, shape: BoxShape.circle),
              );
            }),
          ),
        ),
      ),
    );
  }
}