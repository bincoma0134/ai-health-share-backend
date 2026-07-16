import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../data/models/chat_message_model.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/auth_guard.dart';
import '../../widgets/guest_profile_view.dart';
import '../../widgets/notification_notifier.dart'; // 🚀 Bổ sung thư viện quản lý State thông báo

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with TickerProviderStateMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  // Animation Controller cho Quả cầu năng lượng AI 3D
  late AnimationController _orbController;
  bool _isTyping = false;
  String? _activeConvId;
  List<dynamic> _conversations = [];
  
  List<ChatMessageModel> _messages = [
    ChatMessageModel(
      id: 'welcome',
      role: 'bot',
      content: 'Xin chào! Tôi là Trợ lý AI Đẳng cấp của bạn. Hệ thống y tế thông minh đã sẵn sàng hỗ trợ bạn chẩn đoán triệu chứng, lên thực đơn và tìm kiếm phòng khám ưu đãi tối ưu nhất.',
      timestamp: DateTime.now(),
    )
  ];

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(); // Chạy vô hạn để tạo sóng chuyển động 3D
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    try {
      final res = await ApiClient.instance.get('/ai/conversations');
      if (res.statusCode == 200 && mounted) {
        setState(() {
          _conversations = res.data['data'] ?? [];
        });
        if (_conversations.isNotEmpty && _activeConvId == null) {
          _loadHistory(_conversations.first['id']);
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải danh sách chat: $e");
    }
  }

  Future<void> _loadHistory(String convId) async {
    try {
      final res = await ApiClient.instance.get('/ai/conversations/$convId/history');
      if (res.statusCode == 200 && mounted) {
        final List<dynamic> historyData = res.data['data'] ?? [];
        setState(() {
          _activeConvId = convId;
          _messages = historyData.map((m) => ChatMessageModel(
            id: m['id'].toString(),
            role: m['role'] == 'assistant' ? 'bot' : 'user',
            content: m['content'],
            timestamp: DateTime.parse(m['created_at']).toLocal(),
          )).toList();
        });
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint("Lỗi tải lịch sử chat: $e");
    }
  }

  void _createNewChat() {
    setState(() {
      _activeConvId = null;
      _messages = [
        ChatMessageModel(
          id: 'welcome',
          role: 'bot',
          content: 'Xin chào! Tôi là Trợ lý VN Share. Hệ thống y tế thông minh đã sẵn sàng hỗ trợ bạn chẩn đoán triệu chứng, lên thực đơn và tìm kiếm phòng khám ưu đãi tốt nhất.',
          timestamp: DateTime.now(),
        )
      ];
    });
  }

  @override
  void dispose() {
    _orbController.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // --- TRÍCH XUẤT THÔNG TIN VÀ CHUYỂN ĐỔI CHAT THÀNH CARD HÀNH ĐỘNG ---
  void _processAiResponse(String text) {
    // Thuật toán bẫy chuỗi thông minh từ LLM (Ví dụ: [SUGGEST_BOOKING: partner_id, service_name, price])
    if (text.contains('[SUGGEST_BOOKING:')) {
      final RegExp regExp = RegExp(r'\[SUGGEST_BOOKING:\s*(.*?),\s*(.*?),\s*(.*?)\s*\]');
      final match = regExp.firstMatch(text);
      if (match != null) {
        final partnerId = match.group(1)?.trim() ?? '';
        final serviceName = match.group(2)?.trim() ?? '';
        final price = double.tryParse(match.group(3)?.trim() ?? '0') ?? 0.0;

        final cleanText = text.replaceAll(regExp, '').trim();

        setState(() {
          _messages.add(ChatMessageModel(
            id: DateTime.now().millisecondsSinceEpoch.toString(),
            role: 'bot',
            content: cleanText.isEmpty ? 'Hệ thống gợi ý giải pháp phù hợp nhất dành cho bạn:' : cleanText,
            timestamp: DateTime.now(),
            widgetType: 'booking_suggestion',
            widgetData: {
              'partner_id': partnerId,
              'service_name': serviceName,
              'price': price,
            }
          ));
        });
        _scrollToBottom();
        return;
      }
    }

    // Nếu là hội thoại text thông thường
    setState(() {
      _messages.add(ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'bot',
        content: text,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessageModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        role: 'user',
        content: query,
        timestamp: DateTime.now(),
      ));
      _isTyping = true;
    });
    _scrollToBottom();

    try {
      // 🚀 CHUẨN HÓA ĐẦU VÀO: Chuyển toàn bộ lịch sử tin nhắn hiện tại thành mảng JSON chuẩn Pydantic
      final List<Map<String, dynamic>> messagesPayload = _messages
          .where((m) => m.id != 'welcome') // Bỏ tin nhắn chào mừng hệ thống nếu Be không yêu cầu
          .map((m) => m.toApiJson())
          .toList();

      // Gọi API Endpoint, truyền đúng cấu trúc 'messages' mà schemas.AIChatRequest yêu cầu
      final response = await ApiClient.instance.post(
        '/ai/chat', 
        data: {
          'conversation_id': _activeConvId,
          'messages': messagesPayload
        },
      );

      if (response.statusCode == 200) {
        final apiData = response.data['data'] ?? {};
        final reply = apiData['reply'] ?? '';
        final newConvId = apiData['conversation_id'];
        
        if (mounted) {
          setState(() {
            _isTyping = false;
            if (_activeConvId == null && newConvId != null) {
              _activeConvId = newConvId;
              _loadConversations(); // Cập nhật danh sách nếu là chat mới
            }
          });
          _processAiResponse(reply);
        }
      } else {
        if (mounted) setState(() => _isTyping = false);
        debugPrint("⚠️ API ĐỒNG BỘ TRẢ VỀ MÃ LỖI: ${response.statusCode} - ${response.data}");
      }
    } catch (e) {
      if (!context.mounted) return;
      setState(() => _isTyping = false);
      // In lỗi thực tế ra Terminal (Logcat) giúp việc rà soát JWT hoặc Token đạt độ chuẩn xác tuyệt đối
      debugPrint("❌ CRITICAL ERROR TẠI AI CHAT FLOW: $e");
      AppToast.show(context: context, message: 'Đường truyền mạng trục trặc, vui lòng thử lại!', isSuccess: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthGuardWidget(
      fallbackBuilder: (context) => Scaffold(
        backgroundColor: const Color(0xFFF4F7F6),
        appBar: AppBar(title: const Text('Trợ lý AI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        body: GuestProfileView(onSuccess: () => AuthNotifier.instance.refresh()),
      ),
      builder: (context, token, userId) {
        return Scaffold(
          backgroundColor: const Color(0xFFF4F7F6),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. TOP DOCK: QUẢ CẦU AI HOLOGRAM 3D LƠ LỬNG PHÁT SÁNG
            _buildPremiumOrbHeader(),

            // 2. KHO KỊCH BẢN CHẠM NHANH (PROMPT STARTERS CHUẨN XANH SM)
            if (_messages.length == 1) _buildPromptStarters(),

            // 3. DANH SÁCH BONG BÓNG CHAT HỘI THOẠI
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _messages.length + (_isTyping ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) return _buildTypingIndicator();
                  final msg = _messages[index];
                  return _buildChatBubble(msg);
                },
              ),
            ),

            // 4. Ô NHẬP LIỆU LƠ LỬNG KIỂU CAPSULE VIÊN THUỐC
            _buildInputDock(),
          ],
            ),
          ),
        );
      },
    );
  }

  // --- 🚀 SIÊU WIDGET: HEADER TRỢ LÝ ẢO 3D GLOWING ORB ---
  Widget _buildPremiumOrbHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          // KHỐI RENDER TOÁN HỌC CANVAS 3D ORB ANIMATION
          AnimatedBuilder(
            animation: _orbController,
            builder: (context, child) {
              return CustomPaint(
                painter: _AiOrbPainter(progress: _orbController.value, isTyping: _isTyping),
                child: const SizedBox(width: 56, height: 56),
              );
            },
          ),
          const SizedBox(width: 14),
          Column( // 🚀 Gỡ bỏ từ khóa const ở đầu khối Column để co giãn và tối ưu thuộc tính động linh hoạt
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TRỢ LÝ ẢO Y TẾ', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87, letterSpacing: -0.2)),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 6, 
                    height: 6, 
                    decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle),
                  ),
                  const Text('  Hệ thống AI thông minh đang mở', style: TextStyle(color: Colors.black38, fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              )
            ],
          ),
          const Spacer(),
          // 🚀 NÚT THÔNG BÁO TÍCH HỢP GÓC PHẢI
          ListenableBuilder(
            listenable: NotificationNotifier.instance,
            builder: (context, child) {
              final unread = NotificationNotifier.instance.unreadCount;
              return IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.notifications_none_rounded, color: Colors.black54),
                    if (unread > 0)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFE2C55), // Badge đỏ cảnh báo chuẩn
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5), // Viền trắng tạo hiệu ứng cut-out với nền trắng của Header
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () => context.push('/notifications'),
              );
            },
          ),
          // Nút Lịch sử giữ nguyên bên cạnh
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.black54),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (context) => _buildHistorySheet(),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildHistorySheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      height: MediaQuery.of(context).size.height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Lịch sử trò chuyện', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _createNewChat();
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Chat mới'),
              )
            ],
          ),
          const Divider(),
          Expanded(
            child: _conversations.isEmpty
                ? const Center(child: Text('Chưa có cuộc trò chuyện nào', style: TextStyle(color: Colors.black54)))
                : ListView.builder(
                    itemCount: _conversations.length,
                    itemBuilder: (context, index) {
                      final conv = _conversations[index];
                      final isSelected = conv['id'] == _activeConvId;
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(conv['title'] ?? 'Trò chuyện', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? const Color(0xFF80BF84) : Colors.black87)),
                        onTap: () {
                          Navigator.pop(context);
                          _loadHistory(conv['id']);
                        },
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            try {
                              await ApiClient.instance.delete('/ai/conversations/${conv['id']}');
                              if (!context.mounted) return;
                              if (_activeConvId == conv['id']) _createNewChat();
                              _loadConversations();
                              Navigator.pop(context);
                            } catch (e) {
                              if (!context.mounted) return;
                              AppToast.show(context: context, message: 'Lỗi xóa', isSuccess: false);
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptStarters() {
    final prompts = [
      {'t': 'Phân tích triệu chứng', 'sub': 'Đau đầu, mỏi cơ sốt nhẹ...', 'i': Icons.health_and_safety_rounded},
      {'t': 'Đọc kết quả máu', 'sub': 'Gõ chỉ số WBC, RBC, HGB...', 'i': Icons.analytics_rounded},
      {'t': 'Thiết kế thực đơn', 'sub': 'Chế độ ăn giảm mỡ Keto...', 'i': Icons.restaurant_rounded},
      {'t': 'Tìm phòng khám tốt', 'sub': 'Cơ sở Nha khoa có ưu đãi...', 'i': Icons.explore_rounded},
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.7
        ),
        itemCount: prompts.length,
        itemBuilder: (context, index) {
          final p = prompts[index];
          return InkWell(
            onTap: () {
              _inputController.text = p['t'] as String;
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF80BF84).withOpacity(0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(p['i'] as IconData, color: const Color(0xFF80BF84), size: 24),
                  const SizedBox(height: 6),
                  Text(p['t'] as String, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Colors.black87)),
                  Text(p['sub'] as String, style: const TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- 🚀 THIẾT KẾ BONG BÓNG CHAT VÀ THẺ CÁC CARD HÀNH ĐỘNG ---
  Widget _buildChatBubble(ChatMessageModel msg) {
    final isUser = msg.role == 'user';
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF80BF84) : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 20),
                    ),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4)],
                  ),
                  child: MarkdownBody(
                    data: msg.content,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 14.5, fontWeight: FontWeight.w500, height: 1.35),
                    ),
                  ),
                ),
                
                // 🚀 NẾU CÓ THẺ HÀNH ĐỘNG (ACTIONABLE WIDGET suggestion)
                if (msg.widgetType == 'booking_suggestion' && msg.widgetData != null) ...[
                  const SizedBox(height: 10),
                  _buildActionableBookingCard(msg.widgetData!),
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionableBookingCard(Map<String, dynamic> data) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withOpacity(0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.stars_rounded, color: Colors.blue, size: 16),
              SizedBox(width: 4),
              Text('ĐỀ XUẤT PHÙ HỢP NHẤT', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
            ],
          ),
          const SizedBox(height: 8),
          Text(data['service_name'] ?? 'Dịch vụ y tế chuyên khoa', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 2),
          Text('${(data['price'] as double).toInt().toString()} đ', style: const TextStyle(color: Color(0xFF80BF84), fontWeight: FontWeight.w900, fontSize: 13)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 38,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black87, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0
              ),
              onPressed: () {
                // Điều hướng lướt mượt sang hồ sơ cơ sở để đặt lịch lập tức
                context.push('/public-profile/${data['partner_id']}');
              },
              child: const Text('ẤN ĐẶT LỊCH NGAY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(width: 32, height: 32, decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle), child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
            child: const Text('AI đang phân tích chỉ số...', style: TextStyle(color: Colors.black38, fontSize: 13, fontStyle: FontStyle.italic)),
          )
        ],
      ),
    );
  }

  Widget _buildInputDock() {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, bottom: MediaQuery.viewInsetsOf(context).bottom > 0 ? 12 : 110),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, -4))],
        ),
        child: Row(
          children: [
            const Icon(Icons.mic_none_rounded, color: Colors.black45, size: 24), // Đón lõng tìm kiếm giọng nói
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _inputController,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                decoration: const InputDecoration(hintText: 'Hỏi Trợ lý AI Health của bạn...', hintStyle: TextStyle(color: Colors.black26, fontSize: 13), border: InputBorder.none),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Color(0xFF80BF84)),
              onPressed: _sendMessage,
            )
          ],
        ),
      ),
    );
  }
}

