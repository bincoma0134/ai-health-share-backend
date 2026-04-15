from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from database import supabase
import schemas
import uuid
import urllib.request
import json

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

        # LẤY TÊN DỊCH VỤ ĐỂ BÁO TELEGRAM CHO CHI TIẾT
        service_id = booking_data.get("service_id")
        service_name = "Dịch vụ Y tế"
        service_res = supabase.table("services").select("service_name").eq("id", service_id).execute()
        if service_res.data:
            service_name = service_res.data[0]["service_name"]

        # 2. STRICT PAYLOAD: Lọc và truyền CHÍNH XÁC Enum thực tế từ DB
        clean_payload = {
            "user_id": booking_data.get("user_id"),
            "service_id": service_id,
            "total_amount": booking_data.get("total_amount"),
            "affiliate_id": affiliate_id,
            "payment_status": "UNPAID",   # Cập nhật chuẩn theo Database: payment_status_enum
            "service_status": "PENDING"   # Cập nhật chuẩn theo Database: service_status_enum
        }

        # 3. Đẩy vào Database
        data = supabase.table("bookings_transactions").insert(clean_payload).execute()
        new_booking = data.data[0]

        # 4. 🚀 TÍCH HỢP BOT TELEGRAM BÁO ĐƠN MỚI
        aff_text = f"Có ({affiliate_code})" if affiliate_code else "Không"
        msg = (
            f"🎉 ĐƠN ĐẶT LỊCH MỚI 🎉\n"
            f"---------------------------\n"
            f"👤 ID Khách: {str(booking_data.get('user_id'))[:8]}...\n"
            f"💉 Dịch vụ: {service_name}\n"
            f"💰 Giá trị: {float(booking_data.get('total_amount')):,.0f} VND\n"
            f"🎁 Mã KOL: {aff_text}\n"
            f"---------------------------\n"
            f"👉 Đối tác vui lòng chuẩn bị đón khách!"
        )
        send_telegram_msg(msg)

        return {"status": "success", "data": new_booking}
    except Exception as e:
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
        
        # Tối ưu logic check trạng thái
        if booking.get("service_status", "").upper() == "COMPLETED":
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

        # 6. Cập nhật trạng thái Booking (Khớp với service_status_enum)
        supabase.table("bookings_transactions").update({"service_status": "COMPLETED"}).eq("id", booking_id).execute()
        
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


# --- 4. ENDPOINTS QUẢN LÝ VÍ & AFFILIATE (GET) ---

