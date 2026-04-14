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
<<<<<<< HEAD
    allow_origins=[
        "http://localhost:3000",
        "https://ai-health-share-frontend.vercel.app",
        "http://100.104.211.30:3000"
    ],
    allow_credentials=True,
=======
    allow_origins=["*"],  # Chấp nhận mọi nguồn truy cập
    allow_credentials=False, 
>>>>>>> db66fd74cefa819ef2af906d82861c151d9590f2
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

# --- 3. API TẠO DỊCH VỤ ---
@app.post("/services", tags=["Services"])
async def create_service(service: schemas.ServiceCreate):
    try:
        service_data = service.model_dump() 
        response = supabase.table("services").insert(service_data).execute()
        if not response.data:
            raise HTTPException(status_code=400, detail="Không thể tạo dữ liệu trong Database")
        return {"status": "success", "data": response.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi logic Backend: {str(e)}")

<<<<<<< HEAD
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
=======
# --- 4. API CẬP NHẬT TRẠNG THÁI BOOKING & CHIA TIỀN ESCROW (FINTECH VERSION) ---
@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    try:
        # 1. Lấy thông tin booking
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Booking")
            
        booking = booking_res.data[0]
        
        if booking.get("service_status").lower() == "completed":
            raise HTTPException(status_code=400, detail="Booking này đã được hoàn thành trước đó")

        total_amount = float(booking.get("total_amount", 0))
        affiliate_id = booking.get("affiliate_id")
        service_id = booking.get("service_id")
        
        # 2. Lấy thông tin Partner_id từ bảng services
        service_res = supabase.table("services").select("partner_id").eq("id", service_id).execute()
        if not service_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Dịch vụ liên kết")
        partner_id = service_res.data[0]["partner_id"]
        
        # 3. Tính toán dòng tiền (Partner 70%, Affiliate 15%)
        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        platform_share = total_amount - partner_share - affiliate_share
        
        # 4. Hàm xử lý nghiệp vụ Ví (Tạo mới hoặc Cộng dồn)
        def process_wallet(uid: str, amount: float, tx_type: str):
            wallet_res = supabase.table("wallets").select("*").eq("user_id", uid).execute()
            if wallet_res.data: # Nếu đã có ví
                w_id = wallet_res.data[0]["id"]
                new_balance = float(wallet_res.data[0]["balance"]) + amount
                new_total = float(wallet_res.data[0]["total_earned"]) + amount
                supabase.table("wallets").update({"balance": new_balance, "total_earned": new_total}).eq("id", w_id).execute()
            else: # Nếu chưa có ví -> Tạo ví mới
                new_wallet = supabase.table("wallets").insert({"user_id": uid, "balance": amount, "total_earned": amount}).execute()
                w_id = new_wallet.data[0]["id"]
                
            # Ghi vào Sổ cái (Transactions)
            supabase.table("wallet_transactions").insert({
                "wallet_id": w_id,
                "booking_id": booking_id,
                "amount": amount,
                "transaction_type": tx_type
            }).execute()

        # 5. Giải ngân vào ví Partner
        process_wallet(partner_id, partner_share, "partner_revenue")
        
        # 6. Giải ngân vào ví Affiliate (nếu khách dùng mã giới thiệu)
        if affiliate_id:
            process_wallet(affiliate_id, affiliate_share, "affiliate_commission")

        # 7. Cập nhật trạng thái Booking thành 'completed'
        update_res = supabase.table("bookings_transactions").update({
            "service_status": "completed" 
        }).eq("id", booking_id).execute()
        
        return {
            "status": "success", 
            "message": "Đã giải ngân Escrow thành công",
            "distribution": {
                "total_amount": total_amount,
                "partner_revenue": partner_share,
                "affiliate_revenue": affiliate_share,
                "platform_revenue": platform_share
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi hệ thống ví Escrow: {str(e)}")

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
>>>>>>> db66fd74cefa819ef2af906d82861c151d9590f2
