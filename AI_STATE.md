# 🚀 [DỰ ÁN: AI HEALTH SHARE] - TRẠNG THÁI HỆ THỐNG

> **Mã dự án:** `X_AI_Health-Share`
> **Cập nhật lần cuối:** 17:15 - 14/04/2026
> **Giai đoạn hiện tại:** Phase 1.5 - Hệ thống Ví (Wallet) & Affiliate Dashboard (PENDING HOTFIX)

---

## 1. QUY TẮC CỐT LÕI (CORE RULES)
- **Kiến trúc:** Backend (`FastAPI - Python`) / Frontend (`Next.js - Tailwind`).
- **Naming:** Backend dùng `snake_case`, Frontend dùng `camelCase`.
- **Database:** Supabase (Bắt buộc Enum **VIẾT HOA TOÀN BỘ**, VD: `USER`, `PENDING`).
- **Workflow:** Deploy tự động qua GitHub -> Render. Xác thực Git qua Personal Access Token (PAT).

---

## 2. DATABASE SCHEMA (VERIFIED)

**🗄️ Bảng: `users`**
- `id` (uuid, PK) | `email` (string, unique) | `role` (Enum) | `affiliate_code` (6 chars)

**🗄️ Bảng: `wallets` & `wallet_transactions` (NEW)**
- Đã khởi tạo thành công luồng lưu trữ số dư và sổ cái biến động số dư.
- Đã thiết lập RLS Policy cho phép Backend thao tác (FOR ALL).

**🗄️ Bảng: `bookings_transactions`**
- `payment_status` (Enum: `PENDING`, `PAID`) - **Đang gặp lỗi mismatch case.**
- `service_status` (Enum: `WAITING`, `COMPLETED`).

---

## 3. BACKEND API CONTRACTS
- 🟢 `PATCH /bookings/{id}/complete`: Hoàn tất logic giải ngân tự động 70/15/15 vào ví.
- 🟡 `POST /bookings`: Đang lỗi `22P02` do truyền giá trị Enum lowercase (`unpaid`).
- 🟢 `GET /bookings` & `GET /services`: Đã khôi phục và hoạt động ổn định.

---

## 4. TIẾN ĐỘ & TRẠNG THÁI HIỆN TẠI

**✅ Thành tựu đã đạt:**
- Thông luồng giải ngân: Tiền đã có thể chảy từ đơn hàng vào Ví người dùng trên Database.
- Dashboard Partner đã hiển thị dữ liệu real-time từ Supabase.
- Xử lý thành công lỗi Proxy/DNS và xác thực GitHub trên máy trạm Windows.

**⚠️ Lỗi tồn đọng (Blocking):**
- **Error `22P02`:** Hàm `create_booking` gửi giá trị `"unpaid"` vào cột Enum. Cần sửa thành `"PENDING"` (viết hoa) để khớp với Schema.
- **Dữ liệu mồ côi:** Cần xóa thủ công các Booking cũ không có `user_id` hợp lệ trong bảng `users` để tránh lỗi Foreign Key.

---

## 5. LỘ TRÌNH HÀNH ĐỘNG (ROADMAP - PHASE 1.5)

### 🎯 Phiên làm việc tiếp theo (Ưu tiên cao nhất)
- [ ] **Hotfix:** Sửa `payment_status` trong `main.py` từ `"unpaid"` thành `"PENDING"`.
- [ ] **Integration:** Kết nối dữ liệu thực từ bảng `wallets` lên **Affiliate Dashboard** (Hiện đang dùng data mô phỏng).
- [ ] **UX:** Thêm trạng thái Loading và Toast thông báo khi giải ngân thành công trên Dashboard.

### 🔭 Tầm nhìn chiến lược
- [ ] Xây dựng hệ thống Yêu cầu Rút tiền và phê duyệt từ SuperAdmin.
- [ ] Tích hợp thông báo Telegram Bot khi có đơn hàng mới phát sinh.