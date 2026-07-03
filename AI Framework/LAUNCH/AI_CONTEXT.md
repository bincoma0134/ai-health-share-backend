# AI_CONTEXT.md

## PROJECT CONTEXT
Đây là dự án Full-Stack bao gồm các nền tảng công nghệ:
* **Backend:** Python
* **Frontend Website:** Next.js / React
* **Frontend Mobile:** Flutter

---

## SOURCE OF TRUTH (SOT)
Mọi phân tích hệ thống bắt buộc phải ưu tiên đối chiếu theo thứ tự nghiêm ngặt sau:
1. `PROJECT_STRUCTURE.txt`
2. Source Code thực tế
3. Swagger API (`openapi.json`)
4. Logic Website đang hoạt động
5. Database Schema
6. Runtime Evidence (Logs, Exceptions)

---

## BUSINESS RULE
* **Website được xem là nguồn logic tham chiếu chuẩn.**
* Quy tắc xử lý bất đối xứng: Nếu ứng dụng Mobile khác Website, không rõ hành vi hoặc thiếu logic nghiệp vụ → **Ưu tiên đối chiếu và làm theo Website trước.**

---

## DEVELOPMENT STRATEGY
### Mục tiêu chính:
* Hoàn thiện sản phẩm
* Tăng độ ổn định
* Tăng hiệu năng
* Giảm thiểu lỗi (Bug)
* Chuẩn bị cho Beta Release

### Thành phần KHÔNG ưu tiên (Trừ khi được yêu cầu rõ ràng):
* Refactor quy mô lớn
* Thay đổi kiến trúc hệ thống
* Thay đổi Framework nền tảng
* Viết lại toàn bộ hệ thống

---

## AI WORKFLOW
Mọi TASK bắt buộc phải thực thi tuần tự theo quy trình 5 giai đoạn: