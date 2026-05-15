import os
from dotenv import load_dotenv
import psycopg2
from psycopg2 import pool

load_dotenv()

DATABASE_URL = os.environ.get("NEON_DATABASE_URL")
if not DATABASE_URL:
    raise ValueError("Thiếu cấu hình NEON_DATABASE_URL trong file .env")

# Khởi tạo Connection Pooler (Chống nghẽn cổ chai)
try:
    db_pool = psycopg2.pool.SimpleConnectionPool(1, 20, DATABASE_URL)
    if db_pool:
        print("✅ Đã kết nối thành công tới Database Neon.tech qua PgBouncer Pooler!")
except Exception as e:
    raise RuntimeError(f"❌ Lỗi kết nối Database: {e}")

def get_db_connection():
    """Hàm cấp phát kết nối DB cho mỗi lượt Request API"""
    conn = db_pool.getconn()
    try:
        yield conn
    finally:
        db_pool.putconn(conn)