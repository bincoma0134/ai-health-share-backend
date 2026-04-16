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
        # Mang thẻ từ (token) lên Supabase để quét xem là thật hay giả
        user_data = supabase.auth.get_user(token)
        return user_data.user
    except Exception:
        raise HTTPException(status_code=401, detail="Token không hợp lệ hoặc đã hết hạn! Vui lòng đăng nhập lại.")
# -------------------------------------------

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
def create_booking(booking: schemas.BookingCreate, current_user = Depends(verify_user_token)):
    try:
        booking_data = booking.model_dump()
        
        if current_user.id != str(booking_data.get("user_id")):
            raise HTTPException(status_code=403, detail="Hành động bị từ chối! Lỗi định danh.")

        # 1. Xử lý Affiliate Code
        affiliate_code = booking_data.get("affiliate_code")
        affiliate_id = None
        if affiliate_code:
            aff_res = supabase.table("users").select("id").eq("affiliate_code", affiliate_code.upper()).execute()
            if aff_res.data:
                affiliate_id = aff_res.data[0]["id"]
            else:
                raise HTTPException(status_code=400, detail="Mã giới thiệu (KOL) không hợp lệ! Vui lòng kiểm tra lại.")

        # 2. Lấy thông tin Dịch vụ & Đối tác
        service_id = booking_data.get("service_id")
        service_name = "Dịch vụ Y tế"
        partner_id = None
        service_res = supabase.table("services").select("service_name, partner_id").eq("id", service_id).execute()
        if service_res.data:
            service_name = service_res.data[0]["service_name"]
            partner_id = service_res.data[0]["partner_id"]

        # 3. Tạo Order Code số nguyên cho PayOS
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

        # 4. GỌI PAYOS TẠO LINK THANH TOÁN QR
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
            print("Lỗi tạo PayOS:", payos_err)
            checkout_url = None 

        # 5. Tích hợp Bot Telegram
        aff_text = f"Có ({affiliate_code})" if affiliate_code else "Không"
        msg = f"📝 ĐƠN CHỜ THANH TOÁN 📝\nKhách: {str(current_user.id)[:8]}...\nMã đơn: {order_code}\nGiá trị: {float(booking_data.get('total_amount')):,.0f} VND"
        send_telegram_msg(msg)
        if partner_id:
            partner_res = supabase.table("users").select("telegram_chat_id").eq("id", partner_id).execute()
            if partner_res.data and partner_res.data[0].get("telegram_chat_id"):
                send_telegram_msg(f"🔔 [CÓ ĐƠN MỚI CHỜ KHÁCH CHUYỂN KHOẢN]\n{msg}", partner_res.data[0]["telegram_chat_id"])

        return {
            "status": "success", 
            "data": new_booking,
            "checkout_url": checkout_url
        }
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Lỗi tạo Booking: {str(e)}")

# --- 3. LOGIC GIẢI NGÂN ESCROW & VÍ (PATCH) ---

@app.patch("/bookings/{booking_id}/complete", tags=["Bookings"])
async def complete_booking(booking_id: str):
    try:
        booking_res = supabase.table("bookings_transactions").select("*").eq("id", booking_id).execute()
        if not booking_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Booking")
        booking = booking_res.data[0]
        
        if booking.get("service_status", "").upper() == "COMPLETED":
            raise HTTPException(status_code=400, detail="Booking này đã được hoàn thành")

        total_amount = float(booking.get("total_amount", 0))
        affiliate_id = booking.get("affiliate_id")
        service_id = booking.get("service_id")
        
        service_res = supabase.table("services").select("partner_id").eq("id", service_id).execute()
        if not service_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy Dịch vụ liên kết")
        partner_id = service_res.data[0]["partner_id"]
        
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

        partner_share = total_amount * 0.70
        affiliate_share = total_amount * 0.15 if affiliate_id else 0
        platform_share = total_amount - partner_share - affiliate_share
        
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

        process_wallet(target_partner_user_id, partner_share, "partner_revenue")
        if affiliate_id:
            process_wallet(affiliate_id, affiliate_share, "affiliate_commission")

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


# --- 4. QUẢN LÝ VÍ & AFFILIATE ---

@app.get("/wallets/{user_id}", tags=["Wallets"])
def get_wallet_info(user_id: str):
    try:
        wallet_res = supabase.table("wallets").select("*").eq("user_id", user_id).execute()
        
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


# --- CẤU HÌNH TELEGRAM BOT ---
TELEGRAM_BOT_TOKEN = "8705824981:AAFE1nkirPA55EGaP71Vcvu7VZdyTyHDuLI"
TELEGRAM_CHAT_ID = "8653422521"

def send_telegram_msg(message: str, specific_chat_id: str = None):
    if TELEGRAM_BOT_TOKEN == "YOUR_BOT_TOKEN": 
        return
    
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

