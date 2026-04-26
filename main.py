from fastapi import FastAPI, HTTPException, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import time
import random
import os
from datetime import datetime
from fastapi import UploadFile, File 

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "YOUR_CLIENT_ID")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "YOUR_API_KEY")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "YOUR_CHECKSUM_KEY")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(title="AI Health Share API", version="5.1.0")
security = HTTPBearer()

# --- XÁC THỰC NGƯỜI DÙNG ---
def verify_user_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        user_data = supabase.auth.get_user(token)
        return user_data.user
    except Exception:
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn!")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"]
)

@app.get("/")
def health_check(): 
    return {"status": "success", "message": "Backend AI Health đang chạy mượt mà!"}

# ==========================================
# 1. SERVICES (DỊCH VỤ CƠ SỞ)
# ==========================================
@app.get("/services", tags=["Services"])
def get_services(user_id: str = None):
    try:
        services = supabase.table("services").select("*").eq("status", "APPROVED").execute().data
        partner_ids = list(set([s["partner_id"] for s in services if s.get("partner_id")]))
        partners = supabase.table("users").select("id, avatar_url, full_name, username").in_("id", partner_ids).execute().data
        p_dict = {p["id"]: p for p in partners}

        likes = supabase.table("user_likes").select("*").execute().data or []
        saves = supabase.table("user_saves").select("*").execute().data or []
        comments = supabase.table("service_comments").select("service_id").execute().data or []
        
        for s in services:
            s_id = s["id"]
            s["users"] = p_dict.get(s.get("partner_id"), {})
            s["likes_count"] = len([l for l in likes if l["service_id"] == s_id])
            s["saves_count"] = len([sv for sv in saves if sv["service_id"] == s_id])
            s["comments_count"] = len([c for c in comments if c["service_id"] == s_id])
            s["is_liked"] = any(l["user_id"] == user_id and l["service_id"] == s_id for l in likes) if user_id else False
            s["is_saved"] = any(sv["user_id"] == user_id and sv["service_id"] == s_id for sv in saves) if user_id else False
        return {"status": "success", "data": services}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/services", tags=["Services"])
def create_service(payload: schemas.ServiceCreate, current_user = Depends(verify_user_token)):
    try:
        service_data = payload.model_dump()
        service_data["partner_id"] = current_user.id
        service_data["status"] = "PENDING" 
        res = supabase.table("services").insert(service_data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/interactions/{action}", tags=["Interactions"])
def toggle_interaction(action: str, payload: dict, current_user = Depends(verify_user_token)):
    table = "user_likes" if action == "like" else "user_saves"
    sid = payload.get("service_id")
    existing = supabase.table(table).select("*").eq("user_id", current_user.id).eq("service_id", sid).execute()
    if existing.data:
        supabase.table(table).delete().eq("user_id", current_user.id).eq("service_id", sid).execute()
        return {"status": "success", "action": f"un{action}d"}
    else:
        supabase.table(table).insert({"user_id": current_user.id, "service_id": sid}).execute()
        return {"status": "success", "action": f"{action}d"}

# ==========================================
# 2. BOOKINGS (BẢO CHỨNG ESCROW)
# ==========================================
@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate, current_user = Depends(verify_user_token)):
    try:
        booking_data = booking.model_dump()
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        
        clean_payload = {
            "user_id": current_user.id, 
            "service_id": booking_data.get("service_id"),
            "video_id": booking_data.get("video_id"),
            "total_amount": booking_data.get("total_amount"),
            "payment_status": "UNPAID", 
            "service_status": "PENDING", 
            "order_code": order_code,
            "customer_name": booking_data.get("customer_name"),
            "customer_phone": booking_data.get("customer_phone"),
            "note": booking_data.get("note")
        }
        clean_payload = {k: v for k, v in clean_payload.items() if v is not None}
        
        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        
        try:
            payment_data = PaymentData(
                orderCode=order_code, 
                amount=int(booking_data.get("total_amount")), 
                description=f"Thanh toan don {order_code}", 
                returnUrl="http://localhost:3000/", 
                cancelUrl="http://localhost:3000/"
            )
            checkout_url = payos_client.createPaymentLink(paymentData=payment_data).checkoutUrl
        except: 
            checkout_url = None 
            
        return {"status": "success", "data": data.data[0], "checkout_url": checkout_url}
    except Exception as e: 
        raise HTTPException(status_code=400, detail=str(e))

