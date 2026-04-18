# 🧠 AI_STATE.md | X_AI_Health-Share

> [cite_start]**Project Identity:** `X_AI_Health-Share` (Escrow & Affiliate Healthcare Platform) [cite: 1]
> [cite_start]**Current Version:** `4.9.0-FEATURE_ARCH_AND_LIVE_STREAMING` [cite: 1]
> [cite_start]**Last Synced:** 14:00 - 18/04/2026 (Hoàn thiện Luồng Upload Live, Chuyển đổi Kiến trúc Features, Đồng bộ Loading Brand) [cite: 1]
> **Status:** 🟢 Phase 4.0 COMPLETE | 🟢 Phase 4.7 COMPLETE | [cite_start]🟡 Phase 4.8 IN PROGRESS (Feature Expansion) [cite: 1]

---

## 🛠️ 1. QUY TẮC CỐT LÕI (CORE PROTOCOLS)

| Thành phần | Quy tắc đặt tên | Định dạng bắt buộc |
| :--- | :--- | :--- |
| **Kiến trúc App** | `Feature-based` | [cite_start]Các tính năng chính nằm trong thư mục `/app/features/` [cite: 3] |
| **Backend API** | `snake_case` | [cite_start]FastAPI chuẩn PEP8 + JWT Bearer [cite: 1] |
| **Frontend UI** | `camelCase` | [cite_start]Next.js / TypeScript / Tailwind v4 [cite: 1] |
| **Upload Logic** | `Direct-to-S3` | [cite_start]Frontend đẩy file lên Supabase -> Backend lưu Metadata URL [cite: 9] |
| **UX Standards** | `Brand Loading` | [cite_start]Hiệu ứng "Khơi nguồn sức sống" (Emerald Ping) cho mọi trạng thái chờ [cite: 3, 4] |

---

## 🗄️ 2. KIẾN TRÚC DỮ LIỆU & BIẾN QUAN TRỌNG (SCHEMA & VARS)

### 2.1. Cấu trúc Bảng `services` (Nâng cấp)
* [cite_start]**`video_url`**: (text) Lưu link Public URL từ Supabase Storage thay cho dữ liệu mô phỏng[cite: 2, 3].
* **`status`**: (string) Mặc định `PENDING`. Chỉ video `APPROVED` mới xuất hiện trên Feed chính[cite: 1, 2].
* [cite_start]**`service_type_enum`**: Đã mở rộng các giá trị hợp lệ bao gồm `RELAXATION` và `TREATMENT`[cite: 2].
* [cite_start]**`moderated_by`**: (uuid) Lưu vết ID người kiểm duyệt để minh bạch hóa quy trình[cite: 1, 2].

### 2.2. Hồ sơ Doanh nghiệp (Nâng cấp giao diện Studio)
* [cite_start]**`address`**: (text) Địa chỉ vật lý của cơ sở phục vụ hiển thị trên profile[cite: 9].
* [cite_start]**`social_links`**: (jsonb/string) Lưu trữ tối đa 5 liên kết mạng xã hội dưới dạng mảng JSON[cite: 9].
* **`reputation_points`**: (int) Điểm uy tín hệ thống tích lũy từ đánh giá thật của khách hàng[cite: 2].

---

## 🔄 3. QUY TRÌNH LUỒNG DỮ LIỆU (WORKFLOWS)

1. **Luồng Đăng tải Video (Direct-to-Supabase):**
   * Đối tác chọn video -> Frontend đẩy trực tiếp vào bucket `video_partner` trên Supabase[cite: 9].
   * [cite_start]Frontend lấy `publicUrl` gửi kèm thông tin dịch vụ qua API `POST /services`[cite: 9].
   * [cite_start]Backend kiểm tra quyền `PARTNER_ADMIN` trước khi lưu dữ liệu trạng thái `PENDING`[cite: 2].

2. **Luồng Điều hướng Features (Routing):**
   * [cite_start]Hệ thống Sidebar và Bottom Dock tự động chuyển trạng thái active theo Feature[cite: 3].
   * `/features/calendar`: Quản lý booking, bọc lót trạng thái cho người dùng chưa đăng nhập[cite: 3].
   * [cite_start]`/features/explore`: Công cụ tìm kiếm động và lọc danh mục dịch vụ theo Grid Layout[cite: 3].

3. **Đồng bộ Theme & Loading:**
   * [cite_start]Sử dụng file `app/loading.tsx` để xử lý trạng thái chờ toàn cục khi chuyển trang[cite: 3].
   * Theme Sáng/Tối đồng bộ 2 chiều giữa `localStorage` và `theme_preference` trong Database[cite: 1, 3].

---

## 🚀 4. TRẠNG THÁI TIẾN ĐỘ (MILESTONES)

### ✅ Phase 4.7: Moderation Workflow (100% DONE)
- [x] **Moderator Dashboard:** Hoàn thiện giao diện lưới, nối dây dữ liệu video thật từ Storage[cite: 10].
- [x] **Smart Feed:** Trang chủ tự động cập nhật video thật ngay khi được duyệt (APPROVED)[cite: 2, 3].

### 🟡 Phase 4.8: Feature-driven Expansion (IN PROGRESS)
- [x] **Calendar Feature:** Giao diện thẻ hành trình, phân loại Sắp tới/Hoàn thành/Đã hủy[cite: 3].
- [x] **Explore Feature:** Lưới dịch vụ dạng Grid, thanh tìm kiếm và bộ lọc nhanh[cite: 3].
- [x] **Partner Dashboard:** Đồng bộ giao diện Kính mờ, tích hợp mini-stats dòng tiền Escrow[cite: 11].
- [ ] **Favorite Feature:** Lưu trữ và quản lý dịch vụ yêu thích (Trạng thái: Chờ triển khai).
- [ ] **Notification Center:** Hệ thống thông báo thời gian thực về đơn hàng và bài đăng (Trạng thái: Chờ triển khai).

### 🔵 Phase 5.0: Social Commerce & AI (NEXT)
- [ ] **AI Assistant:** Nâng cấp từ Modal Chat cũ sang trang tính năng `/features/AI` chuyên biệt[cite: 3].
- [ ] **Real Interaction:** Chốt luồng tương tác thực tế (Like, Comment, Save) trên Frontend[cite: 1].

---

## 🚨 5. GHI CHÚ QUAN TRỌNG & DEVOPS PROTOCOLS

* [cite_start]**API Cache Alert:** Sau khi chạy SQL `ALTER TYPE` hoặc thêm cột trong Supabase, **bắt buộc** thực hiện `Reload cache` trong Settings API[cite: 2].
* **Brand Icon Policy:** Không import icon thương hiệu (Facebook, v.v.) từ `lucide-react`. [cite_start]Sử dụng icon thay thế (`Users`, `PlayCircle`, `Music`)[cite: 9].
* **Hydration Protocol:** Luôn bọc Component phụ thuộc vào Theme hoặc Auth trong cờ `isMounted` để tránh lỗi lệch dữ liệu Server-Client[cite: 1, 3].

---
**Sync completed.** Phiên làm việc kết thúc thành công. [cite: 1]