from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any, List
from datetime import datetime

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

# --- 4. CẤU TRÚC TIKTOK FEED (Thay thế Studio) ---
class TikTokFeedCreate(BaseModel):
    title: str
    content: Optional[str] = None
    video_url: str
    price: Optional[float] = None

# --- 5. CẤU TRÚC COMMUNITY (Bài viết diễn đàn) ---
class CommunityPostCreate(BaseModel):
    content: str
    image_url: Optional[str] = None

# --- 6. CẤU TRÚC BÌNH LUẬN (Chia ranh giới rõ ràng) ---
class TikTokCommentCreate(BaseModel):
    content: str
    parent_id: Optional[str] = None 
    # Bổ sung thêm các trường này với giá trị mặc định để tránh lỗi 400 nếu Frontend vô tình gửi thừa
    video_id: Optional[str] = None
    user_id: Optional[str] = None

class CommunityCommentCreate(BaseModel):
    content: str
    parent_id: Optional[str] = None 
    post_id: Optional[str] = None
    user_id: Optional[str] = None 

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

# --- 11. CẤU TRÚC LỊCH HẸN THEO LUỒNG MỚI (BẢO CHỨNG KÉP) ---
class AppointmentRequest(BaseModel):
    """User gửi yêu cầu từ Modal Đặt lịch (Chưa cần thanh toán)"""
    partner_id: str
    service_id: Optional[str] = None
    video_id: Optional[str] = None
    customer_name: str
    customer_phone: str
    note: Optional[str] = None
    affiliate_code: Optional[str] = None
    total_amount: float

class PartnerResponse(BaseModel):
    """Partner trả lời yêu cầu"""
    action: str  # "ACCEPT" hoặc "REJECT"
    start_time: Optional[datetime] = None  # Cần thiết nếu ACCEPT
    end_time: Optional[datetime] = None    # Cần thiết nếu ACCEPT
    reason: Optional[str] = None           # Cần thiết nếu REJECT

class AppointmentCheckIn(BaseModel):
    """Partner quét mã khách khi khách đến"""
    check_in_code: str
    partner_notes: Optional[str] = None

class AppointmentConfirm(BaseModel):
    """User xác nhận hoàn thành dịch vụ"""
    is_satisfied: bool
    feedback: Optional[str] = None


class WithdrawalRequest(BaseModel):
    amount: float
    bank_name: str
    account_number: str
    account_name: str