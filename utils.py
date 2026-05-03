# utils.py
from database import supabase
from typing import Optional

def send_notification(
    user_id: str, 
    noti_type: str, 
    title: str, 
    message: str, 
    action_url: Optional[str] = None,
    reference_id: Optional[str] = None
):
    """
    Hàm trung tâm dùng để đẩy thông báo vào Database.
    - user_id: ID người nhận
    - noti_type: "SYSTEM", "BOOKING", "SOCIAL", "MODERATION"
    """
    try:
        data = {
            "user_id": user_id,
            "type": noti_type,
            "title": title,
            "message": message,
            "is_read": False
        }
        if action_url:
            data["action_url"] = action_url
        if reference_id:
            data["reference_id"] = reference_id
            
        # Ghi vào bảng notifications
        supabase.table("notifications").insert(data).execute()
        return True
    except Exception as e:
        print(f"[Notifier Error]: Lỗi khi gửi thông báo cho {user_id} - {str(e)}")
        return False