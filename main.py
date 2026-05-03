from fastapi import FastAPI, HTTPException, Depends, Security, Request
from fastapi.encoders import jsonable_encoder
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import time
import random
import os
from datetime import datetime
from fastapi import UploadFile, File 
from groq import Groq
from utils import send_notification  # Import hàm gửi thông báo

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "61ec7d8b-1b0a-4ac3-ad85-69d6f1393492")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "c685a770-5b64-48bc-858f-071f54af19d5")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "30f7892af9f9d37ae84681b60878483e049f6e7c3287be6bdf28aa0f485973be")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(title="AI Health Share API", version="5.2.1")
security = HTTPBearer()

def verify_user_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        user_data = supabase.auth.get_user(token)
        return user_data.user
    except Exception:
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn!")

app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

@app.get("/")
def health_check(): return {"status": "success", "message": "Backend AI Health đang chạy mượt mà!"}

# ==========================================
# 1. SERVICES (DỊCH VỤ CƠ SỞ)
# ==========================================
@app.get("/services", tags=["Services"])
def get_services(user_id: str = None):
    """API Explore: Lấy danh sách dịch vụ kèm thông tin đối tác chi tiết"""
    try:
        # Lấy các dịch vụ đã được duyệt và sắp xếp mới nhất
        res = supabase.table("services").select("*").eq("status", "APPROVED").order("created_at", desc=True).execute()
        services = res.data or []
        
        # Tối ưu truy vấn: Lấy thông tin Partner một lần duy nhất
        partner_ids = list(set([s["partner_id"] for s in services if s.get("partner_id")]))
        
        p_dict = {}
        if partner_ids:
            # Bổ sung physical_address để hiển thị vị trí trên thẻ dịch vụ
            partners = supabase.table("users").select("id, avatar_url, full_name, username, physical_address").in_("id", partner_ids).execute().data or []
            p_dict = {p["id"]: p for p in partners}
            
        for s in services:
            # Gắn thông tin User (Partner) vào dịch vụ
            s["users"] = p_dict.get(s.get("partner_id"), {})
            # Đồng bộ biến service_type cho Frontend dễ dàng bắt filter
            s["service_type_enum"] = s.get("service_type", "RELAXATION")
            
        return {"status": "success", "data": services}
    except Exception as e: 
        print(f"[API Explore Error]: {str(e)}")
        raise HTTPException(status_code=500, detail="Lỗi truy xuất dữ liệu Khám phá")

@app.post("/services", tags=["Services"])
def create_service(payload: schemas.ServiceCreate, current_user = Depends(verify_user_token)):
    service_data = payload.model_dump()
    service_data["partner_id"] = current_user.id
    service_data["status"] = "PENDING" 
    res = supabase.table("services").insert(service_data).execute()
    return {"status": "success", "data": res.data[0]}

# ==========================================
# 2. BOOKINGS (BẢO CHỨNG ESCROW)
# ==========================================
# ĐÃ XÓA: API POST /bookings cũ để ngăn chặn lỗi tạo "đơn ảo" (Ghost Booking). 
# Toàn bộ luồng tạo giao dịch giờ đây đi qua API Thanh toán Lịch hẹn (Bảo chứng kép).

# ==========================================
# 3. HỒ SƠ NGƯỜI DÙNG & CÔNG KHAI
# ==========================================
@app.get("/user/profile", tags=["User"])
def get_user_profile(current_user = Depends(verify_user_token)):
    try:
        user_res = supabase.table("users").select("*").eq("id", current_user.id).execute()
        user = user_res.data[0] if user_res.data else None
        
        if not user:
            new_user = {"id": current_user.id, "email": current_user.email, "role": "USER", "full_name": current_user.email.split("@")[0]}
            supabase.table("users").insert(new_user).execute()
            user = new_user
        
        # BỔ SUNG: Tự động tính Stats cho Moderator ngay tại đây
        stats = {"pending_total": 0, "approved_count": 0, "total_processed": 0}
        if user.get("role") in ["MODERATOR", "SUPER_ADMIN"]:
            # 1. Đếm hàng đợi
            q_svc = supabase.table("services").select("id").in_("status", ["PENDING", "PENDING_DELETE"]).execute()
            q_vid = supabase.table("tiktok_feeds").select("id").in_("status", ["PENDING", "PENDING_DELETE"]).execute()
            stats["pending_total"] = len(q_svc.data or []) + len(q_vid.data or [])
            
            # 2. Đếm hiệu suất cá nhân
            s_done = supabase.table("services").select("status").eq("moderated_by", current_user.id).execute()
            v_done = supabase.table("tiktok_feeds").select("status").eq("moderated_by", current_user.id).execute()
            all_done = (s_done.data or []) + (v_done.data or [])
            stats["total_processed"] = len(all_done)
            stats["approved_count"] = sum(1 for i in all_done if i.get("status") == "APPROVED")

        return {"status": "success", "data": {"profile": user, "stats": stats}}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/user/public/{username}", tags=["User"])
def get_public_profile(username: str, request: Request):
    """API QUAN TRỌNG: Lấy thông tin công khai để hiển thị profile"""
    try:
        # SỬA LỖI .single() GÂY CRASH VÀ TỐI ƯU TRUY VẤN THEO ROLE
        user_res = supabase.table("users").select("*").ilike("username", username).execute()
        if not user_res.data: raise HTTPException(status_code=404, detail="Người dùng không tồn tại!")
        
        user = user_res.data[0]
        
        # 1. Đếm số người mà user này ĐANG THEO DÕI (following_count)
        try:
            following_res = supabase.table("user_follows").select("id", count="exact").eq("follower_id", user["id"]).execute()
            user["following_count"] = following_res.count or 0
        except Exception:
            user["following_count"] = 0

        # 2. KIỂM TRA TRẠNG THÁI FOLLOW (Đọc Token thụ động)
        user["is_followed"] = False
        auth_header = request.headers.get("Authorization")
        if auth_header and auth_header.startswith("Bearer "):
            token = auth_header.split(" ")[1]
            try:
                curr_user = supabase.auth.get_user(token).user
                if curr_user:
                    exist = supabase.table("user_follows").select("id").eq("follower_id", curr_user.id).eq("following_id", user["id"]).execute()
                    if exist.data: 
                        user["is_followed"] = True
            except Exception: 
                pass 
        
        # 3. Lấy Video & Bài đăng (Tất cả Role đều có)
        videos = supabase.table("tiktok_feeds").select("*").eq("author_id", user["id"]).eq("status", "APPROVED").order("created_at", desc=True).execute().data or []
        posts = supabase.table("community_posts").select("*").eq("author_id", user["id"]).order("created_at", desc=True).execute().data or []
        
        # 4. TỐI ƯU: Chỉ truy vấn Dịch vụ nếu là Đối tác/Admin
        services = []
        if user.get("role") in ["PARTNER", "PARTNER_ADMIN", "SUPER_ADMIN"]:
            services = supabase.table("services").select("*").eq("partner_id", user["id"]).eq("status", "APPROVED").order("created_at", desc=True).execute().data or []
        
        return {
            "status": "success",
            "data": {
                "profile": user,
                "videos": videos or [],   
                "community_posts": posts or [],     
                "services": services or [],
                "stats": {"total_videos": len(videos or []), "total_services": len(services or [])}
            }
        }
    except Exception as e: raise HTTPException(status_code=404, detail=str(e))

@app.patch("/user/profile", tags=["User"])
def update_user_profile(payload: dict, current_user = Depends(verify_user_token)):
    res = supabase.table("users").update(payload).eq("id", current_user.id).execute()
    return {"status": "success", "data": res.data[0] if res.data else {}}

