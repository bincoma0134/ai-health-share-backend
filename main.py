from fastapi import FastAPI, HTTPException, Depends, Security
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import uuid
import urllib.request
import json
import os
import time
import random
from datetime import datetime, timedelta
from fastapi import UploadFile, File 


# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "YOUR_CLIENT_ID")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "YOUR_API_KEY")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "YOUR_CHECKSUM_KEY")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(title="AI Health Share API", version="5.0.0")
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
def health_check(): return {"status": "success", "message": "Server FastAPI đang hoạt động!"}

# ==========================================
# 1. SERVICES & INTERACTIONS
# ==========================================
@app.get("/services", tags=["Services"])
def get_services(user_id: str = None):
    try:
        services = supabase.table("services").select("*").eq("status", "APPROVED").execute().data
        
        partner_ids = list(set([s["partner_id"] for s in services if s.get("partner_id")]))
        partners = supabase.table("users").select("id, avatar_url, full_name").in_("id", partner_ids).execute().data
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
        user_data = supabase.table("users").select("role").eq("id", current_user.id).single().execute().data
        if not user_data or user_data.get("role") not in ["PARTNER_ADMIN", "SUPER_ADMIN"]:
            raise HTTPException(status_code=403, detail="BẢO MẬT: Chỉ Doanh nghiệp mới có quyền đăng dịch vụ!")

        service_data = payload.model_dump()
        service_data["partner_id"] = current_user.id 
        
        res = supabase.table("services").insert(service_data).execute()
        return {"status": "success", "data": res.data[0] if res.data else {}}
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
# 2. COMMENTS
# ==========================================
@app.get("/comments/{service_id}", tags=["Comments"])
def get_comments_nested(service_id: str, user_id: str = None):
    try:
        res = supabase.table("service_comments").select(
            "*, users(id, full_name, avatar_url, role)"
        ).eq("service_id", service_id).order("created_at", desc=False).execute()
        
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
        raise HTTPException(status_code=500, detail=f"Lỗi hệ thống: {str(e)}")

@app.post("/comments", tags=["Comments"])
def add_comment(payload: schemas.CommentCreate, current_user = Depends(verify_user_token)):
    try:
        insert_data = {
            "user_id": current_user.id,
            "service_id": payload.service_id,
            "content": payload.content,
            "parent_id": payload.parent_id 
        }
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

@app.post("/comments/{comment_id}/like", tags=["Comments"])
def toggle_comment_like(comment_id: str, current_user = Depends(verify_user_token)):
    try:
        existing = supabase.table("comment_likes").select("id").eq("user_id", current_user.id).eq("comment_id", comment_id).execute().data
        if existing:
            supabase.table("comment_likes").delete().eq("user_id", current_user.id).eq("comment_id", comment_id).execute()
            return {"status": "success", "action": "unliked"}
        else:
            supabase.table("comment_likes").insert({"user_id": current_user.id, "comment_id": comment_id}).execute()
            return {"status": "success", "action": "liked"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# ==========================================
# 3. BOOKINGS
# ==========================================
@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate, current_user = Depends(verify_user_token)):
    try:
        booking_data = booking.model_dump()
        service_id = booking_data.get("service_id")
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        clean_payload = {
            "user_id": current_user.id, "service_id": service_id,
            "total_amount": booking_data.get("total_amount"),
            "payment_status": "UNPAID", "service_status": "PENDING", "order_code": order_code
        }
        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        try:
            payment_data = PaymentData(orderCode=order_code, amount=int(booking_data.get("total_amount")), description=f"Thanh toan don {order_code}", returnUrl="http://localhost:3000/partner", cancelUrl="http://localhost:3000/")
            checkout_url = payos_client.createPaymentLink(paymentData=payment_data).checkoutUrl
        except: checkout_url = None 
        return {"status": "success", "data": data.data[0], "checkout_url": checkout_url}
    except Exception as e: raise HTTPException(status_code=400, detail=str(e))

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    pass 

# ==========================================
# 4. USER PROFILE 
# ==========================================
@app.get("/user/profile", tags=["User"])
def get_user_profile(current_user = Depends(verify_user_token)):
    user = supabase.table("users").select("id, email, role, created_at, full_name, bio, avatar_url, cover_url, theme_preference").eq("id", current_user.id).single().execute().data
    
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
            "profile": user,
            "stats": stats,
            "saved_services": [s["services"] for s in saves.data if s.get("services")] if saves.data else [],
            "bookings": bookings.data or []
        }
    }