# ==========================================
# 3. COMMENTS
# ==========================================
@app.get("/comments/{service_id}", tags=["Comments"])
def get_comments_nested(service_id: str, user_id: str = None):
    try:
        res = supabase.table("service_comments").select("*, users(id, full_name, avatar_url, role)").eq("service_id", service_id).order("created_at", desc=False).execute()
        all_comments = res.data or []
        comment_ids = [c["id"] for c in all_comments]
        likes_dict = {}
        
        if comment_ids:
            likes_res = supabase.table("comment_likes").select("*").in_("comment_id", comment_ids).execute()
            for l in likes_res.data:
                likes_dict.setdefault(l["comment_id"], []).append(l["user_id"])

        comment_map = {}
        roots = []

        for c in all_comments:
            c_id = c["id"]
            likes = likes_dict.get(c_id, [])
            c["likes_count"] = len(likes)
            c["is_liked"] = user_id in likes if user_id else False
            c["replies"] = [] 
            comment_map[c_id] = c

        for c in all_comments:
            p_id = c.get("parent_id")
            if p_id and p_id in comment_map:
                comment_map[p_id]["replies"].append(c)
            else:
                roots.append(c)

        roots.sort(key=lambda x: x.get("is_pinned", False), reverse=True)
        return {"status": "success", "data": roots}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/comments", tags=["Comments"])
def add_comment(payload: schemas.CommentCreate, current_user = Depends(verify_user_token)):
    try:
        insert_data = {"user_id": current_user.id, "service_id": payload.service_id, "content": payload.content, "parent_id": payload.parent_id}
        res = supabase.table("service_comments").insert(insert_data).execute()
        if not res.data: raise Exception("Không thể lưu bình luận")
        new_comment = res.data[0]
        user_info = supabase.table("users").select("id, full_name, avatar_url, role").eq("id", current_user.id).single().execute()
        new_comment["users"] = user_info.data
        new_comment["likes_count"] = 0
        new_comment["is_liked"] = False
        new_comment["replies"] = []
        return {"status": "success", "data": new_comment}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# ==========================================
