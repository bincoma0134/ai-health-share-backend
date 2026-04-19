from pydantic import BaseModel, EmailStr
from typing import Optional
from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any

# --- 1. CẤU TRÚC NGƯỜI DÙNG ---
class UserCreate(BaseModel):
    email: EmailStr
    role: str = "USER"  # Mặc định là USER, có thể là PARTNER_ADMIN hoặc CREATOR

# --- 2. CẤU TRÚC ĐỐI TÁC (Cơ sở offline) ---
class PartnerCreate(BaseModel):
    owner_id: str
    business_name: str
    physical_address: str

# --- 3. CẤU TRÚC DỊCH VỤ (Đã thêm các trường mô tả) ---
class ServiceCreate(BaseModel):
    service_name: str
    description: Optional[str] = None
    price: float
    video_url: str  # Bắt buộc phải có link video từ Supabase Storage
    service_type: Optional[str] = "RELAXATION"
    status: Optional[str] = "PENDING" # Mặc định đẩy vào hàng đợi duyệt

# --- 4. CẤU TRÚC ĐẶT LỊCH (Gộp tất cả các trường cần thiết) ---
class BookingCreate(BaseModel):
    user_id: str
    service_id: str
    total_amount: float
    affiliate_code: Optional[str] = None  # Dùng code để tra cứu affiliate_id trong main.py
    description: Optional[str] = None
    service_type: str = "SINGLE_SESSION"

# --- 5. CẤU TRÚC CẬP NHẬT TRẠNG THÁI ---
class BookingUpdate(BaseModel):
    service_status: str
    payment_status: Optional[str] = None


# --- 6. CẤU TRÚC RÚT TIỀN (WITHDRAWAL) ---
class WithdrawalCreate(BaseModel):
    user_id: str
    amount: float
    payout_info: Dict[str, Any]  # Khớp với kiểu JSONB linh hoạt của Supabase

class WithdrawalUpdate(BaseModel):
    status: str  # 'APPROVED' hoặc 'REJECTED'
    admin_note: Optional[str] = None


# Cập nhật trong file: backend/schemas.py

class CommentCreate(BaseModel):
    service_id: str
    content: str
    parent_id: Optional[str] = None # Thêm trường này để nhận ID của bình luận gốc

from typing import List

# --- 7. CẤU TRÚC AI ASSISTANT ---
class ChatMessage(BaseModel):
    role: str
    content: str

class AIChatRequest(BaseModel):
    messages: List[ChatMessage]