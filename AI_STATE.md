# 🧠 AI_STATE.md | X_AI_Health-Share

> **Project Identity:** `X_AI_Health-Share` (Escrow & Affiliate Healthcare Platform)
> **Current Version:** `3.5.0-MVP_READY`
> **Last Synced:** 17:30 - 15/04/2026
> **Status:** 🟢 Phase 3.0 COMPLETED | 🔵 Phase 4.0 INITIALIZING (UI/UX & Mobile MVP)

---

## 🛠️ 1. QUY TẮC CỐT LÕI (CORE PROTOCOLS)

| Thành phần | Quy tắc đặt tên | Định dạng bắt buộc |
| :--- | :--- | :--- |
| **Backend API** | `snake_case` | FastAPI chuẩn PEP8 + JWT Bearer |
| **Frontend UI** | `camelCase` | Next.js / TypeScript |
| **Database Enum** | `UPPERCASE` | **Bắt buộc** (VD: `PENDING`, `UNPAID`) |
| **Dòng tiền (Ratio)**| `70 / 15 / 15` | Partner / Affiliate / Platform |
| **Workflow** | `CI/CD` | Render (BE) / Vercel (FE) |

---

## 🗄️ 2. KIẾN TRÚC DỮ LIỆU (DATABASE SCHEMA)

### 2.1. Hệ thống Phân quyền (Role-based)
* **`role` (Enum):** `USER`, `CREATOR`, `PARTNER_ADMIN`, `SUPER_ADMIN`.
* Có cột `telegram_chat_id` (TEXT) hỗ trợ Deep Link Onboarding 1 chạm.

### 2.2. Hệ thống Đơn hàng & Thanh toán (`bookings_transactions`)
* **`order_code` (BIGINT UNIQUE):** Mã số giao dịch động định dạng số nguyên, sinh ra riêng cho cổng PayOS.
* **`payment_status`**: `UNPAID` ➔ `PAID_ESCROW` ➔ `REVENUE_SPLIT`.
* **`service_status`**: `PENDING` ➔ `COMPLETED`.

### 2.3. Hệ thống Tài chính & Rút tiền (`wallets` & `withdrawal_requests`)
* 🔒 **Bảo mật:** Bật RLS (Row Level Security) cho toàn bộ. Chỉ owner mới được `SELECT`.
* **`wallet_transactions`**: Ghi nhận chi tiết dòng tiền ra/vào (commission, partner_revenue, withdrawal...).
* **`status` (Enum)** rút tiền: `PENDING` ➔ `APPROVED` / `REJECTED`.

---

## 🔌 3. DANH MỤC API (API CONTRACTS)

### 🟢 Dịch vụ, Đơn hàng & Thanh toán
- `POST /bookings`: Khởi tạo đơn, sinh `order_code` và trả về `checkout_url` của PayOS.
- `PATCH /bookings/{id}/complete`: Kích hoạt logic giải ngân Escrow 3 bên (70/15/15).
- `POST /webhook/payos`: Cổng nhận "báo mộng" từ ngân hàng khi khách quét QR thành công (Cập nhật PAID_ESCROW).

### 🟡 Ví & Quản trị Hệ thống
- `GET /wallets/{user_id}`: Truy xuất số dư (Yêu cầu JWT).
- `POST /withdraw`: Gửi yêu cầu rút tiền (Yêu cầu JWT).
- `GET /admin/withdrawals` & `PATCH /admin/withdraw/{id}`: Dashboard quản trị (Chỉ dành cho tài khoản có role `SUPER_ADMIN`).

---

## 📈 4. TRẠNG THÁI TIẾN ĐỘ (MILESTONES)

### ✅ Phase 1.0 ➔ 2.0: Core Backend & Security (DONE)
- [x] Database Schema, Auth Triggers, Wallet Escrow Workflow.
- [x] API Security (JWT Bearer) & Database Security (RLS Bypass via Service Role).

### ✅ Phase 3.0: Mở rộng Hệ sinh thái & Thương mại (DONE)
- [x] **Payment Gateway:** Tích hợp PayOS Webhook (Tự động hóa dòng tiền).
- [x] **CRM & Admin:** Hoàn thiện Partner Portal và SuperAdmin Dashboard.
- [x] **QA Toàn trình:** Thông suốt kịch bản test 16 bước. Tối ưu UX Skeleton, bắt lỗi mã Affiliate.

### 🚀 Phase 4.0: MVP Optimization & Mobile App (NEXT)
- [ ] **UI/UX Polish:** Trau chuốt giao diện toàn diện cho hệ thống Web (Responsive, Typography, Animations, Micro-interactions) đảm bảo thẩm mỹ chuẩn mực để Demo nhà đầu tư.
- [ ] **Mobile Readiness:** Chuẩn hóa giao diện trên Mobile Browser (PWA) hoặc khởi tạo khung kiến trúc cho Mobile App (React Native/Expo).
- [ ] **Data Seeding:** Đổ dữ liệu mẫu thực tế (Video, Hình ảnh cơ sở, Dịch vụ, Đánh giá) để biến MVP thành một hệ sinh thái sống động.
- [ ] **Production Launch:** Trỏ Custom Domain (Tên miền thực tế) và chuẩn bị slide pitch deck.

---

## 🚨 5. GHI CHÚ VẬN HÀNH (DEV NOTES)
1. **Phân quyền Admin:** Bất kỳ ai muốn truy cập `/admin` bắt buộc phải được đổi `role` thành `SUPER_ADMIN` trong bảng `users` của Database.
2. **UX Đặt lịch:** URL thanh toán PayOS được cấu hình tự động mở ở Tab mới (`_blank`) để giữ trải nghiệm liền mạch cho luồng chọn dịch vụ của khách.