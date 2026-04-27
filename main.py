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
from groq import Groq

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "YOUR_CLIENT_ID")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "YOUR_API_KEY")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "YOUR_CHECKSUM_KEY")
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
    try:
        services = supabase.table("services").select("*").eq("status", "APPROVED").execute().data
        partner_ids = list(set([s["partner_id"] for s in services if s.get("partner_id")]))
        partners = supabase.table("users").select("id, avatar_url, full_name, username").in_("id", partner_ids).execute().data
        p_dict = {p["id"]: p for p in partners}
        for s in services:
            s["users"] = p_dict.get(s.get("partner_id"), {})
        return {"status": "success", "data": services}
    except Exception as e: raise HTTPException(status_code=400, detail=str(e))

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
@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate, current_user = Depends(verify_user_token)):
    try:
        booking_data = booking.model_dump()
        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)
        clean_payload = {
            "user_id": current_user.id, "service_id": booking_data.get("service_id"),
            "video_id": booking_data.get("video_id"), "total_amount": booking_data.get("total_amount"),
            "payment_status": "UNPAID", "service_status": "PENDING", "order_code": order_code,
            "customer_name": booking_data.get("customer_name"), "customer_phone": booking_data.get("customer_phone"),
            "note": booking_data.get("note")
        }
        clean_payload = {k: v for k, v in clean_payload.items() if v is not None}
        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        try:
            payment_data = PaymentData(orderCode=order_code, amount=int(booking_data.get("total_amount")), description=f"Thanh toan don {order_code}", returnUrl="http://localhost:3000/", cancelUrl="http://localhost:3000/")
            checkout_url = payos_client.createPaymentLink(paymentData=payment_data).checkoutUrl
        except: checkout_url = None 
        return {"status": "success", "data": data.data[0], "checkout_url": checkout_url}
    except Exception as e: raise HTTPException(status_code=400, detail=str(e))

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
            q_vid = supabase.table("studio_videos").select("id").in_("status", ["PENDING", "PENDING_DELETE"]).execute()
            stats["pending_total"] = len(q_svc.data or []) + len(q_vid.data or [])
            
            # 2. Đếm hiệu suất cá nhân
            s_done = supabase.table("services").select("status").eq("moderated_by", current_user.id).execute()
            v_done = supabase.table("studio_videos").select("status").eq("moderated_by", current_user.id).execute()
            all_done = (s_done.data or []) + (v_done.data or [])
            stats["total_processed"] = len(all_done)
            stats["approved_count"] = sum(1 for i in all_done if i.get("status") == "APPROVED")

        return {"status": "success", "data": {"profile": user, "stats": stats}}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/user/public/{username}", tags=["User"])
