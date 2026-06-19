from fastapi import FastAPI, HTTPException, Depends, Security, Request
from fastapi.encoders import jsonable_encoder
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
import psycopg2
from psycopg2 import pool
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv
load_dotenv()
from utils import send_notification, create_access_token, verify_password, get_password_hash
from jose import JWTError, jwt
import schemas
import time
import random
import os
import json
from datetime import datetime, timedelta
from fastapi import UploadFile, File, Form
from groq import Groq
import boto3
import uuid
import firebase_admin
from firebase_admin import credentials, auth as firebase_auth
from fastapi import APIRouter, Depends, HTTPException
from typing import List
from pydantic import BaseModel


DATABASE_URL = os.environ.get("DATABASE_URL")
if DATABASE_URL:
    db_pool = psycopg2.pool.SimpleConnectionPool(1, 20, DATABASE_URL)
else:
    db_pool = None

def get_db_connection():
    if not db_pool:
        from database import get_db_connection as fallback_db
        yield from fallback_db()
        return
        
    conn = db_pool.getconn()
    try:
        # 🚀 THUẬT TOÁN PING & SELF-HEALING: Kiểm tra sống/chết trước khi cấp phát
        try:
            with conn.cursor() as cur:
                cur.execute("SELECT 1")
        except (psycopg2.OperationalError, psycopg2.InterfaceError):
            db_pool.putconn(conn, close=True)
            conn = db_pool.getconn()
            
        yield conn
    finally:
        # Dọn dẹp rác giao dịch và trả về hồ chứa
        try:
            conn.rollback()
        except Exception:
            pass
        db_pool.putconn(conn)


# Khởi tạo Firebase Admin SDK
PROJECT_ID = "vnshare-auth"

if not firebase_admin._apps:
    try:
        # Tự động tìm file tại thư mục hệ thống của Render hoặc thư mục gốc
        import os
        cred_path = "/etc/secrets/firebase_credentials.json"
        if not os.path.exists(cred_path):
            cred_path = "firebase_credentials.json"
            
        cred = credentials.Certificate(cred_path)
        firebase_admin.initialize_app(cred, {
            'projectId': PROJECT_ID
        })
    except Exception as e:
        print(f"Warning: Firebase Admin SDK chưa được khởi tạo. Lỗi: {e}")

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "61ec7d8b-1b0a-4ac3-ad85-69d6f1393492")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "c685a770-5b64-48bc-858f-071f54af19d5")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "30f7892af9f9d37ae84681b60878483e049f6e7c3287be6bdf28aa0f485973be")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

from notification_scheduler import start_scheduler
import asyncio

app = FastAPI(title="AI Health Share API", version="5.2.1")
security = HTTPBearer()

@app.on_event("startup")
async def startup_event():
    start_scheduler()
    
    # 🚀 TỰ ĐỘNG KHỞI TẠO TẦNG LƯU TRỮ TOKEN (AUTO-MIGRATION)
    if db_pool:
        conn = db_pool.getconn()
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    CREATE TABLE IF NOT EXISTS user_fcm_tokens (
                        id SERIAL PRIMARY KEY,
                        user_id UUID NOT NULL,
                        token TEXT UNIQUE NOT NULL,
                        device_id VARCHAR(255),
                        platform VARCHAR(50),
                        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    );
                    
                    -- Khởi tạo Index tăng tốc độ truy vấn định tuyến từ O(N) về O(log N)
                    CREATE INDEX IF NOT EXISTS idx_user_fcm_tokens_user_id 
                    ON user_fcm_tokens(user_id);
                """)
            conn.commit()
        except Exception as e:
            print(f"[Database Hotfix Error] Không thể tạo bảng user_fcm_tokens: {e}")
        finally:
            db_pool.putconn(conn)

SECRET_KEY = os.environ.get("JWT_SECRET_KEY")
if not SECRET_KEY:
    raise ValueError("Thiếu cấu hình JWT_SECRET_KEY trong môi trường Runtime của main.py!")
ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")

class CurrentUser:
    def __init__(self, id, email, role):
        self.id = id
        self.email = email
        self.role = role

def verify_user_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if not user_id: raise HTTPException(status_code=401)
        return CurrentUser(id=user_id, email=payload.get("email"), role=payload.get("role"))
    except JWTError:
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn!")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

# --- VỊ TRÍ CHÈN ĐOẠN CODE UPLOAD MỚI ---
# Đặt ở đây để giữ luồng code gọn gàng, tách biệt với các API nghiệp vụ chính

@app.post("/upload/image")
async def upload_image(file: UploadFile = File(...)):
    if not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="Chỉ chấp nhận file ảnh")
    
    file_content = await file.read()
    file_key = f"uploads/images/{int(time.time())}_{uuid.uuid4().hex[:8]}.webp"
    
    try:
        r2_client.put_object(
            Bucket=os.environ.get("R2_BUCKET_NAME"),
            Key=file_key,
            Body=file_content,
            ContentType="image/webp"
        )
        public_url = f"{os.environ.get('R2_PUBLIC_DOMAIN').rstrip('/')}/{file_key}"
        return {"status": "success", "url": public_url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/upload/video")
async def upload_video(file: UploadFile = File(...)):
    if not file.content_type.startswith("video/"):
        raise HTTPException(status_code=400, detail="Chỉ chấp nhận file video")
    
    file_content = await file.read()
    # Gợi ý: Tại đây bạn có thể gọi hàm compress_video nếu đã cài đặt FFmpeg
    file_key = f"uploads/videos/{int(time.time())}_{uuid.uuid4().hex[:8]}.mp4"
    
    try:
        r2_client.put_object(
            Bucket=os.environ.get("R2_BUCKET_NAME"),
            Key=file_key,
            Body=file_content,
            ContentType="video/mp4"
        )
        public_url = f"{os.environ.get('R2_PUBLIC_DOMAIN').rstrip('/')}/{file_key}"
        return {"status": "success", "url": public_url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/")
def health_check(): return {"status": "success", "message": "Backend AI Health đang chạy mượt mà!"}

# ==========================================
# 0. AUTH TỰ CHỦ (VÁ LỖ HỔNG SUPABASE MIGRATE)
# ==========================================
@app.post("/auth/login", tags=["Auth"])
def login(payload: schemas.UserLogin, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM users WHERE email = %s OR username = %s LIMIT 1", (payload.email, payload.email))
        user = cur.fetchone()
        if not user: raise HTTPException(status_code=404, detail="Sai tài khoản hoặc mật khẩu!")

        # Kịch bản VÁ LỖ HỔNG: Tài khoản cũ chưa có password
        if user.get("password_hash") is None:
            new_hash = get_password_hash(payload.password)
            cur.execute("UPDATE users SET password_hash = %s WHERE id = %s", (new_hash, user["id"]))
            conn.commit()
        else:
            if not verify_password(payload.password, user["password_hash"]):
                raise HTTPException(status_code=401, detail="Sai tài khoản hoặc mật khẩu!")

        token = create_access_token({"sub": str(user["id"]), "email": user["email"], "role": user["role"]})
        return {"status": "success", "access_token": token, "user": {"id": user["id"], "email": user["email"], "role": user["role"], "full_name": user.get("full_name")}}
    finally: cur.close()

@app.post("/auth/register", tags=["Auth"])
def register(payload: schemas.UserRegister, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT id FROM users WHERE email = %s OR username = %s", (payload.email, payload.username))
        if cur.fetchone(): raise HTTPException(status_code=400, detail="Email hoặc Username đã tồn tại!")
        
        hashed = get_password_hash(payload.password)
        cur.execute("INSERT INTO users (email, username, full_name, role, password_hash) VALUES (%s, %s, %s, %s, %s) RETURNING id, email, role",
                    (payload.email, payload.username, payload.full_name, payload.role, hashed))
        new_user = cur.fetchone()
        conn.commit()
        return {"status": "success", "message": "Đăng ký thành công", "user": new_user}
    finally: cur.close()

from firebase_admin import auth as firebase_auth

@app.post("/auth/firebase", tags=["Auth"], summary="Login with Google/Facebook via Firebase")
def firebase_login(payload: schemas.FirebaseLogin, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # 1. Xác thực ID Token trực tiếp với server Firebase
        try:
            import time
            start_time = time.time()
            print(f"DEBUG: Bắt đầu verify_id_token...")
            
            decoded_token = firebase_auth.verify_id_token(payload.id_token)
            
            end_time = time.time()
            print(f"DEBUG: Verify hoàn tất mất {end_time - start_time:.2f} giây")
            
            email = decoded_token.get("email")
            full_name = decoded_token.get("name") or "Người dùng Khách"
            avatar_url = decoded_token.get("picture")
        except Exception as e:
            raise HTTPException(status_code=401, detail=f"Token Firebase không hợp lệ hoặc đã hết hạn: {str(e)}")

        if not email:
            raise HTTPException(status_code=400, detail="Không lấy được địa chỉ email từ tài khoản mạng xã hội")

        # 2. Xử lý đồng bộ hóa tài khoản
        cur.execute("SELECT * FROM users WHERE email = %s", (email,))
        user = cur.fetchone()
        
        is_new_user = False
        if not user:
            is_new_user = True
            base_username = email.split("@")[0][:15] + str(random.randint(1000, 9999))
            cur.execute("""
                INSERT INTO users (email, username, full_name, avatar_url, role, password_hash) 
                VALUES (%s, %s, %s, %s, 'USER', 'SOCIAL_AUTH') RETURNING *
            """, (email, base_username, full_name, avatar_url))
            user = cur.fetchone()
            
        conn.commit()
        
        # 3. Tạo System JWT Token bảo mật nội bộ
        token = create_access_token({"sub": str(user["id"]), "email": user["email"], "role": user["role"]})
        
        return {
            "status": "success", 
            "access_token": token, 
            "token_type": "bearer",
            "is_new_user": is_new_user,
            "user": {
                "id": user["id"], 
                "email": user["email"], 
                "role": user["role"], 
                "full_name": user.get("full_name"),
                "username": user.get("username"),
                "avatar_url": user.get("avatar_url")
            }
        }
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=f"Lỗi hệ thống: {str(e)}")
    finally: 
        cur.close()

# ==========================================
# 1. SERVICES (DỊCH VỤ CƠ SỞ)
# ==========================================
@app.get("/services", tags=["Services"])
def get_services(user_id: str = None, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        query = """
            SELECT s.*, 
                   json_build_object('id', u.id, 'avatar_url', u.avatar_url, 'full_name', u.full_name, 'username', u.username, 'physical_address', u.physical_address) as users
            FROM services s
            LEFT JOIN users u ON s.partner_id = u.id
            WHERE s.status = 'APPROVED'
            ORDER BY s.created_at DESC
        """
        cur.execute(query)
        services = cur.fetchall()
        for s in services: s["service_type_enum"] = s.get("service_type", "RELAXATION")
        return {"status": "success", "data": services}
    finally: cur.close()

@app.get("/map/partners", tags=["Map Explore"])
def get_map_partners(conn=Depends(get_db_connection)):
    """
    API phục vụ phân hệ Bản đồ khám phá (Map Explore).
    Tự động kết hợp dữ liệu Tọa độ Đối tác, gắn nhãn (tags) ngẫu nhiên dựa trên tên và đóng gói mảng Dịch vụ đi kèm.
    """
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Sử dụng Subquery kết hợp COALESCE và json_agg để đóng gói mảng services native từ DB
        query = """
            SELECT 
                u.id, 
                u.username, 
                u.full_name, 
                COALESCE(u.avatar_url, 'https://ui-avatars.com/api/?name=' || u.username || '&background=80BF84&color=fff') as avatar_url,
                COALESCE(u.latitude, 21.028511) as latitude, 
                COALESCE(u.longitude, 105.804817) as longitude,
                ROUND((RANDOM() * 5.5 + 1.2)::numeric, 1) as distance,
                CASE 
                    WHEN u.username ILIKE '%spa%' OR u.full_name ILIKE '%Spa%' THEN json_build_array('Spa & Clinic', 'Chăm sóc da')
                    WHEN u.username ILIKE '%lab%' OR u.full_name ILIKE '%Lab%' THEN json_build_array('Xét nghiệm', 'Chẩn đoán')
                    ELSE json_build_array('Trị liệu Đông Y', 'Phục hồi chức năng')
                END as tags,
                COALESCE(
                    (
                        SELECT json_agg(json_build_object('id', s.id, 'service_name', s.service_name, 'price', s.price))
                        FROM services s
                        WHERE s.partner_id = u.id AND s.status = 'APPROVED'
                    ),
                    '[]'::json
                ) as services
            FROM users u
            WHERE u.role = 'PARTNER_ADMIN'
            ORDER BY u.created_at DESC
        """
        cur.execute(query)
        partners_data = cur.fetchall()
        return {"status": "success", "data": partners_data}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi truy vấn dữ liệu bản đồ: {str(e)}")
    finally:
        cur.close()

@app.post("/services", tags=["Services"])
def create_service(payload: schemas.ServiceCreate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        tags_json = json.dumps(payload.tags)
        cur.execute("""INSERT INTO services (partner_id, service_name, description, price, image_url, video_url, tags, service_type, status) 
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'PENDING') RETURNING *""",
                    (current_user.id, payload.service_name, payload.description, payload.price, payload.image_url, payload.video_url, tags_json, payload.service_type))
        new_svc = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": new_svc}
    finally: cur.close()

# ==========================================
# 3. HỒ SƠ NGƯỜI DÙNG & CÔNG KHAI
# ==========================================
@app.post("/user/svalue/task", tags=["User"])
def complete_svalue_task(payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """API lưu log lịch sử và cập nhật tiến trình nhiệm vụ bảo mật tự động hệ thống"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        action_type = payload.get("action_type")
        points = int(payload.get("points_changed", 0))
        ref_id = payload.get("reference_id")
        
        # Kiểm tra xem hành động có phải là một Mission chính thức không
        cur.execute("SELECT * FROM missions WHERE code = %s AND status = 'ACTIVE'", (action_type,))
        mission = cur.fetchone()
        
        if mission:
            # Luồng xử lý tiến trình Mission Engine (Server-Driven)
            cur.execute("SELECT * FROM user_missions WHERE user_id = %s AND mission_code = %s FOR UPDATE", (current_user.id, action_type))
            user_mission = cur.fetchone()
            
            now_utc = datetime.utcnow()
            now_vn = now_utc + timedelta(hours=7)
            
            progress = 0
            status = 'IN_PROGRESS'
            
            if user_mission:
                progress = user_mission['current_progress']
                status = user_mission['status']
                last_progress_at = user_mission['last_progress_at']
                
                # Kiểm tra Daily Reset nếu là nhiệm vụ hàng ngày
                if mission['mission_type'] == 'DAILY' and last_progress_at:
                    last_vn = last_progress_at + timedelta(hours=7)
                    if last_vn.date() < now_vn.date():
                        progress = 0
                        status = 'IN_PROGRESS'
            
            # Tăng tiến trình nếu chưa hoàn thành hoặc chưa nhận thưởng
            if status == 'IN_PROGRESS':
                progress += 1
                if progress >= mission['target_value']:
                    progress = mission['target_value']
                    status = 'CLAIMABLE'
                    
                if user_mission:
                    cur.execute("""
                        UPDATE user_missions 
                        SET current_progress = %s, status = %s, last_progress_at = CURRENT_TIMESTAMP 
                        WHERE user_id = %s AND mission_code = %s
                    """, (progress, status, current_user.id, action_type))
                else:
                    cur.execute("""
                        INSERT INTO user_missions (user_id, mission_code, current_progress, status, last_progress_at)
                        VALUES (%s, %s, %s, %s, CURRENT_TIMESTAMP)
                    """, (current_user.id, action_type, progress, status))
            
            conn.commit()
            return {"status": "success", "mission_code": action_type, "current_progress": progress, "mission_status": status}
            
        else:
            # Luồng fallback tương thích ngược cho các task thủ công cũ
            cur.execute(
                "INSERT INTO svalue_transaction_logs (user_id, action_type, points_changed, reference_id) VALUES (%s, %s, %s, %s)",
                (current_user.id, action_type, points, ref_id)
            )
            cur.execute("SELECT balance FROM user_svalue_wallet WHERE user_id = %s FOR UPDATE", (current_user.id,))
            wallet = cur.fetchone()
            if not wallet:
                cur.execute("INSERT INTO user_svalue_wallet (user_id, balance, streak_count) VALUES (%s, %s, 0) RETURNING balance", (current_user.id, points))
                new_balance = points
            else:
                new_balance = wallet['balance'] + points
                cur.execute("UPDATE user_svalue_wallet SET balance = %s, updated_at = CURRENT_TIMESTAMP WHERE user_id = %s", (new_balance, current_user.id))
                
            cur.execute("UPDATE users SET svalue_balance = %s WHERE id = %s", (new_balance, current_user.id))
            conn.commit()
            return {"status": "success", "new_balance": new_balance}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.post("/user/checkin", tags=["User"])