@app.patch("/user/profile", tags=["User"])
def update_user_profile(payload: dict, current_user = Depends(verify_user_token)):
    update_data = {k: v for k, v in payload.items() if v is not None}
    res = supabase.table("users").update(update_data).eq("id", current_user.id).execute()
    return {"status": "success", "data": res.data[0] if res.data else {}}

# ==========================================
# 5. PARTNER PROFILE & REVIEWS
# ==========================================
@app.get("/partner/profile/{partner_id}", tags=["Partner"])
def get_partner_public_profile(partner_id: str):
    try:
        partner = supabase.table("users").select("id, full_name, bio, avatar_url, cover_url, reputation_points").eq("id", partner_id).single().execute().data
        if not partner: raise HTTPException(status_code=404, detail="Không tìm thấy doanh nghiệp")
        
        services = supabase.table("services").select("*").eq("partner_id", partner_id).eq("status", "APPROVED").execute().data or []
        
        reviews = supabase.table("partner_reviews").select("*, users!partner_reviews_user_id_fkey(full_name, avatar_url)").eq("partner_id", partner_id).order("created_at", desc=True).execute().data or []
        
        avg_rating = sum([r["rating"] for r in reviews]) / len(reviews) if reviews else 0.0

        return {
            "status": "success",
            "data": {
                "profile": partner,
                "services": services,
                "reviews": reviews,
                "stats": {"avg_rating": round(avg_rating, 1), "total_reviews": len(reviews), "total_services": len(services)}
            }
        }
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))
    
@app.post("/partner/reviews", tags=["Partner"])
def submit_partner_review(payload: dict, current_user = Depends(verify_user_token)):
    partner_id = payload.get("partner_id")
    rating = payload.get("rating", 5)
    comment = payload.get("comment", "")

    services_res = supabase.table("services").select("id").eq("partner_id", partner_id).execute()
    service_ids = [s["id"] for s in services_res.data] if services_res.data else []
    if not service_ids: raise HTTPException(status_code=400, detail="Doanh nghiệp này chưa có dịch vụ nào.")

    bookings_res = supabase.table("bookings_transactions").select("id").eq("user_id", current_user.id).eq("service_status", "COMPLETED").in_("service_id", service_ids).execute()
    if not bookings_res.data: raise HTTPException(status_code=403, detail="BẢO MẬT: Bạn cần thanh toán và trải nghiệm dịch vụ trước khi đánh giá!")

    existing = supabase.table("partner_reviews").select("id").eq("user_id", current_user.id).eq("partner_id", partner_id).execute()
    if existing.data: raise HTTPException(status_code=400, detail="Bạn đã đánh giá chuyên gia này rồi!")

    try:
        new_review = supabase.table("partner_reviews").insert({
            "user_id": current_user.id, "partner_id": partner_id, "rating": rating, "comment": comment
        }).execute().data[0]

        partner_data = supabase.table("users").select("reputation_points").eq("id", partner_id).single().execute().data
        current_points = partner_data.get("reputation_points") or 0
        supabase.table("users").update({"reputation_points": current_points + rating}).eq("id", partner_id).execute()

        user_data = supabase.table("users").select("full_name, avatar_url").eq("id", current_user.id).execute().data[0]
        new_review["users"] = user_data
        
        return {"status": "success", "data": new_review}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# ==========================================
# 6. MODERATION
# ==========================================
@app.get("/moderation/services", tags=["Moderation"])
def get_pending_services(current_user = Depends(verify_user_token)):
    user_data = supabase.table("users").select("role").eq("id", current_user.id).single().execute().data
    if not user_data or user_data.get("role") not in ["MODERATOR", "SUPER_ADMIN"]:
        raise HTTPException(status_code=403, detail="BẢO MẬT: Chỉ Kiểm duyệt viên mới có quyền truy cập!")
    
    services = supabase.table("services").select("*, users(full_name, email, avatar_url)").eq("status", "PENDING").order("created_at", desc=True).execute().data
    return {"status": "success", "data": services}

