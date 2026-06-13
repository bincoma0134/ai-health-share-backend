\# AI\_RULES.md



\## Mục tiêu



Các quy tắc này nhằm:



\* Giảm ảo giác (Hallucination)

\* Giảm sửa sai phạm vi

\* Giảm Refactor không cần thiết

\* Tăng tốc độ phát triển

\* Tăng khả năng kiểm soát thay đổi

\* Tăng khả năng rollback

\* Đảm bảo AI hoạt động như một Senior Developer hỗ trợ dự án hiện có



\---



\# 1. Phân tích trước khi hành động



Luôn phân tích trước khi đề xuất sửa đổi.



Không được nhảy thẳng vào code.



Trước tiên phải:



\* Hiểu TASK

\* Hiểu phạm vi thay đổi

\* Hiểu ảnh hưởng của thay đổi



\---



\# 2. Xác định file trước khi sửa



Trước mọi thay đổi phải xác định:



\## File bắt buộc



Các file không thể thiếu để thực hiện TASK.



\## File nên có



Các file giúp hiểu rõ hơn logic liên quan.



\## File có thể cần



Các file chỉ cần khi phát sinh nhánh logic bổ sung.



Nếu chưa đủ file:



Yêu cầu thêm file.



Không được suy đoán.



\---



\# 3. Không giả định nghiệp vụ



Không được:



\* Tự suy diễn business logic

\* Tự suy diễn user flow

\* Tự suy diễn quyền hạn người dùng

\* Tự suy diễn API behavior



Nếu chưa rõ:



Yêu cầu thêm context.



\---



\# 4. Không thay đổi hệ thống lõi



Không được tự ý thay đổi:



\* API

\* Database Schema

\* Authentication Flow

\* Authorization Flow

\* Role System

\* Security Logic

\* Payment Logic



Trừ khi TASK yêu cầu rõ ràng.



\---



\# 5. Ưu tiên đúng phạm vi TASK



Chỉ xử lý những gì TASK yêu cầu.



Không mở rộng phạm vi.



Không thêm tính năng ngoài yêu cầu.



Không "tiện tay tối ưu".



Không "tiện tay refactor".



\---



\# 6. Không Refactor ngoài phạm vi



Không được:



\* Đổi cấu trúc thư mục

\* Đổi kiến trúc

\* Đổi pattern

\* Đổi naming convention

\* Đổi state management



Nếu không liên quan trực tiếp đến TASK.



\---



\# 7. Giải thích trước khi sửa



Trước khi đề xuất thay đổi phải nêu:



\## Nguyên nhân



Tại sao cần sửa.



\## File cần sửa



Các file liên quan.



\## Ảnh hưởng



Tác động của thay đổi.



\---



\# 8. Thiếu context phải hỏi



Nếu chưa đủ thông tin:



Dừng lại.



Yêu cầu thêm file.



Yêu cầu thêm context.



Không suy đoán.



\---



\# 9. Website là nguồn tham chiếu logic



Khi hành vi Mobile chưa rõ:



Ưu tiên tham chiếu:



Website hiện tại.



Website được xem là nguồn logic chuẩn nếu TASK không quy định khác.



\---



\# 10. Ưu tiên giải pháp đơn giản nhất



Luôn ưu tiên:



\* Ít thay đổi nhất

\* Ít file nhất

\* Ít rủi ro nhất



Trước khi đề xuất giải pháp phức tạp.



\---



\# 11. Minimal Change Principle



Nguyên tắc sửa đổi tối thiểu.



Chỉ sửa:



\* Đúng vị trí cần sửa

\* Đúng logic cần sửa



Không viết lại toàn bộ file nếu không cần.



Không tái cấu trúc file nếu không cần.



\---



\# 12. Ctrl + H First Principle



Mặc định sử dụng phương pháp:



FIND / REPLACE



trước mọi hình thức chỉnh sửa khác.



Ưu tiên:



Thay đổi nhỏ

→ FIND / REPLACE



Thay đổi vừa

→ FIND / REPLACE



Chỉ khi bất khả thi mới xuất toàn bộ file.



\---



\# 13. Khi nào được xuất toàn bộ file



Chỉ được xuất toàn bộ file khi:



\* File mới hoàn toàn

\* Cấu trúc file thay đổi lớn

\* FIND / REPLACE không còn khả thi

\* TASK yêu cầu rõ ràng



Ngoài các trường hợp trên:



Phải dùng FIND / REPLACE.



\---



\# 14. Đánh giá FIND / REPLACE trước



Trước khi sửa:



Luôn tự đánh giá:



"Có thể giải quyết bằng FIND / REPLACE không?"



Nếu có:



Bắt buộc sử dụng FIND / REPLACE.



\---



\# 15. Mọi thay đổi phải dễ rollback



Mọi thay đổi phải:



\* Dễ áp dụng

\* Dễ kiểm tra

\* Dễ rollback

\* Dễ audit



\---



\# 16. Strict FIND / REPLACE Format



Khi xuất chỉnh sửa:



Luôn sử dụng cấu trúc:



FILE:

<đường dẫn file>



FIND:



<code block>



REPLACE:



<code block>



Yêu cầu:



\* FIND nằm ngoài code block

\* REPLACE nằm ngoài code block

\* Code block chỉ chứa code



Không được đặt bên trong code block:



\* FIND:

\* REPLACE:

\* Notes

\* Comments

\* Explanations

\* Markdown

\* AI annotations



Code phải có khả năng:



\* Copy trực tiếp

\* Paste trực tiếp

\* Sử dụng trực tiếp



Không cần chỉnh sửa thủ công.



\---



\# 17. One Change = One FIND / REPLACE



Mỗi thay đổi phải được tách riêng.



Ưu tiên:



\# 1 thay đổi



1 FIND

\+

1 REPLACE



Không gộp nhiều thay đổi không liên quan.



Điều này giúp:



\* Kiểm tra dễ hơn

\* Rollback dễ hơn

\* Audit dễ hơn



\---



\# 18. Không được rút gọn code



Không sử dụng:



\* ...

\* existing code

\* unchanged code

\* keep remaining code

\* omitted for brevity



FIND phải tồn tại thực tế trong source code.



REPLACE phải đầy đủ và khả dụng ngay.



\---



\# 19. Không được tạo Placeholder Logic



Không tạo:



\* TODO giả

\* Fake implementation

\* Mock business logic

\* Temporary workaround



trừ khi TASK yêu cầu.



\---



\# 20. Ưu tiên bảo toàn hệ thống hiện có



Mọi thay đổi phải cố gắng:



\* Giữ nguyên API

\* Giữ nguyên routing

\* Giữ nguyên state

\* Giữ nguyên flow



trừ khi TASK yêu cầu thay đổi.



\---



\# 21. Ưu tiên hoàn thiện thay vì làm mới



Đây là dự án đang vận hành.



Ưu tiên:



\* Hoàn thiện

\* Bổ sung

\* Nâng cấp



Không ưu tiên:



\* Viết lại

\* Thiết kế lại từ đầu

\* Tái cấu trúc toàn bộ



trừ khi TASK yêu cầu.



\---



\# 22. Nếu có nghi ngờ, hãy hỏi



Nếu tồn tại bất kỳ nghi ngờ nào về:



\* Logic

\* Flow

\* API

\* Role

\* Routing

\* Data Mapping



Hãy yêu cầu thêm file hoặc context.



Không được tự suy đoán.



