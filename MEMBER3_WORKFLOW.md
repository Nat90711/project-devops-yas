# Tổng Kết Quá Trình Làm Việc - Thành viên 3 (GitOps & CD)

Tài liệu này tóm tắt lại toàn bộ hành trình xây dựng hệ thống GitOps CI/CD từ A-Z mà Thành viên 3 đã thực hiện.

## 1. Chuẩn bị môi trường & Cấu hình ArgoCD (Bước 1 - 3)
- **Tiếp quản Cluster & Repository:** Nhận bàn giao cụm K8s Minikube/K3s đã cài sẵn ArgoCD và mã nguồn dự án YAS.
- **Xử lý Helm Dependencies:** Xử lý triệt để lỗi `Chart.lock` out of sync bằng cách ép Git theo dõi file `.lock` (lệnh `git add -f`), đảm bảo ArgoCD có thể render Helm Template một cách hoàn hảo.
- **Phân tách môi trường (dev & staging):** 
  - Khắc phục các xung đột Ingress (như trùng Hostname, đụng độ swagger-ui) giữa `dev` và `staging`.
  - Thiết lập thành công hai Application trong ArgoCD: `yas-dev` (Auto-Sync) và `yas-staging` (Manual Sync).

## 2. Giải quyết bài toán tài nguyên Minikube
- Nhận thấy Minikube liên tục bị quá tải CPU (CrashLoopBackOff) khi khởi động hàng chục ứng dụng Spring Boot cùng lúc.
- Đã sáng tạo và áp dụng thành công script `scale-dev-sequential.sh`.
- **Nguyên lý:** Tắt toàn bộ ứng dụng (scale về 0) sau đó khởi động tuần tự từng dịch vụ một (chờ dịch vụ trước Ready mới bật dịch vụ sau). Nhờ đó, cả `staging` và `dev` đều đã được khởi động "xanh mượt" (Healthy).

## 3. Cấu hình Webhook cho luồng tự động (Bước 4)
- Vào GitHub Repository, thiết lập Webhook trỏ về địa chỉ IP Public của ArgoCD Server (kèm cổng 8090 đã port-forward).
- Đảm bảo ArgoCD ngay lập tức nhận được tín hiệu (push event) mỗi khi có sự thay đổi trên nhánh `gitops`, thay vì phải đợi 3 phút theo chu kỳ mặc định.

## 4. Can thiệp Pipeline CI/CD (Bước 5)
- Mở rộng file `Jenkinsfile` ban đầu (vốn chỉ build và push image).
- Thêm logic dùng lệnh `sed` để tự động thay thế `imageTag` trong các file `values.yaml` của dev và staging bằng mã băm `COMMIT_ID` mới nhất.
- Khắc phục thành công lỗi Bash ("Bad substitution") bằng cách tinh chỉnh cú pháp Groovy String.
- Cấu hình Jenkins tự động commit và Force Push các file cấu hình này sang nhánh `gitops`.

## 5. Test End-to-End thành công (Bước 6)
- **Thực thi Kịch bản:** Thay đổi một file nhỏ (`tax/README.md`) trên mã nguồn, tạo Pull Request và Merge vào `main`.
- **Chuỗi phản ứng tự động:**
  1. GitHub báo cho Jenkins.
  2. Jenkins chạy Pipeline, Build Docker Image mới cho `tax`, tạo tag mới.
  3. Jenkins sửa `values.yaml` và Push sang nhánh `gitops`.
  4. GitHub bắn Webhook sang ArgoCD.
  5. ArgoCD phát hiện sự thay đổi, tự động (Auto-Sync) kéo cấu hình mới về K8s.
  6. Kubernetes thực hiện Rolling Update để thay thế phiên bản cũ bằng phiên bản mới.
- **Kết quả:** Quá trình diễn ra tự động 100%, không cần sự can thiệp của con người. Minikube xử lý gọn gàng và toàn bộ hệ thống dev đã trở lại trạng thái xanh mượt 2/2.
- **Hoàn thành:** Thực hiện lệnh `git tag v1.0.0` để đánh dấu release đầu tiên thành công mỹ mãn!