@app.patch("/moderation/services/{service_id}", tags=["Moderation"])
def moderate_service(service_id: str, payload: dict, current_user = Depends(verify_user_token)):
    user_data = supabase.table("users").select("role").eq("id", current_user.id).single().execute().data
    if not user_data or user_data.get("role") not in ["MODERATOR", "SUPER_ADMIN"]:
        raise HTTPException(status_code=403, detail="BẢO MẬT: Chỉ Kiểm duyệt viên mới có quyền duyệt bài!")
    
    status = payload.get("status")
    note = payload.get("moderation_note", "")
    if status not in ["APPROVED", "REJECTED"]: raise HTTPException(status_code=400, detail="Trạng thái không hợp lệ.")
        
    res = supabase.table("services").update({"status": status, "moderation_note": note, "moderated_by": current_user.id}).eq("id", service_id).execute()
    return {"status": "success", "data": res.data[0] if res.data else {}}

# ==========================================
# 7. PARTNER BACKSTAGE API
# ==========================================
@app.get("/partner/my-services", tags=["Partner"])
def get_my_services(current_user = Depends(verify_user_token)):
    user_data = supabase.table("users").select("role").eq("id", current_user.id).single().execute().data
    if not user_data or user_data.get("role") not in ["PARTNER_ADMIN", "SUPER_ADMIN"]:
        raise HTTPException(status_code=403, detail="BẢO MẬT: Chỉ Doanh nghiệp mới xem được khu vực này!")
        
    services = supabase.table("services").select("*").eq("partner_id", current_user.id).order("created_at", desc=True).execute().data
    return {"status": "success", "data": services}

# ==========================================
# 8. AI ASSISTANT (Groq & Supabase History)
# ==========================================
from groq import Groq

GROQ_API_KEY = os.environ.get("GROQ_API_KEY", "")
groq_client = Groq(api_key=GROQ_API_KEY) if GROQ_API_KEY else None

@app.get("/ai/history", tags=["AI Assistant"])
def get_chat_history(current_user = Depends(verify_user_token)):
    try:
        res = supabase.table("ai_chat_history").select("*").eq("user_id", current_user.id).order("created_at", desc=False).limit(20).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/ai/chat", tags=["AI Assistant"])
def chat_with_llama(payload: schemas.AIChatRequest, current_user = Depends(verify_user_token)):
    try:
        system_prompt = {
            "role": "system",
            "content": """Bạn là Trợ lý AI Health. 
            QUY TẮC TRÌNH BÀY BẮT BUỘC:
            - Sử dụng Markdown để định dạng văn bản.
            - Phân cấp thông tin bằng tiêu đề (##) và danh sách gạch đầu dòng (-).
            - Nhấn mạnh các từ khóa quan trọng bằng chữ in đậm (**text**).
            - Ngắn gọn, súc tích, đi thẳng vào vấn đề. 
            - Luôn có một dòng nhắc nhở khám bác sĩ chuyên khoa ở cuối câu trả lời."""
        }

        messages = [system_prompt]
        for msg in payload.messages:
            role = "assistant" if msg.role == "bot" else "user"
            messages.append({"role": role, "content": msg.content})

        chat_completion = groq_client.chat.completions.create(
            messages=messages,
            model="llama-3.1-8b-instant",
            temperature=0.6,
            max_tokens=1024,
        )

        reply_text = chat_completion.choices[0].message.content

        user_msg = payload.messages[-1].content
        supabase.table("ai_chat_history").insert([
            {"user_id": current_user.id, "role": "user", "content": user_msg},
            {"user_id": current_user.id, "role": "assistant", "content": reply_text}
        ]).execute()

        return {"status": "success", "data": {"reply": reply_text}}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi AI: {str(e)}")

# ==========================================
# 9. NOTIFICATIONS CENTER
# ==========================================
@app.get("/notifications", tags=["Notifications"])
def get_notifications(current_user = Depends(verify_user_token)):
    try:
        res = supabase.table("notifications").select("*").eq("user_id", current_user.id).order("created_at", desc=True).limit(50).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.patch("/notifications/{notif_id}/read", tags=["Notifications"])
def mark_notification_read(notif_id: str, current_user = Depends(verify_user_token)):
    try:
        res = supabase.table("notifications").update({"is_read": True}).eq("id", notif_id).eq("user_id", current_user.id).execute()
        return {"status": "success", "data": res.data[0] if res.data else {}}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))