# ==========================================
# 4. PARTNER BACKSTAGE (QUẢN LÝ RIÊNG)
# ==========================================
@app.get("/partner/my-services", tags=["Partner"])
def get_my_services(current_user = Depends(verify_user_token)):
    # Thêm .neq("status", "DELETED") để ẩn các mục đã xóa
    services = supabase.table("services").select("*").eq("partner_id", current_user.id).neq("status", "DELETED").order("created_at", desc=True).execute().data
    return {"status": "success", "data": services}

@app.patch("/partner/my-services/{service_id}", tags=["Partner"])
def update_my_service(service_id: str, payload: dict, current_user = Depends(verify_user_token)):
    update_data = {k: v for k, v in payload.items() if v is not None}
    update_data["status"] = "PENDING" 
    res = supabase.table("services").update(update_data).eq("id", service_id).execute()
    return {"status": "success", "data": res.data[0]}

@app.delete("/partner/my-services/{service_id}", tags=["Partner"])
def delete_my_service(service_id: str, current_user = Depends(verify_user_token)):
    res = supabase.table("services").update({"status": "PENDING_DELETE"}).eq("id", service_id).execute()
    return {"status": "success", "message": "Yêu cầu xóa đã được gửi đi"}

@app.get("/partner/my-tiktok-feeds", tags=["Partner"])
def get_my_videos(current_user = Depends(verify_user_token)):
    # Thêm .neq("status", "DELETED") để ẩn các mục đã xóa
    videos = supabase.table("tiktok_feeds").select("*").eq("author_id", current_user.id).neq("status", "DELETED").order("created_at", desc=True).execute().data
    return {"status": "success", "data": videos}

@app.patch("/partner/my-tiktok-feeds/{video_id}", tags=["Partner"])
def update_my_video(video_id: str, payload: dict, current_user = Depends(verify_user_token)):
    update_data = {k: v for k, v in payload.items() if v is not None}
    update_data["status"] = "PENDING"
    res = supabase.table("tiktok_feeds").update(update_data).eq("id", video_id).execute()
    return {"status": "success", "data": res.data[0]}

@app.delete("/partner/my-tiktok-feeds/{video_id}", tags=["Partner"])
def delete_my_video(video_id: str, current_user = Depends(verify_user_token)):
    res = supabase.table("tiktok_feeds").update({"status": "PENDING_DELETE"}).eq("id", video_id).execute()
    return {"status": "success", "message": "Yêu cầu gỡ video đã được gửi đi"}
@app.get("/partner/bookings", tags=["Partner"])
def get_partner_bookings(current_user = Depends(verify_user_token)):
    """Lấy danh sách đơn hàng liên quan đến Dịch vụ hoặc Video của Partner này"""
    try:
        # Lấy tất cả ID dịch vụ và video của partner này
        my_services = supabase.table("services").select("id").eq("partner_id", current_user.id).execute()
        my_videos = supabase.table("tiktok_feeds").select("id").eq("author_id", current_user.id).execute()
        
        service_ids = [s["id"] for s in my_services.data] if my_services.data else []
        video_ids = [v["id"] for v in my_videos.data] if my_videos.data else []

        if not service_ids and not video_ids:
            return {"status": "success", "data": []}

        # Query Bookings
        query = supabase.table("bookings_transactions").select("*")
        
        # Giả lập OR logic cho supabase (Python client có giới hạn, ta fetch cả 2 rồi gộp)
        bookings = []
        if service_ids:
            res_svc = supabase.table("bookings_transactions").select("*").in_("service_id", service_ids).execute()
            bookings.extend(res_svc.data)
        if video_ids:
            res_vid = supabase.table("bookings_transactions").select("*").in_("video_id", video_ids).execute()
            bookings.extend(res_vid.data)
            
        # Loại bỏ trùng lặp nếu có
        unique_bookings = {b["id"]: b for b in bookings}.values()
        
        return {"status": "success", "data": list(unique_bookings)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
def complete_booking_escrow(booking_id: str, current_user = Depends(verify_user_token)):
    """CHỐT CHẶN MỚI: Chỉ giải ngân khi khách ĐÃ CHECK-IN (SERVED) & Cộng tiền vào Ví"""
    try:
        # 1. Kiểm tra đơn hàng Escrow
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).single().execute()
        if not booking_res.data: raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
        booking = booking_res.data
        
        if booking["payment_status"] != "PAID":
            raise HTTPException(status_code=400, detail="Khách hàng chưa thanh toán bảo chứng!")
        if booking["service_status"] == "COMPLETED":
            raise HTTPException(status_code=400, detail="Đơn này đã được xử lý rồi!")

        # 2. KIỂM TRA CHÉO LỊCH HẸN (Đảm bảo khách đã đến và đọc mã 6 số)
        appt_res = supabase.table("appointments").select("status").eq("booking_id", booking_id).execute()
        if appt_res.data and len(appt_res.data) > 0:
            if appt_res.data[0]["status"] not in ["SERVED", "COMPLETED"]:
                raise HTTPException(status_code=400, detail="Khách chưa Check-in! Vui lòng nhập mã 6 số của khách trước khi Hoàn thành.")

        # 3. Tính toán chia tiền (70/20/10)
        total = float(booking["total_amount"])
        partner_rev = total * 0.70
        platform_fee = total * 0.20
        affiliate_rev = total * 0.10 if booking.get("affiliate_id") else 0
        if not booking.get("affiliate_id"): platform_fee += total * 0.10

        # 4. THỰC THI 3 GIAO DỊCH (Transaction)
        # 4.1. Chốt đơn hàng Escrow
        update_data = {"service_status": "COMPLETED", "partner_revenue": partner_rev, "platform_fee": platform_fee, "affiliate_revenue": affiliate_rev}
        supabase.table("bookings_transactions").update(update_data).eq("id", booking_id).execute()
        
        # 4.2. Đóng Lịch hẹn
        supabase.table("appointments").update({"status": "COMPLETED"}).eq("booking_id", booking_id).execute()

        # 4.3. CỘNG TIỀN VÀO VÍ ĐỐI TÁC (Tạo ví nếu chưa có)
        wallet_res = supabase.table("wallets").select("*").eq("user_id", current_user.id).execute()
        if wallet_res.data:
            new_balance = float(wallet_res.data[0]["balance"]) + partner_rev
            new_earned = float(wallet_res.data[0]["total_earned"]) + partner_rev
            supabase.table("wallets").update({"balance": new_balance, "total_earned": new_earned}).eq("user_id", current_user.id).execute()
        else:
            supabase.table("wallets").insert({"user_id": current_user.id, "balance": partner_rev, "total_earned": partner_rev}).execute()
        
        return {"status": "success", "message": "Dịch vụ hoàn tất! Tiền đã được cộng vào Ví của bạn.", "distribution": update_data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/partner/withdraw", tags=["Partner"])
def create_withdrawal_request(payload: schemas.WithdrawalRequest, current_user = Depends(verify_user_token)):
    """API RÚT TIỀN: Backend tự kiểm tra số dư và trừ tiền an toàn"""
    try:
        # 1. Kiểm tra số dư ví thật trong DB
        wlt = supabase.table("wallets").select("*").eq("user_id", current_user.id).single().execute()
        if not wlt.data or float(wlt.data["balance"]) < payload.amount:
            raise HTTPException(status_code=400, detail="Số dư không đủ để thực hiện giao dịch!")
        
        if payload.amount < 50000:
            raise HTTPException(status_code=400, detail="Số tiền rút tối thiểu là 50.000 VND")

        # 2. Tạo bản ghi yêu cầu rút
        withdrawal_data = {
            "user_id": current_user.id,
            "amount": payload.amount,
            "status": "PENDING",
            "payout_info": {
                "bank_name": payload.bank_name,
                "account_number": payload.account_number,
                "account_name": payload.account_name
            }
        }
        res = supabase.table("withdrawal_requests").insert(withdrawal_data).execute()

        # 3. TRỪ TIỀN VÍ (Thực hiện tại Server)
        new_balance = float(wlt.data["balance"]) - payload.amount
        supabase.table("wallets").update({"balance": new_balance}).eq("user_id", current_user.id).execute()

        return {"status": "success", "message": "Yêu cầu giải ngân đã được gửi thành công!"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/partner/withdrawals", tags=["Partner"])
def get_my_withdrawals(current_user = Depends(verify_user_token)):
    """Lấy danh sách lịch sử yêu cầu rút tiền của chính Partner"""
    try:
        res = supabase.table("withdrawal_requests").select("*").eq("user_id", current_user.id).order("created_at", desc=True).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
        
# ==========================================
# 5. COMMUNITY & TIKTOK FEEDS (QUẢN LÝ NỘI DUNG)
# ==========================================
@app.get("/community/posts", tags=["Community"])
def get_community_posts(limit: int = 50):
    try:
        res = supabase.table("community_posts").select("*").order("created_at", desc=True).limit(limit).execute()
        posts = res.data or []
        
        author_ids = list(set([p["author_id"] for p in posts if p.get("author_id")]))
        authors = {a["id"]: a for a in (supabase.table("users").select("id, full_name, avatar_url, role").in_("id", author_ids).execute().data or [])} if author_ids else {}
        
        for p in posts:
            p["author"] = authors.get(p.get("author_id"), {})
            
        return {"status": "success", "data": posts}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/community/posts", tags=["Community"])
def create_community_post(post: schemas.CommunityPostCreate, current_user = Depends(verify_user_token)):
    try:
        data = {"author_id": current_user.id, "content": post.content, "image_url": post.image_url}
        res = supabase.table("community_posts").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/tiktok/feeds", tags=["TikTok Feeds"])
def get_tiktok_feeds(user_id: str = None, limit: int = 50):
    try:
        # THAY ĐỔI: Chỉ định rõ ràng dùng 'tiktok_feeds_author_id_fkey'
        res = supabase.table("tiktok_feeds").select(
            "*, author:users!tiktok_feeds_author_id_fkey(id, full_name, avatar_url, username, role)"
        ).eq("status", "APPROVED").order("created_at", desc=True).limit(limit).execute()
        
        videos = res.data or []
        # Sau đó cậu có thể bỏ toàn bộ phần code bóc tách 'author_ids' thủ công ở phía dưới
        # ...
        
        author_ids = list(set([v["author_id"] for v in videos if v.get("author_id")]))
        authors = {a["id"]: a for a in (supabase.table("users").select("id, full_name, avatar_url, username, role").in_("id", author_ids).execute().data or [])} if author_ids else {}
        
        if user_id and videos:
            video_ids = [v['id'] for v in videos]
            likes = supabase.table("tiktok_feed_likes").select("video_id").eq("user_id", user_id).in_("video_id", video_ids).execute().data or []
            saves = supabase.table("tiktok_feed_saves").select("video_id").eq("user_id", user_id).in_("video_id", video_ids).execute().data or []
            liked_set = {l['video_id'] for l in likes}
            saved_set = {s['video_id'] for s in saves}
            for v in videos:
                v['is_liked'] = v['id'] in liked_set
                v['is_saved'] = v['id'] in saved_set
                v["author"] = authors.get(v.get("author_id"), {})
        else:
            for v in videos:
                v['is_liked'] = False
                v['is_saved'] = False
                v["author"] = authors.get(v.get("author_id"), {})
                
        return {"status": "success", "data": videos}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tiktok/feeds", tags=["TikTok Feeds"])
def create_tiktok_feed(payload: schemas.TikTokFeedCreate, current_user = Depends(verify_user_token)):
    try:
        user_info = supabase.table("users").select("role").eq("id", current_user.id).single().execute()
        role = user_info.data.get("role") if user_info.data else "USER"
        status = "APPROVED" if role in ["SUPER_ADMIN", "ADMIN"] else "PENDING"
        
        data = {
            "author_id": current_user.id, 
            "title": payload.title, 
            "content": payload.content, 
            "video_url": payload.video_url, 
            "price": payload.price, 
            "status": status
        }
        res = supabase.table("tiktok_feeds").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))


