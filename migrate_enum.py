import os, psycopg2
from dotenv import load_dotenv
load_dotenv('backend/.env')
url = os.environ.get('NEON_DATABASE_URL') or os.environ.get('DATABASE_URL')
conn = psycopg2.connect(url)
conn.autocommit = True
cur = conn.cursor()
cur.execute("ALTER TYPE public.payment_status_enum ADD VALUE IF NOT EXISTS 'TOPUP_UNPAID';")
cur.execute("ALTER TYPE public.payment_status_enum ADD VALUE IF NOT EXISTS 'TOPUP_PAID';")
print('Cap nhat ENUM tren Neon thanh cong!')
cur.close()
conn.close()
