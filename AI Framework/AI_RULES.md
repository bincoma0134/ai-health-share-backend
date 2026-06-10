AI RULES

Luôn phân tích trước khi đề xuất sửa đổi.

Trước tiên hãy xác định:

File bắt buộc

File nên có

File có thể cần

Không được giả định logic nghiệp vụ.

Không được tự thay đổi:

API

Database Schema

Authentication Flow

Role System

trừ khi TASK yêu cầu.

Ưu tiên sửa đúng phạm vi TASK.

Không refactor các module không liên quan.

Khi đề xuất sửa code phải giải thích:

Nguyên nhân

File cần sửa

Ảnh hưởng

Nếu chưa đủ context:

Hãy yêu cầu thêm file thay vì suy đoán.

Website hiện tại là nguồn tham chiếu logic ưu tiên khi Mobile có hành vi chưa rõ.

Luôn cố gắng tìm giải pháp đơn giản nhất trước.

Ưu tiên chỉnh sửa tối thiểu (Minimal Change Principle):

Chỉ sửa đúng phần cần thiết.

Không viết lại hoặc tái cấu trúc toàn bộ file nếu không thực sự cần thiết.

Mặc định sử dụng phương pháp Ctrl + H (FIND / REPLACE):

Khi sửa code:

Ưu tiên xuất theo định dạng:

FILE:

<đường dẫn file>

FIND:

<đoạn code cần tìm>

REPLACE:

<đoạn code thay thế>

FIND phải đủ đặc trưng để xác định chính xác vị trí sửa.

REPLACE phải giữ nguyên các logic không liên quan.

Không xuất lại toàn bộ file nếu chỉ sửa một phần nhỏ.

Chỉ xuất toàn bộ file khi:

File mới hoàn toàn.

Thay đổi ảnh hưởng phần lớn cấu trúc file.

FIND / REPLACE không còn khả thi.

Trước khi đề xuất sửa đổi, hãy đánh giá:

Có thể giải quyết bằng FIND / REPLACE không?

Nếu có, phải ưu tiên FIND / REPLACE.

Mọi thay đổi phải đảm bảo:

Dễ áp dụng.

Dễ kiểm tra.

Dễ rollback.









