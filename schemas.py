from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any, List

# --- 1. CẤU TRÚC NGƯỜI DÙNG ---
class UserCreate(BaseModel):
    email: EmailStr
    role: str = "USER"  # Mặc định là USER, có thể là PARTNER_ADMIN hoặc CREATOR

# --- 2. CẤU TRÚC ĐỐI TÁC (Cơ sở offline) ---
class PartnerCreate(BaseModel):
    owner_id: str
    business_name: str
    physical_address: str

# --- 3. CẤU TRÚC DỊCH VỤ (Hiển thị trong Tab Quản lý Dịch vụ) ---
class ServiceCreate(BaseModel):
    service_name: str
    description: Optional[str] = None
    price: float
    image_url: Optional[str] = None # Minh họa bằng ảnh
    video_url: Optional[str] = None # Minh họa bằng video
    tags: Optional[list] = []
    service_type: Optional[str] = "RELAXATION"
    status: Optional[str] = "PENDING"

# --- 4. CẤU TRÚC STUDIO & CỘNG ĐỒNG (Hiển thị trên Feed trang chủ) ---
class PostCreate(BaseModel):
    title: Optional[str] = None
    content: str
    image_url: Optional[str] = None
    video_url: Optional[str] = None
    price: Optional[float] = None

# --- 5. CẤU TRÚC BÌNH LUẬN (Dùng chung) ---
class CommentCreate(BaseModel):
    service_id: Optional[str] = None
    post_id: Optional[str] = None
    content: str
    parent_id: Optional[str] = None 

# --- 6. CẤU TRÚC ĐẶT LỊCH ---
class BookingCreate(BaseModel):
    user_id: str
    service_id: str
    total_amount: float
    affiliate_code: Optional[str] = None 
    description: Optional[str] = None
    service_type: str = "SINGLE_SESSION"

class BookingUpdate(BaseModel):
    service_status: str
    payment_status: Optional[str] = None

# --- 7. CẤU TRÚC RÚT TIỀN ---
class WithdrawalCreate(BaseModel):
    user_id: str
    amount: float
    payout_info: Dict[str, Any] 

class WithdrawalUpdate(BaseModel):
    status: str 
    admin_note: Optional[str] = None

# --- 8. CẤU TRÚC AI ASSISTANT ---
class ChatMessage(BaseModel):
    role: str
    content: str

class AIChatRequest(BaseModel):
    messages: List[ChatMessage]

# --- 9. CẤU TRÚC XÁC THỰC (AUTH HELPERS) ---
class AuthResolve(BaseModel):
    identifier: str 

class UsernameSet(BaseModel):
    username: str