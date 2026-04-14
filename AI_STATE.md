[DỰ ÁN: AI HEALTH SHARE] - TRẠNG THÁI HỆ THỐNG
Mã dự án: X_AI_Health-Share
Cập nhật lần cuối: 14:40 - 14/04/2026
Giai đoạn hiện tại: Phase 1 - Luồng Đặt lịch & Affiliate (Tiktok UI)

1. QUY TẮC CỐT LÕI (CORE RULES)
Cấu trúc: Backend (FastAPI - Python) / Frontend (Next.js - Tailwind).

Naming: Backend dùng snake_case, Frontend dùng camelCase.

Database: Supabase (Sử dụng Enum VIẾT HOA toàn bộ cho Role).

Giao thức Remote: Port Forwarding cổng 3000 từ máy trạm (Windows) về MacBook qua Cursor.

2. DATABASE SCHEMA (SUPABASE - VERIFIED)
Table: users

id (uuid, PK) | email (string, unique)

role (Enum: "USER", "CREATOR", "PARTNER_ADMIN", "SUPER_ADMIN")

affiliate_code (string, 6 chars)

Table: services

id (uuid, PK) | partner_id (uuid)

service_name (character varying) | description (text, nullable)

price (numeric) | service_type (USER-DEFINED/Enum)

Table: bookings_transactions

id (uuid, PK)

user_id (uuid, FK) | service_id (uuid, FK) | affiliate_id (uuid, FK, nullable)

total_amount (numeric)

payment_status (Enum, default: 'pending')

service_status (Enum, default: 'waiting')

3. BACKEND API CONTRACTS
POST /users: Payload { "email": string, "role": "USER" }. Đã fix lỗi Enum và kiểm tra TLD Email (không chấp nhận đuôi .abc, .123).

POST /bookings: Payload { "user_id": uuid, "service_id": uuid, "affiliate_code": string/null, "total_amount": number }.

GET /services: Đang hoạt động, cung cấp dữ liệu thật cho TikTok Feed trên Frontend.

GET /bookings: Sẽ dùng cho Partner Dashboard.

4. TIẾN ĐỘ & TRẠNG THÁI HIỆN TẠI
Thành tựu: Đã thông luồng Đặt lịch: Người dùng xem video -> Bấm Đặt lịch -> Hiện Modal -> Nhập Email (Real) -> Tạo thành công User (Role: USER) & Booking liên kết trong DB.

Lỗi đã Fix: - CORS Policy: allow_origins=["*"] trên Render Backend.

Logic Frontend: Fix lỗi thiếu biến userId khi gọi chuỗi API liên hoàn.

Network: Khắc phục rào cản firewall qua Port Forwarding cổng 3000.

5. CẤU HÌNH QUAN TRỌNG
Backend URL: https://ai-health-share-backend.onrender.com

Frontend Local: http://localhost:3000 (Truy cập trực tiếp trên MacBook).

Source of Truth: Code trên GitHub repository là bản chuẩn để Render tự động Deploy.

6. LỘ TRÌNH HÀNH ĐỘNG (ROADMAP)
6.1. PHIÊN LÀM VIỆC TIẾP THEO (GẦN)

[ ] Task 1: Thiết kế Dashboard cho Partner tại /partner/dashboard.

[ ] Task 2: Hiển thị danh sách Booking thực tế, phân loại theo payment_status (Tiền trong ví Escrow).

[ ] Task 3: Nút xác nhận "Hoàn thành dịch vụ" (Update service_status -> 'completed') để chuẩn bị cho logic giải ngân.

6.2. TẦM NHÌN CHIẾN LƯỢC

[ ] Affiliate Logic: Tự động tính % hoa hồng dựa trên total_amount khi Booking hoàn thành.

[ ] Notification: Tích hợp Webhook báo về Telegram/Email khi có đơn hàng mới.