// --- 🚀 TOÁN HỌC CANVAS: VẼ QUẢ CẦU AI HOLOGRAM NĂNG LƯỢNG 3D MƯỢT MÀ ---
class _AiOrbPainter extends CustomPainter {
  final double progress;
  final bool isTyping;
  _AiOrbPainter({required this.progress, required this.isTyping});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseRadius = size.width / 2.4;
    
    final paintOrb = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF80BF84).withOpacity(0.9),
          const Color(0xFF4C8D50).withOpacity(0.5),
          const Color(0xFF80BF84).withOpacity(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: baseRadius * 1.5))
      ..style = PaintingStyle.fill;

    // 1. Vẽ lõi năng lượng phát sáng khuếch tán
    canvas.drawCircle(center, baseRadius * (isTyping ? 1.3 : 1.0), paintOrb);

    // 2. Thuật toán lượng giác vẽ 3 vòng hạt sóng điện từ 3D đan xen lướt động
    final paintLine = Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2;
    final int particleCount = 24;

    for (int layer = 0; layer < 3; layer++) {
      paintLine.color = const Color(0xFF80BF84).withOpacity(0.6 - (layer * 0.15));
      final path = Path();

      for (int i = 0; i <= particleCount; i++) {
        final double angle = (i * 2 * math.pi) / particleCount;
        // Biến thiên sóng hình Sin đứt đoạn lướt theo thời gian (progress)
        final double wave = math.sin(angle * (layer + 2) + (progress * 2 * math.pi)) * (isTyping ? 6.0 : 3.0);
        final double r = baseRadius + wave;
        
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle) * (0.7 + (layer * 0.15)); // Ép góc Elip tạo chiều sâu 3D không gian

        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      canvas.drawPath(path, paintLine);
    }
  }

  @override
  bool shouldRepaint(covariant _AiOrbPainter oldDelegate) => true;
}