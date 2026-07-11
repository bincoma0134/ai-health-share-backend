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
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _darkBgColor, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: _partnerColor.withOpacity(0.15),
              radius: 18,
              child: Icon(Icons.support_agent_rounded, color: _partnerColor, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.partnerName ?? 'Trợ lý AI Cơ Sở',
                    style: TextStyle(color: _darkBgColor, fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Text(
                    'Tư vấn tự động 24/7',
                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // 1. KHU VỰC HIỂN THỊ TIN NHẮN (MESSAGE VIEW)
          Expanded(
            child: _isLoadingHistory
                ? Center(child: CircularProgressIndicator(color: _partnerColor))
                : _chatHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.chat_bubble_outline_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 12),
                            Text(
                              'Bắt đầu cuộc trò chuyện với Trợ lý của chúng tôi!',
                              style: TextStyle(color: _darkBgColor.withOpacity(0.5), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        itemCount: _chatHistory.length + (_isSending ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Hiển thị hiệu ứng AI đang suy nghĩ (Loading Bubble) ở cuối danh sách
                          if (index == _chatHistory.length) {
                            return _buildLoadingBubble();
                          }

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

          // 2. THANH NHẬP LIỆU BÊN DƯỚI (INPUT PANEL)
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 10,
              bottom: MediaQuery.of(context).padding.bottom + 10,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7F7),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFFE2ECEB), width: 1),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      controller: _messageController,
                      maxLines: 4,
                      minLines: 1,
                      style: TextStyle(color: _darkBgColor, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Nhập câu hỏi tư vấn dịch vụ...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _partnerColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _partnerColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ],
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
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