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

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
from payos import PayOS
from payos.type import PaymentData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "YOUR_CLIENT_ID")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "YOUR_API_KEY")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "YOUR_CHECKSUM_KEY")
payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(title="AI Health Share API", version="4.5.0")
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
        services = supabase.table("services").select("*").execute().data
        
        # Thủ thuật lấy thêm Avatar Partner an toàn không lo lỗi JOIN
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
def get_comments(service_id: str):
    data = supabase.table("service_comments").select("*, users(email, avatar_url)").eq("service_id", service_id).order("created_at", desc=True).execute()
    return {"status": "success", "data": data.data}

@app.post("/comments", tags=["Comments"])
def add_comment(payload: dict, current_user = Depends(verify_user_token)):
    try:
        new_comment = supabase.table("service_comments").insert({
            "user_id": current_user.id, "service_id": payload.get("service_id"), "content": payload.get("content")
        }).execute().data[0]
        user_data = supabase.table("users").select("email, avatar_url").eq("id", current_user.id).execute().data[0]
        new_comment["users"] = user_data
        return {"status": "success", "data": new_comment}
    except Exception as e: raise HTTPException(status_code=400, detail=str(e))

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
    pass # Cấu trúc Escrow giữ nguyên

# ==========================================
# 4. USER PROFILE (Cá nhân)
# ==========================================
@app.get("/user/profile", tags=["User"])
def get_user_profile(current_user = Depends(verify_user_token)):
    user = supabase.table("users").select("id, email, role, created_at, full_name, bio, avatar_url, cover_url").eq("id", current_user.id).single().execute().data
    saves = supabase.table("user_saves").select("services(*)").eq("user_id", current_user.id).order("created_at", desc=True).execute()
    bookings = supabase.table("bookings_transactions").select("*, services(service_name)").eq("user_id", current_user.id).order("created_at", desc=True).execute()
    likes_count = supabase.table("user_likes").select("id", count="exact").eq("user_id", current_user.id).execute().count or 0
    return {
        "status": "success",
        "data": {
            "profile": user,
            "stats": {"saved_count": len(saves.data or []), "bookings_count": len(bookings.data or []), "likes_count": likes_count},
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
# 5. 🚀 PARTNER PUBLIC PROFILE & REVIEWS
# ==========================================
@app.get("/partner/profile/{partner_id}", tags=["Partner"])
def get_partner_public_profile(partner_id: str):
    try:
        partner = supabase.table("users").select("id, full_name, bio, avatar_url, cover_url, reputation_points").eq("id", partner_id).single().execute().data
        if not partner: raise HTTPException(status_code=404, detail="Không tìm thấy doanh nghiệp")
        
        services = supabase.table("services").select("*").eq("partner_id", partner_id).execute().data or []
        reviews = supabase.table("partner_reviews").select("*, users(full_name, avatar_url)").eq("partner_id", partner_id).order("created_at", desc=True).execute().data or []
        
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

    # 1. TÌM TẤT CẢ DỊCH VỤ CỦA PARTNER NÀY
    services_res = supabase.table("services").select("id").eq("partner_id", partner_id).execute()
    service_ids = [s["id"] for s in services_res.data] if services_res.data else []
    
    if not service_ids:
        raise HTTPException(status_code=400, detail="Doanh nghiệp này chưa có dịch vụ nào.")

    # 2. KIỂM TRA ĐIỀU KIỆN TIÊN QUYẾT: ĐÃ HOÀN TẤT DỊCH VỤ CHƯA?
    bookings_res = supabase.table("bookings_transactions")\
        .select("id")\
        .eq("user_id", current_user.id)\
        .eq("service_status", "COMPLETED")\
        .in_("service_id", service_ids)\
        .execute()

    if not bookings_res.data:
        raise HTTPException(status_code=403, detail="BẢO MẬT: Bạn cần thanh toán và trải nghiệm dịch vụ của chuyên gia này trước khi đánh giá!")

    # 3. KIỂM TRA XEM ĐÃ ĐÁNH GIÁ CHƯA
    existing = supabase.table("partner_reviews").select("id").eq("user_id", current_user.id).eq("partner_id", partner_id).execute()
    if existing.data:
        raise HTTPException(status_code=400, detail="Bạn đã đánh giá chuyên gia này rồi!")

    try:
        # 4. LƯU ĐÁNH GIÁ
        new_review = supabase.table("partner_reviews").insert({
            "user_id": current_user.id, "partner_id": partner_id, "rating": rating, "comment": comment
        }).execute().data[0]

        # 5. CỘNG ĐIỂM UY TÍN CHO PARTNER (Ví dụ: + rating điểm)
        partner_data = supabase.table("users").select("reputation_points").eq("id", partner_id).single().execute().data
        current_points = partner_data.get("reputation_points") or 0
        supabase.table("users").update({"reputation_points": current_points + rating}).eq("id", partner_id).execute()

        user_data = supabase.table("users").select("full_name, avatar_url").eq("id", current_user.id).execute().data[0]
        new_review["users"] = user_data
        
        return {"status": "success", "data": new_review}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))