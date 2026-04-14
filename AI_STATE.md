# 🚀 [DỰ ÁN: AI HEALTH SHARE] - TRẠNG THÁI HỆ THỐNG

> **Mã dự án:** `X_AI_Health-Share`
> **Cập nhật lần cuối:** 16:10 - 14/04/2026
> **Giai đoạn hiện tại:** Phase 1.5 - Hệ thống Ví (Wallet) & Affiliate Dashboard

---

## 1. QUY TẮC CỐT LÕI (CORE RULES)
- **Kiến trúc:** Backend (`FastAPI - Python`) / Frontend (`Next.js - Tailwind`).
- **Quy tắc Naming:** Backend dùng `snake_case`, Frontend dùng `camelCase`.
- **Database:** Supabase (Bắt buộc sử dụng Enum **VIẾT HOA TOÀN BỘ** cho Role, VD: `USER`).
- **Workflow Remote:** Deploy tự động qua GitHub tới Render. Cấp quyền push Git qua Personal Access Token (PAT) nếu trạm máy Windows kẹt SSH/DNS.

---

## 2. DATABASE SCHEMA (VERIFIED)

**🗄️ Bảng: `users`**
- `id` (uuid, PK) | `email` (string, unique)
- `role` (Enum: "USER", "CREATOR", "PARTNER_ADMIN", "SUPER_ADMIN")
- `affiliate_code` (string, 6 chars)

**🗄️ Bảng: `services`**
- `id` (uuid, PK) | `partner_id` (uuid, FK)
- `service_name` (varchar) | `description` (text, nullable)
- `price` (numeric) | `service_type` (Enum)

**🗄️ Bảng: `bookings_transactions`**
- `id` (uuid, PK)
- `user_id` (uuid, FK) | `service_id` (uuid, FK) | `affiliate_id` (uuid, FK, nullable)
- `total_amount` (numeric)
- `payment_status` (Enum, default: 'pending')
- `service_status` (Enum, default: 'waiting')

---

## 3. BACKEND API CONTRACTS
- 🟢 `POST /users`: Tạo User, tự động sinh `affiliate_code`. Validate Email TLD khắt khe.
- 🟢 `POST /bookings`: Tạo lịch đặt, liên kết User và Affiliate.
- 🟢 `GET /services`: Lấy danh sách dịch vụ (Cung cấp data cho TikTok UI).
- 🟢 `GET /bookings`: Đổ dữ liệu lịch đặt cho Partner Dashboard.
- 🟢 `PATCH /bookings/{id}/complete`: **(Mới)** Xác nhận hoàn thành dịch vụ, tính toán phân bổ dòng tiền Escrow (Partner 70%, Affiliate 15%, Platform 15%).

---

## 4. TIẾN ĐỘ & TRẠNG THÁI HIỆN TẠI

**✅ Thành tựu đã đạt:**
- Lên hình thành công **Partner Escrow Dashboard** (`/partner/dashboard`) với thiết kế Dark Mode chuyên nghiệp.
- Thông luồng Nút "Xác nhận Hoàn thành" -> Bắn API PATCH -> Tính toán chính xác tỷ lệ hoa hồng hiển thị trên Alert.
- Xử lý triệt để rào cản hệ thống: Fix CORS đa luồng, xử lý lỗi phân giải DNS (Tailscale) và bypass lỗi xác thực GitHub 401 trên trạm Windows.

**⚙️ Cấu hình Mạng lưới:**
- **Backend URL:** `https://ai-health-share-backend.onrender.com`
- **Frontend Local:** `http://localhost:3000`
- **Source of Truth:** Nhánh `main` trên GitHub repository.

---

## 5. LỘ TRÌNH HÀNH ĐỘNG (ROADMAP - PHASE 1.5)

### 🎯 Phiên làm việc hiện tại (Ưu tiên cao nhất)
- [ ] **Task 1 (Database):** Tạo bảng `wallets` trên Supabase để lưu trữ số dư khả dụng (Balance) của Đối tác và Affiliate.
- [ ] **Task 2 (Backend):** Nâng cấp logic API `PATCH /bookings/{id}/complete` -> Tự động INSERT/UPDATE số tiền hoa hồng (70/15) thẳng vào bảng `wallets`.
- [ ] **Task 3 (Frontend):** Thiết kế trang **Affiliate Dashboard** (`/affiliate/dashboard`) cho Creator theo dõi Lượt giới thiệu, GMV và Số dư ví.

### 🔭 Tầm nhìn chiến lược
- [ ] Xây dựng luồng Yêu cầu Rút tiền (Withdraw Request).
- [ ] Tích hợp thông báo Webhook (Email/Telegram) khi có đơn hàng mới phát sinh.