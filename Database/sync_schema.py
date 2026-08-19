import os
import psycopg2
from dotenv import load_dotenv

# Tự động tìm và nạp cấu hình từ file .env ở thư mục gốc
load_dotenv(os.path.join(os.path.dirname(os.path.dirname(__file__)), '.env'))

DATABASE_URL = os.environ.get("NEON_DATABASE_URL")
SCHEMA_FILE = os.path.join(os.path.dirname(__file__), "schema.sql")

def apply_schema():
    if not DATABASE_URL:
        print("❌ Lỗi: Không tìm thấy NEON_DATABASE_URL trong cấu hình môi trường.")
        return

    if not os.path.exists(SCHEMA_FILE):
        print(f"❌ Lỗi: Không tìm thấy file gốc tại {SCHEMA_FILE}")
        return

    print("⏳ Đang đọc cấu trúc từ schema.sql...")
    with open(SCHEMA_FILE, "r", encoding="utf-8") as f:
        sql_commands = f.read()

    # Nếu file rỗng thì bỏ qua
    if not sql_commands.strip():
        print("⚠️ File schema.sql hiện đang rỗng, không có lệnh nào để thực thi.")
        return

    print("⏳ Đang kết nối tới Neon.tech và áp dụng thay đổi...")
    try:
        # Lọc bỏ an toàn các dòng lệnh meta-command của psql bắt đầu bằng dấu gạch chéo ngược '\'
        cleaned_commands = "\n".join(
            line for line in sql_commands.splitlines() if not line.strip().startswith('\\')
        )

        conn = psycopg2.connect(DATABASE_URL)
        cur = conn.cursor()
        
        cur.execute(cleaned_commands)
        conn.commit()
        
        cur.close()
        conn.close()
        print("✅ Đã đồng bộ Schema lên Neon.tech thành công!")
    except Exception as e:
        print(f"❌ Lỗi trong quá trình đồng bộ Database: {e}")

if __name__ == "__main__":
    apply_schema()