import os
import json
from datetime import datetime, timedelta
from typing import Optional
from passlib.context import CryptContext
from jose import JWTError, jwt

# CẤU HÌNH JWT BẢO MẬT
SECRET_KEY = os.environ.get("JWT_SECRET_KEY", "fallback_secret_key")
ALGORITHM = os.environ.get("JWT_ALGORITHM", "HS256")
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 30 # 30 Ngày

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)

def get_password_hash(password):
    return pwd_context.hash(password)

def create_access_token(data: dict):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

def send_notification(
    conn, # Bắt buộc truyền connection database
    user_id: str, 
    noti_type: str, 
    title: str, 
    message: str, 
    action_url: Optional[str] = None,
    reference_id: Optional[str] = None,
    sender_id: Optional[str] = None,
    metadata: Optional[dict] = None
):
    try:
        cur = conn.cursor()
        meta_json = json.dumps(metadata) if metadata else "{}"
        query = """
            INSERT INTO public.notifications 
            (user_id, type, title, message, is_read, action_url, reference_id, sender_id, metadata)
            VALUES (%s, %s, %s, %s, False, %s, %s, %s, %s)
        """
        cur.execute(query, (user_id, noti_type, title, message, action_url, reference_id, sender_id, meta_json))
        conn.commit()
        cur.close()
        return True
    except Exception as e:
        print(f"[Notifier Error]: {str(e)}")
        conn.rollback()
        return False