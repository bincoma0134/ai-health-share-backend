import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../widgets/notification_notifier.dart';
import '../../core/router/deep_link_engine.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Lấy dữ liệu mới khi mở trang
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationNotifier.instance.loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAFA),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF27272A), size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          'Thông báo',
          style: TextStyle(color: Color(0xFF27272A), fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () {
              NotificationNotifier.instance.markAllAsRead();
            },
            child: const Text(
              'Đọc tất cả',
              style: TextStyle(color: Color(0xFF10B981), fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: NotificationNotifier.instance,
        builder: (context, _) {
          if (NotificationNotifier.instance.isLoading && NotificationNotifier.instance.notifications.isEmpty) {
            return _buildLoadingState();
          }

          final notifications = NotificationNotifier.instance.notifications;

          if (notifications.isEmpty) {
            return _buildEmptyState();
          }

          return RefreshIndicator(
            color: const Color(0xFF10B981),
            onRefresh: NotificationNotifier.instance.loadNotifications,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final item = notifications[index];
                return _buildNotificationItem(item);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(dynamic item) {
    final bool isRead = item['is_read'] ?? false;
    final String category = item['category'] ?? 'SYSTEM';
    
    Color iconColor = const Color(0xFF3B82F6); // SYSTEM - Xanh dương
    IconData iconData = Icons.notifications;
    
    if (category == 'BOOKING') {
      iconColor = const Color(0xFF10B981); // Emerald
      iconData = Icons.calendar_today;
    } else if (category == 'FINANCIAL') {
      iconColor = const Color(0xFFF59E0B); // Vàng kim
      iconData = Icons.account_balance_wallet;
    } else if (category == 'GAMIFICATION') {
      iconColor = const Color(0xFF8B5CF6); // Tím
      iconData = Icons.emoji_events;
    }

    return GestureDetector(
      onTap: () {
        NotificationNotifier.instance.markAsRead(item['id']);
        DeepLinkEngine.instance.handleNotificationTap(context, item['deep_link_payload']);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : const Color(0xFF80BF84).withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 16,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(iconData, color: iconColor, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item['title'] ?? '',
                          style: TextStyle(
                            color: isRead ? const Color(0xFFA1A1AA) : const Color(0xFF27272A),
                            fontSize: 15,
                            fontWeight: isRead ? FontWeight.w400 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!isRead)
                        Container(
                          margin: const EdgeInsets.only(left: 8, top: 6),
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        )
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item['short_message'] ?? '',
                    style: TextStyle(
                      color: isRead ? const Color(0xFFD4D4D8) : const Color(0xFF71717A),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(item['created_at']),
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.spa_outlined, size: 64, color: const Color(0xFF10B981).withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'Không gian yên tĩnh.\nBạn không có thông báo mới nào tại thời điểm này.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 14, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),
              Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 150, height: 14, color: Colors.grey[100]),
                    const SizedBox(height: 8),
                    Container(width: double.infinity, height: 12, color: Colors.grey[100]),
                    const SizedBox(height: 8),
                    Container(width: double.infinity, height: 12, margin: const EdgeInsets.only(right: 40), color: Colors.grey[100]),
                  ],
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
        );
      },
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final date = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);
      if (diff.inDays > 0) return '${diff.inDays} ngày trước';
      if (diff.inHours > 0) return '${diff.inHours} giờ trước';
      if (diff.inMinutes > 0) return '${diff.inMinutes} phút trước';
      return 'Vừa xong';
    } catch (_) {
      return '';
    }
  }
}