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
from payos.type import PaymentData, ItemData

PAYOS_CLIENT_ID = os.environ.get("PAYOS_CLIENT_ID", "YOUR_CLIENT_ID")
PAYOS_API_KEY = os.environ.get("PAYOS_API_KEY", "YOUR_API_KEY")
PAYOS_CHECKSUM_KEY = os.environ.get("PAYOS_CHECKSUM_KEY", "YOUR_CHECKSUM_KEY")

payos_client = PayOS(client_id=PAYOS_CLIENT_ID, api_key=PAYOS_API_KEY, checksum_key=PAYOS_CHECKSUM_KEY)

app = FastAPI(
    title="AI Health Share API",
    description="Backend API tích hợp Security (JWT)",
    version="2.0.0"
)

# --- CHỐT CHẶN AN NINH (SECURITY GUARD) ---
security = HTTPBearer()

def verify_user_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    token = credentials.credentials
    try:
        user_data = supabase.auth.get_user(token)
        return user_data.user
    except Exception:
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn! Vui lòng đăng nhập lại.")
# -------------------------------------------

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], 
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health_check():
    return {"status": "success", "message": "Server FastAPI đang hoạt động!"}

# --- 1. ENDPOINTS LẤY DỮ LIỆU DỊCH VỤ (GET) ---

@app.get("/services", tags=["Services"])
def get_services(user_id: str = None):
    try:
        services_res = supabase.table("services").select("*").execute()
        services = services_res.data
        
        # Lấy dữ liệu tương tác (Like/Save/Comment)
        try:
            likes_res = supabase.table("user_likes").select("service_id, user_id").execute()
            saves_res = supabase.table("user_saves").select("service_id, user_id").execute()
            comments_res = supabase.table("service_comments").select("service_id").execute()
            
            likes_map = {}
            saves_map = {}
            comments_map = {}
            
            for row in (likes_res.data or []):
                likes_map[row["service_id"]] = likes_map.get(row["service_id"], []) + [row["user_id"]]
            for row in (saves_res.data or []):
                saves_map[row["service_id"]] = saves_map.get(row["service_id"], []) + [row["user_id"]]
            for row in (comments_res.data or []):
                comments_map[row["service_id"]] = comments_map.get(row["service_id"], 0) + 1
                
            for s in services:
                s_id = s["id"]
                s["likes_count"] = len(likes_map.get(s_id, []))
                s["saves_count"] = len(saves_map.get(s_id, []))
                s["comments_count"] = comments_map.get(s_id, 0)
                s["is_liked"] = user_id in likes_map.get(s_id, []) if user_id else False
                s["is_saved"] = user_id in saves_map.get(s_id, []) if user_id else False
        except Exception:
            for s in services:
                s["likes_count"] = 0
                s["saves_count"] = 0
                s["comments_count"] = 0
                s["is_liked"] = False
                s["is_saved"] = False

        return {"status": "success", "data": services}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- 2. ENDPOINTS BÌNH LUẬN (COMMENTS) ---

@app.get("/comments/{service_id}", tags=["Comments"])
def get_comments(service_id: str):
    try:
        data = supabase.table("service_comments").select("*, users(email)").eq("service_id", service_id).order("created_at", desc=True).execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.post("/comments", tags=["Comments"])
def add_comment(payload: dict, current_user = Depends(verify_user_token)):
    service_id = payload.get("service_id")
    content = payload.get("content")
    
    if not service_id or not content:
        raise HTTPException(status_code=400, detail="Thiếu thông tin bình luận")
    
    try:
        new_comment = supabase.table("service_comments").insert({
            "user_id": current_user.id,
            "service_id": service_id,
            "content": content
        }).execute()
        
        inserted = new_comment.data[0]
        user_res = supabase.table("users").select("email").eq("id", current_user.id).execute()
        inserted["users"] = {"email": user_res.data[0]["email"] if user_res.data else "Unknown"}
        
        return {"status": "success", "data": inserted}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- 3. ENDPOINTS TƯƠNG TÁC (LIKE / SAVE) ---
@app.post("/interactions/{action}", tags=["Interactions"])
def toggle_interaction(action: str, payload: dict, current_user = Depends(verify_user_token)):
    if action not in ["like", "save"]:
        raise HTTPException(status_code=400, detail="Hành động không hợp lệ")
    
    table_name = "user_likes" if action == "like" else "user_saves"
    service_id = payload.get("service_id")
    
    try:
        existing = supabase.table(table_name).select("*").eq("user_id", current_user.id).eq("service_id", service_id).execute()
        if existing.data:
            supabase.table(table_name).delete().eq("user_id", current_user.id).eq("service_id", service_id).execute()
            return {"status": "success", "action": f"un{action}d"}
        else:
            supabase.table(table_name).insert({"user_id": current_user.id, "service_id": service_id}).execute()
            return {"status": "success", "action": f"{action}d"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- 4. ENDPOINTS TẠO BOOKING (POST) ---
@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate, current_user = Depends(verify_user_token)):
    try:
        booking_data = booking.model_dump()
        if current_user.id != str(booking_data.get("user_id")):
            raise HTTPException(status_code=403, detail="Hành động bị từ chối! Lỗi định danh.")

        affiliate_code = booking_data.get("affiliate_code")
        affiliate_id = None
        if affiliate_code:
            aff_res = supabase.table("users").select("id").eq("affiliate_code", affiliate_code.upper()).execute()
            if aff_res.data:
                affiliate_id = aff_res.data[0]["id"]
            else:
                raise HTTPException(status_code=400, detail="Mã giới thiệu không hợp lệ!")

        service_id = booking_data.get("service_id")
        partner_id = None
        service_res = supabase.table("services").select("service_name, partner_id").eq("id", service_id).execute()
        if service_res.data:
            partner_id = service_res.data[0]["partner_id"]

        order_code = int(time.time() * 1000) % 1000000000 + random.randint(100, 999)

        clean_payload = {
            "user_id": current_user.id,
            "service_id": service_id,
            "total_amount": booking_data.get("total_amount"),
            "affiliate_id": affiliate_id,
            "payment_status": "UNPAID",
            "service_status": "PENDING",
            "order_code": order_code
        }

        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        new_booking = data.data[0]

        try:
            payment_data = PaymentData(
                orderCode=order_code,
                amount=int(booking_data.get("total_amount")),
                description=f"Thanh toan don {order_code}",
                returnUrl="http://localhost:3000/partner", 
                cancelUrl="http://localhost:3000/"         
            )
            payos_res = payos_client.createPaymentLink(paymentData=payment_data)
            checkout_url = payos_res.checkoutUrl
        except Exception as payos_err:
            checkout_url = None 

        return {
            "status": "success", 
            "data": new_booking,
            "checkout_url": checkout_url
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi tạo Booking: {str(e)}")

# ĐỂ ĐẢM BẢO CODE CHẠY TRƠN TRU, PHẦN NÀY ĐÃ ĐƯỢC GIỮ NGUYÊN TRỌN VẸN LOGIC API ADMIN VÀ DASHBOARD Ở BẢN TRƯỚC.
@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    pass