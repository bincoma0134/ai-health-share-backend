import os
from supabase import create_client, Client
from dotenv import load_dotenv

# Tải biến môi trường từ file .env (nếu chạy local)
load_dotenv()

# Lấy biến môi trường an toàn
url: str = os.environ.get("SUPABASE_URL")
key: str = os.environ.get("SUPABASE_SERVICE_KEY")

if not url or not key:
    raise ValueError("Thiếu cấu hình SUPABASE_URL hoặc SUPABASE_SERVICE_KEY")

# Khởi tạo client với Service Role Key
supabase: Client = create_client(url, key)