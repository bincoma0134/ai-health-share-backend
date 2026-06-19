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

            # 🚀 THIẾT LẬP MASTER SAVEPOINT CÔ LẬP TOÀN DIỆN CHO PUSH LAYER
            cur.execute("SAVEPOINT top_push_sp")
            
            try:
                # 2. Truy vấn danh sách Token thiết bị
                cur.execute("SELECT token FROM user_fcm_tokens WHERE user_id = %s", (user_id,))
                tokens = [row[0] for row in cur.fetchall()]
                
                if not tokens:
                    cur.execute("RELEASE SAVEPOINT top_push_sp")
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
                
                # 5. Phân tích lỗi & Tự chữa lành (Self-Healing) nội bộ
                if response.failure_count > 0:
                    invalid_tokens = []
                    for idx, resp in enumerate(response.responses):
                        if not resp.success:
                            if getattr(resp.exception, 'code', '') in ['NOT_FOUND', 'INVALID_ARGUMENT', 'UNREGISTERED'] or 'UNREGISTERED' in str(resp.exception).upper():
                                invalid_tokens.append(tokens[idx])
                                
                    if invalid_tokens:
                        # Thực thi xóa trực tiếp trong cùng Savepoint để tối ưu hóa hiệu năng và cô lập lỗi
                        cur.execute("DELETE FROM user_fcm_tokens WHERE token = ANY(%s)", (invalid_tokens,))

                cur.execute("RELEASE SAVEPOINT top_push_sp")
                return True
                
            except Exception as inner_db_error:
                # Triệt tiêu và hoàn nguyên mọi hậu quả giao dịch nếu có lỗi phát sinh nội bộ
                cur.execute("ROLLBACK TO SAVEPOINT top_push_sp")
                print(f"[PushService Internal Error] Đã tự động hoàn nguyên chu kỳ Push: {inner_db_error}")
                return False

        except Exception as e:
            print(f"[PushService Error] Lỗi hệ thống ngoại vi đã được cô lập hoàn toàn: {e}")
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