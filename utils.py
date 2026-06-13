import os
from datetime import datetime, timedelta
from typing import Optional
import bcrypt
from jose import JWTError, jwt
import firebase_admin
from firebase_admin import credentials

# Khởi tạo Firebase Admin SDK
if not firebase_admin._apps:
    try:
        firebase_admin.initialize_app()
    except Exception as e:
        print(f"Lưu ý: Không thể khởi tạo Firebase mặc định: {e}")

# Cấu hình JWT từ biến môi trường
SECRET_KEY = os.environ.get("JWT_SECRET_KEY")
if not SECRET_KEY:
    raise ValueError("Thiếu cấu hình JWT_SECRET_KEY trong file .env")

ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 ngày

async def send_notification(*args, **kwargs):
    """
    Hàm gửi thông báo hệ thống (Đã được khôi phục để phục vụ main.py)
    """
    print(f"[Notification] Triggered notification with args: {args}, kwargs: {kwargs}")
    return True

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Kiểm tra mật khẩu thô có khớp với chuỗi đã băm trong Database không
    """
    try:
        return bcrypt.checkpw(
            plain_password.encode('utf-8'), 
            hashed_password.encode('utf-8')
        )
    except Exception:
        return False

def get_password_hash(password: str) -> str:
    """
    Băm mật khẩu nguyên bản sang chuỗi bảo mật để lưu vào Database
    """
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(password.encode('utf-8'), salt)
    return hashed.decode('utf-8')

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None):
    """
    Tạo JSON Web Token (JWT) cho phiên đăng nhập
    """
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    encoded_jwt = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str):
    """
    Giải mã và kiểm tra tính hợp lệ của JWT
    """
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        return None