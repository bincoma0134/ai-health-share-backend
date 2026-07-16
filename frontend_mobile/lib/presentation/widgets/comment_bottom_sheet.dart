import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'auth_guard.dart';
import 'package:go_router/go_router.dart'; // Bổ sung GoRouter
import '../../core/network/api_client.dart';
import '../../data/models/comment_model.dart';
import 'shimmer_wrapper.dart';

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
  List<CommentModel> _parentComments = [];
  Map<String, List<CommentModel>> _childrenMap = {};
  
  bool _isLoading = true;
  bool _isSending = false;
  final _commentController = TextEditingController();
  final _storage = const FlutterSecureStorage();

  // MỚI: State xử lý Reply (Trả lời bình luận)
  String? _replyToId;
  String? _replyToName;
  final FocusNode _focusNode = FocusNode();
  
  final List<String> _quickEmojis = ['❤️', '😂', '👍', '😮', '🎉', '🙏'];

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
        final parsedComments = data.map((json) => CommentModel.fromJson(json)).toList();
        _processCommentTree(parsedComments);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _processCommentTree(List<CommentModel> allComments) {
    final parents = <CommentModel>[];
    final childrenMap = <String, List<CommentModel>>{};

    for (var c in allComments) {
      if (c.parentId == null || c.parentId!.isEmpty) {
        parents.add(c);
      } else {
        childrenMap.putIfAbsent(c.parentId!, () => []).add(c);
      }
    }

    setState(() {
      _comments = allComments;
      _parentComments = parents;
      _childrenMap = childrenMap;
      _isLoading = false;
    });
  }

  Future<void> _postComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    if (!AuthNotifier.instance.isAuthenticated) {
      Navigator.pop(context); 
      widget.onAuthRequired(); 
      return;
    }

    setState(() => _isSending = true);
    
    // 1. Optimistic Update: Thêm fake comment vào UI ngay lập tức
    final tempComment = CommentModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: text,
      parentId: _replyToId,
      createdAt: DateTime.now().toIso8601String(),
      user: {'full_name': 'Bạn', 'role': 'USER', 'avatar_url': null},
    );
    
    final currentComments = List<CommentModel>.from(_comments)..insert(0, tempComment);
    _processCommentTree(currentComments);
    
    final targetReplyId = _replyToId;
    
    _commentController.clear();
    setState(() {
      _replyToId = null;
      _replyToName = null;
    });
    widget.onCommentAdded();

    // 2. Gọi API ngầm dưới nền
    try {
      final res = await ApiClient.instance.post(
        '/tiktok/feeds/${widget.videoId}/comments',
        data: {
          'content': text,
          if (targetReplyId != null) 'parent_id': targetReplyId
        },
      );

      if (res.statusCode == 200) {
        _fetchComments(); // Đồng bộ lại ID thực tế sau khi thành công
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi mạng. Vui lòng thử lại!')));
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

  Widget _buildShimmerLoading() {
    return ShimmerWrapper(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        itemCount: 6,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 24.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(radius: 18, backgroundColor: Colors.grey.shade200),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(width: 100, height: 12, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 8),
                    Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
                    const SizedBox(height: 6),
                    Container(width: 180, height: 14, decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // Glassmorphism XanhSM
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutQuart,
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
                    ? _buildShimmerLoading()
                    : _comments.isEmpty
                        ? const Center(child: Text('Chưa có bình luận nào. Hãy là người đầu tiên!', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                            itemCount: _parentComments.length,
                            itemBuilder: (context, index) {
                              final parent = _parentComments[index];
                              final children = _childrenMap[parent.id] ?? [];
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

              // MỚI: Thanh Quick Emoji Bar và Text Input kết hợp thành thiết kế lơ lửng, bọc Glow
              Container(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF80BF84).withOpacity(0.2),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                    const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_replyToId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF80BF84).withOpacity(0.1),
                              border: const Border(bottom: BorderSide(color: Colors.black12, width: 0.5)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.reply_rounded, size: 14, color: Color(0xFF80BF84)),
                                    const SizedBox(width: 6),
                                    Text('Trả lời ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                    Text('@$_replyToName', style: const TextStyle(fontSize: 12, color: Color(0xFF80BF84), fontWeight: FontWeight.w900)),
                                  ],
                                ),
                                GestureDetector(
                                  onTap: () => setState(() { _replyToId = null; _replyToName = null; }),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(color: Colors.grey.shade200, shape: BoxShape.circle),
                                    child: const Icon(Icons.close_rounded, size: 12, color: Colors.grey),
                                  ),
                                )
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: _quickEmojis.map((emoji) => GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                _commentController.text += emoji;
                                _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
                                _focusNode.requestFocus();
                              },
                              child: Text(emoji, style: const TextStyle(fontSize: 20)),
                            )).toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  focusNode: _focusNode,
                                  maxLines: 4,
                                  minLines: 1,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                  decoration: InputDecoration(
                                    hintText: _replyToId != null ? 'Thêm bình luận...' : 'Để lại bình luận yêu thương...',
                                    hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13, fontStyle: FontStyle.italic),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                                    filled: true,
                                    fillColor: Colors.grey.shade100.withOpacity(0.8),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: _isSending ? null : _postComment,
                                child: Container(
                                  height: 42, width: 42,
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [Color(0xFF80BF84), Color(0xFF5A9B60)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                                    shape: BoxShape.circle,
                                    boxShadow: [BoxShadow(color: const Color(0xFF80BF84).withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 2))],
                                  ),
                                  child: _isSending
                                      ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                                ),
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}