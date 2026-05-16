from fastapi import FastAPI, HTTPException, Depends, Security, Request
from fastapi.encoders import jsonable_encoder
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from database import get_db_connection
import psycopg2
from psycopg2.extras import RealDictCursor
from utils import send_notification, create_access_token, verify_password, get_password_hash
from jose import JWTError, jwt
import schemas
import time
import random
import os
import json
from datetime import datetime
from fastapi import UploadFile, File, Form
from groq import Groq
import boto3

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "61ec7d8b-1b0a-4ac3-ad85-69d6f1393492")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "c685a770-5b64-48bc-858f-071f54af19d5")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "30f7892af9f9d37ae84681b60878483e049f6e7c3287be6bdf28aa0f485973be")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(title="AI Health Share API", version="5.2.1")
security = HTTPBearer()

SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "fallback_secret_key")
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
@app.get("/user/profile", tags=["User"])
def get_user_profile(current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM users WHERE id = %s", (current_user.id,))
        user_info = cur.fetchone()
        cur.execute("SELECT count(*) as pending FROM services WHERE partner_id = %s AND status = 'PENDING'", (current_user.id,))
        pending = cur.fetchone()["pending"]
        cur.execute("SELECT count(*) as approved FROM services WHERE partner_id = %s AND status = 'APPROVED'", (current_user.id,))
        approved = cur.fetchone()["approved"]

        return {"status": "success", "data": {"profile": user_info, "stats": {"pending_total": pending, "approved_count": approved, "total_processed": 0}}}
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
        
        data = {
            "profile": user, "is_followed": is_followed, "services": services, "videos": videos,
            "stats": {"followers_count": user.get("followers_count", 0), "services_count": len(services), "videos_count": len(videos)}
        }
        return {"status": "success", "data": data}
    finally: cur.close()

@app.patch("/user/profile", tags=["User"])
def update_user_profile(payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        updates, values = [], []
        for k, v in payload.items():
            if k not in ["id", "email", "password_hash"]: # Bảo vệ trường hệ thống
                updates.append(f"{k} = %s")
                values.append(json.dumps(v) if isinstance(v, (dict, list)) else v)
        if not updates: return {"status": "success"}
        values.append(current_user.id)
        cur.execute(f"UPDATE users SET {', '.join(updates)} WHERE id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        conn.commit()
        return {"status": "success", "data": updated}
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

        total = float(booking["total_amount"])
        partner_rev = total * 0.70
        platform_fee = total * 0.20
        affiliate_rev = total * 0.10 if booking.get("affiliate_id") else 0
        if not booking.get("affiliate_id"): platform_fee += total * 0.10

        cur.execute("UPDATE bookings_transactions SET service_status = 'COMPLETED', partner_revenue = %s, platform_fee = %s, affiliate_revenue = %s WHERE id = %s", 
                    (partner_rev, platform_fee, affiliate_rev, booking_id))
        cur.execute("UPDATE appointments SET status = 'COMPLETED' WHERE booking_id = %s", (booking_id,))

        cur.execute("SELECT * FROM wallets WHERE user_id = %s", (current_user.id,))
        if cur.fetchone():
            cur.execute("UPDATE wallets SET balance = balance + %s, total_earned = total_earned + %s WHERE user_id = %s", (partner_rev, partner_rev, current_user.id))
        else:
            cur.execute("INSERT INTO wallets (user_id, balance, total_earned) VALUES (%s, %s, %s)", (current_user.id, partner_rev, partner_rev))
        
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
def get_tiktok_feeds(user_id: str = None, limit: int = 50, conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
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
# 6. AI ASSISTANT
# ==========================================
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

@app.post("/ai/chat", tags=["AI Assistant"])
def chat_with_llama(payload: schemas.AIChatRequest, current_user = Depends(verify_user_token)):
    try:
        messages = [{"role": "system", "content": "Bạn là Trợ lý AI Health. Dùng Markdown. Ngắn gọn."}]
        for msg in payload.messages:
            messages.append({"role": "assistant" if msg.role == "bot" else "user", "content": msg.content})
        chat_completion = groq_client.chat.completions.create(messages=messages, model="llama-3.1-8b-instant", temperature=0.6, max_tokens=1024)
        return {"status": "success", "data": {"reply": chat_completion.choices[0].message.content}}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

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
        
        combined = s_data + v_data
        combined.sort(key=lambda x: str(x.get("updated_at") or x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined}
    finally: cur.close()

@app.patch("/moderation/action/{item_type}/{item_id}", tags=["Moderation"])
def moderate_item(item_type: str, item_id: str, payload: dict, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor()
    try:
        action = payload.get("action")
        status = "DELETED" if action == "DELETED" else action
        table = "services" if item_type == "service" else "tiktok_feeds"
        
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
        cur.execute("SELECT count(*) FROM users")
        total_users = cur.fetchone()["count"]
        cur.execute("SELECT count(*) FROM services WHERE status = 'APPROVED'")
        total_services = cur.fetchone()["count"]
        cur.execute("SELECT COALESCE(SUM(platform_fee), 0) FROM bookings_transactions WHERE service_status = 'COMPLETED'")
        total_revenue = cur.fetchone()["coalesce"]
        return {"status": "success", "data": {"total_users": total_users, "total_services": total_services, "total_revenue": float(total_revenue)}}
    finally: cur.close()

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
        conn.commit()
        return {"status": "success", "message": f"Đã xử lý: {payload.status}"}
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
            
        values.append(appointment_id)
        cur.execute(f"UPDATE appointments SET {', '.join(updates)} WHERE id = %s RETURNING *", tuple(values))
        updated = cur.fetchone()
        
        status_msg = "đã CHẤP NHẬN" if payload.action == "ACCEPT" else f"đã TỪ CHỐI. Lý do: {payload.reason}"
        send_notification(conn, appt["user_id"], "BOOKING", "Cập nhật Lịch hẹn", f"Cơ sở {status_msg}", sender_id=current_user.id)
        
        conn.commit()
        return jsonable_encoder({"status": "success", "data": updated})
    except Exception as e:
        conn.rollback()
        raise HTTPException(status_code=500, detail=str(e))
    finally: cur.close()

@app.post("/appointments/{appointment_id}/pay", tags=["Scheduling"])
def create_appointment_payment(appointment_id: str, current_user = Depends(verify_user_token), conn=Depends(get_db_connection)):
    cur = conn.cursor(cursor_factory=RealDictCursor)
    try:
        cur.execute("SELECT * FROM appointments WHERE id = %s", (appointment_id,))
        appt = cur.fetchone()
        if appt["status"] != "PENDING_PAYMENT": raise HTTPException(status_code=400, detail="Không ở trạng thái chờ thanh toán!")
            
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        cur.execute("""INSERT INTO bookings_transactions (user_id, service_id, video_id, total_amount, payment_status, service_status, order_code, customer_name, customer_phone, note)
                       VALUES (%s, %s, %s, %s, 'UNPAID', 'PENDING', %s, %s, %s, %s) RETURNING id""",
                    (current_user.id, appt.get("service_id"), appt.get("video_id"), appt.get("total_amount", 0), order_code, appt.get("customer_name"), appt.get("customer_phone"), appt.get("note")))
        booking_id = cur.fetchone()["id"]
        
        cur.execute("UPDATE appointments SET booking_id = %s WHERE id = %s", (booking_id, appointment_id))
        conn.commit()

        payment_data = PaymentData(orderCode=order_code, amount=int(appt.get("total_amount", 0)), description=f"Lich {order_code}", returnUrl="http://localhost:3000/features/calendar", cancelUrl="http://localhost:3000/features/calendar")
        return {"status": "success", "checkout_url": payos_client.createPaymentLink(paymentData=payment_data).checkoutUrl}
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
        cur.execute("UPDATE appointments SET status = 'CONFIRMED' WHERE booking_id = %s RETURNING partner_id, customer_name, user_id", (booking["id"],))
        appt = cur.fetchone()
        
        if appt:
            send_notification(conn, appt["partner_id"], "ESCROW", "Thanh toán thành công", f"Khách hàng {appt['customer_name']} đã thanh toán {booking['total_amount']:,.0f}đ.", sender_id=appt["user_id"])
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
                total = float(booking["total_amount"])
                partner_rev = total * 0.70
                platform_fee = total * 0.20
                affiliate_rev = total * 0.10 if booking.get("affiliate_id") else 0
                if not booking.get("affiliate_id"): platform_fee += total * 0.10

                cur.execute("UPDATE bookings_transactions SET service_status = 'COMPLETED', partner_revenue = %s, platform_fee = %s, affiliate_revenue = %s WHERE id = %s", 
                            (partner_rev, platform_fee, affiliate_rev, booking_id))
                
                cur.execute("SELECT id FROM wallets WHERE user_id = %s", (appt["partner_id"],))
                if cur.fetchone():
                    cur.execute("UPDATE wallets SET balance = balance + %s, total_earned = total_earned + %s WHERE user_id = %s", (partner_rev, partner_rev, appt["partner_id"]))
                else:
                    cur.execute("INSERT INTO wallets (user_id, balance, total_earned) VALUES (%s, %s, %s)", (appt["partner_id"], partner_rev, partner_rev))

        cur.execute("UPDATE appointments SET status = 'COMPLETED', user_confirmed = True WHERE id = %s", (appointment_id,))
        send_notification(conn, appt["partner_id"], "ESCROW", "Đã nhận Doanh thu", f"{partner_rev:,.0f}đ đã chuyển vào Ví.", sender_id=current_user.id)
        
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

        cur.execute("UPDATE appointments SET status = 'CANCELLED', rejection_reason = 'Người dùng tự hủy' WHERE id = %s", (appointment_id,))
        conn.commit()
        return {"status": "success", "message": "Đã hủy."}
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
                cur.execute("UPDATE appointments SET status = 'CONFIRMED' WHERE booking_id = %s RETURNING partner_id, customer_name, user_id", (booking["id"],))
                appt = cur.fetchone()
                if appt:
                    send_notification(conn, appt["partner_id"], "ESCROW", "Thanh toán thành công", f"Khách hàng {appt.get('customer_name')} đã thanh toán.", sender_id=appt["user_id"])
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
async def upload_media(request: Request, file: UploadFile = File(...), folder: str = Form(None)):
    try:
        file_content = await file.read()

        # 1. Đọc thư mục từ Request (Form Data hoặc URL)
        actual_folder = folder or request.query_params.get("folder")
        
        # 2. Safety Net: Tự động phân loại nếu Front-End không truyền
        if not actual_folder or actual_folder == "general":
            f_lower = file.filename.lower()
            c_type = file.content_type.lower() if file.content_type else ""
            
            if c_type.startswith("video/") or f_lower.endswith(('.mp4', '.mov')):
                actual_folder = "tiktok_feeds/videos" if "feed" in f_lower or "tiktok" in f_lower else "services/videos"
            elif c_type.startswith("image/") or f_lower.endswith(('.jpg', '.png', '.webp')):
                if "avatar" in f_lower or "profile" in f_lower: actual_folder = "users/avatars"
                elif "cover" in f_lower: actual_folder = "users/covers"
                else: actual_folder = "services/images"
            else:
                actual_folder = "general"

        clean_folder = str(actual_folder).strip().strip('/')
        file_key = f"{clean_folder}/{file.filename}" if clean_folder else file.filename

        r2_client.put_object(
            Bucket=str(R2_BUCKET_NAME).strip(),
            Key=str(file_key).strip(),
            Body=file_content,
            ContentType=file.content_type
        )

        # Chuẩn hóa URL trả về sạch sẽ
        base_domain = str(R2_PUBLIC_DOMAIN).strip().rstrip('/')
        public_url = f"{base_domain}/{file_key}"
        return {"status": "success", "url": public_url}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi R2: {str(e)}")