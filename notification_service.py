import json
from push_service import PushService

class NotificationService:
    """
    Dịch vụ Thông báo Độc lập (Overlay Layer).
    Bọc thép hoàn toàn: Lỗi Firebase hoặc DB nội bộ không bao giờ lan ra Business Flow chính.
    """
    @staticmethod
    def dispatch_event(conn, user_id: str, event_type: str, reference_id: str, metadata: dict = None, sender_id: str = None):
        try:
            mapping = NotificationService._get_event_mapping(event_type, metadata or {})
            if not mapping:
                return False
            
            category = mapping.get("category", "SYSTEM")
            title = mapping.get("title", "Thông báo")
            message = mapping.get("message", "")
            deep_link = {
                "screen": mapping.get("screen", "home"),
                "reference_id": reference_id,
                "event_type": event_type
            }
            
            # 1. Create & Save Notification vào Database
            notif_id = NotificationService._create_and_save_record(
                conn, user_id, category, title, message, deep_link, sender_id
            )
            
            # 2. Send Push Notification qua FCM
            if notif_id:
                PushService.send_push_to_user(
                    conn, user_id, title, message, deep_link
                )
            
            return True
        except Exception as e:
            print(f"[NotificationService Error] Đã tự động cô lập lỗi: {str(e)}")
            return False

    @staticmethod
    def mark_notification_as_read(conn, user_id: str, notification_id: str):
        """Đánh dấu một thông báo là đã đọc (Mark Read)"""
        cur = conn.cursor()
        try:
            cur.execute(
                "UPDATE notifications SET is_read = TRUE WHERE id = %s AND user_id = %s",
                (notification_id, user_id)
            )
            return cur.rowcount > 0
        except Exception as e:
            print(f"[NotificationService] Read Error: {e}")
            return False
        finally:
            cur.close()

    @staticmethod
    def _get_event_mapping(event_type: str, metadata: dict):
        # Hỗ trợ backward compatibility cho main.py đang dùng send_notification() thô
        if event_type == "LEGACY":
            return {
                "category": metadata.get("category", "SYSTEM"),
                "title": metadata.get("title", "Thông báo"),
                "message": metadata.get("message", ""),
                "screen": "home"
            }
        
        # Ma trận Event bọc thép (Mở rộng cho Beta)
        events = {
            "SYS_WELCOME": {
                "category": "SYSTEM",
                "title": "Lời chào khởi đầu",
                "message": "Chào mừng bạn đến với không gian VNShare Wellness. Hãy dành cho bản thân một vài phút tĩnh lặng hôm nay để lắng nghe cơ thể mình nhé.",
                "screen": "home"
            },
            "SYS_MAINTENANCE": {
                "category": "SYSTEM",
                "title": "Lịch bảo trì định kỳ",
                "message": "Hệ thống nghỉ ngơi. VNShare sẽ tiến hành bảo trì định kỳ từ 01:00 đến 03:00 ngày mai.",
                "screen": "home"
            },
            "SYS_MORNING_SPA": {
                "category": "SYSTEM",
                "title": "Dòng năng lượng buổi sớm",
                "message": "Chào buổi sáng yên lành. Một ly nước ấm đầu ngày và vài nhịp thở sâu sẽ giúp bạn khơi dậy năng lượng tinh khôi.",
                "screen": "home"
            },
            "SYS_EVENING_MEDITATION": {
                "category": "SYSTEM",
                "title": "Tĩnh tâm buông bỏ",
                "message": "Thả lỏng và gác lại âu lo. Dành cho tâm trí 5 phút thiền buông thư trước khi chìm vào giấc ngủ sâu.",
                "screen": "home"
            },
            "SYS_INACTIVE_REMINDER": {
                "category": "SYSTEM",
                "title": "Nhắc nhở kết nối chánh niệm",
                "message": "Đã vài ngày bạn chưa ghé không gian thiền định VNShare. Dành một chút thời gian hôm nay để tái tạo năng lượng nhé.",
                "screen": "home"
            },
            "SYS_WEEKEND_RETREAT": {
                "category": "SYSTEM",
                "title": "Kế hoạch thanh lọc cuối tuần",
                "message": "Cuối tuần thanh lọc cơ thể. Tạm rời xa khói bụi, hãy lên lịch cho một buổi trị liệu bùn khoáng hoặc massage thảo dược.",
                "screen": "home"
            },
            "APPOINTMENT_REQUESTED": {
                "category": "BOOKING",
                "title": "Yêu cầu lịch hẹn mới",
                "message": "Khách hàng đã gửi một yêu cầu hẹn lịch mới.",
                "screen": "partner_dashboard_booking"
            },
            "APPOINTMENT_ACCEPTED": {
                "category": "BOOKING",
                "title": "Lịch hẹn được chấp nhận",
                "message": "Lịch hẹn của bạn đã được xác nhận. Vui lòng thanh toán.",
                "screen": "calendar_payment"
            },
            "REVENUE_DISBURSED": {
                "category": "FINANCIAL",
                "title": "Doanh thu được giải ngân",
                "message": "Số tiền bảo chứng đã được cộng vào Ví đối tác.",
                "screen": "partner_wallet"
            }
        }
        return events.get(event_type)

    @staticmethod
    def _create_and_save_record(conn, user_id, category, title, message, deep_link, sender_id):
        cur = conn.cursor()
        try:
            cur.execute("SAVEPOINT notif_insert_sp")
            cur.execute("""
                INSERT INTO notifications (user_id, sender_id, category, title, short_message, deep_link_payload)
                VALUES (%s, %s, %s, %s, %s, %s::jsonb)
                RETURNING id
            """, (user_id, sender_id, category, title, message, json.dumps(deep_link)))
            record = cur.fetchone()
            cur.execute("RELEASE SAVEPOINT notif_insert_sp")
            return str(record[0]) if record else None
        except Exception as e:
            cur.execute("ROLLBACK TO SAVEPOINT notif_insert_sp")
            print(f"[Notification DB Error] Lỗi ghi DB đã được cô lập: {e}")
            return None
        finally:
            cur.close()

    # Đã bóc tách _send_fcm_multicast sang PushService để cô lập hạ tầng mạng