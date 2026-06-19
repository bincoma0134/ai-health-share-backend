import json
import firebase_admin
from firebase_admin import messaging

class PushService:
    """
    Dịch vụ phân phát tin đẩy (Push Layer).
    Chịu trách nhiệm giao tiếp độc lập với Firebase FCM và tự động dọn dẹp Token rác.
    """
    @staticmethod
    def send_push_to_user(conn, user_id: str, title: str, message: str, deep_link_payload: dict):
        cur = conn.cursor()
        try:
            # 1. Bỏ qua an toàn nếu chưa khởi tạo Firebase
            if not firebase_admin._apps:
                return False

            # 2. Truy vấn danh sách Token thiết bị an toàn qua SAVEPOINT
            cur.execute("SAVEPOINT push_read_sp")
            try:
                cur.execute("SELECT token FROM user_fcm_tokens WHERE user_id = %s", (user_id,))
                tokens = [row[0] for row in cur.fetchall()]
                cur.execute("RELEASE SAVEPOINT push_read_sp")
            except Exception as db_err:
                cur.execute("ROLLBACK TO SAVEPOINT push_read_sp")
                print(f"[PushService DB Error] Lỗi truy vấn Token: {db_err}")
                return False
            
            if not tokens:
                return False

            # 3. Đóng gói Payload Multicast FCM
            msg = messaging.MulticastMessage(
                notification=messaging.Notification(
                    title=title,
                    body=message
                ),
                data={"payload": json.dumps(deep_link_payload)},
                tokens=tokens
            )
            
            # 4. Gửi qua Firebase SDK
            response = messaging.send_each_for_multicast(msg)
            
            # 5. Phân tích lỗi & Tự chữa lành (Self-Healing)
            if response.failure_count > 0:
                invalid_tokens = []
                for idx, resp in enumerate(response.responses):
                    if not resp.success:
                        # FCM Exception codes: token bị gỡ hoặc hết hạn
                        if getattr(resp.exception, 'code', '') in ['NOT_FOUND', 'INVALID_ARGUMENT', 'UNREGISTERED'] or 'UNREGISTERED' in str(resp.exception).upper():
                            invalid_tokens.append(tokens[idx])
                            
                if invalid_tokens:
                    PushService._clean_invalid_tokens(conn, invalid_tokens)

            return True

        except Exception as e:
            print(f"[PushService Error] Lỗi I/O ngoại vi đã được cô lập: {e}")
            return False
        finally:
            cur.close()

    @staticmethod
    def _clean_invalid_tokens(conn, invalid_tokens: list):
        """Xóa vật lý các Token đã hết hạn/rác khỏi Database an toàn"""
        if not invalid_tokens:
            return
        cur = conn.cursor()
        try:
            cur.execute("SAVEPOINT push_clean_sp")
            cur.execute("DELETE FROM user_fcm_tokens WHERE token = ANY(%s)", (invalid_tokens,))
            cur.execute("RELEASE SAVEPOINT push_clean_sp")
        except Exception as e:
            cur.execute("ROLLBACK TO SAVEPOINT push_clean_sp")
            print(f"[PushService Cleanup Error] Đã cô lập lỗi dọn rác: {e}")
        finally:
            cur.close()