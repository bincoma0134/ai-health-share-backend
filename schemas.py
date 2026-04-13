from pydantic import BaseModel, EmailStr
from typing import Optional

# Cấu trúc hứng dữ liệu khi tạo Người dùng mới
class UserCreate(BaseModel):
    email: EmailStr
    role: str = "USER" # Mặc định là USER, có thể truyền PARTNER_ADMIN

# Cấu trúc hứng dữ liệu khi tạo Đối tác (Cơ sở offline)
class PartnerCreate(BaseModel):
    owner_id: str
    business_name: str
    physical_address: str

# Cấu trúc hứng dữ liệu khi Đối tác tạo Dịch vụ mới
class ServiceCreate(BaseModel):
    partner_id: str
    service_name: str
    price: float

# Cấu trúc hứng dữ liệu khi User đặt lịch
class BookingCreate(BaseModel):
    user_id: str
    service_id: str
    total_amount: float
    affiliate_id: Optional[str] = None # Có thể không có nếu khách tự đến
    description: Optional[str] = None
    service_type: str = "SINGLE_SESSION"

# Cấu trúc hứng dữ liệu khi User đặt lịch
class BookingCreate(BaseModel):
    user_id: str
    service_id: str
    total_amount: float
    affiliate_code: Optional[str] = None # Có thể không có nếu khách tự đến

# Cấu trúc hứng dữ liệu khi cập nhật trạng thái Booking
class BookingUpdate(BaseModel):
    service_status: str
    payment_status: Optional[str] = None