@app.get("/wallets/{user_id}", tags=["Wallets"])
def get_wallet_info(user_id: str):
    try:
        # 1. Lấy thông tin ví chính
        wallet_res = supabase.table("wallets").select("*").eq("user_id", user_id).execute()
        
        # Nếu user chưa có ví (chưa có giao dịch), trả về 0
        if not wallet_res.data:
            return {
                "status": "success", 
                "data": {
                    "wallet": {"balance": 0, "total_earned": 0},
                    "transactions": []
                }
            }
            
        wallet_data = wallet_res.data[0]
        wallet_id = wallet_data["id"]
        
        # 2. Lấy lịch sử dòng tiền (transactions)
        tx_res = supabase.table("wallet_transactions").select("*").eq("wallet_id", wallet_id).order("created_at", desc=True).execute()
        
        return {
            "status": "success",
            "data": {
                "wallet": wallet_data,
                "transactions": tx_res.data
            }
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi truy xuất ví: {str(e)}")


# --- CẤU HÌNH TELEGRAM BOT (Thay mã của bạn vào đây sau) ---
TELEGRAM_BOT_TOKEN = "8705824981:AAFE1nkirPA55EGaP71Vcvu7VZdyTyHDuLI"
TELEGRAM_CHAT_ID = "8653422521"

def send_telegram_msg(message: str, specific_chat_id: str = None):
    if TELEGRAM_BOT_TOKEN == "YOUR_BOT_TOKEN": 
        return # Bỏ qua nếu chưa cài token
    
    # Nếu truyền specific_chat_id thì gửi cho người đó, nếu không thì gửi cho SuperAdmin
    target_chat = specific_chat_id if specific_chat_id else TELEGRAM_CHAT_ID
    if not target_chat:
        return

    try:
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = json.dumps({"chat_id": target_chat, "text": message}).encode('utf-8')
        req = urllib.request.Request(url, data=data, headers={'Content-Type': 'application/json'})
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        print("Telegram error:", e)

# --- 5. ENDPOINTS RÚT TIỀN & XÉT DUYỆT ---

@app.post("/withdraw", tags=["Withdrawals"])
def request_withdrawal(req: schemas.WithdrawalCreate):
    try:
        # 1. Kiểm tra số dư ví
        wallet_res = supabase.table("wallets").select("*").eq("user_id", req.user_id).execute()
        if not wallet_res.data:
            raise HTTPException(status_code=400, detail="Không tìm thấy ví người dùng.")
        
        wallet = wallet_res.data[0]
        if float(wallet["balance"]) < req.amount:
            raise HTTPException(status_code=400, detail="Số dư không đủ để rút số tiền này.")

        # 2. Đóng băng tiền (Trừ số dư ngay lập tức)
        new_balance = float(wallet["balance"]) - req.amount
        supabase.table("wallets").update({"balance": new_balance}).eq("id", wallet["id"]).execute()

        # 3. Ghi nhận lịch sử ví (Giao dịch âm)
        supabase.table("wallet_transactions").insert({
            "wallet_id": wallet["id"],
            "amount": -req.amount,
            "transaction_type": "withdrawal_request"
        }).execute()

        # 4. Tạo yêu cầu rút tiền
        wd_res = supabase.table("withdrawal_requests").insert({
            "user_id": req.user_id,
            "amount": req.amount,
            "payout_info": req.payout_info,
            "status": "PENDING" # Viết hoa chuẩn chỉnh
        }).execute()

        # 5. Bắn thông báo Telegram cho Admin
        msg = f"🚨 YÊU CẦU RÚT TIỀN MỚI 🚨\n- Mã User: {req.user_id[:8]}...\n- Số tiền: {req.amount:,.0f} VND\n- Ngân hàng: {req.payout_info.get('bank_name', 'N/A')}\n👉 Vui lòng duyệt trên hệ thống!"
        send_telegram_msg(msg)

        return {"status": "success", "data": wd_res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.patch("/admin/withdraw/{withdraw_id}", tags=["Withdrawals"])
def process_withdrawal(withdraw_id: str, payload: schemas.WithdrawalUpdate):
    try:
        # 1. Lấy thông tin yêu cầu
        wd_res = supabase.table("withdrawal_requests").select("*").eq("id", withdraw_id).execute()
        if not wd_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu rút tiền.")
        wd = wd_res.data[0]

        if wd["status"] != "PENDING":
            raise HTTPException(status_code=400, detail="Yêu cầu này đã được xử lý từ trước.")

        # 2. Cập nhật trạng thái
        update_data = {"status": payload.status}
        if payload.admin_note:
            update_data["admin_note"] = payload.admin_note
        
        supabase.table("withdrawal_requests").update(update_data).eq("id", withdraw_id).execute()

        # 3. Xử lý Hoàn tiền nếu BỊ TỪ CHỐI (REJECTED)
        if payload.status == "REJECTED":
            wallet_res = supabase.table("wallets").select("*").eq("user_id", wd["user_id"]).execute()
            if wallet_res.data:
                wallet = wallet_res.data[0]
                # Cộng lại tiền vào ví
                new_balance = float(wallet["balance"]) + float(wd["amount"])
                supabase.table("wallets").update({"balance": new_balance}).eq("id", wallet["id"]).execute()
                
                # Ghi nhận hoàn tiền
                supabase.table("wallet_transactions").insert({
                    "wallet_id": wallet["id"],
                    "amount": float(wd["amount"]),
                    "transaction_type": "withdrawal_refund"
                }).execute()
                
                send_telegram_msg(f"❌ Yêu cầu {withdraw_id[:8]} đã bị TỪ CHỐI. Tiền đã được hoàn lại vào ví user.")

        elif payload.status == "APPROVED":
             send_telegram_msg(f"✅ Yêu cầu {withdraw_id[:8]} đã DUYỆT THÀNH CÔNG. Vui lòng chuyển khoản cho đối tác!")

        return {"status": "success", "message": f"Đã xử lý trạng thái: {payload.status}"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))
# --- 6. ENDPOINTS QUẢN TRỊ ADMIN (GET) ---

@app.get("/admin/withdrawals", tags=["Admin"])
def get_all_withdrawals():
    try:
        # Lấy tất cả yêu cầu rút tiền, sắp xếp mới nhất lên đầu
        data = supabase.table("withdrawal_requests").select("*").order("created_at", desc=True).execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))


# --- 7. TELEGRAM WEBHOOK (ONBOARDING 1 CHẠM CHO ĐỐI TÁC) ---

@app.post("/webhook/telegram", tags=["Webhook"])
async def telegram_webhook(req: dict):
    try:
        # Kiểm tra xem Telegram có gửi tin nhắn text không
        if "message" in req and "text" in req["message"]:
            text = req["message"]["text"]
            chat_id = req["message"]["chat"]["id"]

            # Luồng Deep Link: Khi đối tác bấm link, Telegram sẽ tự gửi lệnh có dạng "/start <user_id>"
            if text.startswith("/start "):
                user_id = text.split(" ")[1] # Tách lấy user_id
                
                try:
                    # 1. Lưu Chat ID vào Database
                    supabase.table("users").update({"telegram_chat_id": str(chat_id)}).eq("id", user_id).execute()
                    
                    # 2. Bắn tin nhắn chào mừng đích danh cho Đối tác
                    welcome_msg = (
                        "✅ KẾT NỐI THÀNH CÔNG!\n\n"
                        "Chào mừng bạn đến với AI Health Share. Từ bây giờ, hệ thống sẽ tự động "
                        "gửi thông báo tiền về và đơn hàng mới cho bạn ngay tại đây. Chúc bạn bùng nổ doanh số! 🚀"
                    )
                    send_telegram_msg(welcome_msg, str(chat_id))
                except Exception as db_err:
                    print("Lỗi lưu DB webhook:", db_err)

        return {"status": "ok"}
    except Exception as e:
        print("Lỗi Webhook:", e)
        return {"status": "error"}