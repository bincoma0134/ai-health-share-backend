import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart'; // Bổ sung GoRouter
import '../../core/network/api_client.dart';
import '../../data/models/comment_model.dart';

class CommentBottomSheet extends StatefulWidget {
  final String videoId;
  final VoidCallback onAuthRequired;
  final VoidCallback onCommentAdded;

  const CommentBottomSheet({
    super.key, 
    required this.videoId, 
    required this.onAuthRequired,
    required this.onCommentAdded,
  });

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet> {
  List<CommentModel> _comments = [];
  bool _isLoading = true;
  bool _isSending = false;
  final _commentController = TextEditingController();
  final _storage = const FlutterSecureStorage();

  // MỚI: State xử lý Reply (Trả lời bình luận)
  String? _replyToId;
  String? _replyToName;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _fetchComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchComments() async {
    try {
      final res = await ApiClient.instance.get('/tiktok/feeds/${widget.videoId}/comments');
      if (res.statusCode == 200 && res.data['status'] == 'success') {
        final List<dynamic> data = res.data['data'];
        setState(() {
          _comments = data.map((json) => CommentModel.fromJson(json)).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final token = await _storage.read(key: 'ai-health-token');
    if (token == null || token.isEmpty) {
      Navigator.pop(context); 
      widget.onAuthRequired(); 
      return;
    }

    setState(() => _isSending = true);
    try {
      final res = await ApiClient.instance.post(
        '/tiktok/feeds/${widget.videoId}/comments',
        data: {
          'content': text,
          if (_replyToId != null) 'parent_id': _replyToId // Đính kèm ID của bình luận cha
        },
      );

      if (res.statusCode == 200) {
        _commentController.clear();
        setState(() {
          _replyToId = null;
          _replyToName = null;
        });
        widget.onCommentAdded(); 
        await _fetchComments();  
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi gửi bình luận')));
    } finally {
      setState(() => _isSending = false);
    }
  }

  // MỚI: Thuật toán vẽ Role Badge (Huy hiệu) đồng bộ 100% với Web
  Widget _buildRoleBadge(String? role) {
    if (role == null || role == 'USER') return const SizedBox.shrink();
    
    Color bgColor;
    Color textColor = Colors.black87;
    String text;
    IconData icon;
    
    switch (role) {
      case 'SUPER_ADMIN':
      case 'ADMIN':
        bgColor = Colors.red.shade100;
        text = 'QTV';
        icon = Icons.admin_panel_settings;
        break;
      case 'MODERATOR':
        bgColor = Colors.blue.shade100;
        text = 'Kiểm duyệt';
        icon = Icons.gavel_rounded;
        break;
      case 'PARTNER_ADMIN':
        bgColor = const Color(0xFF80BF84).withOpacity(0.3);
        text = 'Đối tác';
        icon = Icons.verified_rounded;
        break;
      case 'CREATOR':
        bgColor = Colors.purple.shade100;
        text = 'Creator';
        icon = Icons.palette_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textColor),
          const SizedBox(width: 3),
          Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: textColor)),
        ],
      ),
    );
  }

  // MỚI: Khối Render từng dòng bình luận (Hỗ trợ phân cấp thụt lề isChild)
  Widget _buildCommentItem(CommentModel c, {bool isChild = false}) {
    final userMap = c.user; 
    final authorName = userMap['full_name'] ?? userMap['username'] ?? 'Người dùng';
    // Lấy 'username' thay vì 'id' để truyền cho app_router
    final authorUsername = userMap['username']?.toString() ?? ''; 
    final role = userMap['role'];
    
    final parentId = c.parentId; 

    return Padding(
      padding: EdgeInsets.only(bottom: 16.0, left: isChild ? 44.0 : 0.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Avatar dẫn đến Profile
          GestureDetector(
            onTap: () {
              Navigator.pop(context); // Đóng modal bình luận trước khi chuyển trang
              if (authorUsername.isNotEmpty) context.push('/public-profile/$authorUsername');
            },
            child: CircleAvatar(
              radius: isChild ? 14 : 18,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: NetworkImage(userMap['avatar_url'] ?? 'https://via.placeholder.com/150'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 2. Tên + Huy hiệu dẫn đến Profile
                GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (authorUsername.isNotEmpty) context.push('/public-profile/$authorUsername');
                  },
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(authorName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87), overflow: TextOverflow.ellipsis),
                      ),
                      _buildRoleBadge(role),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(c.content, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 6),
                
                // 3. Nút Trả lời (Reply)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                     setState(() {
                       // Nếu đang bấm reply một child, thì gán parent_id là id của thằng cha cao nhất
                       _replyToId = isChild ? parentId : c.id; 
                       _replyToName = authorName;
                     });
                     _focusNode.requestFocus(); // Tự động bật bàn phím
                  },
                  child: const Text('Trả lời', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Phân loại bình luận Cha
    final parentComments = _comments.where((c) {
      return c.parentId == null || c.parentId!.isEmpty;
    }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // Glassmorphism XanhSM
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          margin: const EdgeInsets.only(top: kToolbarHeight), 
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.5))),
          ),
          child: Column(
            children: [
              // Thanh Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40, height: 5, 
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))
                )
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Bình luận (${_comments.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    GestureDetector(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, size: 20))),
                  ],
                ),
              ),
              const Divider(height: 1, color: Colors.black12),
              
              // Danh sách bình luận
              Expanded(
                child: _isLoading 
                    ? const Center(child: CircularProgressIndicator(color: Color(0xFF80BF84)))
                    : _comments.isEmpty
                        ? const Center(child: Text('Chưa có bình luận nào. Hãy là người đầu tiên!', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            itemCount: parentComments.length,
                            itemBuilder: (context, index) {
                              final parent = parentComments[index];
                              // Lọc các bình luận con thuộc về cha này
                              final children = _comments.where((c) {
                                return c.parentId == parent.id;
                              }).toList();
                              
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildCommentItem(parent, isChild: false),
                                  ...children.map((child) => _buildCommentItem(child, isChild: true)),
                                ],
                              );
                            },
                          ),
              ),
              
              // Thanh nhập liệu (Có cờ báo Reply)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
                ),
                child: Column(
                  children: [
                    // Cờ báo hiệu đang Reply ai đó
                    if (_replyToId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0, left: 8, right: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Đang trả lời @$_replyToName', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
                            GestureDetector(
                              onTap: () => setState(() { _replyToId = null; _replyToName = null; }),
                              child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
                            )
                          ],
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            focusNode: _focusNode,
                            decoration: InputDecoration(
                              hintText: _replyToId != null ? 'Viết câu trả lời...' : 'Thêm bình luận...',
                              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _isSending ? null : _postComment,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: Color(0xFF80BF84), shape: BoxShape.circle),
                            child: _isSending 
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                          ),
                        )
                      ],
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}