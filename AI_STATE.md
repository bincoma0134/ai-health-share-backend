# AI Health Share - Project State Log
**Ngày cập nhật:** 13/04/2026 (Cuối ngày làm việc - Hoàn tất Lõi Phase 1)
**Trạng thái:** Đã hoàn thiện Lõi Backend, Luồng dữ liệu và Kết nối Frontend cơ bản.

## 1. Tầm nhìn & Kiến trúc Hệ thống
* [cite_start]**Tầm nhìn:** Xây dựng một hệ sinh thái số trung lập cho ngành chăm sóc sức khỏe không xâm lấn & phòng ngừa [cite: 60-66].
* [cite_start]**Mô hình:** Nền tảng đa lớp (Multi-layer Platform) gồm 6 lớp: Content, Trust, Booking, CRM, Affiliate, và Data [cite: 697-709, 1285-1293].
* **Tech Stack:** FastAPI (Backend), Next.js 14+ (Frontend), Supabase (Database), Tailwind CSS, Axios.

## 2. Các lớp Giá trị đã hiện thực hóa
* [cite_start]**Lớp Nội dung & Người dùng (Lớp 1):** Đã xây dựng khung User Feed, hỗ trợ hiển thị danh sách dịch vụ [cite: 712-721, 1329-1335].
* [cite_start]**Lớp Đặt lịch & Hành trình (Lớp 3):** Triển khai luồng Booking khép kín từ User đến Partner [cite: 702-703, 766-778].
* [cite_start]**Lớp CRM & Đối tác (Lớp 4):** Dashboard dành cho đối tác quản lý giao dịch và trạng thái dịch vụ [cite: 785-805, 1365-1372].
* [cite_start]**Lớp Affiliate (Lớp 5):** Hệ thống mã giới thiệu 6 ký tự tự động, ghi nhận ID người giới thiệu vào giao dịch (Affiliate Tier 1) [cite: 808-817, 1373-1375].

## 3. Cấu trúc Dữ liệu & Logic Lõi (Supabase)
* [cite_start]**Bảng `users`**: Phân quyền Role-based (USER, PARTNER_ADMIN, CREATOR) và quản lý `affiliate_code` [cite: 851-862].
* **Bảng `bookings_transactions` (Escrow Flow)**: 
    * Tiền được giữ ở trạng thái `UNPAID` / `PENDING` khi mới đặt [cite: 1081, 1156-1162, 1389-1392].
    * [cite_start]Cập nhật sang `REVENUE_SPLIT` / `COMPLETED` khi dịch vụ hoàn thành để kích hoạt chia tiền [cite: 1083-1088, 1194-1197, 1202-1206].

## 4. Hệ thống API (FastAPI)
* `POST /users`: Đăng ký người dùng & sinh mã Affiliate tự động.
* `POST /partners` & `POST /services`: Khởi tạo hạ tầng cho đối tác.
* `GET /services`: Cung cấp dữ liệu cho Feed người dùng.
* `POST /bookings`: Đặt lịch, tự động tra cứu ID từ mã Affiliate khách nhập.
* `GET /bookings` & `PATCH /bookings/{id}`: Quản lý luồng tiền và trạng thái dịch vụ cho đối tác.

## 5. Trạng thái Frontend (Next.js)
* **User Flow (`/user`)**: Hiển thị dịch vụ thật, hỗ trợ nhập mã giới thiệu của KOL để đặt lịch.
* **Partner Flow (`/`)**: Dashboard quản lý lịch hẹn và thực hiện các hành động Check-in/Hoàn thành.
* **Kết nối**: Đã cấu hình CORS để Frontend gọi API Backend thành công.

## 6. Mục tiêu 10 giờ tiếp theo (Sprint Finish)
* **Deployment**: Triển khai Backend lên Render và Frontend lên Vercel.
* [cite_start]**Affiliate Tier 2**: Nâng cấp logic chia doanh thu tự động 2 tầng (Người giới thiệu của người giới thiệu)[cite: 810, 1000, 1376].
* [cite_start]**UI/UX TikTok-style**: Chuyển đổi Feed người dùng sang dạng video ngắn/hình ảnh trải nghiệm thật [cite: 98-104, 715-721].
* **Real Content**: Thay thế toàn bộ dữ liệu mẫu bằng các liệu trình thực tế để tạo niềm tin tự nhiên [cite: 206-210].

-----------------------
-----------------------
-----------------------
# AI Health Share - Project State Log
**Ngày cập nhật:** 14/04/2026 (Khối 1/10h - Triển khai Backend)
**Trạng thái:** Backend đã LIVE. Đang cấu hình Frontend lên Vercel.

## 1. Tầm nhìn & Kiến trúc Hệ thống
* [cite_start]**Tầm nhìn:** Xây dựng một hệ sinh thái số trung lập cho ngành chăm sóc sức khỏe không xâm lấn & phòng ngừa [cite: 60-66].
* [cite_start]**Mô hình:** Nền tảng đa lớp (Multi-layer Platform) gồm 6 lớp: Content, Trust, Booking, CRM, Affiliate, và Data [cite: 697-709, 1285-1293].
* **Tech Stack:** FastAPI (Backend), Next.js 14+ (Frontend), Supabase (Database), Tailwind CSS, Axios.