# 4. USER PROFILE 
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

        saves = supabase.table("user_saves").select("services(*)").eq("user_id", current_user.id).order("created_at", desc=True).execute()
        bookings = supabase.table("bookings_transactions").select("*, services(service_name)").eq("user_id", current_user.id).order("created_at", desc=True).execute()
        likes_count = supabase.table("user_likes").select("id", count="exact").eq("user_id", current_user.id).execute().count or 0
        
        stats = {
            "saved_count": len(saves.data or []), 
            "bookings_count": len(bookings.data or []), 
            "likes_count": likes_count
        }

        if user and user.get("role") in ["MODERATOR", "SUPER_ADMIN"]:
            pending_res = supabase.table("services").select("id", count="exact").eq("status", "PENDING").execute()
            handled_res = supabase.table("services").select("id", count="exact").eq("moderated_by", current_user.id).execute()
            stats["pendingTotal"] = pending_res.count or 0
            stats["approvedByMe"] = handled_res.count or 0

        return {
            "status": "success",
            "data": {
                "profile": user, "stats": stats,
                "saved_services": [s["services"] for s in saves.data if s.get("services")] if saves.data else [],
                "bookings": bookings.data or []
            }
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi máy chủ Profile: {str(e)}")

@app.patch("/user/profile", tags=["User"])
def update_user_profile(payload: dict, current_user = Depends(verify_user_token)):
    res = supabase.table("users").update(payload).eq("id", current_user.id).execute()
    return {"status": "success", "data": res.data[0] if res.data else {}}

# ==========================================
# 5. PARTNER BACKSTAGE
# ==========================================
@app.get("/partner/my-services", tags=["Partner"])
def get_my_services(current_user = Depends(verify_user_token)):
    services = supabase.table("services").select("*").eq("partner_id", current_user.id).order("created_at", desc=True).execute().data
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

# ==========================================
# 6. COMMUNITY (BÀI VIẾT DIỄN ĐÀN)
# ==========================================
@app.get("/community/posts", tags=["Community"])
def get_community_posts(limit: int = 50):
    try:
        res = supabase.table("posts").select("*, author:users(full_name, avatar_url, role)").order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/community/posts", tags=["Community"])
def create_community_post(post: schemas.CommunityPostCreate, current_user = Depends(verify_user_token)):
    try:
        data = {"author_id": current_user.id, "content": post.content, "image_url": post.image_url}
        res = supabase.table("posts").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# 7. STUDIO VIDEOS (TIKTOK FEED TRANG CHỦ)
# ==========================================
@app.get("/studio/videos", tags=["Studio"])
def get_studio_videos(limit: int = 50):
    """Lấy video đã duyệt để hiển thị Trang chủ"""
    try:
        res = supabase.table("studio_videos").select(
            "*, author:users(full_name, avatar_url, username, role)"
        ).eq("status", "APPROVED").order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi Studio: {str(e)}")

@app.post("/studio/videos", tags=["Studio"])
def create_studio_video(payload: schemas.StudioVideoCreate, current_user = Depends(verify_user_token)):
    """Partner đăng video lên Studio"""
    try:
        data = {
            "author_id": current_user.id,
            "title": payload.title,
            "content": payload.content,
            "video_url": payload.video_url,
            "price": payload.price,
            "status": "PENDING" 
        }
        res = supabase.table("studio_videos").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/studio/videos/{video_id}/{action}", tags=["Studio"])
def toggle_studio_interaction(video_id: str, action: str, current_user = Depends(verify_user_token)):
    """Thích hoặc Lưu video Studio"""
    table = "studio_likes" if action == "like" else "studio_saves"
    count_field = "likes_count" if action == "like" else "saves_count"
    try:
        existing = supabase.table(table).select("id").eq("video_id", video_id).eq("user_id", current_user.id).execute()
        video_res = supabase.table("studio_videos").select(count_field).eq("id", video_id).execute()
        current_count = video_res.data[0].get(count_field, 0) if video_res.data else 0

        if existing.data:
            supabase.table(table).delete().eq("video_id", video_id).eq("user_id", current_user.id).execute()
            supabase.table("studio_videos").update({count_field: max(0, current_count - 1)}).eq("id", video_id).execute()
            return {"status": "success", "action": f"un{action}d"}
        else:
            supabase.table(table).insert({"video_id": video_id, "user_id": current_user.id}).execute()
            supabase.table("studio_videos").update({count_field: current_count + 1}).eq("id", video_id).execute()
            return {"status": "success", "action": f"{action}d"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
@app.get("/partner/my-videos", tags=["Partner"])
def get_my_videos(current_user = Depends(verify_user_token)):
    """Lấy danh sách video Studio của chính Partner để theo dõi trạng thái duyệt"""
    try:
        res = supabase.table("studio_videos").select("*").eq("author_id", current_user.id).order("created_at", desc=True).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
# ==========================================
# 8. AI ASSISTANT (Groq)
# ==========================================
from groq import Groq
GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

@app.post("/ai/chat", tags=["AI Assistant"])
def chat_with_llama(payload: schemas.AIChatRequest, current_user = Depends(verify_user_token)):
    try:
        system_prompt = {"role": "system", "content": "Bạn là Trợ lý AI Health. Dùng Markdown. Ngắn gọn."}
        messages = [system_prompt]
        for msg in payload.messages:
            role = "assistant" if msg.role == "bot" else "user"
            messages.append({"role": role, "content": msg.content})

        chat_completion = groq_client.chat.completions.create(messages=messages, model="llama-3.1-8b-instant", temperature=0.6, max_tokens=1024)
        reply_text = chat_completion.choices[0].message.content

        supabase.table("ai_chat_history").insert([
            {"user_id": current_user.id, "role": "user", "content": payload.messages[-1].content},
            {"user_id": current_user.id, "role": "assistant", "content": reply_text}
        ]).execute()
        return {"status": "success", "data": {"reply": reply_text}}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=f"Lỗi AI: {str(e)}")

# ==========================================
# 9. NOTIFICATIONS
# ==========================================
@app.get("/notifications", tags=["Notifications"])
def get_notifications(current_user = Depends(verify_user_token)):
    try:
        res = supabase.table("notifications").select("*").eq("user_id", current_user.id).order("created_at", desc=True).limit(50).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

@app.patch("/notifications/{notif_id}/read", tags=["Notifications"])
def mark_notification_read(notif_id: str, current_user = Depends(verify_user_token)):
    try:
        res = supabase.table("notifications").update({"is_read": True}).eq("id", notif_id).eq("user_id", current_user.id).execute()
        return {"status": "success", "data": res.data[0] if res.data else {}}
    except Exception as e: 
        raise HTTPException(status_code=500, detail=str(e))

# ==========================================
# 10. AUTH HELPERS
# ==========================================
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