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
# --- SỬA LẠI ĐOẠN IMPORT NÀY ---
from payos import PayOS
from payos.type import PaymentData, ItemData

# --- CẤU HÌNH CỔNG THANH TOÁN PAYOS ---
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
                # THÊM ĐOẠN NÀY: Bắt lỗi nếu mã không tồn tại
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
                returnUrl="http://localhost:3000/partner", # Trả về web khi thanh toán xong
                cancelUrl="http://localhost:3000/"         # Trả về web nếu hủy
            )
            payos_res = payos_client.createPaymentLink(paymentData=payment_data)
            checkout_url = payos_res.checkoutUrl
        except Exception as payos_err:
            print("Lỗi tạo PayOS:", payos_err)
            checkout_url = None 

        # 5. Tích hợp Bot Telegram báo đơn mới (Chờ thanh toán)
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
            "checkout_url": checkout_url # Trả URL về cho Frontend
        }
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

# --- 8. PAYOS WEBHOOK (ĐÓN TIỀN VỀ ESCROW) ---
@app.post("/webhook/payos", tags=["Webhook"])
async def payos_webhook(request: dict):
    try:
        data = request.get("data", {})
        order_code = data.get("orderCode")
        
        # Nếu giao dịch thành công (code == "00")
        if request.get("code") == "00" or request.get("success") == True:
            # 1. Cập nhật trạng thái tiền vào Escrow
            supabase.table("bookings_transactions").update({"payment_status": "PAID_ESCROW"}).eq("order_code", order_code).execute()
            
            # 2. Báo Telegram Admin
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


from fastapi import APIRouter, Depends, HTTPException
from datetime import datetime, timedelta

# Lưu ý: Cậu nhớ import supabase client và hàm get_current_user của dự án
# @router hoặc @app tùy thuộc vào cấu trúc file của cậu
@app.get("/admin/dashboard")
async def get_admin_dashboard(current_user: dict = Depends(get_current_user)):
    # 1. Kiểm tra quyền (RBAC)
    if current_user.get("role") != "SUPER_ADMIN":
        raise HTTPException(status_code=403, detail="Chỉ Super Admin mới được xem thống kê")

    try:
        # 2. Truy vấn thống kê tổng quan (Sử dụng count của Supabase)
        users_count_res = supabase.table("users").select("id", count="exact").eq("role", "USER").execute()
        partners_count_res = supabase.table("users").select("id", count="exact").eq("role", "PARTNER_ADMIN").execute()
        services_count_res = supabase.table("services").select("id", count="exact").execute()
        pending_wd_res = supabase.table("withdrawal_requests").select("id", count="exact").eq("status", "PENDING").execute()

        # 3. Tính tổng doanh thu từ các Booking đã thanh toán thành công
        # Lấy thêm thông tin đối tác để tính Top Partners
        bookings_res = supabase.table("bookings").select("*, services(partner_id), users(email)").eq("status", "PAID").execute()
        bookings = bookings_res.data

        total_revenue = sum(b.get("total_amount", 0) for b in bookings) if bookings else 0

        # 4. Xử lý dữ liệu Biểu đồ Doanh thu (7 ngày gần nhất)
        today = datetime.now()
        revenue_chart = []
        for i in range(6, -1, -1):
            target_date = (today - timedelta(days=i)).date()
            daily_revenue = sum(
                b.get("total_amount", 0) 
                for b in bookings 
                if datetime.fromisoformat(b["created_at"].replace("Z", "+00:00")).date() == target_date
            )
            revenue_chart.append({
                "date": target_date.strftime("%d/%m"),
                "revenue": daily_revenue
            })

        # 5. Xử lý Top Partners (Nhóm theo đối tác)
        partner_stats = {}
        for b in bookings:
            # Lấy email đối tác (Nơi cung cấp dịch vụ)
            partner_id = b.get("services", {}).get("partner_id")
            if not partner_id: continue
            
            if partner_id not in partner_stats:
                # Cần query thêm email của partner này để hiển thị cho đẹp
                partner_info = supabase.table("users").select("email").eq("id", partner_id).execute()
                p_email = partner_info.data[0]["email"] if partner_info.data else "Unknown"
                
                partner_stats[partner_id] = {
                    "email": p_email,
                    "total_bookings": 0,
                    "total_revenue": 0
                }
            
            partner_stats[partner_id]["total_bookings"] += 1
            partner_stats[partner_id]["total_revenue"] += b.get("total_amount", 0)

        # Sắp xếp lấy top 3 đối tác có doanh thu cao nhất
        top_partners = sorted(partner_stats.values(), key=lambda x: x["total_revenue"], reverse=True)[:3]

        # 6. Trả về đúng cấu trúc Frontend đang chờ
        return {
            "status": "success",
            "data": {
                "stats": {
                    "total_revenue": total_revenue,
                    "total_users": users_count_res.count if users_count_res else 0,
                    "total_partners": partners_count_res.count if partners_count_res else 0,
                    "total_services": services_count_res.count if services_count_res else 0,
                    "pending_withdrawals": pending_wd_res.count if pending_wd_res else 0
                },
                "revenue_chart": revenue_chart,
                "top_partners": top_partners
            }
        }

    except Exception as e:
        print("Dashboard Error:", str(e))
        raise HTTPException(status_code=500, detail="Lỗi khi truy xuất dữ liệu thống kê")