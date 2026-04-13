from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import uuid

app = FastAPI(
    title="AI Health Share API",
    description="Backend API cho Phase 1 - Luồng Đặt lịch, Escrow và Affiliate",
    version="1.0.0"
)

# --- MỞ KHÓA CORS CHO FRONTEND ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
def health_check():
    return {"status": "success", "message": "Server FastAPI đang hoạt động!"}

# --- 1. API TẠO NGƯỜI DÙNG (CÓ SINH MÃ AFFILIATE TỰ ĐỘNG) ---
@app.post("/users", tags=["Users"])
def create_user(user: schemas.UserCreate):
    try:
        # Sinh mã giới thiệu 6 ký tự in hoa
        new_code = str(uuid.uuid4())[:6].upper()
        
        data = supabase.table("users").insert({
            "email": user.email,
            "role": user.role,
            "affiliate_code": new_code
        }).execute()
        return {"status": "success", "data": data.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 2. API TẠO ĐỐI TÁC ---
@app.post("/partners", tags=["Partners"])
def create_partner(partner: schemas.PartnerCreate):
    try:
        data = supabase.table("partners").insert({
            "owner_id": partner.owner_id,
            "business_name": partner.business_name,
            "physical_address": partner.physical_address
        }).execute()
        return {"status": "success", "data": data.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 3. API TẠO DỊCH VỤ ---
@app.post("/services", tags=["Services"])
def create_service(service: schemas.ServiceCreate):
    try:
        data = supabase.table("services").insert({
            "partner_id": service.partner_id,
            "service_name": service.service_name,
            "price": service.price,
            "description": service.description,
            "service_type": service.service_type
        }).execute()
        return {"status": "success", "data": data.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 4. API TẠO BOOKING (TÍCH HỢP QUÉT MÃ AFFILIATE) ---
@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate):
    try:
        affiliate_id = None
        
        # Tra cứu ID thực sự của KOL thông qua mã giới thiệu
        if booking.affiliate_code:
            aff_user = supabase.table("users").select("id").eq("affiliate_code", booking.affiliate_code).execute()
            if aff_user.data:
                affiliate_id = aff_user.data[0]["id"]

        # Ghi nhận giao dịch vào cơ sở dữ liệu
        data = supabase.table("bookings_transactions").insert({
            "user_id": booking.user_id,
            "service_id": booking.service_id,
            "affiliate_id": affiliate_id,
            "total_amount": booking.total_amount
        }).execute()
        
        return {
            "status": "success", 
            "message": "Booking tạo thành công. Đang chờ thanh toán để vào ví Escrow.", 
            "data": data.data[0]
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 5. API LẤY DANH SÁCH BOOKING ---
@app.get("/bookings", tags=["Bookings"])
def get_all_bookings():
    try:
        data = supabase.table("bookings_transactions").select("*").execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 6. API CẬP NHẬT TRẠNG THÁI BOOKING & ESCROW ---
@app.patch("/bookings/{booking_id}", tags=["Bookings"])
def update_booking_status(booking_id: str, update_data: schemas.BookingUpdate):
    try:
        payload = {"service_status": update_data.service_status}
        if update_data.payment_status:
            payload["payment_status"] = update_data.payment_status

        data = supabase.table("bookings_transactions").update(payload).eq("id", booking_id).execute()
        return {"status": "success", "message": "Cập nhật thành công", "data": data.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 7. API LẤY DANH SÁCH DỊCH VỤ ---
@app.get("/services", tags=["Services"])
def get_all_services():
    try:
        data = supabase.table("services").select("*").execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))