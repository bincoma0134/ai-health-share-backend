import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/chat_message_model.dart';
import '../../widgets/auth_bottom_sheet.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final _storage = const FlutterSecureStorage();
  
  static const String _historyKey = 'ai_chat_local_history';
  bool _isTyping = false;
  
  List<ChatMessageModel> _messages = [
    ChatMessageModel(
      id: 'welcome',
      role: 'bot',
      content: 'Xin chào! Tôi là Trợ lý AI Health. Hệ thống đã sẵn sàng phân tích và tư vấn. Bạn cần giúp gì hôm nay?',
      timestamp: DateTime.now(),
    )
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // --- LOGIC LƯU TRỮ CỤC BỘ ---
  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyString = prefs.getString(_historyKey);
    
    if (historyString != null) {
      final List<dynamic> decoded = jsonDecode(historyString);
      setState(() {
        _messages = decoded.map((e) => ChatMessageModel.fromJson(e)).toList();
      });
      _scrollToBottom();
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_messages.map((m) => m.toJson()).toList());
    await prefs.setString(_historyKey, encoded);
  }

  void _clearChat() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey); // Xóa khỏi bộ nhớ
    
    setState(() {
      _messages = [
        ChatMessageModel(
          id: 'welcome',
          role: 'bot',
          content: 'Cuộc trò chuyện đã được làm mới. Tôi có thể giúp gì cho bạn?',
          timestamp: DateTime.now(),
        )
      ];
    });
  }
  // -----------------------------

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

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isTyping) return;

    final token = await _storage.read(key: 'ai-health-token');
    if (token == null || token.isEmpty) {
      if (mounted) {
        showModalBottomSheet(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => AuthBottomSheet(onSuccess: () {}),
        );
      }
      return;
    }

    setState(() {
      _messages.add(ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
      _inputController.clear();
    });
    
    _saveHistory(); // Ghi bộ nhớ sau khi User chat
    _scrollToBottom();

    try {
      // Dùng hàm toApiJson() để gửi đúng cấu trúc Backend yêu cầu
      final payload = _messages.map((m) => m.toApiJson()).toList();
      final res = await ApiClient.instance.post('/ai/chat', data: {'messages': payload});

      if (res.statusCode == 200 && res.data['status'] == 'success') {
        setState(() {
          _messages.add(ChatMessageModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: 'bot',
            content: res.data['data']['reply'],
            timestamp: DateTime.now(),
          ));
        });
        _saveHistory(); // Ghi bộ nhớ sau khi Bot trả lời
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessageModel(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: 'bot',
          content: 'Xin lỗi, hệ thống AI đang bận hoặc mất kết nối. Vui lòng thử lại sau.',
          timestamp: DateTime.now(),
        ));
      });
    } finally {
      setState(() => _isTyping = false);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090b),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF5e9662)]),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.black, size: 20),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Assistant', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text('Phân tích đa luồng', style: TextStyle(color: Color(0xFF80BF84), fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            onPressed: _clearChat,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
              itemCount: _messages.length + (_isTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isTyping) return _buildTypingIndicator();
                final msg = _messages[index];
                final isUser = msg.role == 'user';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                    children: [
                      if (!isUser) _buildAvatar(isUser: false),
                      if (!isUser) const SizedBox(width: 12),
                      
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isUser ? const Color(0xFF80BF84) : const Color(0xFF121214),
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(24),
                              topRight: const Radius.circular(24),
                              bottomLeft: Radius.circular(isUser ? 24 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 24),
                            ),
                            border: isUser ? null : Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: isUser 
                              ? Text(msg.content, style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w500))
                              : MarkdownBody(
                                  data: msg.content,
                                  styleSheet: MarkdownStyleSheet(
                                    p: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
                                    strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                    h1: const TextStyle(color: Color(0xFF80BF84), fontSize: 18, fontWeight: FontWeight.bold),
                                    h2: const TextStyle(color: Color(0xFF80BF84), fontSize: 16, fontWeight: FontWeight.bold),
                                    listBullet: const TextStyle(color: Colors.white70),
                                  ),
                                ),
                        ),
                      ),
                      
                      if (isUser) const SizedBox(width: 12),
                      if (isUser) _buildAvatar(isUser: true),
                    ],
                  ),
                );
              },
            ),
          ),
          
          Container(
            padding: EdgeInsets.only(left: 16, right: 16, top: 12, bottom: MediaQuery.of(context).padding.bottom > 0 ? MediaQuery.of(context).padding.bottom + 90 : 110),
            decoration: const BoxDecoration(
              color: Colors.black,
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: TextField(
                      controller: _inputController,
                      style: const TextStyle(color: Colors.white),
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Nhập câu hỏi của bạn...',
                        hintStyle: TextStyle(color: Colors.white30),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    height: 50,
                    width: 50,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF5e9662)]),
                      shape: BoxShape.circle,
                    ),
                    child: _isTyping 
                        ? const Padding(padding: EdgeInsets.all(14.0), child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                        : const Icon(Icons.send, color: Colors.black, size: 20),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar({required bool isUser}) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isUser ? const Color(0xFF80BF84).withOpacity(0.2) : Colors.white10,
        border: Border.all(color: isUser ? const Color(0xFF80BF84) : Colors.white24),
      ),
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 16,
        color: isUser ? const Color(0xFF80BF84) : Colors.white,
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(isUser: false),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF121214),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24), bottomRight: Radius.circular(24), bottomLeft: Radius.circular(4)),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: const Text('Đang phân tích...', style: TextStyle(color: Color(0xFF80BF84), fontSize: 13, fontStyle: FontStyle.italic)),
          ),
        ],
      ),
    );
  }
}