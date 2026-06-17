\# AI\_CONTEXT.md



\## PROJECT CONTEXT



Đây là dự án Full-Stack gồm:



\### Backend



Python



\### Frontend Website



Next.js / React



\### Frontend Mobile



Flutter



\---



\# SOURCE OF TRUTH



Mọi phân tích phải ưu tiên theo thứ tự:



1\. PROJECT\_STRUCTURE.txt

2\. Source Code thực tế

3\. Swagger API (openapi.js)

4\. Logic Website đang hoạt động

5\. Database Schema

6\. Runtime Evidence (Logs, Exceptions)



\---



\# BUSINESS RULE



Website được xem là nguồn logic tham chiếu chuẩn.



Nếu:



\* Mobile khác Website

\* Mobile không rõ hành vi

\* Mobile thiếu logic



=> Ưu tiên đối chiếu Website trước.



\---



\# DEVELOPMENT STRATEGY



Mục tiêu chính:



\* Hoàn thiện sản phẩm

\* Tăng độ ổn định

\* Tăng hiệu năng

\* Giảm bug

\* Chuẩn bị Beta Release



Không ưu tiên:



\* Refactor lớn

\* Đổi kiến trúc

\* Đổi framework

\* Viết lại hệ thống



trừ khi được yêu cầu rõ ràng.



\---



\# AI WORKFLOW



Mọi TASK phải đi theo trình tự:



PHASE 1



Audit



↓



PHASE 2



Root Cause



↓



PHASE 3



Fix Strategy



↓



PHASE 4



Implementation



↓



PHASE 5



Verification



\---



\# FILE DELIVERY RULE



Nếu số file ít:



Ưu tiên gửi toàn bộ nội dung file dạng text.



Không phụ thuộc vào file upload.



\---



Nếu file lớn:



Chia thành nhiều phần.



Ưu tiên source text hơn attachment.



\---



\# RUNTIME EVIDENCE



Nếu bug không được giải quyết sau:



2 vòng Audit



=> Bắt buộc yêu cầu:



\* Console Logs

\* Network Logs

\* Stack Trace

\* Runtime Error

\* API Response



Không tiếp tục suy luận chỉ từ source code.



\---



\# USER FLOW FIRST



Mọi tính năng phải được hiểu từ User Flow trước.



Không được sửa code trước khi xác định:



\* Điểm bắt đầu

\* Điểm kết thúc

\* Dữ liệu đi qua đâu

\* API nào tham gia

\* Database nào tham gia



\---



\# MOBILE PERFORMANCE TARGET



Mục tiêu của Flutter App:



\* Feed mở nhanh

\* Explore mở nhanh

\* TikTok Feed mượt

\* Avatar xuất hiện tức thì

\* Cover xuất hiện tức thì

\* Chuyển tab tức thì

\* Không tải lại dữ liệu không cần thiết

\* Tối ưu RAM

\* Tối ưu Cache

\* Tối ưu Network



\---



\# BETA READINESS GOAL



Trước Beta Release:



Bắt buộc hoàn thành:



\* Booking Flow

\* Payment Flow

\* Wallet Flow

\* AI Feature

\* Notification

\* Performance Optimization

\* Crash Audit

\* UX Consistency Audit



Beta ưu tiên:



Ổn định > Tính năng mới