# --- 5. RÚT TIỀN & XÉT DUYỆT ---

@app.post("/withdraw", tags=["Withdrawals"])
def request_withdrawal(req: schemas.WithdrawalCreate):
    try:
        wallet_res = supabase.table("wallets").select("*").eq("user_id", req.user_id).execute()
        if not wallet_res.data:
            raise HTTPException(status_code=400, detail="Không tìm thấy ví người dùng.")
        
        wallet = wallet_res.data[0]
        if float(wallet["balance"]) < req.amount:
            raise HTTPException(status_code=400, detail="Số dư không đủ để rút số tiền này.")

        new_balance = float(wallet["balance"]) - req.amount
        supabase.table("wallets").update({"balance": new_balance}).eq("id", wallet["id"]).execute()

        supabase.table("wallet_transactions").insert({
            "wallet_id": wallet["id"],
            "amount": -req.amount,
            "transaction_type": "withdrawal_request"
        }).execute()

        wd_res = supabase.table("withdrawal_requests").insert({
            "user_id": req.user_id,
            "amount": req.amount,
            "payout_info": req.payout_info,
            "status": "PENDING"
        }).execute()

        msg = f"🚨 YÊU CẦU RÚT TIỀN MỚI 🚨\n- Mã User: {req.user_id[:8]}...\n- Số tiền: {req.amount:,.0f} VND\n- Ngân hàng: {req.payout_info.get('bank_name', 'N/A')}\n👉 Vui lòng duyệt trên hệ thống!"
        send_telegram_msg(msg)

        return {"status": "success", "data": wd_res.data[0]}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@app.patch("/admin/withdraw/{withdraw_id}", tags=["Withdrawals"])
def process_withdrawal(withdraw_id: str, payload: schemas.WithdrawalUpdate):
    try:
        wd_res = supabase.table("withdrawal_requests").select("*").eq("id", withdraw_id).execute()
        if not wd_res.data:
            raise HTTPException(status_code=404, detail="Không tìm thấy yêu cầu rút tiền.")
        wd = wd_res.data[0]

        if wd["status"] != "PENDING":
            raise HTTPException(status_code=400, detail="Yêu cầu này đã được xử lý từ trước.")

        update_data = {"status": payload.status}
        if payload.admin_note:
            update_data["admin_note"] = payload.admin_note
        
        supabase.table("withdrawal_requests").update(update_data).eq("id", withdraw_id).execute()

        if payload.status == "REJECTED":
            wallet_res = supabase.table("wallets").select("*").eq("user_id", wd["user_id"]).execute()
            if wallet_res.data:
                wallet = wallet_res.data[0]
                new_balance = float(wallet["balance"]) + float(wd["amount"])
                supabase.table("wallets").update({"balance": new_balance}).eq("id", wallet["id"]).execute()
                
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

@app.get("/admin/withdrawals", tags=["Admin"])
def get_all_withdrawals():
    try:
        data = supabase.table("withdrawal_requests").select("*").order("created_at", desc=True).execute()
        return {"status": "success", "data": data.data}
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

# --- 7. WEBHOOKS ---

@app.post("/webhook/telegram", tags=["Webhook"])
async def telegram_webhook(req: dict):
    try:
        if "message" in req and "text" in req["message"]:
            text = req["message"]["text"]
            chat_id = req["message"]["chat"]["id"]

            if text.startswith("/start "):
                user_id = text.split(" ")[1]
                try:
                    supabase.table("users").update({"telegram_chat_id": str(chat_id)}).eq("id", user_id).execute()
                    welcome_msg = "✅ KẾT NỐI THÀNH CÔNG!\nChào mừng bạn đến với AI Health Share. Từ bây giờ, hệ thống sẽ tự động gửi thông báo tiền về và đơn hàng mới cho bạn ngay tại đây. Chúc bạn bùng nổ doanh số! 🚀"
                    send_telegram_msg(welcome_msg, str(chat_id))
                except Exception as db_err:
                    print("Lỗi lưu DB webhook:", db_err)

        return {"status": "ok"}
    except Exception as e:
        print("Lỗi Webhook:", e)
        return {"status": "error"}

@app.post("/webhook/payos", tags=["Webhook"])
async def payos_webhook(request: dict):
    try:
        data = request.get("data", {})
        order_code = data.get("orderCode")
        
        if request.get("code") == "00" or request.get("success") == True:
            supabase.table("bookings_transactions").update({"payment_status": "PAID_ESCROW"}).eq("order_code", order_code).execute()
            
            bk_res = supabase.table("bookings_transactions").select("total_amount").eq("order_code", order_code).execute()
            if bk_res.data:
                send_telegram_msg(
                    f"💰 TING TING! KHÁCH ĐÃ CHUYỂN KHOẢN 💰\n"
                    f"- Mã đơn: {order_code}\n"
                    f"- Số tiền: {bk_res.data[0]['total_amount']:,.0f} VND\n"
                    f"👉 Tiền đã khóa an toàn trong Escrow!"
                )
        return {"success": True}
    except Exception as e:
        print("Webhook error:", e)
        return {"success": False}

