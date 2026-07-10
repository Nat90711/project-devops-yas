# 📋 Báo Cáo Hoàn Chỉnh Quá Trình Thực Hiện – Thành Viên 3 (ArgoCD GitOps & CD)

**Thông tin chung:**
- **Mục tiêu:** Thay thế toàn bộ phần Jenkins CD cho dev/staging (GitOps).
- **Hạ tầng:** GCP VM (136.110.22.108) – Minikube (IP nội bộ: 192.168.49.2) – 32GB RAM.

---

## 1. Chuẩn bị môi trường & Cài đặt ArgoCD

**Quá trình thực hiện:**
- Tiếp quản Cluster & Repository: Nhận bàn giao cụm K8s Minikube/K3s đã cài đặt các thành phần cơ bản và mã nguồn dự án YAS.
- Tiến hành cài đặt ArgoCD lên Kubernetes Cluster thông qua manifest chuẩn của ArgoProj.
- Cấu hình expose dịch vụ `argocd-server` ra ngoài thông qua NodePort (30200) và thiết lập Port-Forward (cổng 8090) để có thể truy cập giao diện ArgoCD UI từ Internet.
- Lấy mật khẩu admin khởi tạo mặc định và đăng nhập thành công vào ArgoCD CLI/UI.

> 📸 **[ẢNH CẦN THÊM 1]:** Giao diện ArgoCD UI truy cập thành công qua trình duyệt (đăng nhập bằng IP `136.110.22.108:8090` hoặc NodePort).
> 📸 **[ẢNH CẦN THÊM 2]:** Dashboard của ArgoCD sau khi đăng nhập thành công.

---

## 2. Xây dựng cấu trúc GitOps & Quản lý Helm Dependencies

**Quá trình thực hiện:**
- Tạo cấu trúc thư mục chuẩn GitOps trong Repository tại đường dẫn `k8s/environments/`.
- Cấu trúc bao gồm các thư mục `argocd` (chứa định nghĩa các ArgoCD Applications), `dev` và `staging` (chứa file `values.yaml` quản lý phiên bản image riêng biệt cho từng môi trường).
- **Xử lý Helm Dependencies:** Khắc phục triệt để lỗi `Chart.lock` out of sync bằng cách ép Git theo dõi file `.lock` (sử dụng lệnh `git add -f`), đảm bảo ArgoCD có thể render Helm Template một cách hoàn hảo khi sync.

> 📸 **[ẢNH CẦN THÊM 3]:** Hình ảnh cấu trúc thư mục `k8s/environments` (dev, staging, argocd) trên GitHub Repository.

---

## 3. Tạo ArgoCD Applications và Phân tách môi trường

**Quá trình thực hiện:**
- **Phân tách môi trường (dev & staging):** Giải quyết các xung đột liên quan đến Ingress (trùng Hostname, đụng độ swagger-ui) giữa namespace `dev` và `staging`.
- Khởi tạo 2 ArgoCD Application quản lý 2 môi trường:
  - **`yas-dev`**: Cấu hình chế độ **Auto-Sync** (`automated: prune: true, selfHeal: true`). Bất kỳ thay đổi nào trên branch chỉ định sẽ lập tức được cập nhật xuống cluster.
  - **`yas-staging`**: Cấu hình chế độ **Manual Sync**. Chỉ đồng bộ khi nhận được trigger thủ công (từ Jenkins khi có release tag).

> 📸 **[ẢNH CẦN THÊM 4]:** Trạng thái của Application `yas-dev` hiển thị **Synced + Healthy** (màu xanh mượt) trên giao diện ArgoCD UI.
> 📸 **[ẢNH CẦN THÊM 5]:** Trạng thái của Application `yas-staging` hiển thị **Synced** trên giao diện ArgoCD UI.

---

## 4. Giải quyết bài toán tài nguyên Minikube (Tối ưu hóa)

**Khó khăn gặp phải:**
- Nhận thấy Minikube liên tục bị quá tải CPU (CrashLoopBackOff) khi khởi động hàng chục ứng dụng Spring Boot cùng lúc.

