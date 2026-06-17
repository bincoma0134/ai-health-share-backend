\# AI\_RULES.md



\# 0. ROOT CAUSE FIRST PRINCIPLE



Không được sửa code trước khi xác định Root Cause.



Không được:



Audit



↓



Đoán



↓



Sửa



Phải:



Audit



↓



Root Cause



↓



Evidence



↓



Fix



\---



\# 1. PHÂN TÍCH TRƯỚC KHI HÀNH ĐỘNG



Luôn:



\* Hiểu Task

\* Hiểu User Flow

\* Hiểu phạm vi thay đổi

\* Hiểu rủi ro



trước khi đề xuất sửa.



\---



\# 2. FILE CLASSIFICATION RULE



Luôn chia file thành:



\## File bắt buộc



\## File nên có



\## File có thể cần



Nếu thiếu file:



Yêu cầu thêm file.



Không suy đoán.



\---



\# 3. USER FLOW FIRST



Trước mọi thay đổi:



Phải mô tả User Flow hiện tại.



Nếu User Flow chưa rõ:



Dừng lại.



Yêu cầu thêm context.



\---



\# 4. SOURCE OF TRUTH RULE



Ưu tiên:



PROJECT\_STRUCTURE.txt



↓



Source Code



↓



Swagger



↓



Website Logic



↓



Database



↓



Runtime Logs



Không được đảo ngược thứ tự.



\---



\# 5. WEBSITE REFERENCE RULE



Nếu cùng tính năng:



Website là nguồn đối chiếu logic mặc định.



Mobile phải đồng bộ logic với Website.



Trừ khi có yêu cầu khác.



\---



\# 6. NO BUSINESS ASSUMPTION



Không được tự suy diễn:



\* Business Logic

\* User Flow

\* Role

\* API Behavior

\* Payment Logic



\---



\# 7. RUNTIME EVIDENCE RULE



Nếu:



\* Đã Audit

\* Đã Fix

\* Vẫn lỗi



=> Bắt buộc yêu cầu:



\* Console Logs

\* Runtime Error

\* Stack Trace

\* Network Logs



Không tiếp tục suy luận từ source.



\---



\# 8. SCREEN-FIRST DEBUGGING



Nếu lỗi UI xuất hiện trên nhiều màn hình:



Không bắt đầu từ Widget.



Bắt đầu từ:



Screen



↓



Shared Component



↓



Shared Service



↓



Root Cause



\---



\# 9. ISOLATION FIRST



Trước khi sửa:



Phải cô lập:



\* File

\* Function

\* Class

\* Logic



gây lỗi.



Không sửa diện rộng.



\---



\# 10. MINIMAL CHANGE PRINCIPLE



Ưu tiên:



Ít file nhất.



Ít code nhất.



Ít rủi ro nhất.



\---



\# 11. NO UNREQUESTED REFACTOR



Không được:



\* Refactor

\* Rename

\* Re-architecture



nếu TASK không yêu cầu.



\---



\# 12. CTRL+H FIRST



Mặc định:



FIND / REPLACE



trước mọi hình thức sửa khác.



\---



\# 13. ONE ROOT CAUSE = ONE FIX



Không gộp nhiều vấn đề.



Không sửa nhiều lỗi trong cùng một thay đổi.



\---



\# 14. FILE CHANGE TRACKING



Sau mỗi lần sửa:



Bắt buộc liệt kê:



\## Files Changed



\## Files Created



\## Files Expected Next Phase



Giúp chuẩn bị file cho vòng tiếp theo.



\---



\# 15. IMPLEMENTATION PHASE RULE



Không được triển khai code khi đang Audit.



Audit và Code phải tách riêng.



\---



\# 16. PERFORMANCE SAFETY RULE



Khi tối ưu:



Không được làm thay đổi:



\* Business Logic

\* API Contract

\* Payment Flow

\* Notification Flow



trừ khi được yêu cầu.



\---



\# 17. PAYMENT SAFETY RULE



Mọi thay đổi liên quan:



\* Booking

\* Invoice

\* Voucher

\* Payment

\* Wallet



phải Audit đầy đủ User Flow trước.



Không được sửa trực tiếp.



\---



\# 18. NOTIFICATION SAFETY RULE



Mọi Notification phải xác định:



\* Trigger

\* Receiver

\* Payload

\* Deep Link

\* Read State



trước khi triển khai.



\---



\# 19. BETA SAFETY RULE



Trước Beta:



Ưu tiên:



\* Bug Fix

\* Stability

\* Performance



Không ưu tiên:



\* Feature Expansion



\---



\# 20. IF UNSURE, ASK



Nếu còn nghi ngờ:



Dừng.



Yêu cầu thêm file.



Yêu cầu thêm context.



Không suy đoán.



