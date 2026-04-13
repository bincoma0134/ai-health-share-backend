import os
from dotenv import load_dotenv
from supabase import create_client, Client

# Tải biến môi trường từ file .env
load_dotenv()

url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_KEY")

if not url or not key:
    raise ValueError("Thiếu cấu hình SUPABASE_URL hoặc SUPABASE_KEY trong file .env")

# Khởi tạo client kết nối với Supabase
supabase: Client = create_client(url, key)