def get_public_profile(username: str):
    """API QUAN TRỌNG: Lấy thông tin công khai để hiển thị profile"""
    try:
        # Tìm user theo username (ILIKE để không phân biệt hoa thường)
        user_res = supabase.table("users").select("*").ilike("username", username).single().execute()
        if not user_res.data: raise HTTPException(status_code=404, detail="Người dùng không tồn tại!")
        
        user = user_res.data
        # Lấy video studio đã duyệt
        videos = supabase.table("studio_videos").select("*").eq("author_id", user["id"]).eq("status", "APPROVED").execute().data
        # Lấy dịch vụ đã duyệt
        services = supabase.table("services").select("*").eq("partner_id", user["id"]).eq("status", "APPROVED").execute().data
        
        return {
            "status": "success",
            "data": {
                "profile": user,
                "posts": videos or [], 
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

@app.get("/partner/my-videos", tags=["Partner"])
def get_my_videos(current_user = Depends(verify_user_token)):
    # Thêm .neq("status", "DELETED") để ẩn các mục đã xóa
    videos = supabase.table("studio_videos").select("*").eq("author_id", current_user.id).neq("status", "DELETED").order("created_at", desc=True).execute().data
    return {"status": "success", "data": videos}

@app.patch("/partner/my-videos/{video_id}", tags=["Partner"])
def update_my_video(video_id: str, payload: dict, current_user = Depends(verify_user_token)):
    update_data = {k: v for k, v in payload.items() if v is not None}
    update_data["status"] = "PENDING"
    res = supabase.table("studio_videos").update(update_data).eq("id", video_id).execute()
    return {"status": "success", "data": res.data[0]}

@app.delete("/partner/my-videos/{video_id}", tags=["Partner"])
def delete_my_video(video_id: str, current_user = Depends(verify_user_token)):
    res = supabase.table("studio_videos").update({"status": "PENDING_DELETE"}).eq("id", video_id).execute()
    return {"status": "success", "message": "Yêu cầu gỡ video đã được gửi đi"}
@app.get("/partner/bookings", tags=["Partner"])
def get_partner_bookings(current_user = Depends(verify_user_token)):
    """Lấy danh sách đơn hàng liên quan đến Dịch vụ hoặc Video của Partner này"""
    try:
        # Lấy tất cả ID dịch vụ và video của partner này
        my_services = supabase.table("services").select("id").eq("partner_id", current_user.id).execute()
        my_videos = supabase.table("studio_videos").select("id").eq("author_id", current_user.id).execute()
        
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
    """Giải ngân: Chỉ gọi được khi khách đã PAID. Tự động chia 70-20-10"""
    try:
        # 1. Kiểm tra đơn hàng
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).single().execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
        
        booking = booking_res.data
        
        if booking["payment_status"] != "PAID":
            raise HTTPException(status_code=400, detail="Khách hàng chưa thanh toán, không thể hoàn thành!")
            
        if booking["service_status"] == "COMPLETED":
            raise HTTPException(status_code=400, detail="Đơn này đã được giải ngân rồi!")

        # 2. Tính toán chia tiền (Logic bảo mật tại Server)
        total = float(booking["total_amount"])
        partner_rev = total * 0.70
        platform_fee = total * 0.20
        affiliate_rev = total * 0.10 if booking.get("affiliate_id") else 0
        
        if not booking.get("affiliate_id"):
            platform_fee += total * 0.10 # Nền tảng giữ luôn nếu ko có người giới thiệu

        # 3. Cập nhật Database
        update_data = {
            "service_status": "COMPLETED",
            "partner_revenue": partner_rev,
            "platform_fee": platform_fee,
            "affiliate_revenue": affiliate_rev
        }
        
        res = supabase.table("bookings_transactions").update(update_data).eq("id", booking_id).execute()
        
        return {
            "status": "success", 
            "message": "Giải ngân thành công",
            "distribution": update_data
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
# ==========================================
# 5. COMMUNITY & STUDIO VIDEOS
# ==========================================
@app.get("/community/posts", tags=["Community"])
def get_community_posts(limit: int = 50):
    try:
        res = supabase.table("posts").select("*, author:users(full_name, avatar_url, role)").order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/community/posts", tags=["Community"])
def create_community_post(post: schemas.CommunityPostCreate, current_user = Depends(verify_user_token)):
    try:
        data = {"author_id": current_user.id, "content": post.content, "image_url": post.image_url}
        res = supabase.table("posts").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/studio/videos", tags=["Studio"])
def get_studio_videos(limit: int = 50):
    try:
        res = supabase.table("studio_videos").select("*, author:users(full_name, avatar_url, username, role)").eq("status", "APPROVED").order("created_at", desc=True).limit(limit).execute()
        return {"status": "success", "data": res.data or []}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/studio/videos", tags=["Studio"])
def create_studio_video(payload: schemas.StudioVideoCreate, current_user = Depends(verify_user_token)):
    try:
        data = {"author_id": current_user.id, "title": payload.title, "content": payload.content, "video_url": payload.video_url, "price": payload.price, "status": "PENDING"}
        res = supabase.table("studio_videos").insert(data).execute()
        return {"status": "success", "data": res.data[0]}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.post("/studio/videos/{video_id}/{action}", tags=["Studio"])
def toggle_studio_interaction(video_id: str, action: str, current_user = Depends(verify_user_token)):
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

        services_res = supabase.table("services").select("*, users(full_name, email, avatar_url)").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).order("created_at", desc=True).execute()
        videos_res = supabase.table("studio_videos").select("*, author:users(full_name, email, avatar_url)").in_("status", ["PENDING", "PENDING_DELETE", "PENDING_UPDATE"]).order("created_at", desc=True).execute()

        services = services_res.data or []
        for s in services:
            s["type"] = "service"
            s["author"] = s.get("users") or {}
            
        videos = videos_res.data or []
        for v in videos:
            v["type"] = "video"
            
        combined = services + videos
        combined.sort(key=lambda x: str(x.get("created_at") or ""), reverse=True)

        return {"status": "success", "data": combined}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.patch("/moderation/action/{item_type}/{item_id}", tags=["Moderation"])
def moderate_item(item_type: str, item_id: str, payload: dict, current_user = Depends(verify_user_token)):
    try:
        action = payload.get("action")
        note = payload.get("note", "")
        table = "services" if item_type == "service" else "studio_videos"
        final_status = "DELETED" if action == "DELETED" else action
        
        # 1. Cập nhật trạng thái và ghi chú (Chắc chắn thành công)
        res = supabase.table(table).update({
            "status": final_status, 
            "moderation_note": note
        }).eq("id", item_id).execute()
        
        # 2. Lưu thời gian & người duyệt (Lớp giáp: Bỏ qua nếu DB chưa có cột này)
        try:
            supabase.table(table).update({
                "moderated_by": current_user.id,
                "updated_at": datetime.now().isoformat()
            }).eq("id", item_id).execute()
        except Exception: pass

        return {"status": "success", "message": f"Đã xử lý {action} thành công!"}
    except Exception as e: raise HTTPException(status_code=500, detail=str(e))

@app.get("/moderation/history", tags=["Moderation"])
def get_moderation_history(current_user = Depends(verify_user_token)):
    try:
        # Lớp giáp: Lấy theo moderated_by, nếu lỗi (chưa có cột) thì lấy tất cả bản ghi đã duyệt
        try:
            svcs = supabase.table("services").select("*, users(full_name, avatar_url)").eq("moderated_by", current_user.id).execute().data or []
        except Exception:
            svcs = supabase.table("services").select("*, users(full_name, avatar_url)").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []
            
        for s in svcs: 
            s["type"] = "service"
            s["author"] = s.get("users") or {}
        
        try:
            vids = supabase.table("studio_videos").select("*, author:users(full_name, avatar_url)").eq("moderated_by", current_user.id).execute().data or []
        except Exception:
            vids = supabase.table("studio_videos").select("*, author:users(full_name, avatar_url)").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []
            
        for v in vids: v["type"] = "video"
            
        combined = svcs + vids
        combined.sort(key=lambda x: str(x.get("updated_at") or x.get("created_at") or ""), reverse=True)
        return {"status": "success", "data": combined[:50]}
    except Exception as e: return {"status": "error", "message": str(e)}

@app.get("/moderation/stats", tags=["Moderation"])
def get_moderation_stats(current_user = Depends(verify_user_token)):
    try:
        # Lớp giáp an toàn tương tự
        try:
            s_done = supabase.table("services").select("status, created_at, updated_at").eq("moderated_by", current_user.id).execute().data or []
        except Exception:
            s_done = supabase.table("services").select("status, created_at, updated_at").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []

        try:
            v_done = supabase.table("studio_videos").select("status, created_at, updated_at").eq("moderated_by", current_user.id).execute().data or []
        except Exception:
            v_done = supabase.table("studio_videos").select("status, created_at, updated_at").in_("status", ["APPROVED", "REJECTED", "DELETED"]).execute().data or []
        
        all_items = s_done + v_done
        approved = sum(1 for i in all_items if i.get("status") == "APPROVED")
        rejected = sum(1 for i in all_items if i.get("status") in ["REJECTED", "DELETED"])
        
        from datetime import datetime, timedelta
        daily_stats = {}
        for i in range(6, -1, -1):
            d = datetime.now() - timedelta(days=i)
            day_key = d.strftime('%Y-%m-%d')
            daily_stats[day_key] = {"date": d.strftime('%d/%m'), "Duyệt": 0, "Từ chối": 0}
            
        for item in all_items:
            date_val = item.get("updated_at") or item.get("created_at") or ""
            raw_date = str(date_val)[:10]
            if raw_date in daily_stats:
                if item.get("status") == "APPROVED": daily_stats[raw_date]["Duyệt"] += 1
                elif item.get("status") in ["REJECTED", "DELETED"]: daily_stats[raw_date]["Từ chối"] += 1
        
        return {
            "status": "success", 
            "data": {
                "total_processed": len(all_items),
                "approved_count": approved,
                "rejected_count": rejected,
                "chart_data": list(daily_stats.values())
            }
        }
    except Exception as e: return {"status": "error", "message": str(e)}