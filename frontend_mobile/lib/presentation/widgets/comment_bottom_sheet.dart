import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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

  @override
  void initState() {
    super.initState();
    _fetchComments();
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
      Navigator.pop(context); // Đóng bảng comment
      widget.onAuthRequired(); // Yêu cầu đăng nhập
      return;
    }

    setState(() => _isSending = true);
    try {
      final res = await ApiClient.instance.post(
        '/tiktok/feeds/${widget.videoId}/comments',
        data: {'content': text},
      );

      if (res.statusCode == 200) {
        _commentController.clear();
        widget.onCommentAdded(); // Báo cho Feed tăng số lượng
        await _fetchComments();  // Tải lại danh sách
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lỗi gửi bình luận')));
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Bình luận (${_comments.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close)),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Danh sách bình luận
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator(color: Colors.green))
                : _comments.isEmpty
                    ? const Center(child: Text('Chưa có bình luận nào.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _comments.length,
                        itemBuilder: (context, index) {
                          final c = _comments[index];
                          // Layout Phase 1: Hiển thị phẳng
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: NetworkImage(c.user['avatar_url'] ?? 'https://via.placeholder.com/150'),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(c.user['full_name'] ?? 'Ẩn danh', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                                      const SizedBox(height: 4),
                                      Text(c.content, style: const TextStyle(fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
          
          // Ô nhập liệu
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    decoration: InputDecoration(
                      hintText: 'Thêm bình luận...',
                      hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isSending ? null : _postComment,
                  icon: _isSending 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send, color: Colors.blue),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}