# ==========================================
# 6. AI & AUTH HELPERS
# ==========================================
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

@app.post("/ai/chat", tags=["AI Assistant"])
def chat_with_llama(payload: schemas.AIChatRequest, current_user = Depends(verify_user_token)):
    try:
        messages = [{"role": "system", "content": "Bạn là Trợ lý AI Health. Dùng Markdown. Ngắn gọn."}]
        for msg in payload.messages:
            role = "assistant" if msg.role == "bot" else "user"
            messages.append({"role": role, "content": msg.content})
        chat_completion = groq_client.chat.completions.create(messages=messages, model="llama-3.1-8b-instant", temperature=0.6, max_tokens=1024)
        return {"status": "success", "data": {"reply": chat_completion.choices[0].message.content}}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/auth/resolve", tags=["Auth"])
def resolve_identifier(payload: schemas.AuthResolve):
    ident = payload.identifier.strip()
    if "@" in ident: return {"status": "success", "email": ident}
    res = supabase.table("users").select("email").or_(f"username.eq.{ident},phone.eq.{ident}").execute()
    if not res.data: raise HTTPException(status_code=404, detail="Không tìm thấy tài khoản!")
    return {"status": "success", "email": res.data[0]["email"]}

@app.post("/auth/check-username", tags=["Auth"])
def check_username(payload: schemas.UsernameSet):
    username = payload.username.strip().lower()
    if len(username) < 3: raise HTTPException(status_code=400, detail="Username phải có ít nhất 3 ký tự!")
    existing = supabase.table("users").select("id").eq("username", username).execute()
    if existing.data: raise HTTPException(status_code=400, detail="Tên người dùng này đã tồn tại!")
    return {"status": "success", "message": "Username hợp lệ"}


