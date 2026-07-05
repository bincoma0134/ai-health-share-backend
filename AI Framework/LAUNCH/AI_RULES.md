# AI_RULES.md


## Đặc biệt quan trọng, quan trọng nhất là nguyên tắc CTRL+H:
* Mặc định sử dụng cơ chế Tìm kiếm / Thay thế (`FIND / REPLACE`) trực tiếp trước khi áp dụng bất kỳ hình thức chỉnh sửa code nào khác.
* Gửi Find và Replace thành 2 khối code riêng biệt - 2 box typescript riêng biệt.
* Trong box Typescript chỉ có code, không thêm chú thích FIND / REPLACE trong box, sẵn sàng copy-paste tức thời.

## 0. ROOT CAUSE FIRST PRINCIPLE
Không được sửa code trước khi xác định Root Cause.
* **Quy trình cấm:** Audit → Đoán → Sửa
* **Quy trình bắt buộc:** Audit → Root Cause → Evidence → Fix

---

## 1. PHÂN TÍCH TRƯỚC KHI HÀNH ĐỘNG
Luôn luôn thấu hiểu các yếu tố sau trước khi đề xuất bất kỳ chỉnh sửa nào:
* Hiểu Task
* Hiểu User Flow
* Hiểu phạm vi thay đổi
* Hiểu rủi ro

---

## 2. FILE CLASSIFICATION RULE
Luôn chia các file liên quan thành nhóm rõ ràng:
* **File bắt buộc**
* **File nên có**
* **File có thể cần**

> **Nguyên tắc:** Nếu thiếu file, phải yêu cầu người dùng cung cấp thêm. Tuyệt đối không tự suy đoán.

---

## 3. USER FLOW FIRST
* Trước mọi thay đổi, bắt buộc phải mô tả trực quan và chính xác User Flow hiện tại.
* Nếu User Flow chưa rõ ràng: **DỪNG LẠI**, yêu cầu cung cấp thêm ngữ cảnh (context).

---

## 4. SOURCE OF TRUTH RULE
Thứ tự ưu tiên đối chiếu thông tin (Không được đảo ngược thứ tự):
1. `PROJECT_STRUCTURE.txt`
2. Source Code thực tế
3. Swagger API (`openapi.json`)
4. Website Logic
5. Database Schema
6. Runtime Logs

---

## 5. WEBSITE REFERENCE RULE
* Nếu cùng một tính năng, hệ thống mặc định lấy **Website làm nguồn đối chiếu logic chuẩn**.
* Mobile bắt buộc phải đồng bộ logic theo Website trừ khi có yêu cầu đặc biệt khác.

---

## 6. NO BUSINESS ASSUMPTION
Tuyệt đối không được tự suy diễn hoặc giả định các logic liên quan đến nghiệp vụ:
* Business Logic
* User Flow
* Phân quyền (Role)
* Hành vi API (API Behavior)
* Logic thanh toán (Payment Logic)

---

## 7. RUNTIME EVIDENCE RULE
Nếu hệ thống đã được **Audit** và **Fix** nhưng vẫn xảy ra lỗi, bắt buộc phải yêu cầu cung cấp:
* Console Logs
* Runtime Error
* Stack Trace
* Network Logs

> **Nguyên tắc:** Không tiếp tục suy luận một chiều từ source code khi chưa có bằng chứng thực tế.

---

## 8. SCREEN-FIRST DEBUGGING
Nếu lỗi giao diện (UI) xuất hiện đồng thời trên nhiều màn hình, quy trình phân tích điểm bắt đầu như sau:
* Screen → Shared Component → Shared Service → Root Cause (Không bắt đầu từ Widget đơn lẻ).

---

## 9. ISOLATION FIRST
Trước khi sửa đổi, phải cô lập chính xác phạm vi gây lỗi:
* Cô lập theo: File, Function, Class, Logic.
* Tuyệt đối không sửa đổi tràn lan trên diện rộng.

---

## 10. MINIMAL CHANGE PRINCIPLE
Ưu tiên giải pháp tối giản nhất:
* Ảnh hưởng ít file nhất.
* Viết ít dòng code nhất.
* Tạo ra ít rủi ro hệ thống nhất.

---

## 11. NO UNREQUESTED REFACTOR
Tuyệt đối không tự ý thực hiện các hành động sau nếu TASK không có yêu cầu cụ thể:
* Refactor (Cấu trúc lại code)
* Rename (Đổi tên file/biến/hàm)
* Re-architecture (Thay đổi kiến trúc hệ thống)

---

## 12. CTRL+H FIRST
* Mặc định sử dụng cơ chế Tìm kiếm / Thay thế (`FIND / REPLACE`) trực tiếp trước khi áp dụng bất kỳ hình thức chỉnh sửa code nào khác.
* Gửi Find và Replace thành 2 khối code riêng biệt - 2 box typescript riêng biệt.
* Trong box Typescript chỉ có code, không thêm chú thích FIND / REPLACE trong box, sẵn sàng copy-paste tức thời.

---

## 13. ONE ROOT CAUSE = ONE FIX
* Không gộp nhiều vấn đề khác nhau vào chung một giải pháp.
* Không sửa đổi nhiều lỗi không liên quan trong cùng một lượt cập nhật.

---

## 14. FILE CHANGE TRACKING
Sau mỗi lần chỉnh sửa, bắt buộc phải liệt kê rõ ràng các danh mục:
* `## Files Changed`
* `## Files Created`
* `## Files Expected Next Phase`

---

## 15. IMPLEMENTATION PHASE RULE
* Không được triển khai, viết code hoặc thay đổi mã nguồn khi đang trong quá trình Audit.
* Giai đoạn phân tích (Audit) và giai đoạn thực thi (Code) phải hoàn toàn tách biệt.

---

## 16. PERFORMANCE SAFETY RULE
Khi thực hiện tối ưu hóa hiệu năng, tuyệt đối không làm thay đổi các thành phần cốt lõi:
* Business Logic
* API Contract
* Payment Flow
* Notification Flow

---

## 17. PAYMENT SAFETY RULE
Mọi thay đổi liên quan đến các phân hệ tài chính và đặt lịch bắt buộc phải Audit đầy đủ User Flow trước khi sửa, không được sửa trực tiếp:
* Booking, Invoice, Voucher, Payment, Wallet.

---

## 18. NOTIFICATION SAFETY RULE
Mọi thông báo (Notification) trước khi triển khai phải xác định rõ 5 yếu tố:
* Trigger (Điểm kích hoạt)
* Receiver (Đối tượng nhận)
* Payload (Dữ liệu truyền tải)
* Deep Link (Liên kết điều hướng)
* Read State (Trạng thái đọc)

---

## 19. BETA SAFETY RULE
Trong giai đoạn chuẩn bị cho Beta Release, thứ tự ưu tiên được thiết lập như sau:
* **Ưu tiên:** Bug Fix > Stability (Độ ổn định) > Performance (Hiệu năng).
* **Không ưu tiên:** Feature Expansion (Mở rộng tính năng mới).

---

## 20. IF UNSURE, ASK
* Nếu còn bất kỳ điểm nghi ngờ nào chưa rõ ràng: **DỪNG LẠI**. 
* Chủ động yêu cầu thêm file hoặc ngữ cảnh (context), tuyệt đối không suy đoán bừa bãi.