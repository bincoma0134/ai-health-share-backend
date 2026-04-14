from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import uuid

app = FastAPI(
    title="AI Health Share API",
    description="Backend API cho Phase 1 - X_AI_Health-Share",
    version="1.0.0"
)

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

# --- 1. ENDPOINTS LẤY DỮ LIỆU (GET) ---

@app.get("/services", tags=["Services"])
def get_services():
    try:
        data = supabase.table("services").select("*").execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.get("/bookings", tags=["Bookings"])
def get_bookings():
    try:
        data = supabase.table("bookings_transactions").select("*").order("created_at", desc=True).execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 2. ENDPOINTS TẠO DỮ LIỆU (POST) ---

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

@app.post("/bookings", tags=["Bookings"])
def create_booking(booking: schemas.BookingCreate):
    try:
        # Chuyển đổi Pydantic model sang Dictionary
        booking_data = booking.model_dump()
        
        # 1. Xử lý Affiliate Code (Dịch từ mã 6 số sang UUID)
        affiliate_code = booking_data.get("affiliate_code")
        affiliate_id = None
        
        if affiliate_code:
            aff_res = supabase.table("users").select("id").eq("affiliate_code", affiliate_code.upper()).execute()
            if aff_res.data:
                affiliate_id = aff_res.data[0]["id"]

        # 2. STRICT PAYLOAD: Chỉ lọc lấy đúng các trường hiện có trong DB Table
        # Việc này giúp loại bỏ các trường thừa như 'description' từ Frontend gửi lên
        clean_payload = {
            "user_id": booking_data.get("user_id"),
            "service_id": booking_data.get("service_id"),
            "total_amount": booking_data.get("total_amount"),
            "affiliate_id": affiliate_id,
            "payment_status": "unpaid", # Mặc định cho đơn mới
            "service_status": "waiting"  # Mặc định cho đơn mới
        }

        # 3. Đẩy vào Database
        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        return {"status": "success", "data": data.data[0]}
    except Exception as e:
        # Debug lỗi chi tiết cho Mỹ
        raise HTTPException(status_code=400, detail=f"Lỗi tạo Booking: {str(e)}")

# --- 3. LOGIC GIẢI NGÂN ESCROW & VÍ (PATCH) ---

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    try:
        # 1. Lấy thông tin booking
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Booking")
        booking = booking_res.data[0]
        
        if booking.get("service_status").lower() == "completed":
            raise HTTPException(status_code=400, detail="Booking này đã được hoàn thành")

        total_amount = float(booking.get("total_amount", 0))
        affiliate_id = booking.get("affiliate_id")
        service_id = booking.get("service_id")
        
        # 2. Lấy partner_id từ bảng services
        service_res = supabase.table("services").select("partner_id").eq("id", service_id).execute()
        if not service_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Dịch vụ liên kết")
        partner_id = service_res.data[0]["partner_id"]
        
        # --- [LOGIC PHÒNG NGỰ DỮ LIỆU RÁC] ---
        target_partner_user_id = partner_id
        partner_record = supabase.table("partners").select("owner_id").eq("id", partner_id).execute()
        if partner_record.data:
            target_partner_user_id = partner_record.data[0]["owner_id"]

        check_partner = supabase.table("users").select("id").eq("id", target_partner_user_id).execute()
        if not check_partner.data:
            raise HTTPException(status_code=400, detail="Tài khoản Đối tác không tồn tại.")

        if affiliate_id:
            check_aff = supabase.table("users").select("id").eq("id", affiliate_id).execute()
            if not check_aff.data:
                affiliate_id = None 
        # -------------------------------------

        # 3. Tính toán dòng tiền
        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        platform_share = total_amount - partner_share - affiliate_share
        
        # 4. Hàm xử lý nghiệp vụ Ví
        def process_wallet(uid: str, amount: float, tx_type: str):
            wallet_res = supabase.table("wallets").select("*").eq("user_id", uid).execute()
            if wallet_res.data:
                w_id = wallet_res.data[0]["id"]
                new_balance = float(wallet_res.data[0]["balance"]) + amount
                new_total = float(wallet_res.data[0].get("total_earned", 0)) + amount
                supabase.table("wallets").update({"balance": new_balance, "total_earned": new_total}).eq("id", w_id).execute()
            else:
                new_wallet = supabase.table("wallets").insert({"user_id": uid, "balance": amount, "total_earned": amount}).execute()
                w_id = new_wallet.data[0]["id"]
                
            supabase.table("wallet_transactions").insert({
                "wallet_id": w_id, "booking_id": booking_id, "amount": amount, "transaction_type": tx_type
            }).execute()

        # 5. Thực thi giải ngân
        process_wallet(target_partner_user_id, partner_share, "partner_revenue")
        if affiliate_id:
            process_wallet(affiliate_id, affiliate_share, "affiliate_commission")

        # 6. Cập nhật trạng thái Booking
        supabase.table("bookings_transactions").update({"service_status": "completed"}).eq("id", booking_id).execute()
        
        return {
            "status": "success", 
            "message": "Giải ngân thành công",
            "distribution": {
                "total_amount": total_amount,
                "partner_revenue": partner_share,
                "affiliate_revenue": affiliate_share,
                "platform_revenue": platform_share
            }
        }
    except HTTPException as he:
        raise he
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi hệ thống: {str(e)}")