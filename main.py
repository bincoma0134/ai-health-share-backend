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
    allow_origins=["*"],  # Chấp nhận mọi nguồn truy cập (kể cả Tailscale, ngrok, v.v.)
    allow_credentials=False, # Bắt buộc phải là False khi dùng "*"
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