# ==========================================
# 7. QUẢN TRỊ KIỂM DUYỆT (MODERATION)
# ==========================================
@app.get("/moderation/queue", tags=["Moderation"])
def get_moderation_queue(current_user = Depends(verify_user_token)):
    try:
        user_info = supabase.table("users").select("role").eq("id", current_user.id).single().execute()
        if user_info.data.get("role") not in ["MODERATOR", "SUPER_ADMIN"]:
            raise HTTPException(status_code=403, detail="Không có quyền truy cập!")

        # 1. Lấy dữ liệu thô từ 2 bảng
        services_res = supabase.table("services").select("*").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).execute()
        videos_res = supabase.table("tiktok_feeds").select("*").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).execute()

        # 2. Thu thập tất cả ID tác giả để lấy thông tin một lần (Tối ưu performance)
        author_ids = list(set(
            [s["partner_id"] for s in (services_res.data or []) if s.get("partner_id")] +
            [v["author_id"] for v in (videos_res.data or []) if v.get("author_id")]
        ))
        
        authors = {}
        if author_ids:
            authors_data = supabase.table("users").select("id, full_name, email, avatar_url").in_("id", author_ids).execute().data or []
            authors = {a["id"]: a for a in authors_data}

        combined = []
        for s in (services_res.data or []):
            s["type"] = "service"
            s["title"] = s.get("service_name")
            s["author"] = authors.get(s.get("partner_id"), {})
            combined.append(s)
            
        for v in (videos_res.data or []):
            v["type"] = "video"
            v["author"] = authors.get(v.get("author_id"), {})
            combined.append(v)
            
        combined.sort(key=lambda x: str(x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.patch("/moderation/action/{item_type}/{item_id}", tags=["Moderation"])
def moderate_item(item_type: str, item_id: str, payload: dict, current_user = Depends(verify_user_token)):
    try:
        action = payload.get("action")
        note = payload.get("note", "")
        table = "services" if item_type == "service" else "tiktok_feeds"
        
        update_data = {
            "status": "DELETED" if action == "DELETED" else action,
            "moderation_note": note,
        }
        # 1. Cập nhật cốt lõi (Chắc chắn thành công)
        supabase.table(table).update(update_data).eq("id", item_id).execute()
        
        # 2. Cập nhật lưu vết (Bỏ qua lỗi nếu DB chưa tạo cột)
        try:
            supabase.table(table).update({
                "moderated_by": current_user.id,
                "updated_at": datetime.now().isoformat()
            }).eq("id", item_id).execute()
        except Exception: pass
        
        return {"status": "success", "message": "Xử lý thành công"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/moderation/history", tags=["Moderation"])
def get_moderation_history(current_user = Depends(verify_user_token)):
    try:
        s_res = supabase.table("services").select("*").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute()
        v_res = supabase.table("tiktok_feeds").select("*").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute()
        
        author_ids = list(set([s.get("partner_id") for s in (s_res.data or []) if s.get("partner_id")] + [v.get("author_id") for v in (v_res.data or []) if v.get("author_id")]))
        authors = {a["id"]: a for a in (supabase.table("users").select("id, full_name, avatar_url").in_("id", author_ids).execute().data or [])} if author_ids else {}

        combined = []
        for s in (s_res.data or []):
            if s.get("moderated_by") == current_user.id or not s.get("moderated_by"):
                s["type"] = "service"
                s["title"] = s.get("service_name")
                s["author"] = authors.get(s.get("partner_id"), {})
                combined.append(s)
        for v in (v_res.data or []):
            if v.get("moderated_by") == current_user.id or not v.get("moderated_by"):
                v["type"] = "video"
                v["author"] = authors.get(v.get("author_id"), {})
                combined.append(v)
            
        combined.sort(key=lambda x: str(x.get("updated_at") or x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined[:50]}
    except Exception as e: return {"status": "error", "message": str(e)}

@app.get("/moderation/stats", tags=["Moderation"])
def get_moderation_stats(current_user = Depends(verify_user_token)):
    try:
        # 1. Tổng Pending
        q_svc = supabase.table("services").select("id").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).execute()
        q_vid = supabase.table("tiktok_feeds").select("id").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).execute()
        pending_total = len(q_svc.data or []) + len(q_vid.data or [])

        # 2. Xử lý an toàn dữ liệu đã duyệt
        s_done = supabase.table("services").select("*").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []
        v_done = supabase.table("tiktok_feeds").select("*").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []
        all_done = s_done + v_done
        
        my_done = [i for i in all_done if i.get("moderated_by") == current_user.id]
        if not my_done and len(all_done) > 0: my_done = all_done # Fallback
        
        approved = sum(1 for i in my_done if i.get("status") == "APPROVED")
        rejected = sum(1 for i in my_done if i.get("status") in ["REJECTED", "DELETED"])
        
        # 3. Khởi tạo và map biểu đồ 7 ngày
        from datetime import datetime, timedelta
        daily_stats = {}
        for i in range(6, -1, -1):
            d = (datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d')
            daily_stats[d] = {"date": d[8:10] + "/" + d[5:7], "Duyệt": 0, "Từ chối": 0}
            
        for item in my_done:
            raw_date = str(item.get("updated_at") or item.get("created_at") or "")[:10]
            if raw_date in daily_stats:
                if item.get("status") == "APPROVED": daily_stats[raw_date]["Duyệt"] += 1
                else: daily_stats[raw_date]["Từ chối"] += 1
        
        return {
            "status": "success", 
            "data": {
                "pending_total": pending_total,
                "total_processed": len(my_done),
                "approved_count": approved,
                "rejected_count": rejected,
                "chart_data": list(daily_stats.values())
            }
        }
    except Exception as e: return {"status": "error", "message": str(e)}



# ==========================================
# 8. CREATOR WORKSPACE (QUẢN LÝ SÁNG TẠO)
# ==========================================
@app.get("/creator/stats", tags=["Creator"])
def get_creator_stats(current_user = Depends(verify_user_token)):
    """Lấy thống kê hiệu suất của Creator (Lượt thích, Video, Bài đăng, Tỷ lệ duyệt)"""
    try:
        # Lấy video
        v_res = supabase.table("tiktok_feeds").select("id, likes_count, status").eq("author_id", current_user.id).execute()
        videos = v_res.data or []
        
        # Lấy bài đăng cộng đồng
        p_res = supabase.table("community_posts").select("id").eq("author_id", current_user.id).execute()
        posts = p_res.data or []
        
        total_videos = len(videos)
        total_posts = len(posts)
        total_likes = sum(v.get("likes_count") or 0 for v in videos)
        
        # Tính tỷ lệ duyệt (Chất lượng nội dung)
        approved_videos = sum(1 for v in videos if v.get("status") == "APPROVED")
        approval_rate = round((approved_videos / total_videos) * 100) if total_videos > 0 else 0

        return {
            "status": "success",
            "data": {
                "total_videos": total_videos,
                "total_posts": total_posts,
                "total_likes": total_likes,
                "approval_rate": approval_rate
            }
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/creator/content", tags=["Creator"])
def get_creator_content(current_user = Depends(verify_user_token)):
    """Lấy danh sách Video và Bài đăng cộng đồng của chính Creator"""
    try:
        videos = supabase.table("tiktok_feeds").select("*").eq("author_id", current_user.id).order("created_at", desc=True).execute().data or []
        posts = supabase.table("community_posts").select("*").eq("author_id", current_user.id).order("created_at", desc=True).execute().data or []
        
        return {
            "status": "success", 
            "data": {
                "videos": videos,
                "community_posts": posts
            }
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}


# ==========================================
# 9. QUẢN TRỊ VIÊN CẤP CAO (SUPER ADMIN)
# ==========================================
@app.get("/admin/profile-stats", tags=["Admin"])
def get_admin_profile_stats(current_user = Depends(verify_user_token)):
    """Lấy chỉ số Header cho Admin Profile"""
    try:
        user_info = supabase.table("users").select("role, followers_count").eq("id", current_user.id).single().execute()
        if user_info.data.get("role") != "SUPER_ADMIN":
            raise HTTPException(status_code=403, detail="Không có quyền truy cập!")
            
        # Đếm tổng dịch vụ đang Active trên toàn nền tảng
        services_res = supabase.table("services").select("id", count="exact").eq("status", "APPROVED").execute()
        active_services = services_res.count or 0
        
        return {
            "status": "success",
            "data": {
                "followers_count": user_info.data.get("followers_count") or 0,
                "active_services": active_services,
                "system_stability": 99.9
            }
        }
    except Exception as e:
        return {"status": "error", "message": str(e)}
        
@app.get("/admin/my-content", tags=["Admin"])
def get_admin_content(current_user = Depends(verify_user_token)):
    """Lấy nội dung do Admin tự đăng"""
    try:
        videos = supabase.table("tiktok_feeds").select("*").eq("author_id", current_user.id).order("created_at", desc=True).execute().data or []
        posts = supabase.table("community_posts").select("*").eq("author_id", current_user.id).order("created_at", desc=True).execute().data or []
        return {"status": "success", "data": {"videos": videos, "community_posts": posts}}
    except Exception as e:
        return {"status": "error", "message": str(e)}

# ==========================================
# 9. QUẢN TRỊ VIÊN CẤP CAO (SUPER ADMIN) - TIẾP TỤC
# ==========================================
@app.get("/admin/dashboard-stats", tags=["Admin"])
def get_admin_dashboard_stats(current_user = Depends(verify_user_token)):
    """Lấy số liệu tổng quan toàn hệ thống (Tập trung Tài chính & Escrow)"""
    try:
        user_info = supabase.table("users").select("role").eq("id", current_user.id).single().execute()
        if user_info.data.get("role") != "SUPER_ADMIN":
            raise HTTPException(status_code=403, detail="Truy cập bị từ chối")

        # 1. Thống kê Tài chính từ bảng bookings_transactions
        bookings = supabase.table("bookings_transactions").select("total_amount, platform_fee, payment_status, service_status, created_at").execute().data or []
        
        gmv = sum(b.get("total_amount", 0) for b in bookings if b.get("payment_status") == "PAID")
        platform_revenue = sum(b.get("platform_fee", 0) for b in bookings if b.get("service_status") == "COMPLETED")
        escrow_holding = sum(b.get("total_amount", 0) for b in bookings if b.get("payment_status") == "PAID" and b.get("service_status") != "COMPLETED")

        # 2. Yêu cầu rút tiền (Withdrawals)
        # Bọc giáp try-catch phòng trường hợp bảng withdrawals chưa được tạo
        pending_withdrawals = 0
        try:
            pending_withdrawals = supabase.table("withdrawal_requests").select("id", count="exact").eq("status", "PENDING").execute().count or 0
        except Exception: pass

        # 3. Tổng User & Đối tác
        users_count = supabase.table("users").select("id", count="exact").execute().count or 0
        partners_count = supabase.table("users").select("id", count="exact").eq("role", "PARTNER").execute().count or 0

        # 4. Biểu đồ GMV 7 ngày qua
        from datetime import datetime, timedelta
        daily_stats = {}
        for i in range(6, -1, -1):
            d = (datetime.now() - timedelta(days=i)).strftime('%Y-%m-%d')
            daily_stats[d] = {"date": d[8:10] + "/" + d[5:7], "GMV": 0, "Doanh thu": 0}
            
        for b in bookings:
            if b.get("payment_status") == "PAID":
                raw_date = str(b.get("created_at") or "")[:10]
                if raw_date in daily_stats:
                    daily_stats[raw_date]["GMV"] += b.get("total_amount", 0)
                    if b.get("service_status") == "COMPLETED":
                        daily_stats[raw_date]["Doanh thu"] += b.get("platform_fee", 0)

        return {
            "status": "success",
            "data": {
                "gmv": gmv,
                "platform_revenue": platform_revenue,
                "escrow_holding": escrow_holding,
                "pending_withdrawals": pending_withdrawals,
                "total_users": users_count,
                "total_partners": partners_count,
                "chart_data": list(daily_stats.values())
            }
        }
    except Exception as e: return {"status": "error", "message": str(e)}

@app.get("/admin/withdrawals", tags=["Admin"])
def get_withdrawals(current_user = Depends(verify_user_token)):
    """Lấy danh sách yêu cầu rút tiền / Giải ngân với chỉ định FK rõ ràng"""
    try:
        # Sử dụng dấu ! để chỉ định tên Constraint FK giúp Supabase Join chính xác
        res = supabase.table("withdrawal_requests").select(
            "*, users!withdrawal_requests_user_id_fkey(full_name, email, role)"
        ).order("created_at", desc=True).execute()
        
        return {"status": "success", "data": res.data or []}
    except Exception as e: 
        print(f"LỖI TRUY VẤN RÚT TIỀN: {str(e)}") 
        raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")


@app.patch("/admin/withdrawals/{w_id}", tags=["Admin"])
def process_withdrawal(w_id: str, payload: schemas.WithdrawalUpdate, current_user = Depends(verify_user_token)):
    """Duyệt hoặc từ chối lệnh rút tiền - ĐÃ VÁ LỖI THIẾU CỘT VÀ SINGLE()"""
    try:
        # 1. Lấy thông tin lệnh rút (Dùng execute() thay vì single() để an toàn)
        w_res = supabase.table("withdrawal_requests").select("*").eq("id", w_id).execute()
        if not w_res.data: 
            raise HTTPException(status_code=404, detail="Không tìm thấy lệnh rút tiền này")
        request = w_res.data[0]

        # 2. Nếu từ chối (REJECTED), hoàn tiền vào ví cho Partner
        if payload.status == "REJECTED" and request["status"] == "PENDING":
            wlt_res = supabase.table("wallets").select("*").eq("user_id", request["user_id"]).execute()
            if wlt_res.data:
                wallet = wlt_res.data[0]
                new_bal = float(wallet["balance"]) + float(request["amount"])
                supabase.table("wallets").update({"balance": new_bal}).eq("user_id", request["user_id"]).execute()

        # 3. Cập nhật trạng thái lệnh rút (Đảm bảo cột processed_by đã được thêm ở Bước 1)
        update_data = {
            "status": payload.status, 
            "admin_note": payload.admin_note if payload.admin_note else "", 
            "processed_by": current_user.id, 
            "updated_at": datetime.now().isoformat()
        }
        
        supabase.table("withdrawal_requests").update(update_data).eq("id", w_id).execute()
        
        return {"status": "success", "message": f"Đã xử lý: {payload.status}"}
    except Exception as e: 
        print(f"DEBUG ERROR: {str(e)}") # Theo dõi lỗi cụ thể tại terminal backend
        raise HTTPException(status_code=500, detail="Lỗi hệ thống khi xử lý yêu cầu")


# ==========================================
# 10. HỆ THỐNG BÌNH LUẬN & TƯƠNG TÁC (VIDEO)
# ==========================================
@app.get("/tiktok/feeds/{video_id}/comments", tags=["Comments"])
def get_tiktok_comments(video_id: str):
    try:
        res = supabase.table("tiktok_feed_comments").select("*").eq("video_id", video_id).order("created_at", desc=False).execute()
        comments = res.data or []
        author_ids = list(set([c["user_id"] for c in comments if c.get("user_id")]))
        authors = {a["id"]: a for a in (supabase.table("users").select("id, full_name, username, avatar_url, role").in_("id", author_ids).execute().data or [])} if author_ids else {}
        for c in comments:
            c["users"] = authors.get(c.get("user_id"), {})
        return {"status": "success", "data": comments}
    except Exception as e: return {"status": "error", "message": str(e)}

@app.post("/tiktok/feeds/{video_id}/comments", tags=["Comments"])
def create_tiktok_comment(video_id: str, payload: dict, current_user = Depends(verify_user_token)):
    try:
        content = payload.get("content", "").strip()
        if not content: raise HTTPException(status_code=400, detail="Nội dung trống")
        data = {"video_id": video_id, "user_id": current_user.id, "content": content}
        if payload.get("parent_id"): data["parent_id"] = payload.get("parent_id")
        res = supabase.table("tiktok_feed_comments").insert(data).execute()
        # Cập nhật số lượng bình luận (comments_count)
        f_res = supabase.table("tiktok_feeds").select("comments_count").eq("id", video_id).single().execute()
        new_count = (f_res.data.get("comments_count") or 0) + 1
        supabase.table("tiktok_feeds").update({"comments_count": new_count}).eq("id", video_id).execute()
        return {"status": "success", "data": res.data[0] if res.data else data}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.delete("/tiktok/feeds/comments/{comment_id}", tags=["Comments"])
def delete_tiktok_comment(comment_id: str, current_user = Depends(verify_user_token)):
    try:
        c_res = supabase.table("tiktok_feed_comments").select("video_id").eq("id", comment_id).single().execute()
        if c_res.data:
            vid = c_res.data["video_id"]
            supabase.table("tiktok_feed_comments").delete().eq("id", comment_id).execute()
            f_res = supabase.table("tiktok_feeds").select("comments_count").eq("id", vid).single().execute()
            new_count = max(0, (f_res.data.get("comments_count") or 0) - 1)
            supabase.table("tiktok_feeds").update({"comments_count": new_count}).eq("id", vid).execute()
        return {"status": "success", "message": "Đã xóa"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

# ĐẶT HÀM DƯỚI CÙNG ĐỂ TRÁNH XUNG ĐỘT ROUTING
@app.post("/tiktok/feeds/{video_id}/{action}", tags=["TikTok Feeds"])
def toggle_tiktok_interaction(video_id: str, action: str, current_user = Depends(verify_user_token)):
    if action not in ["like", "save", "share"]: raise HTTPException(status_code=400, detail="Lỗi")
    try:
        if action == "share":
            supabase.table("tiktok_feed_shares").insert({"video_id": video_id, "user_id": current_user.id}).execute()
            f_res = supabase.table("tiktok_feeds").select("shares_count").eq("id", video_id).single().execute()
            supabase.table("tiktok_feeds").update({"shares_count": (f_res.data.get("shares_count") or 0) + 1}).eq("id", video_id).execute()
            return {"status": "success", "action": "shared"}

        table = "tiktok_feed_likes" if action == "like" else "tiktok_feed_saves"
        count_col = "likes_count" if action == "like" else "saves_count"
        
        # Kiểm tra sự tồn tại (Dùng video_id thay vì id để an toàn)
        exist = supabase.table(table).select("video_id").eq("video_id", video_id).eq("user_id", current_user.id).execute()
        f_res = supabase.table("tiktok_feeds").select(count_col).eq("id", video_id).single().execute()
        curr = f_res.data.get(count_col) or 0

        if exist.data:
            supabase.table(table).delete().eq("video_id", video_id).eq("user_id", current_user.id).execute()
            supabase.table("tiktok_feeds").update({count_col: max(0, curr - 1)}).eq("id", video_id).execute()
            return {"status": "success", "action": f"un{action}d"}
        else:
            supabase.table(table).insert({"video_id": video_id, "user_id": current_user.id}).execute()
            supabase.table("tiktok_feeds").update({count_col: curr + 1}).eq("id", video_id).execute()
            return {"status": "success", "action": f"{action}d"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))


# ==========================================
# 11. HỆ THỐNG LỊCH HẸN (SCHEDULING) & CHECK-IN
# ==========================================
@app.get("/appointments/me", tags=["Scheduling"])
def get_my_appointments(current_user = Depends(verify_user_token)):
    """Lấy danh sách lịch hẹn của tôi (User hoặc Partner)"""
    try:
        # BỔ SUNG: Thêm 'username' vào phần select của partner
        res = supabase.table("appointments").select(
            "*, services(service_name, price), "
            "users!appointments_user_id_fkey(full_name, avatar_url, phone), "
            "partner:users!appointments_partner_id_fkey(full_name, username, physical_address)"
        ).or_(f"user_id.eq.{current_user.id},partner_id.eq.{current_user.id}")\
         .order("created_at", desc=False).execute()
         
        return jsonable_encoder({"status": "success", "data": res.data or []})
    except Exception as e: 
        return {"status": "error", "message": str(e)}

@app.post("/appointments/request", tags=["Scheduling"])
def request_appointment(payload: schemas.AppointmentRequest, current_user = Depends(verify_user_token)):
    """BƯỚC 1: Khách hàng gửi yêu cầu (Chưa có giờ cụ thể, chỉ chọn dịch vụ)"""
    try:
        data = payload.model_dump()
        data["user_id"] = current_user.id
        data["status"] = "WAITING_PARTNER"  # Trạng thái chờ Partner xác nhận
        
        # Sinh mã bí mật trước, chỉ dùng ở bước cuối
        data["check_in_code"] = str(random.randint(100000, 999999))
        
        res = supabase.table("appointments").insert(data).execute()
        appt_id = res.data[0]["id"]
        
        # 🚀 GỬI THÔNG BÁO CHO PARTNER NGAY SAU KHI INSERT THÀNH CÔNG
        send_notification(
            user_id=data["partner_id"],
            noti_type="BOOKING",
            title="Lịch hẹn mới",
            message=f"Khách hàng {data['customer_name']} vừa gửi yêu cầu đặt lịch.",
            action_url="/features/calendar" # Dẫn đối tác thẳng vào màn hình Lịch để xem
        )

        return jsonable_encoder({"status": "success", "message": "Đã gửi yêu cầu đến cơ sở!", "data": res.data[0]})
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.patch("/appointments/{appointment_id}/respond", tags=["Scheduling"])
def respond_appointment(appointment_id: str, payload: schemas.PartnerResponse, current_user = Depends(verify_user_token)):
    """BƯỚC 2: Partner trả lời (Đồng ý + Cho giờ HOẶC Từ chối + Lý do)"""
    try:
        appt_res = supabase.table("appointments").select("*").eq("id", appointment_id).single().execute()
        if not appt_res.data: raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu")
        
        if appt_res.data["partner_id"] != current_user.id:
            raise HTTPException(status_code=403, detail="Chỉ đối tác mới có quyền phản hồi!")

        update_data = {}
        if payload.action == "ACCEPT":
            if not payload.start_time or not payload.end_time:
                raise HTTPException(status_code=400, detail="Vui lòng ấn định thời gian cho khách!")
            
            update_data["status"] = "PENDING_PAYMENT"
            update_data["start_time"] = jsonable_encoder(payload.start_time)
            update_data["end_time"] = jsonable_encoder(payload.end_time)
            
            # Khách có 2 giờ (7200 giây) để thanh toán
            update_data["payment_deadline"] = jsonable_encoder(datetime.fromtimestamp(time.time() + 7200))
            
        elif payload.action == "REJECT":
            if not payload.reason: raise HTTPException(status_code=400, detail="Vui lòng nhập lý do từ chối!")
            update_data["status"] = "CANCELLED"
            update_data["rejection_reason"] = payload.reason
            
        res = supabase.table("appointments").update(update_data).eq("id", appointment_id).execute()
        return jsonable_encoder({"status": "success", "message": "Đã phản hồi khách hàng!", "data": res.data[0]})
    except Exception as e:
        if "no_overlap" in str(e): raise HTTPException(status_code=400, detail="Khung giờ bạn ấn định đã bị trùng với lịch khác!")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/appointments/{appointment_id}/pay", tags=["Scheduling"])
def create_appointment_payment(appointment_id: str, current_user = Depends(verify_user_token)):
    """BƯỚC 3: User đồng ý chốt lịch -> Tạo link PayOS và móc nối với Escrow"""
    try:
        appt_res = supabase.table("appointments").select("*").eq("id", appointment_id).single().execute()
        appt = appt_res.data
        
        if appt["status"] != "PENDING_PAYMENT":
            raise HTTPException(status_code=400, detail="Lịch này không ở trạng thái chờ thanh toán!")
            
        # 1. Tạo bản ghi vào bảng giao dịch Escrow
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        booking_payload = {
            "user_id": current_user.id,
            "service_id": appt.get("service_id"),
            "video_id": appt.get("video_id"),
            "total_amount": appt.get("total_amount", 0),
            "payment_status": "UNPAID",
            "service_status": "PENDING",
            "order_code": order_code,
            "customer_name": appt.get("customer_name"),
            "customer_phone": appt.get("customer_phone"),
            "note": appt.get("note")
        }
        # Loại bỏ các trường None để Supabase không báo lỗi
        booking_payload = {k: v for k, v in booking_payload.items() if v is not None}
        
        booking_res = supabase.table("bookings_transactions").insert(booking_payload).execute()
        booking_id = booking_res.data[0]["id"]
        
        # Liên kết ID giao dịch Escrow vào lịch hẹn này
        supabase.table("appointments").update({"booking_id": booking_id}).eq("id", appointment_id).execute()

        # 2. Tạo link PayOS
        try:
            payment_data = PaymentData(
                orderCode=order_code, 
                amount=int(appt.get("total_amount", 0)), 
                description=f"Thanh toan lich {order_code}", 
                returnUrl="http://localhost:3000/features/calendar", 
                cancelUrl="http://localhost:3000/features/calendar"
            )
            checkout_url = payos_client.createPaymentLink(paymentData=payment_data).checkoutUrl
        except Exception as payos_err: 
            print(f"Lỗi tạo link PayOS: {payos_err}")
            checkout_url = None
        
        return {"status": "success", "checkout_url": checkout_url}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/appointments/payment/verify", tags=["Scheduling"])
def verify_appointment_payment(orderCode: int, current_user = Depends(verify_user_token)):
    """BƯỚC 3.5 (MỚI): Xác thực thanh toán khi PayOS trả khách về Website"""
    try:
        # 1. Gọi API PayOS kiểm tra trạng thái thanh toán thật (Chống Fake URL)
        payment_info = payos_client.getPaymentLinkInformation(orderCode)
        if payment_info.status != "PAID":
            return {"status": "pending", "message": "Thanh toán chưa hoàn tất"}

        # 2. Tìm đơn hàng tương ứng trong Database
        booking_res = supabase.table("bookings_transactions").select("*").eq("order_code", orderCode).single().execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
        booking = booking_res.data

        # Nếu đã cập nhật rồi thì bỏ qua (tránh lỗi spam reload)
        if booking["payment_status"] == "PAID":
            return {"status": "success", "message": "Đã xác nhận trước đó"}

        # 3. Cập nhật bảng bookings_transactions -> PAID
        supabase.table("bookings_transactions").update({"payment_status": "PAID"}).eq("id", booking["id"]).execute()

        # 4. Cập nhật bảng appointments -> CONFIRMED
        supabase.table("appointments").update({"status": "CONFIRMED"}).eq("booking_id", booking["id"]).execute()

        return {"status": "success", "message": "Xác nhận thanh toán thành công!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/appointments/{appointment_id}/check-in", tags=["Scheduling"])
def check_in_appointment(appointment_id: str, payload: schemas.AppointmentCheckIn, current_user = Depends(verify_user_token)):
    """BƯỚC 4: Partner nhập mã khách đưa khi đến nơi"""
    try:
        appt_res = supabase.table("appointments").select("*").eq("id", appointment_id).single().execute()
        appt = appt_res.data

        if appt["partner_id"] != current_user.id: raise HTTPException(status_code=403, detail="Cơ sở không hợp lệ!")
        if appt["status"] != "CONFIRMED": raise HTTPException(status_code=400, detail="Lịch chưa được chốt hoặc đã xử lý!")
        if appt.get("check_in_code") != payload.check_in_code: raise HTTPException(status_code=400, detail="Mã Check-in sai!")

        update_data = {"status": "SERVED"}
        if payload.partner_notes: update_data["partner_notes"] = payload.partner_notes
            
        supabase.table("appointments").update(update_data).eq("id", appointment_id).execute()
        return {"status": "success", "message": "Check-in thành công. Chờ khách xác nhận giải ngân!"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.patch("/appointments/{appointment_id}/user-confirm", tags=["Scheduling"])
def confirm_appointment(appointment_id: str, payload: schemas.AppointmentConfirm, current_user = Depends(verify_user_token)):
    """BƯỚC 5: User xác nhận -> Hệ thống TỰ ĐỘNG CHIA TIỀN VÀ GIẢI NGÂN (CHUẨN SCHEMA)"""
    try:
        # 1. Lấy thông tin lịch hẹn (Dùng execute thay vì single để an toàn)
        appt_res = supabase.table("appointments").select("*").eq("id", appointment_id).execute()
        if not appt_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy lịch hẹn!")
        appt = appt_res.data[0]

        if appt["user_id"] != current_user.id: 
            raise HTTPException(status_code=403, detail="Bạn không có quyền thực hiện thao tác này!")
        if appt["status"] != "SERVED": 
            raise HTTPException(status_code=400, detail="Cơ sở chưa phục vụ xong, không thể xác nhận!")

        # 2. Xử lý giải ngân an toàn
        booking_id = appt.get("booking_id")
        if booking_id:
            booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
            if booking_res.data:
                booking = booking_res.data[0]
                if booking["payment_status"] == "PAID" and booking["service_status"] != "COMPLETED":
                    total = float(booking["total_amount"])
                    partner_rev = total * 0.70
                    platform_fee = total * 0.20
                    affiliate_rev = total * 0.10 if booking.get("affiliate_id") else 0
                    if not booking.get("affiliate_id"): 
                        platform_fee += total * 0.10

                    # 2.1. Chốt đơn Escrow
                    supabase.table("bookings_transactions").update({
                        "service_status": "COMPLETED", 
                        "partner_revenue": partner_rev, 
                        "platform_fee": platform_fee, 
                        "affiliate_revenue": affiliate_rev
                    }).eq("id", booking_id).execute()

                    # 2.2. Cộng tiền vào Ví cho Partner
                    wallet_res = supabase.table("wallets").select("*").eq("user_id", appt["partner_id"]).execute()
                    if wallet_res.data:
                        new_balance = float(wallet_res.data[0]["balance"]) + partner_rev
                        new_earned = float(wallet_res.data[0]["total_earned"]) + partner_rev
                        supabase.table("wallets").update({
                            "balance": new_balance, 
                            "total_earned": new_earned
                        }).eq("user_id", appt["partner_id"]).execute()
                    else:
                        supabase.table("wallets").insert({
                            "user_id": appt["partner_id"], 
                            "balance": partner_rev, 
                            "total_earned": partner_rev
                        }).execute()

        # 3. Đóng Lịch hẹn (Xóa bỏ cột feedback không tồn tại)
        supabase.table("appointments").update({
            "status": "COMPLETED", 
            "user_confirmed": True
        }).eq("id", appointment_id).execute()

        return {"status": "success", "message": "Cảm ơn bạn! Đã giải ngân thành công cho đối tác."}
    
    except HTTPException as he:
        raise he
    except Exception as e:
        print(f"[LỖI XÁC NHẬN NGHIÊM TRỌNG]: {str(e)}")
        raise HTTPException(status_code=500, detail="Lỗi hệ thống khi giải ngân. Vui lòng liên hệ Admin!")


@app.patch("/appointments/{appointment_id}/cancel", tags=["Scheduling"])
def cancel_appointment(appointment_id: str, current_user = Depends(verify_user_token)):
    """BỔ SUNG: Người dùng chủ động hủy lịch để giải phóng slot cho cơ sở"""
    try:
        appt_res = supabase.table("appointments").select("*").eq("id", appointment_id).single().execute()
        if not appt_res.data: raise HTTPException(status_code=404, detail="Không tìm thấy lịch")
        appt = appt_res.data

        if appt["user_id"] != current_user.id:
            raise HTTPException(status_code=403, detail="Bạn không có quyền hủy lịch này!")

        # Chỉ cho phép hủy khi chưa thanh toán hoặc đang chờ duyệt
        if appt["status"] not in ["WAITING_PARTNER", "PENDING_PAYMENT"]:
             raise HTTPException(status_code=400, detail="Lịch đã chốt hoặc đã thanh toán không thể tự hủy!")

        supabase.table("appointments").update({
            "status": "CANCELLED", 
            "rejection_reason": "Người dùng chủ động hủy bỏ yêu cầu"
        }).eq("id", appointment_id).execute()
        
        return {"status": "success", "message": "Đã hủy yêu cầu đặt lịch thành công."}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))


# ==========================================
# 12. PAYOS WEBHOOK (ĐẢM BẢO KHÔNG RỚT ĐƠN)
# ==========================================
from fastapi import Request

@app.post("/payos/webhook", tags=["Payment"])
async def payos_webhook(request: Request):
    """PayOS sẽ âm thầm gọi API này khi nhận được tiền từ Ngân hàng"""
    try:
        body = await request.json()
        
        # Kiểm tra xem có phải giao dịch thành công (Mã 00) không
        if body.get("success") and body.get("code") == "00":
            data = body.get("data", {})
            orderCode = data.get("orderCode")
            
            # 1. Tìm đơn hàng
            booking_res = supabase.table("bookings_transactions").select("*").eq("order_code", orderCode).single().execute()
            if booking_res.data and booking_res.data["payment_status"] != "PAID":
                booking_id = booking_res.data["id"]
                
                # 2. Cập nhật Đơn hàng -> PAID
                supabase.table("bookings_transactions").update({"payment_status": "PAID"}).eq("id", booking_id).execute()
                
                # 3. Cập nhật Lịch hẹn -> CONFIRMED
                supabase.table("appointments").update({"status": "CONFIRMED"}).eq("booking_id", booking_id).execute()
                print(f"[Webhook] Đã xác nhận thành công đơn {orderCode}")

        return {"success": True, "message": "Webhook received"}
    except Exception as e:
        print(f"[Webhook Error]: {str(e)}")
        return {"success": False}

# ==========================================
# 13. HỆ THỐNG BẢN ĐỒ (LEAFLET MAP HUB)
# ==========================================
@app.get("/map/partners", tags=["Map"])
def get_map_partners():
    """API lấy danh sách Đối tác có tọa độ để render lên Bản đồ"""
    try:
        # 1. Chỉ tìm PARTNER_ADMIN vì Database Enum không có giá trị PARTNER
        res_partners = supabase.table("users").select(
            "id, full_name, username, avatar_url, physical_address, latitude, longitude"
        ).eq("role", "PARTNER_ADMIN").execute()
        
        # Lọc toạ độ IS NOT NULL bằng Python thuần để triệt tiêu hoàn toàn lỗi cú pháp Supabase
        raw_partners = res_partners.data or []
        partners = [p for p in raw_partners if p.get("latitude") is not None and p.get("longitude") is not None]
        
        if not partners:
            return {"status": "success", "data": []}
            
        # 2. Lấy dịch vụ (Approved) của các Partner này
        partner_ids = [p["id"] for p in partners]
        res_services = supabase.table("services").select(
            "id, partner_id, service_name, price, service_type"
        ).eq("status", "APPROVED").in_("partner_id", partner_ids).execute()
        
        services = res_services.data or []
        
        # 3. Gom nhóm Dịch vụ theo Partner
        from collections import defaultdict
        services_map = defaultdict(list)
        for s in services:
            services_map[s["partner_id"]].append(s)
            
        # 4. Lắp ráp dữ liệu chuẩn bị cho Frontend
        for p in partners:
            p_services = services_map.get(p["id"], [])
            p["services"] = p_services[:3] # Chỉ lấy 3 dịch vụ tiêu biểu cho Card Map
            
            # Lấy trực tiếp loại hình dịch vụ để khớp với Filter Frontend
            raw_tags = list(set([s.get("service_type") for s in p_services if s.get("service_type")]))
            # Map dữ liệu chuẩn: TREATMENT -> Trị liệu, RELAXATION -> Massage, v.v..
            p["tags"] = raw_tags if raw_tags else ["Cơ sở Y tế"]
            
            # Gắn khoảng cách giả định (Sẽ được tính toán chuẩn tại Frontend dựa trên GPS người dùng)
            p["distance"] = round(random.uniform(0.5, 5.0), 1)

        return {"status": "success", "data": partners}
    except Exception as e:
        print(f"[MAP API ERROR]: {str(e)}")
        raise HTTPException(status_code=500, detail="Lỗi trích xuất dữ liệu không gian")

# ==========================================
# 14. HỆ THỐNG FOLLOW (QUAN TÂM DOANH NGHIỆP)
# ==========================================
@app.post("/user/follow/{target_id}", tags=["Follow"])
def toggle_follow(target_id: str, current_user = Depends(verify_user_token)):
    """API Toggle: Nhấn để Follow, nhấn lại để Unfollow"""
    if target_id == current_user.id:
        raise HTTPException(status_code=400, detail="Bạn không thể tự theo dõi chính mình!")
    
    try:
        # 1. Kiểm tra đối tác có tồn tại không
        target_check = supabase.table("users").select("id").eq("id", target_id).execute()
        if not target_check.data:
            raise HTTPException(status_code=404, detail="Người dùng không tồn tại!")

        # 2. Kiểm tra trạng thái Follow hiện tại
        exist = supabase.table("user_follows").select("id").eq("follower_id", current_user.id).eq("following_id", target_id).execute()
        
        if exist.data:
            # Đã follow -> Thực hiện Unfollow
            supabase.table("user_follows").delete().eq("follower_id", current_user.id).eq("following_id", target_id).execute()
            return {"status": "success", "action": "unfollowed", "message": "Đã bỏ quan tâm cơ sở này."}
        else:
            # Chưa follow -> Thực hiện Follow
            supabase.table("user_follows").insert({
                "follower_id": current_user.id, 
                "following_id": target_id
            }).execute()
            return {"status": "success", "action": "followed", "message": "Đã quan tâm cơ sở thành công!"}
            
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/user/follow-status/{target_id}", tags=["Follow"])
def check_follow_status(target_id: str, current_user = Depends(verify_user_token)):
    """API Check: Frontend gọi hàm này để biết nút hiển thị 'Quan tâm' hay 'Đang theo dõi'"""
    try:
        exist = supabase.table("user_follows").select("id").eq("follower_id", current_user.id).eq("following_id", target_id).execute()
        return {"status": "success", "is_followed": len(exist.data) > 0}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# 15. HỆ THỐNG THÔNG BÁO (NOTIFICATIONS)
# ==========================================
@app.get("/notifications", tags=["Notifications"])
def get_my_notifications(limit: int = 50, current_user = Depends(verify_user_token)):
    """Lấy danh sách thông báo của người dùng hiện tại"""
    try:
        res = supabase.table("notifications").select("*").eq("user_id", current_user.id).order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/notifications/{notification_id}/read", tags=["Notifications"])
def mark_notification_read(notification_id: str, current_user = Depends(verify_user_token)):
    """Đánh dấu 1 thông báo là đã đọc"""
    try:
        # Bảo mật: Chỉ cho phép người dùng tự đổi trạng thái thông báo của mình
        supabase.table("notifications").update({"is_read": True}).eq("id", notification_id).eq("user_id", current_user.id).execute()
        return {"status": "success"}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/notifications/read-all", tags=["Notifications"])
def mark_all_notifications_read(current_user = Depends(verify_user_token)):
    """Đánh dấu TẤT CẢ thông báo là đã đọc"""
    try:
        supabase.table("notifications").update({"is_read": True}).eq("user_id", current_user.id).eq("is_read", False).execute()
        return {"status": "success"}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))