**Giải pháp:**
- Đã sáng tạo và áp dụng thành công script `scale-dev-sequential.sh`.
- **Nguyên lý hoạt động:** Tắt toàn bộ ứng dụng (scale về 0), sau đó khởi động tuần tự từng dịch vụ một (chờ dịch vụ trước chuyển sang trạng thái Ready mới bật dịch vụ sau). 
- **Kết quả:** Nhờ tối ưu hóa, cả hai môi trường `staging` và `dev` đều đã được khởi động và duy trì ở trạng thái "xanh mượt" (Healthy).

---

## 5. Cấu hình Webhook Tự Động (GitHub -> ArgoCD)

**Quá trình thực hiện:**
- Thiết lập Webhook trên GitHub Repository trỏ về địa chỉ IP Public của ArgoCD Server (`https://136.110.22.108:8090/api/webhook`).
- Đảm bảo ArgoCD ngay lập tức nhận được tín hiệu (push event) mỗi khi có sự thay đổi cấu hình trên nhánh GitOps (thay vì phải đợi 3 phút theo chu kỳ pull mặc định của ArgoCD).

> 📸 **[ẢNH CẦN THÊM 6]:** Cấu hình Webhook trên GitHub hiển thị trạng thái kết nối thành công (Dấu tick xanh ✅ 200 OK).

---

## 6. Can thiệp Pipeline CI/CD (Tích hợp Jenkins CI -> GitOps)

**Quá trình thực hiện:**
- Phối hợp mở rộng file `Jenkinsfile` ban đầu (vốn chỉ build và push image).
- Thêm logic sử dụng lệnh `sed` để tự động thay thế `imageTag` trong các file `values.yaml` của dev và staging bằng mã băm `COMMIT_ID` mới nhất.
- Khắc phục thành công lỗi Bash ("Bad substitution") trong Pipeline bằng cách tinh chỉnh cú pháp Groovy String.
- Cấu hình Jenkins tự động commit và Force Push các thay đổi cấu hình (values.yaml) lên Repository.

> 📸 **[ẢNH CẦN THÊM 7]:** Hình ảnh Commit History trên repo GitHub, hiển thị rõ các commit do **Jenkins CI Bot** tự động thực hiện (ví dụ: `ci: update dev image tag to <commit-id>`).
> 📸 **[ẢNH CẦN THÊM 8]:** Log của Jenkins Pipeline hiển thị quá trình chạy thành công các stage Build & Update GitOps.

---

## 7. Test End-to-End & Sơ đồ Luồng GitOps

**Thực thi Kịch bản Kiểm thử:**
1. Developer thay đổi một file nhỏ (`tax/README.md`) trên mã nguồn, tạo Pull Request và Merge vào `main`.
2. GitHub bắn sự kiện cho Jenkins thông qua Webhook CI.
3. Jenkins chạy Pipeline, Build Docker Image mới cho `tax`, tạo tag mới.
4. Jenkins tự động sửa file `values.yaml` và Push sang repository.
5. GitHub bắn Webhook GitOps sang ArgoCD.
6. ArgoCD phát hiện sự thay đổi, tự động (Auto-Sync) kéo cấu hình mới về Kubernetes.
7. Kubernetes thực hiện Rolling Update để thay thế phiên bản cũ bằng phiên bản mới.

**Kết quả cuối cùng:**
- Quá trình diễn ra tự động 100%, không cần sự can thiệp của con người.
- Thực hiện lệnh đánh tag release (`git tag v1.0.0`) thành công mỹ mãn cho môi trường staging.

**Sơ đồ luồng GitOps hoàn chỉnh:**
```text
Developer Push Code
       │
       ▼
  GitHub Repo ──webhook──▶ ArgoCD (nhận diện thay đổi lập tức)
       │
       ▼
 Jenkins CI Pipeline
   ├── Build Docker Image
   ├── Push to Docker Hub (tag: <commit-id>)
   └── Update k8s/environments/dev/values.yaml
              │
              ▼
         Git Commit (CI Bot)
              │
              ▼ (webhook)
         ArgoCD yas-dev
              │
              ▼ (auto-sync)
        Namespace: dev (K8S)
```

> 📸 **[ẢNH CẦN THÊM 9]:** Kết quả lệnh `kubectl get pods -n dev` hiển thị toàn bộ Pods trạng thái Running sau khi luồng GitOps hoàn tất.
> 📸 **[ẢNH CẦN THÊM 10]:** Danh sách các ArgoCD App thông qua lệnh CLI (`argocd app list`).