## 2. Các lớp Giá trị đã hiện thực hóa
* [cite_start]**Lớp Nội dung & Người dùng (Lớp 1):** Đã xây dựng khung User Feed, hỗ trợ hiển thị danh sách dịch vụ [cite: 712-721, 1329-1335].
* [cite_start]**Lớp Đặt lịch & Hành trình (Lớp 3):** Triển khai luồng Booking khép kín từ User đến Partner [cite: 702-703, 766-778].
* [cite_start]**Lớp CRM & Đối tác (Lớp 4):** Dashboard dành cho đối tác quản lý giao dịch và trạng thái dịch vụ [cite: 785-805, 1365-1372].
* [cite_start]**Lớp Affiliate (Lớp 5):** Hệ thống mã giới thiệu 6 ký tự tự động, ghi nhận ID người giới thiệu vào giao dịch (Affiliate Tier 1) [cite: 808-817, 1373-1375].

## 3. Cấu trúc Dữ liệu & Logic Lõi (Supabase)
* [cite_start]**Bảng `users`**: Phân quyền Role-based (USER, PARTNER_ADMIN, CREATOR) và quản lý `affiliate_code` [cite: 851-862].
* **Bảng `bookings_transactions` (Escrow Flow)**: 
    * Tiền được giữ ở trạng thái `UNPAID` / `PENDING` khi mới đặt [cite: 1081, 1156-1162, 1389-1392].
    * [cite_start]Cập nhật sang `REVENUE_SPLIT` / `COMPLETED` khi dịch vụ hoàn thành để kích hoạt chia tiền [cite: 1083-1088, 1194-1197, 1202-1206].

## 4. Trạng thái Triển khai & Hệ thống API (FastAPI)
* **Status:** Backend ĐÃ LIVE trên Render (`https://ai-health-share-backend.onrender.com`).
* **APIs:** * `POST /users`: Đăng ký & sinh mã Affiliate tự động.
  * `POST /partners` & `POST /services`: Khởi tạo hạ tầng đối tác.
  * `GET /services`: Nguồn dữ liệu cho Feed người dùng.
  * `POST /bookings`: Đặt lịch, tự động tra cứu ID Affiliate.
  * `GET /bookings` & `PATCH /bookings/{id}`: Quản lý luồng tiền Escrow cho đối tác.

## 5. Trạng thái Frontend (Next.js)
* **User Flow (`/user`)**: Hiển thị dịch vụ thật, hỗ trợ nhập mã giới thiệu của KOL để đặt lịch.
* **Partner Flow (`/`)**: Dashboard quản lý lịch hẹn và thực hiện Check-in/Hoàn thành.
* **Mục tiêu hiện tại:** Thay thế URL Localhost bằng URL Render và Deploy lên Vercel.

## 6. Mục tiêu Sprint 10 giờ (MVP Finish)
* **Deployment**: Hoàn tất đưa Frontend lên Vercel.
* [cite_start]**Affiliate Tier 2**: Nâng cấp logic chia doanh thu tự động 2 tầng (Người giới thiệu của người giới thiệu) [cite: 810, 1000, 1373-1376].
* [cite_start]**UI/UX TikTok-style**: Chuyển đổi Feed người dùng sang dạng video ngắn/hình ảnh trải nghiệm thật [cite: 98-104, 715-721].
* **Real Content**: Thay thế toàn bộ dữ liệu mẫu bằng các liệu trình thực tế để tạo niềm tin tự nhiên [cite: 206-210].

# AI Health Share - Project State Log
**Ngày cập nhật:** 14/04/2026 (Hoàn tất Khối 1/10h - Go-Live Hệ thống)
**Trạng thái:** Hệ thống đã LIVE toàn diện. Bắt đầu Phase 2 (Affiliate Tier 2 & Real Content).

## 1. Tầm nhìn & Kiến trúc Hệ thống
* **Tầm nhìn:** Xây dựng một hệ sinh thái số trung lập cho ngành chăm sóc sức khỏe không xâm lấn & phòng ngừa.
* **Mô hình:** Nền tảng đa lớp (Multi-layer Platform) gồm 6 lớp: Content, Trust, Booking, CRM, Affiliate, Data.
* **Tech Stack:** FastAPI (Backend), Next.js 14+ (Frontend), Supabase (Database).

## 2. Các lớp Giá trị đã hiện thực hóa
* **Lớp Nội dung & Người dùng (Lớp 1):** Khung User Feed hiển thị danh sách dịch vụ.
* **Lớp Đặt lịch & Hành trình (Lớp 3):** Luồng Booking khép kín từ User đến Partner.
* **Lớp CRM & Đối tác (Lớp 4):** Dashboard đối tác quản lý giao dịch và Check-in.
* **Lớp Affiliate (Lớp 5):** Mã giới thiệu 6 ký tự, ghi nhận Affiliate Tier 1 tự động.

## 3. Cấu trúc Dữ liệu & Logic Lõi (Supabase)
* **Bảng `users`**: Phân quyền (USER, PARTNER_ADMIN, CREATOR) và quản lý `affiliate_code`.
* **Bảng `bookings_transactions` (Escrow Flow)**: 
    * `UNPAID` / `PENDING` khi mới đặt.
    * `REVENUE_SPLIT` / `COMPLETED` khi dịch vụ hoàn thành để kích hoạt chia tiền.

## 4. Trạng thái Triển khai (LIVE)
* **Backend:** Đang chạy tại Render (`https://ai-health-share-backend.onrender.com`).
* **Frontend:** Đang chạy tại Vercel (Partner Dashboard & User Feed).
* **Kết nối:** Đã thông luồng CORS và API gọi chéo thành công.

## 5. Mục tiêu Sprint tiếp theo
* **Affiliate Tier 2**: Nâng cấp logic chia doanh thu tự động 2 tầng (Người giới thiệu của người giới thiệu).
* **UI/UX TikTok-style**: Chuyển đổi Feed người dùng sang dạng video ngắn/hình ảnh trải nghiệm thật.
* **Real Content**: Bơm dữ liệu liệu trình Spa thực tế qua API để test hệ thống.