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

# --- CẬP NHẬT CORS: CHO PHÉP CẢ LOCAL VÀ VERCEL ---
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "https://ai-health-share-frontend.vercel.app",
        "http://100.104.211.30:3000"
    ],
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

# --- 3. API TẠO DỊCH VỤ (ĐÃ CHỈNH SỬA) ---
@app.post("/services", tags=["Services"])
async def create_service(service: schemas.ServiceCreate):
    try:
        # Sử dụng model_dump để lấy dữ liệu từ Pydantic
        service_data = service.model_dump() 
        
        response = supabase.table("services").insert(service_data).execute()
        
        if not response.data:
            raise HTTPException(status_code=400, detail="Không thể tạo dữ liệu trong Database")
            
        return {"status": "success", "data": response.data[0]}
    except Exception as e:
        # Trả về chi tiết lỗi để chúng mình dễ debug
        raise HTTPException(status_code=400, detail=f"Lỗi logic Backend: {str(e)}")

# --- CÁC API KHÁC GIỮ NGUYÊN ---
# (Cần đảm bảo file schemas.py cũng đã được cập nhật trường description và service_type)

# --- 4. API CẬP NHẬT TRẠNG THÁI BOOKING & CHIA TIỀN ESCROW ---
@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    try:
        # 1. Lấy thông tin booking hiện tại
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Booking")
            
        booking = booking_res.data[0]
        
        # Ép kiểu lowercase để tránh lỗi Case-sensitive
        if booking.get("service_status").lower() == "completed":
            raise HTTPException(status_code=400, detail="Booking này đã được hoàn thành trước đó")

        total_amount = float(booking.get("total_amount", 0))
        affiliate_id = booking.get("affiliate_id")
        
        # 2. Logic chia tiền tự động (Phase 1: Đối tác 70%, Affiliate 15%, Nền tảng 15%)
        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        platform_share = total_amount - partner_share - affiliate_share
        
        # 3. Cập nhật trạng thái thành 'completed'
        update_res = supabase.table("bookings_transactions").update({
            "service_status": "completed" 
        }).eq("id", booking_id).execute()

        # Phase 2 sẽ INSERT các khoản partner_share, affiliate_share vào bảng `wallets`
        
        return {
            "status": "success", 
            "message": "Đã hoàn thành dịch vụ và giải ngân Escrow",
            "distribution": {
                "total_amount": total_amount,
                "partner_revenue": partner_share,
                "affiliate_revenue": affiliate_share,
                "platform_revenue": platform_share
            },
            "data": update_res.data[0]
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi khi xử lý Escrow: {str(e)}")