def user_daily_checkin(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """API điểm danh hàng ngày cộng điểm SValue"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        now_utc = datetime.utcnow()
        now_vn = now_utc + timedelta(hours=7)
        today_date = now_vn.date()
        
        cur.execute("SELECT balance, streak_count, last_checkin_at FROM user_svalue_wallet WHERE user_id = %s FOR UPDATE", (current_user.id,))
        wallet = cur.fetchone()
        
        if not wallet:
            cur.execute("INSERT INTO user_svalue_wallet (user_id, balance, streak_count) VALUES (%s, 0, 0) RETURNING balance, streak_count, last_checkin_at", (current_user.id,))
            wallet = cur.fetchone()
            
        last_checkin_at = wallet.get('last_checkin_at')
        current_streak = wallet.get('streak_count')
        if current_streak is None:
            current_streak = 0
        
        if last_checkin_at:
            last_checkin_vn = (last_checkin_at + timedelta(hours=7)).date()
            if last_checkin_vn == today_date:
                raise HTTPException(status_code=400, detail="Bạn đã điểm danh hôm nay rồi.")
            elif (today_date - last_checkin_vn).days > 1 or current_streak >= 7:
                current_streak = 0
                
        new_streak = current_streak + 1
        points_earned = 40 if new_streak in [3, 7] else 20
        new_balance = wallet['balance'] + points_earned
        
        cur.execute("""
            UPDATE user_svalue_wallet 
            SET balance = %s, streak_count = %s, last_checkin_at = %s, updated_at = %s 
            WHERE user_id = %s
        """, (new_balance, new_streak, now_utc, now_utc, current_user.id))
        
        cur.execute("UPDATE users SET svalue_balance = %s WHERE id = %s", (new_balance, current_user.id))
        
        cur.execute("""
            INSERT INTO svalue_transaction_logs (user_id, action_type, points_changed, reference_id) 
            VALUES (%s, %s, %s, %s)
        """, (current_user.id, "DAILY_CHECKIN", points_earned, "CHECKIN_SYSTEM"))
        
        conn.commit()
        return {"status": "success", "data": {"new_streak": new_streak, "balance": new_balance, "points_earned": points_earned}}
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.post("/user/checkin", tags=["User"])
def user_daily_checkin(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """API điểm danh hàng ngày cộng điểm SValue"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        now_utc = datetime.utcnow()
        now_vn = now_utc + timedelta(hours=7)
        today_date = now_vn.date()
        
        cur.execute("SELECT balance, streak_count, last_checkin_at FROM user_svalue_wallet WHERE user_id = %s FOR UPDATE", (current_user.id,))
        wallet = cur.fetchone()
        
        if not wallet:
            cur.execute("INSERT INTO user_svalue_wallet (user_id, balance, streak_count) VALUES (%s, 0, 0) RETURNING balance, streak_count, last_checkin_at", (current_user.id,))
            wallet = cur.fetchone()
            
        last_checkin_at = wallet.get('last_checkin_at')
        current_streak = wallet.get('streak_count') or 0
        
        if last_checkin_at:
            last_checkin_vn = (last_checkin_at + timedelta(hours=7)).date()
            if last_checkin_vn == today_date:
                raise HTTPException(status_code=400, detail="Bạn đã điểm danh hôm nay rồi.")
            elif (today_date - last_checkin_vn).days > 1 or current_streak >= 7:
                current_streak = 0
                
        new_streak = current_streak + 1
        points_earned = 40 if new_streak in [3, 7] else 20
        new_balance = wallet['balance'] + points_earned
        
        cur.execute("""
            UPDATE user_svalue_wallet 
            SET balance = %s, streak_count = %s, last_checkin_at = %s, updated_at = %s 
            WHERE user_id = %s
        """, (new_balance, new_streak, now_utc, now_utc, current_user.id))
        
        cur.execute("UPDATE users SET svalue_balance = %s WHERE id = %s", (new_balance, current_user.id))
        
        cur.execute("""
            INSERT INTO svalue_transaction_logs (user_id, action_type, points_changed, reference_id) 
            VALUES (%s, %s, %s, %s)
        """, (current_user.id, "DAILY_CHECKIN", points_earned, "CHECKIN_SYSTEM"))
        
        conn.commit()
        return {"status": "success", "data": {"new_streak": new_streak, "balance": new_balance, "points_earned": points_earned}}
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.get("/user/missions", tags=["Missions"])
def get_user_missions(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Lấy danh sách nhiệm vụ hệ thống kèm tiến trình real-time của người dùng"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM missions WHERE status = 'ACTIVE' ORDER BY created_at ASC")
        all_missions = cur.fetchall()
        
        cur.execute("SELECT * FROM user_missions WHERE user_id = %s", (current_user.id,))
        user_progress = {p['mission_code']: p for p in cur.fetchall()}
        
        now_vn = datetime.utcnow() + timedelta(hours=7)
        result = []
        
        for m in all_missions:
            code = m['code']
            progress = 0
            status = 'IN_PROGRESS'
            
            if code in user_progress:
                p_data = user_progress[code]
                progress = p_data['current_progress']
                status = p_data['status']
                last_progress_at = p_data['last_progress_at']
                
                # Áp dụng bộ lọc thời gian Daily Reset ngay khi đọc dữ liệu
                if m['mission_type'] == 'DAILY' and last_progress_at:
                    last_vn = last_progress_at + timedelta(hours=7)
                    if last_vn.date() < now_vn.date():
                        progress = 0
                        status = 'IN_PROGRESS'
            
            result.append({
                "code": code,
                "title": m['title'],
                "description": m['description'],
                "mission_type": m['mission_type'],
                "target_value": m['target_value'],
                "reward_points": m['reward_points'],
                "current_progress": progress,
                "status": status
            })
            
        return {"status": "success", "data": result}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.post("/user/missions/{mission_code}/claim", tags=["Missions"])
def claim_mission_reward(mission_code: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Xử lý nhận thưởng bọc thép: Chống nhận trùng lặp, chống nhấp đúp qua Row-level Locking"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM missions WHERE code = %s AND status = 'ACTIVE'", (mission_code,))
        mission = cur.fetchone()
        if not mission:
            raise HTTPException(status_code=404, detail="Nhiệm vụ không tồn tại hoặc đã bị đóng.")
            
        cur.execute("SELECT * FROM user_missions WHERE user_id = %s AND mission_code = %s FOR UPDATE", (current_user.id, mission_code))
        user_mission = cur.fetchone()
        
        if not user_mission or user_mission['status'] != 'CLAIMABLE':
            raise HTTPException(status_code=400, detail="Nhiệm vụ chưa hoàn thành hoặc đã nhận thưởng trước đó.")
            
        reward_points = mission['reward_points']
        
        # Cập nhật trạng thái tiến trình sang COMPLETED
        cur.execute("""
            UPDATE user_missions 
            SET status = 'COMPLETED', completed_at = CURRENT_TIMESTAMP 
            WHERE user_id = %s AND mission_code = %s
        """, (current_user.id, mission_code))
        
        # Cộng điểm vào ví chuyên trách user_svalue_wallet
        cur.execute("SELECT balance FROM user_svalue_wallet WHERE user_id = %s FOR UPDATE", (current_user.id,))
        wallet = cur.fetchone()
        new_balance = reward_points
        if wallet:
            new_balance = wallet['balance'] + reward_points
            cur.execute("UPDATE user_svalue_wallet SET balance = %s, updated_at = CURRENT_TIMESTAMP WHERE user_id = %s", (new_balance, current_user.id))
        else:
            cur.execute("INSERT INTO user_svalue_wallet (user_id, balance, streak_count) VALUES (%s, %s, 0)", (current_user.id, new_balance))
            
        # Đồng bộ hóa sang bảng users phục vụ hiển thị cũ
        cur.execute("UPDATE users SET svalue_balance = %s WHERE id = %s", (new_balance, current_user.id))
        
        # Ghi log lịch sử giao dịch điểm thưởng
        cur.execute("""
            INSERT INTO svalue_transaction_logs (user_id, action_type, points_changed, reference_id) 
            VALUES (%s, %s, %s, %s)
        """, (current_user.id, f"CLAIM_{mission_code}", reward_points, str(user_mission['id'])))
        
        conn.commit()
        return {"status": "success", "message": f"Nhận thưởng thành công +{reward_points} SValue", "balance": new_balance}
    except HTTPException:
        conn.rollback()
        raise
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.get("/user/saves", tags=["User"])
def get_user_saves(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Lấy danh sách các nội dung (video/dịch vụ) người dùng đã lưu"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT v.*, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url, 'username', u.username, 'role', u.role) as author
            FROM tiktok_feed_saves s
            JOIN tiktok_feeds v ON s.video_id = v.id
            JOIN users u ON v.author_id = u.id
            WHERE s.user_id = %s AND v.status = 'APPROVED'
            ORDER BY s.created_at DESC
        """, (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.get("/user/profile", tags=["User"])
def get_user_profile(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Tự động đồng bộ cấu trúc cột nếu hệ thống chưa đồng bộ
        cur.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS svalue_balance INT DEFAULT 0")
        
        # ĐỒNG BỘ: Chuyển nguồn sự thật SValue sang user_svalue_wallet theo DB Reality
        cur.execute("SELECT balance, streak_count, last_checkin_at FROM user_svalue_wallet WHERE user_id = %s", (current_user.id,))
        wallet = cur.fetchone()
        if not wallet:
            cur.execute("INSERT INTO user_svalue_wallet (user_id, balance, streak_count) VALUES (%s, 0, 0) RETURNING balance, streak_count, last_checkin_at", (current_user.id,))
            wallet = cur.fetchone()
        conn.commit()
        
        cur.execute("SELECT * FROM users WHERE id = %s", (current_user.id,))
        user_info = cur.fetchone()
        
        # Bơm dữ liệu Ví vào user_info để Mobile App vẽ tiến trình 7 ngày
        user_info['svalue_balance'] = wallet['balance']
        user_info['streak_count'] = wallet['streak_count']
        user_info['last_checkin_at'] = wallet['last_checkin_at'].isoformat() if wallet['last_checkin_at'] else None
        
        # Thống kê dành cho vai trò đối tác (Partner)
        cur.execute("SELECT count(*) as pending FROM services WHERE partner_id = %s AND status = 'PENDING'", (current_user.id,))
        pending = cur.fetchone()["pending"]
        cur.execute("SELECT count(*) as approved FROM services WHERE partner_id = %s AND status = 'APPROVED'", (current_user.id,))
        approved = cur.fetchone()["approved"]

        # Thống kê lượng tương tác thô thời gian thực (Real-time Raw Data Counting) cho người dùng tiêu chuẩn
        cur.execute("SELECT count(*) as likes FROM tiktok_feed_likes WHERE user_id = %s", (current_user.id,))
        likes_count = cur.fetchone()["likes"]
        
        cur.execute("SELECT count(*) as saves FROM tiktok_feed_saves WHERE user_id = %s", (current_user.id,))
        saved_count = cur.fetchone()["saves"]
        
        cur.execute("SELECT count(*) as appointments FROM appointments WHERE user_id = %s", (current_user.id,))
        bookings_count = cur.fetchone()["appointments"]

        return {
            "status": "success", 
            "data": {
                "profile": user_info, 
                "stats": {
                    "pending_total": pending, 
                    "approved_count": approved, 
                    "total_processed": 0,
                    "likes_count": likes_count,
                    "saved_count": saved_count,
                    "bookings_count": bookings_count
                }
            }
        }
    finally: cur.close()

@app.get("/user/public/{username}", tags=["User"])
def get_public_profile(username: str, request: Request, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        viewer_id = None
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            try:
                payload = jwt.decode(auth_header.split(" ")[1], SECRET_KEY, algorithms=[ALGORITHM])
                viewer_id = payload.get("sub")
            except: pass 

        clean_username = username.lstrip('@')
        cur.execute("SELECT * FROM users WHERE username = %s", (clean_username,))
        user = cur.fetchone()
        if not user: raise HTTPException(status_code=404, detail="Người dùng không tồn tại!")
        target_id = user["id"]
        
        is_followed = False
        if viewer_id:
            cur.execute("SELECT 1 FROM user_follows WHERE follower_id = %s AND following_id = %s", (viewer_id, target_id))
            is_followed = bool(cur.fetchone())
            
        cur.execute("SELECT * FROM services WHERE partner_id = %s AND status = 'APPROVED' ORDER BY created_at DESC", (target_id,))
        services = cur.fetchall()
        
        cur.execute("SELECT * FROM tiktok_feeds WHERE author_id = %s AND status = 'APPROVED' ORDER BY created_at DESC", (target_id,))
        videos = cur.fetchall()
        
        cur.execute("SELECT * FROM community_posts WHERE author_id = %s ORDER BY created_at DESC", (target_id,))
        posts = cur.fetchall()

        # Lấy danh sách Voucher của riêng đối tác này (Chỉ hiển thị mã đã duyệt và còn hạn)
        cur.execute("""
            SELECT * FROM vouchers 
            WHERE issuer_id = %s AND issuer_type = 'PARTNER' AND status = 'APPROVED' AND valid_until > NOW()
            ORDER BY created_at DESC
        """, (target_id,))
        vouchers = cur.fetchall()
        
        data = {
            "profile": user, 
            "is_followed": is_followed, 
            "services": services, 
            "videos": videos, 
            "posts": posts,
            "vouchers": vouchers,
            "stats": {
                "followers_count": user.get("followers_count", 0), 
                "services_count": len(services), 
                "videos_count": len(videos), 
                "posts_count": len(posts),
                "vouchers_count": len(vouchers)
            }
        }
        return {"status": "success", "data": data}
    finally: cur.close()

@app.patch("/user/profile", tags=["User"])
def update_user_profile(payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        new_email = payload.get("email")
        new_username = payload.get("username")
        
        # Bắt lỗi trùng lặp Email hoặc Username
        if new_email or new_username:
            cur.execute("""
                SELECT id FROM users 
                WHERE (email = %s OR username = %s) AND id != %s
            """, (new_email, new_username, current_user.id))
            if cur.fetchone():
                raise HTTPException(status_code=400, detail="Email hoặc Tên người dùng này đã được sử dụng!")

        updates, values = [], []
        for k, v in payload.items():
            # Đã gỡ 'email' khỏi danh sách cấm để cho phép User tự cập nhật
            if k not in ["id", "password_hash"]: 
                updates.append(f"{k} = %s")
                values.append(json.dumps(v) if isinstance(v, (dict, list)) else v)
                
        if not updates: return {"status": "success"}
        values.append(current_user.id)
        cur.execute(f"UPDATE users SET {', '.join(updates)} WHERE id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": updated}
    except HTTPException:
        raise
    except psycopg2.IntegrityError:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Dữ liệu bị trùng lặp với người dùng khác!")
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

# ==========================================
# 4. PARTNER BACKSTAGE (QUẢN LÝ RIÊNG)
# ==========================================
@app.get("/partner/my-services", tags=["Partner"])
def get_my_services(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM services WHERE partner_id = %s AND status != 'DELETED' ORDER BY created_at DESC", (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/partner/my-services/{service_id}", tags=["Partner"])
def update_my_service(service_id: str, payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Bộ lọc chỉ cho phép các cột thực tế của bảng services được cập nhật
        allowed_cols = {"service_name", "description", "price", "image_url", "video_url", "tags", "service_type"}
        updates, values = ["status = 'PENDING'"], []
        
        for k, v in payload.items():
            if k in allowed_cols and v is not None:
                if k == "tags":
                    # Ép kiểu cưỡng chế trực tiếp trong câu lệnh SQL sang jsonb để khớp với kiểu dữ liệu của Postgres
                    updates.append(f"{k} = %s::jsonb")
                    values.append(json.dumps(v))
                else:
                    updates.append(f"{k} = %s")
                    values.append(v)
                
        values.extend([service_id, current_user.id])
        cur.execute(f"UPDATE services SET {', '.join(updates)} WHERE id = %s AND partner_id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": updated}
    finally: cur.close()

@app.delete("/partner/my-services/{service_id}", tags=["Partner"])
def delete_my_service(service_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        cur.execute("UPDATE services SET status = 'PENDING_DELETE', updated_at = now() WHERE id = %s AND partner_id = %s RETURNING id", (service_id, current_user.id))
        if not cur.fetchone(): raise HTTPException(status_code=403, detail="Cấm!")
        conn.commit()
        return {"status": "success"}
    finally: cur.close()

@app.get("/partner/my-tiktok-feeds", tags=["Partner"])
def get_my_videos(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM tiktok_feeds WHERE author_id = %s AND status != 'DELETED' ORDER BY created_at DESC", (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/partner/my-tiktok-feeds/{video_id}", tags=["Partner"])
def update_my_video(video_id: str, payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Bộ lọc chỉ cho phép các cột thực tế của bảng tiktok_feeds được cập nhật
        allowed_cols = {"title", "content", "video_url", "price"}
        updates, values = ["status = 'PENDING'"], []
        
        for k, v in payload.items():
            if k in allowed_cols and v is not None:
                updates.append(f"{k} = %s")
                values.append(v)
                
        values.extend([video_id, current_user.id])
        cur.execute(f"UPDATE tiktok_feeds SET {', '.join(updates)} WHERE id = %s AND author_id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": updated}
    finally: cur.close()

@app.delete("/partner/my-tiktok-feeds/{video_id}", tags=["Partner"])
def delete_my_video(video_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        cur.execute("UPDATE tiktok_feeds SET status = 'PENDING_DELETE', updated_at = now() WHERE id = %s AND author_id = %s RETURNING id", (video_id, current_user.id))
        if not cur.fetchone(): raise HTTPException(status_code=403, detail="Cấm!")
        conn.commit()
        return {"status": "success"}
    finally: cur.close()

@app.get("/partner/bookings", tags=["Partner"])
def get_partner_bookings(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        query = """
            SELECT DISTINCT b.* FROM bookings_transactions b
            LEFT JOIN services s ON b.service_id = s.id
            LEFT JOIN tiktok_feeds v ON b.video_id = v.id
            WHERE s.partner_id = %s OR v.author_id = %s
            ORDER BY b.created_at DESC
        """
        cur.execute(query, (current_user.id, current_user.id))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
def complete_booking_escrow(booking_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM bookings_transactions WHERE id = %s", (booking_id,))
        booking = cur.fetchone()
        if not booking: raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
        if booking["payment_status"] != "PAID": raise HTTPException(status_code=400, detail="Chưa thanh toán!")
        if booking["service_status"] == "COMPLETED": raise HTTPException(status_code=400, detail="Đã xử lý!")

        cur.execute("SELECT status FROM appointments WHERE booking_id = %s", (booking_id,))
        appt = cur.fetchone()
        if appt and appt["status"] not in ["SERVED", "COMPLETED"]: raise HTTPException(status_code=400, detail="Khách chưa Check-in!")

        # ĐỒNG BỘ CÔNG THỨC TOÁN HỌC ESCROW BỌC THÉP
        original_total = float(booking["total_amount"])
        discount_amount = float(booking.get("voucher_discount_amount") or 0)
        funded_by = booking.get("discount_funded_by")
        
        revenue_base = original_total - discount_amount if funded_by == 'PARTNER' else original_total

        partner_rev = revenue_base * 0.70
        platform_fee = revenue_base * 0.20
        affiliate_rev = revenue_base * 0.10 if booking.get("affiliate_id") else 0
        if not booking.get("affiliate_id"): platform_fee += revenue_base * 0.10

        cur.execute("UPDATE bookings_transactions SET service_status = 'COMPLETED', partner_revenue = %s, platform_fee = %s, affiliate_revenue = %s WHERE id = %s", 
                    (partner_rev, platform_fee, affiliate_rev, booking_id))
        cur.execute("UPDATE appointments SET status = 'COMPLETED' WHERE booking_id = %s", (booking_id,))

        cur.execute("SELECT * FROM wallets WHERE user_id = %s", (current_user.id,))
        if cur.fetchone():
            cur.execute("UPDATE wallets SET balance = balance + %s, total_earned = total_earned + %s WHERE user_id = %s", (partner_rev, partner_rev, current_user.id))
        else:
            cur.execute("INSERT INTO wallets (user_id, balance, total_earned) VALUES (%s, %s, %s)", (current_user.id, partner_rev, partner_rev))
        
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=current_user.id, event_type="REVENUE_DISBURSED", reference_id=booking_id, sender_id=booking["user_id"])
        conn.commit()
        return {"status": "success", "message": "Hoàn tất!"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=400, detail=str(e))
    finally: cur.close()

@app.post("/partner/withdraw", tags=["Partner"])
def create_withdrawal_request(payload: schemas.WithdrawalRequest, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT balance FROM wallets WHERE user_id = %s", (current_user.id,))
        wlt = cur.fetchone()
        if not wlt or float(wlt["balance"]) < payload.amount: raise HTTPException(status_code=400, detail="Số dư không đủ!")
        if payload.amount < 50000: raise HTTPException(status_code=400, detail="Tối thiểu 50k")

        payout_info = json.dumps({"bank_name": payload.bank_name, "account_number": payload.account_number, "account_name": payload.account_name})
        cur.execute("INSERT INTO withdrawal_requests (user_id, amount, status, payout_info) VALUES (%s, %s, 'PENDING', %s)", (current_user.id, payload.amount, payout_info))
        cur.execute("UPDATE wallets SET balance = balance - %s WHERE user_id = %s", (payload.amount, current_user.id))
        
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=current_user.id, event_type="LEGACY", reference_id="", metadata={"category": "FINANCIAL", "title": "Yêu cầu rút tiền", "message": f"Yêu cầu rút tiền số tiền {payload.amount:,.0f}đ đang chờ hệ thống xử lý."})
        conn.commit()
        return {"status": "success", "message": "Đã gửi yêu cầu!"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.get("/partner/withdrawals", tags=["Partner"])
def get_my_withdrawals(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM withdrawal_requests WHERE user_id = %s ORDER BY created_at DESC", (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()
        
# ==========================================
# 5. COMMUNITY & TIKTOK FEEDS (QUẢN LÝ NỘI DUNG)
# ==========================================
@app.get("/community/posts", tags=["Community"])
def get_community_posts(limit: int = 50, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT p.*, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url, 'role', u.role) as author
            FROM community_posts p LEFT JOIN users u ON p.author_id = u.id
            ORDER BY p.created_at DESC LIMIT %s
        """, (limit,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.post("/community/posts", tags=["Community"])
def create_community_post(post: schemas.CommunityPostCreate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("INSERT INTO community_posts (author_id, content, image_url) VALUES (%s, %s, %s) RETURNING *", (current_user.id, post.content, post.image_url))
        data = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": data}
    finally: cur.close()

@app.get("/tiktok/feeds", tags=["TikTok Feeds"])
def get_tiktok_feeds(user_id: str = None, filter: str = None, limit: int = 50, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Hỗ trợ bộ lọc 'liked' để lấy đúng danh sách video người dùng đã thả tim
        if filter == "liked" and user_id:
            cur.execute("""
                SELECT v.*, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url, 'username', u.username, 'role', u.role) as author
                FROM tiktok_feed_likes l
                JOIN tiktok_feeds v ON l.video_id = v.id
                JOIN users u ON v.author_id = u.id
                WHERE l.user_id = %s AND v.status = 'APPROVED' 
                ORDER BY l.created_at DESC LIMIT %s
            """, (user_id, limit))
        else:
            cur.execute("""
                SELECT v.*, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url, 'username', u.username, 'role', u.role) as author
                FROM tiktok_feeds v JOIN users u ON v.author_id = u.id
                WHERE v.status = 'APPROVED' ORDER BY v.created_at DESC LIMIT %s
            """, (limit,))
        videos = cur.fetchall()
        
        if user_id and videos:
            v_ids = tuple([v["id"] for v in videos])
            cur.execute("SELECT video_id FROM tiktok_feed_likes WHERE user_id = %s AND video_id IN %s", (user_id, v_ids))
            likes = {r["video_id"] for r in cur.fetchall()}
            cur.execute("SELECT video_id FROM tiktok_feed_saves WHERE user_id = %s AND video_id IN %s", (user_id, v_ids))
            saves = {r["video_id"] for r in cur.fetchall()}
            for v in videos:
                v['is_liked'] = v['id'] in likes
                v['is_saved'] = v['id'] in saves
        return {"status": "success", "data": videos}
    finally: cur.close()

@app.post("/tiktok/feeds", tags=["TikTok Feeds"])
def create_tiktok_feed(payload: schemas.TikTokFeedCreate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        status = "APPROVED" if current_user.role in ["SUPER_ADMIN", "ADMIN"] else "PENDING"
        cur.execute("""INSERT INTO tiktok_feeds (author_id, title, content, video_url, price, status) 
                       VALUES (%s, %s, %s, %s, %s, %s) RETURNING *""",
                    (current_user.id, payload.title, payload.content, payload.video_url, payload.price, status))
        data = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": data}
    finally: cur.close()

 # ==========================================
# 6. AI ASSISTANT (TÁI CẤU TRÚC ĐA LUỒNG & LƯU TRỮ)
# ==========================================
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

@app.get("/ai/conversations", tags=["AI Assistant"])
def get_conversations(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Lấy danh sách các cuộc trò chuyện của User, sắp xếp mới nhất lên đầu"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT id, title, updated_at 
            FROM ai_conversations 
            WHERE user_id = %s 
            ORDER BY updated_at DESC
        """, (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.get("/ai/conversations/{conversation_id}/history", tags=["AI Assistant"])
def get_conversation_history(conversation_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Lấy lịch sử tin nhắn của một cuộc trò chuyện cụ thể"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT id FROM ai_conversations WHERE id = %s AND user_id = %s", (conversation_id, current_user.id))
        if not cur.fetchone():
            raise HTTPException(status_code=403, detail="Cuộc trò chuyện không tồn tại hoặc không có quyền truy cập.")
            
        cur.execute("""
            SELECT id, role, content, created_at 
            FROM ai_chat_history 
            WHERE conversation_id = %s 
            ORDER BY created_at ASC
        """, (conversation_id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.delete("/ai/conversations/{conversation_id}", tags=["AI Assistant"])
def delete_conversation(conversation_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Xóa một cuộc trò chuyện (CASCADE sẽ tự xóa tin nhắn)"""
    cur = conn.cursor()
    try:
        cur.execute("DELETE FROM ai_conversations WHERE id = %s AND user_id = %s RETURNING id", (conversation_id, current_user.id))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy cuộc trò chuyện.")
        conn.commit()
        return {"status": "success", "message": "Đã xóa cuộc trò chuyện."}
    finally: cur.close()

@app.post("/ai/chat", tags=["AI Assistant"])
def chat_with_llama(payload: schemas.AIChatRequest, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        conversation_id = getattr(payload, 'conversation_id', None)
        
        # 1. Quản lý Phiên chat (Conversation)
        if not conversation_id:
            # Lấy 30 ký tự đầu của câu hỏi làm Title
            first_msg = next((m.content for m in payload.messages if m.role == 'user'), "Trò chuyện mới")
            title = (first_msg[:30] + '...') if len(first_msg) > 30 else first_msg

            cur.execute("INSERT INTO ai_conversations (user_id, title) VALUES (%s, %s) RETURNING id", (current_user.id, title))
            conversation_id = str(cur.fetchone()['id'])
        else:
            cur.execute("SELECT id FROM ai_conversations WHERE id = %s AND user_id = %s", (conversation_id, current_user.id))
            if not cur.fetchone():
                raise HTTPException(status_code=403, detail="Cấm truy cập cuộc trò chuyện này!")
            cur.execute("UPDATE ai_conversations SET updated_at = CURRENT_TIMESTAMP WHERE id = %s", (conversation_id,))

        # 2. Xử lý Logic AI LLM (Groq)
        messages = [{"role": "system", "content": "Bạn là Trợ lý AI Health. Dùng Markdown. Trả lời trực tiếp, rõ ràng."}]
        for msg in payload.messages:
            messages.append({"role": "assistant" if msg.role == "bot" else "user", "content": msg.content})
        
        chat_completion = groq_client.chat.completions.create(
            messages=messages, 
            model="llama-3.1-8b-instant", 
            temperature=0.6, 
            max_tokens=1024
        )
        bot_reply = chat_completion.choices[0].message.content

        # 3. Lưu cặp tin nhắn MỚI NHẤT vào Database để tránh lặp dữ liệu
        last_user_msg = payload.messages[-1].content if payload.messages else ""
        if last_user_msg:
            cur.execute(
                "INSERT INTO ai_chat_history (conversation_id, user_id, role, content) VALUES (%s, %s, 'user', %s)",
                (conversation_id, current_user.id, last_user_msg)
            )
        cur.execute(
            "INSERT INTO ai_chat_history (conversation_id, user_id, role, content) VALUES (%s, %s, 'assistant', %s)",
            (conversation_id, current_user.id, bot_reply)
        )
        conn.commit()

        return {
            "status": "success", 
            "data": {
                "conversation_id": conversation_id,
                "reply": bot_reply
            }
        }
    except HTTPException:
        raise
    except Exception as e: 
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: 
        cur.close()

# ==========================================
# 7. QUẢN TRỊ KIỂM DUYỆT (MODERATION)
# ==========================================
@app.get("/moderation/queue", tags=["Moderation"])
def get_moderation_queue(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        if current_user.role not in ["MODERATOR", "SUPER_ADMIN"]: raise HTTPException(status_code=403, detail="Cấm!")
        
        cur.execute("""
            SELECT s.*, 'service' as type, s.service_name as title, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url) as author
            FROM services s LEFT JOIN users u ON s.partner_id = u.id WHERE s.status::text IN ('PENDING', 'PENDING_DELETE', 'PENDING_UPDATE')
        """)
        s_data = cur.fetchall()
        
        cur.execute("""
            SELECT v.*, 'video' as type, v.title as title, v.content as description, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url) as author
            FROM tiktok_feeds v LEFT JOIN users u ON v.author_id = u.id WHERE v.status::text IN ('PENDING', 'PENDING_DELETE', 'PENDING_UPDATE')
        """)
        v_data = cur.fetchall()

        cur.execute("""
            SELECT vc.*, 'voucher' as type, vc.code as title, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url) as author
            FROM vouchers vc LEFT JOIN users u ON vc.issuer_id = u.id WHERE vc.status::text IN ('PENDING')
        """)
        vc_data = cur.fetchall()
        
        combined = s_data + v_data + vc_data
        combined.sort(key=lambda x: str(x.get("updated_at") or x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined}
    finally: cur.close()

@app.patch("/moderation/action/{item_type}/{item_id}", tags=["Moderation"])
def moderate_item(item_type: str, item_id: str, payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        action = payload.get("action")
        status = "DELETED" if action == "DELETED" else action
        
        if item_type == "service":
            table = "services"
        elif item_type == "video":
            table = "tiktok_feeds"
        elif item_type == "voucher":
            table = "vouchers"
        else:
            raise HTTPException(status_code=400, detail="Loại mục kiểm duyệt không hợp lệ")
        
        cur.execute(f"UPDATE {table} SET status = %s, moderation_note = %s, moderated_by = %s, updated_at = now() WHERE id = %s", 
                    (status, payload.get("note", ""), current_user.id, item_id))
        conn.commit()
        return {"status": "success", "message": "Xử lý thành công"}
    finally: cur.close()

@app.get("/moderation/history", tags=["Moderation"])
def get_moderation_history(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT s.*, 'service' as type, s.service_name as title, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url) as author
            FROM services s LEFT JOIN users u ON s.partner_id = u.id WHERE s.status::text IN ('APPROVED', 'REJECTED', 'DELETED') AND (s.moderated_by = %s OR s.moderated_by IS NULL)
        """, (current_user.id,))
        s_data = cur.fetchall()
        
        cur.execute("""
            SELECT v.*, 'video' as type, v.title as title, v.content as description, json_build_object('id', u.id, 'full_name', u.full_name, 'avatar_url', u.avatar_url) as author
            FROM tiktok_feeds v LEFT JOIN users u ON v.author_id = u.id WHERE v.status::text IN ('APPROVED', 'REJECTED', 'DELETED') AND (v.moderated_by = %s OR v.moderated_by IS NULL)
        """, (current_user.id,))
        v_data = cur.fetchall()
        
        combined = s_data + v_data
        combined.sort(key=lambda x: str(x.get("updated_at") or x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined[:50]}
    finally: cur.close()

@app.get("/moderation/stats", tags=["Moderation"])
def get_moderation_stats(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT count(*) FROM services WHERE status IN ('PENDING', 'PENDING_DELETE', 'PENDING_UPDATE')")
        p_svc = cur.fetchone()["count"]
        cur.execute("SELECT count(*) FROM tiktok_feeds WHERE status IN ('PENDING', 'PENDING_DELETE', 'PENDING_UPDATE')")
        p_vid = cur.fetchone()["count"]
        
        cur.execute("SELECT status, updated_at, created_at FROM services WHERE moderated_by = %s OR moderated_by IS NULL", (current_user.id,))
        s_done = cur.fetchall()
        cur.execute("SELECT status, updated_at, created_at FROM tiktok_feeds WHERE moderated_by = %s OR moderated_by IS NULL", (current_user.id,))
        v_done = cur.fetchall()
        
        my_done = [i for i in s_done + v_done if i.get("status") in ("APPROVED", "REJECTED", "DELETED")]
        
        approved = sum(1 for i in my_done if i.get("status") == "APPROVED")
        rejected = sum(1 for i in my_done if i.get("status") in ["REJECTED", "DELETED"])
        
        from datetime import datetime, timedelta
        daily_stats = { (datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d'): {"date": (datetime.now() - timedelta(days=i)).strftime('%d/%m'), "Duyệt": 0, "Từ chối": 0} for i in range(6, -1, -1)}
            
        for item in my_done:
            raw_date = str(item.get("updated_at") or item.get("created_at") or "")[:10]
            if raw_date in daily_stats:
                if item.get("status") == "APPROVED": daily_stats[raw_date]["Duyệt"] += 1
                else: daily_stats[raw_date]["Từ chối"] += 1
        
        return {"status": "success", "data": {"pending_total": p_svc + p_vid, "total_processed": len(my_done), "approved_count": approved, "rejected_count": rejected, "chart_data": list(daily_stats.values())}}
    finally: cur.close()

# ==========================================
# 8. CREATOR WORKSPACE
# ==========================================
@app.get("/creator/stats", tags=["Creator"])
def get_creator_stats(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT id, likes_count, status FROM tiktok_feeds WHERE author_id = %s", (current_user.id,))
        videos = cur.fetchall()
        cur.execute("SELECT id FROM community_posts WHERE author_id = %s", (current_user.id,))
        posts = cur.fetchall()
        
        total_likes = sum(v.get("likes_count") or 0 for v in videos)
        approved = sum(1 for v in videos if v.get("status") == "APPROVED")
        approval_rate = round((approved / len(videos)) * 100) if videos else 0

        return {"status": "success", "data": {"total_videos": len(videos), "total_posts": len(posts), "total_likes": total_likes, "approval_rate": approval_rate}}
    finally: cur.close()

@app.get("/creator/content", tags=["Creator"])
def get_creator_content(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM tiktok_feeds WHERE author_id = %s ORDER BY created_at DESC", (current_user.id,))
        videos = cur.fetchall()
        cur.execute("SELECT * FROM community_posts WHERE author_id = %s ORDER BY created_at DESC", (current_user.id,))
        posts = cur.fetchall()
        return {"status": "success", "data": {"videos": videos, "community_posts": posts}}
    finally: cur.close()

# ==========================================
# 9. QUẢN TRỊ VIÊN CẤP CAO (SUPER ADMIN)
# ==========================================
@app.get("/admin/profile-stats", tags=["Admin"])
def get_admin_profile_stats(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT role, followers_count FROM users WHERE id = %s", (current_user.id,))
        u = cur.fetchone()
        if u.get("role") != "SUPER_ADMIN": raise HTTPException(status_code=403, detail="Cấm!")
        cur.execute("SELECT count(*) FROM services WHERE status = 'APPROVED'")
        active = cur.fetchone()["count"]
        return {"status": "success", "data": {"followers_count": u.get("followers_count") or 0, "active_services": active, "system_stability": 99.9}}
    finally: cur.close()
        
@app.get("/admin/my-content", tags=["Admin"])
def get_admin_content(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM tiktok_feeds WHERE author_id = %s ORDER BY created_at DESC", (current_user.id,))
        videos = cur.fetchall()
        cur.execute("SELECT * FROM community_posts WHERE author_id = %s ORDER BY created_at DESC", (current_user.id,))
        posts = cur.fetchall()
        return {"status": "success", "data": {"videos": videos, "community_posts": posts}}
    finally: cur.close()

@app.get("/admin/dashboard-stats", tags=["Admin"])
def get_admin_dashboard_stats(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # 1. Tổng GMV (Dòng tiền đã thanh toán)
        cur.execute("SELECT COALESCE(SUM(total_amount), 0) FROM bookings_transactions WHERE payment_status = 'PAID'")
        gmv = cur.fetchone()["coalesce"]

        # 2. Doanh thu nền tảng (Platform Revenue)
        cur.execute("SELECT COALESCE(SUM(platform_fee), 0) FROM bookings_transactions WHERE service_status = 'COMPLETED'")
        platform_revenue = cur.fetchone()["coalesce"]

        # 3. Quỹ tạm giữ Escrow (Khách đã trả tiền nhưng chưa Check-in)
        cur.execute("SELECT COALESCE(SUM(total_amount), 0) FROM bookings_transactions WHERE payment_status = 'PAID' AND service_status = 'PENDING'")
        escrow_holding = cur.fetchone()["coalesce"]

        # 4. Yêu cầu rút tiền cần duyệt
        cur.execute("SELECT count(*) FROM withdrawal_requests WHERE status = 'PENDING'")
        pending_withdrawals = cur.fetchone()["count"]

        # 5. Phân bổ User và Partner
        cur.execute("SELECT count(*) FROM users WHERE role = 'USER'")
        total_users = cur.fetchone()["count"]
        
        cur.execute("SELECT count(*) FROM users WHERE role != 'USER'")
        total_partners = cur.fetchone()["count"]

        # 6. Biểu đồ 7 ngày qua (Dùng hàm Sinh ngày của Postgres để biểu đồ không bị đứt quãng)
        cur.execute("""
            WITH last_7_days AS (
                SELECT generate_series(CURRENT_DATE - INTERVAL '6 days', CURRENT_DATE, '1 day')::date AS date
            )
            SELECT 
                TO_CHAR(d.date, 'DD/MM') as date,
                COALESCE(SUM(b.total_amount) FILTER (WHERE b.payment_status = 'PAID'), 0) as "GMV",
                COALESCE(SUM(b.platform_fee) FILTER (WHERE b.service_status = 'COMPLETED'), 0) as "Doanh thu"
            FROM last_7_days d
            LEFT JOIN bookings_transactions b ON DATE(b.created_at) = d.date
            GROUP BY d.date
            ORDER BY d.date ASC
        """)
        chart_data = cur.fetchall()

        return {
            "status": "success", 
            "data": {
                "gmv": float(gmv),
                "platform_revenue": float(platform_revenue),
                "escrow_holding": float(escrow_holding),
                "pending_withdrawals": pending_withdrawals,
                "total_users": total_users,
                "total_partners": total_partners,
                "chart_data": chart_data
            }
        }
    finally: 
        cur.close()

@app.get("/admin/withdrawals", tags=["Admin"])
def get_withdrawals(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT w.*, json_build_object('full_name', u.full_name, 'email', u.email, 'role', u.role) as users
            FROM withdrawal_requests w JOIN users u ON w.user_id = u.id ORDER BY w.created_at DESC
        """)
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/admin/withdrawals/{w_id}", tags=["Admin"])
def process_withdrawal(w_id: str, payload: schemas.WithdrawalUpdate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM withdrawal_requests WHERE id = %s", (w_id,))
        req = cur.fetchone()
        if not req: raise HTTPException(status_code=404, detail="Không tìm thấy")

        if payload.status == "REJECTED" and req["status"] == "PENDING":
            cur.execute("UPDATE wallets SET balance = balance + %s WHERE user_id = %s", (req["amount"], req["user_id"]))

        cur.execute("UPDATE withdrawal_requests SET status = %s, admin_note = %s, processed_by = %s, updated_at = now() WHERE id = %s",
                    (payload.status, payload.admin_note or "", current_user.id, w_id))
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=req["user_id"], event_type="LEGACY", reference_id=w_id, metadata={"category": "FINANCIAL", "title": f"Lệnh rút tiền {payload.status}", "message": f"Yêu cầu rút tiền của bạn đã được cập nhật trạng thái sang {payload.status}. Ghi chú: {payload.admin_note or ''}"}, sender_id=current_user.id)
        conn.commit()
        return {"status": "success", "message": f"Đã xử lý: {payload.status}"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.post("/vouchers/{voucher_code}/claim", tags=["Vouchers"])
def claim_voucher(voucher_code: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT id, total_quantity, used_quantity, valid_until, status FROM vouchers WHERE code = %s", (voucher_code,))
        voucher = cur.fetchone()
        
        if not voucher or voucher['status'] != 'APPROVED': 
            raise HTTPException(status_code=400, detail="Mã không tồn tại hoặc chưa duyệt.")
        if voucher['used_quantity'] >= voucher['total_quantity']: 
            raise HTTPException(status_code=400, detail="Mã này đã hết lượt dùng.")
        if voucher['valid_until'] < datetime.now(): 
            raise HTTPException(status_code=400, detail="Mã này đã hết hạn.")
            
        cur.execute("INSERT INTO user_vouchers (user_id, voucher_id) VALUES (%s, %s) RETURNING id", (current_user.id, voucher['id']))
        conn.commit()
        return {"status": "success", "message": "Đã lưu Voucher vào ví!"}
        
    except psycopg2.IntegrityError:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Bạn đã có mã này trong ví rồi!")
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.get("/admin/partners", tags=["Admin"])
def get_admin_partners(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        if current_user.role != "SUPER_ADMIN": raise HTTPException(status_code=403, detail="Cấm!")
        cur.execute("SELECT id, full_name, email, avatar_url, created_at, role FROM users WHERE role IN ('PARTNER_ADMIN', 'CREATOR', 'MODERATOR') ORDER BY created_at DESC")
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

# ==========================================
# 10. HỆ THỐNG BÌNH LUẬN & TƯƠNG TÁC
# ==========================================
@app.get("/tiktok/feeds/{video_id}/comments", tags=["Comments"])
def get_tiktok_comments(video_id: str, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT c.*, json_build_object('id', u.id, 'full_name', u.full_name, 'username', u.username, 'avatar_url', u.avatar_url, 'role', u.role) as users
            FROM tiktok_feed_comments c JOIN users u ON c.user_id = u.id WHERE c.video_id = %s ORDER BY c.created_at ASC
        """, (video_id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.post("/tiktok/feeds/{video_id}/comments", tags=["Comments"])
def create_tiktok_comment(video_id: str, payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        content = payload.get("content", "").strip()
        if not content: raise HTTPException(status_code=400, detail="Trống")
        parent_id = payload.get("parent_id")
        
        cur.execute("INSERT INTO tiktok_feed_comments (video_id, user_id, content, parent_id) VALUES (%s, %s, %s, %s) RETURNING *", 
                    (video_id, current_user.id, content, parent_id))
        data = cur.fetchone()
        cur.execute("UPDATE tiktok_feeds SET comments_count = comments_count + 1 WHERE id = %s", (video_id,))
        conn.commit()
        return {"status": "success", "data": data}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.delete("/tiktok/feeds/comments/{comment_id}", tags=["Comments"])
def delete_tiktok_comment(comment_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("DELETE FROM tiktok_feed_comments WHERE id = %s RETURNING video_id", (comment_id,))
        row = cur.fetchone()
        if row:
            cur.execute("UPDATE tiktok_feeds SET comments_count = GREATEST(0, comments_count - 1) WHERE id = %s", (row["video_id"],))
        conn.commit()
        return {"status": "success"}
    finally: cur.close()

@app.post("/tiktok/feeds/{video_id}/{action}", tags=["TikTok Feeds"])
def toggle_tiktok_interaction(video_id: str, action: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        if action == "share":
            cur.execute("INSERT INTO tiktok_feed_shares (video_id, user_id) VALUES (%s, %s)", (video_id, current_user.id))
            cur.execute("UPDATE tiktok_feeds SET shares_count = shares_count + 1 WHERE id = %s", (video_id,))
            conn.commit()
            return {"status": "success", "action": "shared"}

        table = "tiktok_feed_likes" if action == "like" else "tiktok_feed_saves"
        count_col = "likes_count" if action == "like" else "saves_count"
        
        cur.execute(f"SELECT 1 FROM {table} WHERE video_id = %s AND user_id = %s", (video_id, current_user.id))
        if cur.fetchone():
            cur.execute(f"DELETE FROM {table} WHERE video_id = %s AND user_id = %s", (video_id, current_user.id))
            cur.execute(f"UPDATE tiktok_feeds SET {count_col} = GREATEST(0, {count_col} - 1) WHERE id = %s", (video_id,))
            conn.commit()
            return {"status": "success", "action": f"un{action}d"}
        else:
            cur.execute(f"INSERT INTO {table} (video_id, user_id) VALUES (%s, %s)", (video_id, current_user.id))
            cur.execute(f"UPDATE tiktok_feeds SET {count_col} = {count_col} + 1 WHERE id = %s", (video_id,))
            conn.commit()
            return {"status": "success", "action": f"{action}d"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()


 

@app.get("/affiliates/validate", tags=["Affiliates"])
def validate_affiliate(code: str, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Tạm thời query theo id hoặc username để xác thực Affiliate
        cur.execute("SELECT id, full_name, avatar_url FROM users WHERE id = %s OR username = %s LIMIT 1", (code, code))
        affiliate = cur.fetchone()
        if not affiliate: 
            raise HTTPException(status_code=404, detail="Mã giới thiệu không tồn tại")
        return {"status": "success", "data": affiliate}
    finally:
        cur.close()

@app.get("/appointments/me", tags=["Scheduling"])
def get_my_appointments(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Bổ sung tự động tạo cột nếu chưa có để tránh lỗi
        cur.execute("ALTER TABLE appointments ADD COLUMN IF NOT EXISTS applied_user_voucher_id UUID")
        conn.commit()
        
        query = """
            SELECT a.*, 
                   json_build_object('service_name', s.service_name, 'price', s.price) as services,
                   json_build_object('full_name', u.full_name, 'phone', u.phone) as users,
                   json_build_object('username', pu.username, 'physical_address', pu.physical_address) as partner,
                   json_build_object('issuer_type', v.issuer_type, 'discount_type', v.discount_type, 'discount_value', v.discount_value, 'max_discount_amount', v.max_discount_amount) as vouchers
            FROM appointments a
            LEFT JOIN services s ON a.service_id = s.id
            LEFT JOIN users u ON a.user_id = u.id
            LEFT JOIN users pu ON a.partner_id = pu.id
            LEFT JOIN user_vouchers uv ON a.applied_user_voucher_id = uv.id
            LEFT JOIN vouchers v ON uv.voucher_id = v.id
            WHERE a.partner_id = %s OR a.user_id = %s
            ORDER BY a.created_at DESC
        """
        cur.execute(query, (current_user.id, current_user.id))
        return {"status": "success", "data": cur.fetchall()}
    finally:
        cur.close()

@app.post("/appointments/request", tags=["Scheduling"])
def request_appointment(payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        service_id = payload.get("service_id")
        partner_id = payload.get("partner_id")
        video_id = payload.get("video_id")
        
        # Tiền xử lý chuỗi rỗng để tránh lỗi UUID Format của PostgreSQL
        if not video_id or video_id == "": video_id = None
        if not service_id or service_id == "": service_id = None

        # --- BỌC THÉP TỰ ĐỘNG CHỮA LỖI (SELF-HEALING) ---
        # 1. Kiểm tra video_id xem có thực sự nằm trong bảng tiktok_feeds không
        if video_id:
            cur.execute("SELECT id FROM tiktok_feeds WHERE id = %s", (video_id,))
            if not cur.fetchone():
                # Không tìm thấy trong tiktok_feeds -> Quét xuống bảng services
                cur.execute("SELECT id FROM services WHERE id = %s", (video_id,))
                if cur.fetchone():
                    service_id = video_id  # Cứu dữ liệu: Đẩy ID này sang đúng cột service_id
                video_id = None  # Xóa sạch video_id rác để tránh lỗi Foreign Key
                
        # 2. Quét dọn luôn cột service_id để đảm bảo an toàn tuyệt đối
        if service_id:
            cur.execute("SELECT id FROM services WHERE id = %s", (service_id,))
            if not cur.fetchone():
                service_id = None

        total_amount = payload.get("total_amount", 0)
        customer_name = payload.get("customer_name", "")
        customer_phone = payload.get("customer_phone", "")
        note = payload.get("note", "")
        voucher_code = payload.get("voucher_code")

        cur.execute("ALTER TABLE appointments ADD COLUMN IF NOT EXISTS applied_user_voucher_id UUID")
        
        applied_uv_id = None
        if voucher_code:
            cur.execute("""
                SELECT uv.id FROM user_vouchers uv 
                JOIN vouchers v ON uv.voucher_id = v.id 
                WHERE uv.user_id = %s AND uv.status = 'UNUSED' AND v.code = %s AND v.valid_until > NOW() AND v.used_quantity < v.total_quantity
            """, (current_user.id, voucher_code))
            uv = cur.fetchone()
            if uv:
                applied_uv_id = uv["id"]
                cur.execute("UPDATE user_vouchers SET status = 'LOCKED', locked_until = NULL WHERE id = %s", (applied_uv_id,))
            else:
                # BỌC THÉP & TỰ CHỮA LỖI (SELF-HEALING)
                # Tự động Claim mã vào ví nếu frontend chưa Claim, hoặc chặn lại nếu mã sai/đã dùng
                cur.execute("SELECT id FROM vouchers WHERE code = %s AND status = 'APPROVED' AND valid_until > NOW() AND used_quantity < total_quantity", (voucher_code,))
                public_v = cur.fetchone()
                if public_v:
                    try:
                        cur.execute("INSERT INTO user_vouchers (user_id, voucher_id, status) VALUES (%s, %s, 'LOCKED') RETURNING id", (current_user.id, public_v["id"]))
                        applied_uv_id = cur.fetchone()["id"]
                    except psycopg2.IntegrityError:
                        raise HTTPException(status_code=400, detail="Mã giảm giá đã được sử dụng hoặc đang bị khóa cho một lịch hẹn khác!")
                else:
                    raise HTTPException(status_code=400, detail="Mã giảm giá không hợp lệ, đã hết hạn hoặc hết lượt!")

        cur.execute("""
            INSERT INTO appointments 
            (user_id, partner_id, service_id, video_id, total_amount, customer_name, customer_phone, note, status, applied_user_voucher_id, created_at) 
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 'WAITING_PARTNER', %s, NOW()) 
            RETURNING *
        """, (current_user.id, partner_id, service_id, video_id, total_amount, customer_name, customer_phone, note, applied_uv_id))
        
        new_appt = cur.fetchone()
        conn.commit() # BỌC THÉP: Chốt hạ giao dịch Booking thành công vào DB trước để bảo toàn dữ liệu
        
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=partner_id, event_type="APPOINTMENT_REQUESTED", reference_id=str(new_appt['id']), sender_id=current_user.id)
        
        try: 
            conn.commit() # Thử chốt giao dịch của Notification Layer
        except Exception: 
            conn.rollback() # Tự chữa lành: Xóa trạng thái InFailedSqlTransaction để trả kết nối sạch về Pooler
        return {"status": "success", "message": "Yêu cầu đã được gửi! Vui lòng theo dõi tại tab 'Lịch hẹn'.", "data": new_appt}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        cur.close()

@app.patch("/appointments/{appointment_id}/respond", tags=["Scheduling"])
def respond_appointment(appointment_id: str, payload: schemas.PartnerResponse, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if not appt: raise HTTPException(status_code=404, detail="Không tìm thấy")
        if appt["partner_id"] != current_user.id: raise HTTPException(status_code=403, detail="Cấm!")

        updates, values = [], []
        if payload.action == "ACCEPT":
            if not payload.start_time or not payload.end_time: raise HTTPException(status_code=400, detail="Thiếu giờ")
            updates.extend(["status = 'PENDING_PAYMENT'", "start_time = %s", "end_time = %s", "payment_deadline = %s"])
            values.extend([payload.start_time, payload.end_time, datetime.fromtimestamp(time.time() + 7200)])
        else:
            updates.extend(["status = 'CANCELLED'", "rejection_reason = %s"])
            values.append(payload.reason)
            if appt.get("applied_user_voucher_id"):
                cur.execute("UPDATE user_vouchers SET status = 'UNUSED', locked_until = NULL WHERE id = %s", (appt["applied_user_voucher_id"],))
            
        values.append(appointment_id)
        cur.execute(f"UPDATE appointments SET {', '.join(updates)} WHERE id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        
        from notification_service import NotificationService
        if payload.action == "ACCEPT":
            NotificationService.dispatch_event(conn, user_id=appt["user_id"], event_type="APPOINTMENT_ACCEPTED", reference_id=appointment_id, sender_id=current_user.id)
        else:
            NotificationService.dispatch_event(conn, user_id=appt["user_id"], event_type="LEGACY", reference_id=appointment_id, metadata={"category": "BOOKING", "title": "Cập nhật Lịch hẹn", "message": f"Cơ sở đã từ chối. Lý do: {payload.reason}"}, sender_id=current_user.id)
        
        conn.commit()
        return jsonable_encoder({"status": "success", "data": updated})
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.get("/appointments/{appointment_id}/preview", tags=["Scheduling"])
def preview_appointment_payment(appointment_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """API giả lập thanh toán: Trả về số tiền tạm tính và mã tự động áp dụng để hiển thị Pop-up cho khách"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if not appt: raise HTTPException(status_code=404, detail="Không tìm thấy lịch hẹn")
        if appt["status"] != "PENDING_PAYMENT": raise HTTPException(status_code=400, detail="Không ở trạng thái chờ thanh toán!")
        
        original_amount = 0.0
        if appt.get("service_id"):
            cur.execute("SELECT price FROM services WHERE id = %s", (appt["service_id"],))
            s = cur.fetchone()
            if s: original_amount = float(s["price"])
        elif appt.get("video_id"):
            cur.execute("SELECT price FROM tiktok_feeds WHERE id = %s", (appt["video_id"],))
            v = cur.fetchone()
            if v: original_amount = float(v["price"])
            
        if original_amount == 0.0:
            original_amount = float(appt.get("total_amount", 0))
            
        partner_id = appt.get("partner_id")
        
        # Sử dụng đúng mã Voucher đã bị khóa từ lúc Request
        applied_uv_id = appt.get("applied_user_voucher_id")
        best_voucher = None
        max_discount = 0.0
        
        if applied_uv_id:
            cur.execute("""
                SELECT uv.id as user_voucher_id, v.id as voucher_id, v.code, v.issuer_type, v.discount_type, 
                       v.discount_value, v.max_discount_amount
                FROM user_vouchers uv JOIN vouchers v ON uv.voucher_id = v.id
                WHERE uv.id = %s
            """, (applied_uv_id,))
            best_voucher = cur.fetchone()
            
            if best_voucher:
                discount = float(best_voucher["discount_value"])
                if best_voucher["discount_type"] == 'PERCENTAGE':
                    discount = (discount / 100) * original_amount
                    if best_voucher["max_discount_amount"] and discount > float(best_voucher["max_discount_amount"]):
                        discount = float(best_voucher["max_discount_amount"])
                max_discount = discount
                
        # --- BỌC THÉP VOUCHER STATE PERSISTENCE ---
        # Đã đồng bộ: total_amount lưu giá gốc từ Booking.
        db_total_amount = float(appt.get("total_amount", 0))
        if db_total_amount > 0:
            # Tự động chữa lỗi (Self-Healing) cho các app cũ từng gửi nhầm giá đã giảm
            if original_amount > 0 and db_total_amount <= (original_amount - max_discount):
                original_amount = db_total_amount + max_discount
            else:
                original_amount = db_total_amount
            
        final_amount = original_amount - max_discount
            
        if final_amount < 10000: final_amount = 10000 
            
        return {
            "status": "success", 
            "data": {
                "original_amount": original_amount,
                "discount_amount": max_discount,
                "final_amount": final_amount,
                "applied_voucher_code": best_voucher["code"] if best_voucher else None,
                "discount_funded_by": best_voucher["issuer_type"] if best_voucher else None
            }
        }
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.post("/appointments/{appointment_id}/pay", tags=["Scheduling"])
def create_appointment_payment(appointment_id: str, request: Request, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if appt["status"] != "PENDING_PAYMENT": raise HTTPException(status_code=400, detail="Không ở trạng thái chờ thanh toán!")
        
        original_amount = 0.0
        if appt.get("service_id"):
            cur.execute("SELECT price FROM services WHERE id = %s", (appt["service_id"],))
            s = cur.fetchone()
            if s: original_amount = float(s["price"])
        elif appt.get("video_id"):
            cur.execute("SELECT price FROM tiktok_feeds WHERE id = %s", (appt["video_id"],))
            v = cur.fetchone()
            if v: original_amount = float(v["price"])
            
        if original_amount == 0.0:
            original_amount = float(appt.get("total_amount", 0))
            
        partner_id = appt.get("partner_id")
        
        # Sử dụng mã Voucher đã khóa
        applied_uv_id = appt.get("applied_user_voucher_id")
        best_voucher = None
        max_discount = 0.0
        
        if applied_uv_id:
            cur.execute("""
                SELECT uv.id as user_voucher_id, v.id as voucher_id, v.issuer_type, v.discount_type, 
                       v.discount_value, v.max_discount_amount
                FROM user_vouchers uv JOIN vouchers v ON uv.voucher_id = v.id
                WHERE uv.id = %s
            """, (applied_uv_id,))
            best_voucher = cur.fetchone()
            
            if best_voucher:
                discount = float(best_voucher["discount_value"])
                if best_voucher["discount_type"] == 'PERCENTAGE':
                    discount = (discount / 100) * original_amount
                    if best_voucher["max_discount_amount"] and discount > float(best_voucher["max_discount_amount"]):
                        discount = float(best_voucher["max_discount_amount"])
                max_discount = discount
                
        # --- BỌC THÉP VOUCHER STATE PERSISTENCE ---
        # Đã đồng bộ: total_amount lưu giá gốc từ Booking để đảm bảo Payment chính xác.
        db_total_amount = float(appt.get("total_amount", 0))
        if db_total_amount > 0:
            # Tự động chữa lỗi (Self-Healing) cho các app cũ từng gửi nhầm giá đã giảm
            if original_amount > 0 and db_total_amount <= (original_amount - max_discount):
                original_amount = db_total_amount + max_discount
            else:
                original_amount = db_total_amount
            
        final_amount = original_amount - max_discount
            
        if final_amount < 10000: final_amount = 10000 # Ràng buộc PayOS tối thiểu 10k
            
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        
        applied_v_id = best_voucher["voucher_id"] if best_voucher else None
        funded_by = best_voucher["issuer_type"] if best_voucher else None
        
        cur.execute("""INSERT INTO bookings_transactions 
                       (user_id, service_id, video_id, total_amount, payment_status, service_status, order_code, 
                        customer_name, customer_phone, note, applied_voucher_id, voucher_discount_amount, discount_funded_by, final_paid_amount)
                       VALUES (%s, %s, %s, %s, 'UNPAID', 'PENDING', %s, %s, %s, %s, %s, %s, %s, %s) RETURNING id""",
                    (current_user.id, appt.get("service_id"), appt.get("video_id"), original_amount, order_code, 
                     appt.get("customer_name"), appt.get("customer_phone"), appt.get("note"), 
                     applied_v_id, max_discount, funded_by, final_amount))
        booking_id = cur.fetchone()["id"]
        
        cur.execute("UPDATE appointments SET booking_id = %s WHERE id = %s", (booking_id, appointment_id))
        # Không cần khóa thêm 10 phút vì mã đã bị khóa vô thời hạn từ lúc gửi yêu cầu
            
        conn.commit()

        frontend_origin = request.headers.get("origin", "https://ai-health-share-frontend.vercel.app").rstrip('/')
        target_url = f"{frontend_origin}/features/calendar" if "localhost" in frontend_origin or "127.0.0.1" in frontend_origin else "https://ai-health-share-frontend.vercel.app/features/calendar"

        payment_data = PaymentData(orderCode=order_code, amount=int(final_amount), description=f"Lich {order_code}", returnUrl=target_url, cancelUrl=target_url)
        payment_link = payos_client.createPaymentLink(paymentData=payment_data)
        
        return {
            "status": "success", 
            "checkout_url": payment_link.checkoutUrl,
            "in_app_data": {
                "qr_code": getattr(payment_link, 'qrCode', None),
                "account_number": getattr(payment_link, 'accountNumber', None),
                "account_name": getattr(payment_link, 'accountName', None),
                "amount": getattr(payment_link, 'amount', None),
                "description": getattr(payment_link, 'description', None),
                "order_code": order_code
            }
        }
    except Exception as e: 
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.get("/appointments/payment/verify", tags=["Scheduling"])
def verify_appointment_payment(orderCode: int, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        payment_info = payos_client.getPaymentLinkInformation(orderCode)
        if payment_info.status != "PAID": return {"status": "pending", "message": "Chưa hoàn tất"}

        cur.execute("SELECT * FROM bookings_transactions WHERE order_code = %s", (orderCode,))
        booking = cur.fetchone()
        if not booking: raise HTTPException(status_code=404, detail="Không tìm thấy")
        if booking["payment_status"] == "PAID": return {"status": "success", "message": "Đã xác nhận"}

        cur.execute("UPDATE bookings_transactions SET payment_status = 'PAID' WHERE id = %s", (booking["id"],))
        
        # LOGIC VOUCHER: Đổi sang USED và tăng biến đếm
        if booking.get("applied_voucher_id"):
            cur.execute("UPDATE user_vouchers SET status = 'USED' WHERE user_id = %s AND voucher_id = %s AND status = 'LOCKED'", (booking["user_id"], booking["applied_voucher_id"]))
            cur.execute("UPDATE vouchers SET used_quantity = used_quantity + 1 WHERE id = %s", (booking["applied_voucher_id"],))

        cur.execute("UPDATE appointments SET status = 'CONFIRMED' WHERE booking_id = %s RETURNING partner_id, customer_name, user_id", (booking["id"],))
        appt = cur.fetchone()
        
        if appt:
            from notification_service import NotificationService
            NotificationService.dispatch_event(conn, user_id=appt["partner_id"], event_type="LEGACY", reference_id=str(booking["id"]), metadata={"category": "ESCROW", "title": "Thanh toán thành công", "message": f"Khách hàng {appt['customer_name']} đã thanh toán {booking['total_amount']:,.0f}đ."}, sender_id=appt["user_id"])
        conn.commit()
        return {"status": "success"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.patch("/appointments/{appointment_id}/check-in", tags=["Scheduling"])
def check_in_appointment(appointment_id: str, payload: schemas.AppointmentCheckIn, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if appt["partner_id"] != current_user.id: raise HTTPException(status_code=403, detail="Cấm!")
        if appt["status"] != "CONFIRMED" or appt.get("check_in_code") != payload.check_in_code: raise HTTPException(status_code=400, detail="Sai mã hoặc sai trạng thái!")

        cur.execute("UPDATE appointments SET status = 'SERVED', partner_notes = %s WHERE id = %s", (payload.partner_notes, appointment_id))
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=appt["user_id"], event_type="LEGACY", reference_id=appointment_id, metadata={"category": "BOOKING", "title": "Xác nhận Check-in thành công", "message": "Bạn đã check-in thành công tại cơ sở dịch vụ. Chúc bạn có trải nghiệm tuyệt vời!"}, sender_id=current_user.id)
        conn.commit()
        return {"status": "success", "message": "Check-in thành công."}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.patch("/appointments/{appointment_id}/user-confirm", tags=["Scheduling"])
def confirm_appointment(appointment_id: str, payload: schemas.AppointmentConfirm, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if appt["user_id"] != current_user.id or appt["status"] != "SERVED": raise HTTPException(status_code=400, detail="Lỗi trạng thái hoặc phân quyền")

        booking_id = appt.get("booking_id")
        partner_rev = 0
        if booking_id:
            cur.execute("SELECT * FROM bookings_transactions WHERE id = %s", (booking_id,))
            booking = cur.fetchone()
            if booking and booking["payment_status"] == "PAID" and booking["service_status"] != "COMPLETED":
                original_total = float(booking["total_amount"])
                discount_amount = float(booking.get("voucher_discount_amount") or 0)
                funded_by = booking.get("discount_funded_by")
                
                # Xác định doanh thu thực tế để tính phế (Ai tạo mã người nấy chịu)
                revenue_base = original_total - discount_amount if funded_by == 'PARTNER' else original_total

                partner_rev = revenue_base * 0.70
                platform_fee = revenue_base * 0.20
                affiliate_rev = revenue_base * 0.10 if booking.get("affiliate_id") else 0
                if not booking.get("affiliate_id"): platform_fee += revenue_base * 0.10

                cur.execute("UPDATE bookings_transactions SET service_status = 'COMPLETED', partner_revenue = %s, platform_fee = %s, affiliate_revenue = %s WHERE id = %s", 
                            (partner_rev, platform_fee, affiliate_rev, booking_id))
                
                cur.execute("SELECT id FROM wallets WHERE user_id = %s", (appt["partner_id"],))
                if cur.fetchone():
                    cur.execute("UPDATE wallets SET balance = balance + %s, total_earned = total_earned + %s WHERE user_id = %s", (partner_rev, partner_rev, appt["partner_id"]))
                else:
                    cur.execute("INSERT INTO wallets (user_id, balance, total_earned) VALUES (%s, %s, %s)", (appt["partner_id"], partner_rev, partner_rev))

        cur.execute("UPDATE appointments SET status = 'COMPLETED', user_confirmed = True WHERE id = %s", (appointment_id,))
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=appt["partner_id"], event_type="REVENUE_DISBURSED", reference_id=appointment_id, sender_id=current_user.id)
        
        conn.commit()
        return {"status": "success", "message": "Giải ngân thành công."}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.patch("/appointments/{appointment_id}/cancel", tags=["Scheduling"])
def cancel_appointment(appointment_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if appt["user_id"] != current_user.id: raise HTTPException(status_code=403, detail="Cấm!")
        if appt["status"] not in ["WAITING_PARTNER", "PENDING_PAYMENT"]: raise HTTPException(status_code=400, detail="Không thể hủy!")

        if appt.get("applied_user_voucher_id"):
            if appt["status"] == "WAITING_PARTNER":
                # Cơ sở chưa xác nhận -> Hoàn lại Voucher
                cur.execute("UPDATE user_vouchers SET status = 'UNUSED', locked_until = NULL WHERE id = %s", (appt["applied_user_voucher_id"],))
            elif appt["status"] == "PENDING_PAYMENT":
                # Cơ sở đã xác nhận mà khách hủy -> Phạt mất Voucher
                cur.execute("UPDATE user_vouchers SET status = 'USED' WHERE id = %s", (appt["applied_user_voucher_id"],))

        cur.execute("UPDATE appointments SET status = 'CANCELLED', rejection_reason = 'Người dùng tự hủy' WHERE id = %s", (appointment_id,))
        from notification_service import NotificationService
        NotificationService.dispatch_event(conn, user_id=appt["partner_id"], event_type="LEGACY", reference_id=appointment_id, metadata={"category": "BOOKING", "title": "Khách hàng hủy lịch", "message": "Lịch hẹn mã số xử lý tự động đã bị hủy bỏ bởi khách hàng."}, sender_id=current_user.id)
        conn.commit()
        return {"status": "success", "message": "Đã hủy."}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

# ==========================================
# 11. VOUCHER & KHUYẾN MÃI
# ==========================================
@app.post("/vouchers", tags=["Vouchers"])
def create_voucher(payload: schemas.VoucherCreate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        issuer_type = "ADMIN" if current_user.role == "SUPER_ADMIN" else "PARTNER"
        status = "APPROVED" if issuer_type == "ADMIN" else "PENDING"
        
        cur.execute("""
            INSERT INTO vouchers (code, issuer_type, issuer_id, discount_type, discount_value, max_discount_amount, 
                                  min_order_value, applicable_services, total_quantity, valid_from, valid_until, status)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s::uuid[], %s, %s, %s, %s) RETURNING *
        """, (payload.code, issuer_type, current_user.id if issuer_type == "PARTNER" else None, 
              payload.discount_type, payload.discount_value, payload.max_discount_amount, payload.min_order_value, 
              payload.applicable_services, payload.total_quantity, payload.valid_from, payload.valid_until, status))
        new_voucher = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": new_voucher}
    except psycopg2.IntegrityError:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Mã code này đã tồn tại trên hệ thống!")
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.post("/vouchers/{voucher_code}/claim", tags=["Vouchers"])
def claim_voucher(voucher_code: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT id, total_quantity, used_quantity, valid_until, status FROM vouchers WHERE code = %s", (voucher_code,))
        voucher = cur.fetchone()
        if not voucher or voucher['status'] != 'APPROVED': raise HTTPException(status_code=400, detail="Mã không tồn tại hoặc chưa duyệt.")
        if voucher['used_quantity'] >= voucher['total_quantity']: raise HTTPException(status_code=400, detail="Mã này đã hết lượt dùng.")
        if voucher['valid_until'] < datetime.now(): raise HTTPException(status_code=400, detail="Mã này đã hết hạn.")
            
        cur.execute("INSERT INTO user_vouchers (user_id, voucher_id) VALUES (%s, %s) RETURNING id", (current_user.id, voucher['id']))
        conn.commit()
        return {"status": "success", "message": "Đã lưu Voucher vào ví!"}
    except psycopg2.IntegrityError:
        conn.rollback()
        raise HTTPException(status_code=400, detail="Bạn đã có mã này trong ví rồi!")
    finally: cur.close()

@app.get("/vouchers/me", tags=["Vouchers"])
def get_my_vouchers(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Giải phóng mã bị kẹt quá 10 phút trước khi query
        cur.execute("UPDATE user_vouchers SET status = 'UNUSED', locked_until = NULL WHERE status = 'LOCKED' AND locked_until < NOW()")
        conn.commit()
        
        cur.execute("""
            SELECT uv.id as user_voucher_id, uv.status as wallet_status, v.* FROM user_vouchers uv JOIN vouchers v ON uv.voucher_id = v.id 
            WHERE uv.user_id = %s ORDER BY v.valid_until ASC
        """, (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.get("/vouchers/public", tags=["Vouchers"])
def get_public_vouchers(conn=Depends(get_db_connection)):
    """Hiển thị tất cả mã ưu đãi công khai (Cả ADMIN và PARTNER) đã được duyệt và còn hạn/số lượng"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        # Bổ sung u.username as partner_username để Frontend làm đường dẫn chuẩn
        cur.execute("""
            SELECT v.*, u.full_name as partner_name, u.username as partner_username 
            FROM vouchers v
            LEFT JOIN users u ON v.issuer_id = u.id
            WHERE v.status = 'APPROVED' 
              AND v.valid_until > NOW() 
              AND v.used_quantity < v.total_quantity
            ORDER BY v.issuer_type ASC, v.created_at DESC
        """)
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.get("/partner/vouchers", tags=["Partner"])
def get_partner_vouchers(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Đối tác truy vấn danh sách toàn bộ mã ưu đãi do chính cơ sở mình tạo lập phục vụ hiển thị tại Partner Dashboard"""
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT * FROM vouchers 
            WHERE issuer_id = %s AND status != 'DELETED'
            ORDER BY created_at DESC
        """, (current_user.id,))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.get("/admin/vouchers", tags=["Admin"])
def get_admin_vouchers(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Quản trị viên hệ thống quản lý tổng thể kho mã ưu đãi toàn sàn phục vụ hiển thị tại Admin Dashboard"""
    if current_user.role not in ["SUPER_ADMIN", "MODERATOR"]: 
        raise HTTPException(status_code=403, detail="Cấm quyền truy cập!")
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT v.*, u.full_name as issuer_name, u.email as issuer_email
            FROM vouchers v
            LEFT JOIN users u ON v.issuer_id = u.id
            ORDER BY v.created_at DESC
        """)
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/admin/vouchers/{voucher_id}/status", tags=["Admin"])
async def update_voucher_status(voucher_id: str, request: Request, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Kiểm duyệt mã ưu đãi (APPROVED / REJECTED) bởi Moderator hoặc Admin"""
    if current_user.role not in ["SUPER_ADMIN", "MODERATOR"]:
        raise HTTPException(status_code=403, detail="Cấm quyền truy cập!")
    
    try:
        payload = await request.json()
    except Exception:
        payload = {}

    new_status = payload.get("status")
    if new_status not in ["APPROVED", "REJECTED", "DELETED"]:
        raise HTTPException(status_code=400, detail="Trạng thái không hợp lệ")

    cur = conn.cursor()
    try:
        cur.execute("UPDATE vouchers SET status = %s WHERE id = %s RETURNING id", (new_status, voucher_id))
        if not cur.fetchone():
            raise HTTPException(status_code=404, detail="Không tìm thấy mã ưu đãi")
        conn.commit()
        return {"status": "success", "message": f"Đã cập nhật trạng thái thành {new_status}"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

# ==========================================
# 12. PAYOS WEBHOOK
# ==========================================
@app.post("/payos/webhook", tags=["Payment"])
async def payos_webhook(request: Request, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        body = await request.json()
        if body.get("success") and body.get("code") == "00":
            data = body.get("data", {})
            orderCode = data.get("orderCode")
            
            cur.execute("SELECT * FROM bookings_transactions WHERE order_code = %s", (orderCode,))
            booking = cur.fetchone()
            if booking and booking["payment_status"] != "PAID":
                cur.execute("UPDATE bookings_transactions SET payment_status = 'PAID' WHERE id = %s", (booking["id"],))
                
                # BỌC THÉP LOGIC VOUCHER CHO WEBHOOK
                if booking.get("applied_voucher_id"):
                    cur.execute("UPDATE user_vouchers SET status = 'USED' WHERE user_id = %s AND voucher_id = %s AND status = 'LOCKED'", (booking["user_id"], booking["applied_voucher_id"]))
                    cur.execute("UPDATE vouchers SET used_quantity = used_quantity + 1 WHERE id = %s", (booking["applied_voucher_id"],))

                cur.execute("UPDATE appointments SET status = 'CONFIRMED' WHERE booking_id = %s RETURNING partner_id, customer_name, user_id", (booking["id"],))
                appt = cur.fetchone()
                if appt:
                    from notification_service import NotificationService
                    NotificationService.dispatch_event(conn, user_id=appt["partner_id"], event_type="LEGACY", reference_id=str(booking["id"]), metadata={"category": "ESCROW", "title": "Thanh toán thành công", "message": f"Khách hàng {appt.get('customer_name')} đã thanh toán."}, sender_id=appt["user_id"])
                conn.commit()
        return {"success": True}
    except Exception:
        conn.rollback()
        return {"success": False}
    finally: cur.close()

# ==========================================
# 14. FOLLOW & 15. NOTIFICATIONS
# ==========================================
@app.post("/user/follow/{target_id}", tags=["Follow"])
def toggle_follow(target_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        if target_id == current_user.id: raise HTTPException(status_code=400, detail="Cấm tự follow!")
        cur.execute("SELECT 1 FROM user_follows WHERE follower_id = %s AND following_id = %s", (current_user.id, target_id))
        if cur.fetchone():
            cur.execute("DELETE FROM user_follows WHERE follower_id = %s AND following_id = %s", (current_user.id, target_id))
            conn.commit()
            return {"status": "success", "action": "unfollowed"}
        else:
            cur.execute("INSERT INTO user_follows (follower_id, following_id) VALUES (%s, %s)", (current_user.id, target_id))
            conn.commit()
            return {"status": "success", "action": "followed"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.get("/user/follow-status/{target_id}", tags=["Follow"])
def check_follow_status(target_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        cur.execute("SELECT 1 FROM user_follows WHERE follower_id = %s AND following_id = %s", (current_user.id, target_id))
        return {"status": "success", "is_followed": bool(cur.fetchone())}
    finally: cur.close()

@app.get("/notifications", tags=["Notifications"])
def get_my_notifications(limit: int = 50, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("""
            SELECT n.*, json_build_object('full_name', u.full_name, 'username', u.username, 'avatar_url', u.avatar_url, 'role', u.role) as sender
            FROM notifications n LEFT JOIN users u ON n.sender_id = u.id
            WHERE n.user_id = %s ORDER BY n.created_at DESC LIMIT %s
        """, (current_user.id, limit))
        return {"status": "success", "data": cur.fetchall()}
    finally: cur.close()

@app.patch("/notifications/{notification_id}/read", tags=["Notifications"])
def mark_notification_read(notification_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        cur.execute("UPDATE notifications SET is_read = True WHERE id = %s AND user_id = %s", (notification_id, current_user.id))
        conn.commit()
        return {"status": "success"}
    finally: cur.close()

@app.patch("/notifications/read-all", tags=["Notifications"])
def mark_all_notifications_read(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        cur.execute("UPDATE notifications SET is_read = True WHERE user_id = %s AND is_read = False", (current_user.id,))
        conn.commit()
        return {"status": "success"}
    finally: cur.close()

# Khai báo trực tiếp Model để bọc thép chống lỗi đồng bộ dòng giữa các file trên Render
class FCMTokenUpdate(BaseModel):
    token: str
    device_id: Optional[str] = None
    platform: Optional[str] = None

@app.post("/notifications/token", tags=["Notifications"])
def update_fcm_token(payload: FCMTokenUpdate, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    """Lưu trữ FCM Token của thiết bị. Sử dụng UPSERT để tránh Crash khi trùng Token"""
    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO user_fcm_tokens (user_id, token, device_id, platform)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (token) DO UPDATE 
            SET user_id = EXCLUDED.user_id, 
                device_id = EXCLUDED.device_id, 
                platform = EXCLUDED.platform
        """, (current_user.id, payload.token, payload.device_id, payload.platform))
        conn.commit()
        return {"status": "success", "message": "Token đồng bộ thành công"}
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

# ==========================================
# 16. CLOUDFLARE R2 MEDIA UPLOAD
# ==========================================
R2_ENDPOINT_URL = os.environ.get("R2_ENDPOINT_URL")
R2_ACCESS_KEY_ID = os.environ.get("R2_ACCESS_KEY_ID")
R2_SECRET_ACCESS_KEY = os.environ.get("R2_SECRET_ACCESS_KEY")
R2_BUCKET_NAME = os.environ.get("R2_BUCKET_NAME")
R2_PUBLIC_DOMAIN = os.environ.get("R2_PUBLIC_DOMAIN")

r2_client = boto3.client(
    "s3",
    endpoint_url=R2_ENDPOINT_URL,
    aws_access_key_id=R2_ACCESS_KEY_ID,
    aws_secret_access_key=R2_SECRET_ACCESS_KEY
)

@app.post("/media/upload", tags=["Media"])
async def upload_media(request: Request, file: UploadFile = File(...), folder: str = Form(default="")):
    try:
        file_content = await file.read()

        # 1. Đọc thư mục từ Request
        actual_folder = folder or request.query_params.get("folder")
        
        # 2. Safety Net: Tự động phân loại nếu Front-End không truyền
        if not actual_folder or actual_folder == "general":
            f_lower = str(file.filename or "").lower()
            c_type = str(file.content_type or "").lower()
            
            if c_type.startswith("video/") or f_lower.endswith(('.mp4', '.mov')):
                actual_folder = "tiktok_feeds/videos" if "feed" in f_lower or "tiktok" in f_lower else "services/videos"
            elif c_type.startswith("image/") or f_lower.endswith(('.jpg', '.jpeg', '.png', '.webp')):
                if "avatar" in f_lower or "profile" in f_lower: actual_folder = "users/avatars"
                elif "cover" in f_lower: actual_folder = "users/covers"
                else: actual_folder = "services/images"
            else:
                actual_folder = "general"

        clean_folder = str(actual_folder).strip().strip('/')
        
        # 3. VÁ LỖ HỔNG KÝ TỰ TỪ MOBILE: Tự động sinh tên file an toàn (Safe Filename)
        import time
        import random
        original_name = str(file.filename or "")
        ext = original_name.split('.')[-1].lower() if '.' in original_name else 'bin'
        safe_filename = f"{int(time.time() * 1000)}_{random.randint(100,999)}.{ext}"
        
        file_key = f"{clean_folder}/{safe_filename}" if clean_folder else safe_filename

        r2_client.put_object(
            Bucket=str(R2_BUCKET_NAME).strip(),
            Key=str(file_key).strip(),
            Body=file_content,
            ContentType=file.content_type or "application/octet-stream"
        )

        # 4. Chuẩn hóa URL
        base_domain = str(R2_PUBLIC_DOMAIN).strip().rstrip('/')
        public_url = f"{base_domain}/{file_key}"
        return {"status": "success", "url": public_url}
    except Exception as e:
        print(f"LỖI UPLOAD R2: {e}") # Bắn log ra Terminal để kiểm soát nếu có sự cố khác
        raise HTTPException(status_code=500, detail=f"Lỗi R2: {str(e)}")