# =====================================================================
# 🚀 API 8: ADMIN DASHBOARD (DỮ LIỆU THỐNG KÊ THẬT 100%)
# =====================================================================
@app.get("/admin/dashboard", tags=["Admin"])
def get_admin_dashboard(current_user = Depends(verify_user_token)):
    try:
        # 1. KIỂM TRA QUYỀN (RBAC) - Truy vấn thẳng vào bảng users
        user_res = supabase.table("users").select("role").eq("id", current_user.id).execute()
        if not user_res.data or user_res.data[0].get("role") != "SUPER_ADMIN":
            raise HTTPException(status_code=403, detail="Chỉ Super Admin mới được quyền truy cập Dashboard.")

        # 2. ĐẾM SỐ LƯỢNG TỔNG QUAN
        users_res = supabase.table("users").select("id", count="exact").eq("role", "USER").execute()
        partners_res = supabase.table("users").select("id", count="exact").eq("role", "PARTNER_ADMIN").execute()
        services_res = supabase.table("services").select("id", count="exact").execute()
        withdrawals_res = supabase.table("withdrawal_requests").select("id", count="exact").eq("status", "PENDING").execute()

        # 3. TÍNH TOÁN DOANH THU & GIAO DỊCH THÀNH CÔNG
        # Lấy tất cả bookings đã thanh toán vào Escrow HOẶC đã hoàn thành
        paid_res = supabase.table("bookings_transactions").select("*").in_("payment_status", ["PAID_ESCROW", "COMPLETED"]).execute()
        valid_bookings = paid_res.data if paid_res.data else []

        total_revenue = sum(float(b.get("total_amount", 0)) for b in valid_bookings)

        # 4. TẠO DỮ LIỆU BIỂU ĐỒ 7 NGÀY GẦN NHẤT
        today = datetime.now()
        revenue_chart = []
        for i in range(6, -1, -1):
            target_date = (today - timedelta(days=i)).date()
            daily_rev = 0
            for b in valid_bookings:
                created_at_str = b.get("created_at", "")
                if created_at_str:
                    # Chuyển đổi định dạng ISO an toàn
                    b_date = datetime.fromisoformat(created_at_str.replace("Z", "+00:00")).date()
                    if b_date == target_date:
                        daily_rev += float(b.get("total_amount", 0))
            
            revenue_chart.append({
                "date": target_date.strftime("%d/%m"),
                "revenue": daily_rev
            })

        # 5. TÌM KIẾM TOP 3 ĐỐI TÁC CÓ DOANH THU CAO NHẤT
        # Tải danh sách Services để map Partner
        all_services_res = supabase.table("services").select("id, partner_id").execute()
        service_map = {s["id"]: s["partner_id"] for s in (all_services_res.data or [])}

        # Tải danh sách Partners để lấy Email
        all_partners_res = supabase.table("users").select("id, email").eq("role", "PARTNER_ADMIN").execute()
        partner_email_map = {p["id"]: p["email"] for p in (all_partners_res.data or [])}

        partner_stats = {}
        for b in valid_bookings:
            s_id = b.get("service_id")
            p_id = service_map.get(s_id)
            if not p_id:
                continue
            
            if p_id not in partner_stats:
                partner_stats[p_id] = {
                    "email": partner_email_map.get(p_id, "Unknown Partner"),
                    "total_bookings": 0,
                    "total_revenue": 0
                }
            
            partner_stats[p_id]["total_bookings"] += 1
            partner_stats[p_id]["total_revenue"] += float(b.get("total_amount", 0))

        # Sắp xếp và lấy Top 3
        top_partners = sorted(partner_stats.values(), key=lambda x: x["total_revenue"], reverse=True)[:3]

        # 6. TRẢ VỀ JSON CHUẨN CHO FRONTEND
        return {
            "status": "success",
            "data": {
                "stats": {
                    "total_revenue": total_revenue,
                    "total_users": users_res.count if users_res else 0,
                    "total_partners": partners_res.count if partners_res else 0,
                    "total_services": services_res.count if services_res else 0,
                    "pending_withdrawals": withdrawals_res.count if withdrawals_res else 0
                },
                "revenue_chart": revenue_chart,
                "top_partners": top_partners
            }
        }

    except Exception as e:
        print("Lỗi Admin Dashboard API:", str(e))
        raise HTTPException(status_code=500, detail=f"Lỗi truy xuất hệ thống: {str(e)}")