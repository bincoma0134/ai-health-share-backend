import asyncio
from datetime import datetime, timedelta
import os
import psycopg2
from notification_service import NotificationService

# Theo dõi phút cuối cùng đã chạy để tránh kích hoạt trùng lặp trong cùng 1 phút
last_run_minute = -1

async def _scheduler_loop():
    global last_run_minute
    while True:
        try:
            # Đồng bộ Múi giờ Việt Nam (UTC + 7) không cần thư viện pytz
            now_vn = datetime.utcnow() + timedelta(hours=7)
            current_hour = now_vn.hour
            current_minute = now_vn.minute
            current_weekday = now_vn.weekday() # 0 = Mon, 5 = Sat

            # Chỉ xét duyệt trigger khi phút hiện tại chuyển sang phút mới
            if current_minute != last_run_minute:
                last_run_minute = current_minute
                
                events_to_trigger = []
                
                # 1. Dòng năng lượng buổi sớm
                if current_hour == 7 and current_minute == 30:
                    events_to_trigger.append("SYS_MORNING_SPA")
                
                # 2. Tĩnh tâm buông bỏ
                elif current_hour == 21 and current_minute == 30:
                    events_to_trigger.append("SYS_EVENING_MEDITATION")
                
                # 3. Kế hoạch thanh lọc cuối tuần (Sáng Thứ Bảy)
                elif current_weekday == 5 and current_hour == 8 and current_minute == 30:
                    events_to_trigger.append("SYS_WEEKEND_RETREAT")
                
                # 4. Nhắc nhở kết nối chánh niệm (Người dùng vắng mặt 3 ngày)
                elif current_hour == 15 and current_minute == 0:
                    events_to_trigger.append("SYS_INACTIVE_REMINDER")
                    
                if events_to_trigger:
                    _execute_triggers(events_to_trigger)

        except Exception as e:
            print(f"[Scheduler Error] Lỗi vòng lặp chạy ngầm: {e}")
        
        # Cập nhật nhịp đập 20s một lần để tiết kiệm CPU mà không lọt lưới bất kỳ phút nào
        await asyncio.sleep(20)

def _execute_triggers(events):
    """Mở một connection độc lập hoàn toàn để không cướp pool của main api"""
    DATABASE_URL = os.environ.get("DATABASE_URL")
    if not DATABASE_URL:
        return
    
    try:
        conn = psycopg2.connect(DATABASE_URL)
        cur = conn.cursor()
        try:
            for event in events:
                if event == "SYS_INACTIVE_REMINDER":
                    # Lấy những User chưa có biến động điểm danh SValue trong 3 ngày qua (hoặc mới tạo)
                    cur.execute("""
                        SELECT u.id FROM users u
                        LEFT JOIN user_svalue_wallet w ON u.id = w.user_id
                        WHERE w.last_checkin_at IS NULL 
                           OR w.last_checkin_at < NOW() - INTERVAL '3 days'
                    """)
                    users = cur.fetchall()
                    for u in users:
                        NotificationService.dispatch_event(conn, str(u[0]), event, "")
                else:
                    # Multicast cho toàn mạng lưới
                    cur.execute("SELECT id FROM users")
                    users = cur.fetchall()
                    for u in users:
                        NotificationService.dispatch_event(conn, str(u[0]), event, "")
            conn.commit()
        finally:
            cur.close()
            conn.close()
    except Exception as e:
        print(f"[Scheduler DB Error] Lỗi truy xuất hàng loạt: {e}")

def start_scheduler():
    """Kích hoạt Task chạy nền trong Event Loop của FastAPI"""
    asyncio.create_task(_scheduler_loop())