# ==========================================
# 10. CỘNG ĐỒNG (COMMUNITY API)
# ==========================================

@app.get("/community/posts", tags=["Community"])
def get_posts(limit: int = 50):
    """Lấy danh sách bài viết mới nhất kèm thông tin người đăng"""
    try:
        # Lấy bài viết và join với bảng users để lấy tên, avatar, role
        res = supabase.table("posts").select(
            "*, author:users(full_name, avatar_url, role)"
        ).order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi lấy bài viết: {str(e)}")


@app.post("/community/posts", tags=["Community"])
def create_post(post: schemas.PostCreate, current_user = Depends(verify_user_token)):
    """Đăng bài viết mới"""
    try:
        data = {
            "author_id": current_user.id,
            "content": post.content,
            "image_url": post.image_url
        }
        res = supabase.table("posts").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi đăng bài: {str(e)}")


@app.post("/community/posts/{post_id}/comments", tags=["Community"])
def add_comment(post_id: str, comment: schemas.CommentCreate, current_user = Depends(verify_user_token)):
    """Thêm bình luận vào bài viết"""
    try:
        data = {
            "post_id": post_id,
            "user_id": current_user.id,
            "content": comment.content
        }
        res = supabase.table("post_comments").insert(data).execute()
        
        # Tăng biến đếm comments_count trong bảng posts
        # (Trong thực tế nên dùng Trigger của DB, nhưng MVP ta gọi update luôn cho nhanh)
        post_data = supabase.table("posts").select("comments_count").eq("id", post_id).execute()
        if post_data.data:
            current_count = post_data.data[0].get("comments_count", 0)
            supabase.table("posts").update({"comments_count": current_count + 1}).eq("id", post_id).execute()

        return {"status": "success", "message": "Đã thêm bình luận"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/community/posts/{post_id}/like", tags=["Community"])
def toggle_like(post_id: str, current_user = Depends(verify_user_token)):
    """Thích / Bỏ thích bài viết"""
    try:
        # Kiểm tra xem user đã like chưa
        existing = supabase.table("post_likes").select("*").eq("post_id", post_id).eq("user_id", current_user.id).execute()
        post_data = supabase.table("posts").select("likes_count").eq("id", post_id).execute()
        current_likes = post_data.data[0].get("likes_count", 0) if post_data.data else 0

        if existing.data:
            # Đã like -> Hủy like (Unlike)
            supabase.table("post_likes").delete().eq("post_id", post_id).eq("user_id", current_user.id).execute()
            supabase.table("posts").update({"likes_count": max(0, current_likes - 1)}).eq("id", post_id).execute()
            return {"status": "success", "action": "unliked"}
        else:
            # Chưa like -> Thêm like
            supabase.table("post_likes").insert({"post_id": post_id, "user_id": current_user.id}).execute()
            supabase.table("posts").update({"likes_count": current_likes + 1}).eq("id", post_id).execute()
            return {"status": "success", "action": "liked"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))



# ==========================================
# 11. XỬ LÝ MEDIA / UPLOAD
# ==========================================

@app.post("/upload/image", tags=["Media"])
async def upload_image(file: UploadFile = File(...), current_user = Depends(verify_user_token)):
    """Upload ảnh lên Supabase Storage và trả về Public URL"""
    try:
        # 1. Tạo tên file độc nhất để tránh trùng lặp hoặc bị ghi đè
        file_ext = file.filename.split(".")[-1]
        file_name = f"community/{current_user.id}_{int(time.time())}.{file_ext}"
        
        # 2. Đọc dữ liệu file
        file_bytes = await file.read()
        
        # 3. Upload lên bucket có tên 'media' của Supabase 
        # (Lưu ý: Cậu cần vào Supabase -> Storage -> Tạo một bucket tên là 'media' và để ở chế độ Public)
        res = supabase.storage.from_("community_media").upload(
            file_name, 
            file_bytes, 
            {"content-type": file.content_type}
        )
        
        # 4. Lấy URL public của ảnh vừa upload
        public_url = supabase.storage.from_("media").get_public_url(file_name)
        
        return {"status": "success", "data": {"image_url": public_url}}
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Lỗi upload ảnh: {str(e)}")