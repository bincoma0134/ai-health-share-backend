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

# --- CẬP NHẬT CORS: ĐÃ FIX DẤU PHẨY ---
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

# --- 1. API TẠO NGƯỜI DÙNG ---
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
        
        # 2. Lấy thông tin Partner_id
        service_res = supabase.table("services").select("partner_id").eq("id", service_id).execute()
        if not service_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Dịch vụ liên kết")
        partner_id = service_res.data[0]["partner_id"]
        
        # 3. Tính toán dòng tiền
        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        platform_share = total_amount - partner_share - affiliate_share
        
        # 4. Logic Ví
        def process_wallet(uid: str, amount: float, tx_type: str):
            wallet_res = supabase.table("wallets").select("*").eq("user_id", uid).execute()
            if wallet_res.data:
                w_id = wallet_res.data[0]["id"]
                new_balance = float(wallet_res.data[0]["balance"]) + amount
                new_total = float(wallet_res.data[0]["total_earned"]) + amount
                supabase.table("wallets").update({"balance": new_balance, "total_earned": new_total}).eq("id", w_id).execute()
            else:
                new_wallet = supabase.table("wallets").insert({"user_id": uid, "balance": amount, "total_earned": amount}).execute()
                w_id = new_wallet.data[0]["id"]
            supabase.table("wallet_transactions").insert({
                "wallet_id": w_id, "booking_id": booking_id, "amount": amount, "transaction_type": tx_type
            }).execute()

        process_wallet(partner_id, partner_share, "partner_revenue")
        if affiliate_id:
            process_wallet(affiliate_id, affiliate_share, "affiliate_commission")

        update_res = supabase.table("bookings_transactions").update({"service_status": "completed"}).eq("id", booking_id).execute()
        
        return {
            "status": "success", 
            "message": "Đã giải ngân Escrow thành công",
            "distribution": {
                "total_amount": total_amount, "partner_revenue": partner_share, "affiliate_revenue": affiliate_share, "platform_revenue": platform_share
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi hệ thống ví Escrow: {str(e)}")