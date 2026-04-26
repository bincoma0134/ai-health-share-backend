from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any, List

# --- 1. CẤU TRÚC NGƯỜI DÙNG ---
class UserCreate(BaseModel):
    email: EmailStr
    role: str = "USER"

# --- 2. CẤU TRÚC ĐỐI TÁC ---
class PartnerCreate(BaseModel):
    owner_id: str
    business_name: str
    physical_address: str

# --- 3. CẤU TRÚC DỊCH VỤ (Hồ sơ Partner) ---
class ServiceCreate(BaseModel):
    service_name: str
    description: Optional[str] = None
    price: float
    image_url: Optional[str] = None
    video_url: Optional[str] = None
    tags: Optional[list] = []
    service_type: Optional[str] = "RELAXATION"
    status: Optional[str] = "PENDING"

# --- 4. CẤU TRÚC STUDIO (Video Tiktok Trang chủ) ---
class StudioVideoCreate(BaseModel):
    title: str
    content: Optional[str] = None
    video_url: str
    price: Optional[float] = None

# --- 5. CẤU TRÚC COMMUNITY (Bài viết diễn đàn Cộng đồng) ---
class CommunityPostCreate(BaseModel):
    content: str
    image_url: Optional[str] = None

# --- 6. CẤU TRÚC BÌNH LUẬN (Dùng chung) ---
class CommentCreate(BaseModel):
    service_id: Optional[str] = None
    video_id: Optional[str] = None
    post_id: Optional[str] = None
    content: str
    parent_id: Optional[str] = None 

# --- 7. CẤU TRÚC ĐẶT LỊCH (Bảo chứng Escrow hỗ trợ cả Service và Video) ---
class BookingCreate(BaseModel):
    user_id: str
    service_id: Optional[str] = None
    video_id: Optional[str] = None
    total_amount: float
    affiliate_code: Optional[str] = None
    customer_name: Optional[str] = None
    customer_phone: Optional[str] = None
    note: Optional[str] = None
    service_type: str = "SINGLE_SESSION"

class BookingUpdate(BaseModel):
    service_status: str
    payment_status: Optional[str] = None

# --- 8. CẤU TRÚC RÚT TIỀN ---
class WithdrawalCreate(BaseModel):
    user_id: str
    amount: float
    payout_info: Dict[str, Any]

class WithdrawalUpdate(BaseModel):
    status: str
    admin_note: Optional[str] = None

# --- 9. CẤU TRÚC AI ASSISTANT ---
class ChatMessage(BaseModel):
    role: str
    content: str

class AIChatRequest(BaseModel):
    messages: List[ChatMessage]

# --- 10. CẤU TRÚC AUTH ---
class AuthResolve(BaseModel):
    identifier: str

class UsernameSet(BaseModel):
    username: str