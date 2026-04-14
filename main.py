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
        booking_data = booking.model_dump()
        data = supabase.table("bookings_transactions").insert(booking_data).execute()
        return {"status": "success", "data": data.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 3. LOGIC GIẢI NGÂN ESCROW & VÍ (PATCH) ---

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    try:
        # Lấy thông tin booking
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Booking")
        booking = booking_res.data[0]
        
        if booking.get("service_status").lower() == "completed":
            raise HTTPException(status_code=400, detail="Booking này đã được hoàn thành")

        total_amount = float(booking.get("total_amount", 0))
        affiliate_id = booking.get("affiliate_id")
        service_id = booking.get("service_id")
        
        # Lấy partner_id
        service_res = supabase.table("services").select("partner_id").eq("id", service_id).execute()
        partner_id = service_res.data[0]["partner_id"]
        
        # Chia tiền (Partner 70%, Affiliate 15%) [cite: 1212]
        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        
        def process_wallet(uid: str, amount: float, tx_type: str):
            wallet_res = supabase.table("wallets").select("*").eq("user_id", uid).execute()
            if wallet_res.data:
                w_id = wallet_res.data[0]["id"]
                new_balance = float(wallet_res.data[0]["balance"]) + amount
                supabase.table("wallets").update({"balance": new_balance}).eq("id", w_id).execute()
            else:
                new_wallet = supabase.table("wallets").insert({"user_id": uid, "balance": amount}).execute()
                w_id = new_wallet.data[0]["id"]
            supabase.table("wallet_transactions").insert({
                "wallet_id": w_id, "booking_id": booking_id, "amount": amount, "transaction_type": tx_type
            }).execute()

        process_wallet(partner_id, partner_share, "partner_revenue")
        if affiliate_id:
            process_wallet(affiliate_id, affiliate_share, "affiliate_commission")

        supabase.table("bookings_transactions").update({"service_status": "completed"}).eq("id", booking_id).execute()
        return {"status": "success", "message": "Giải ngân thành công"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi: {str(e)}")