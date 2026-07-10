# Tổng hợp Lỗi và Cách Khắc Phục (Member 3 - GitOps & CD)

Trong quá trình thiết lập luồng CI/CD và GitOps với ArgoCD, chúng ta đã gặp và giải quyết thành công các vấn đề sau:

## 1. Lỗi thiếu file Chart.lock khi build Helm Dependency
- **Hiện tượng:** Jenkins báo lỗi `Error: the lock file (Chart.lock) is out of sync with the dependencies file (Chart.yaml). Please update the dependencies` khi chạy `helm dependency build`.
- **Nguyên nhân:** File `Chart.lock` được sinh ra ở local nhưng bị quy tắc của `.gitignore` bỏ qua, dẫn đến việc không được push lên Git. Môi trường CI không có file này nên báo lỗi out of sync.
- **Cách khắc phục:** Ép Git theo dõi file bằng lệnh `git add -f k8s/charts/yas-all/Chart.lock`, sau đó commit và push lên repository.

## 2. Xung đột Ingress giữa môi trường dev và staging
- **Hiện tượng:** Không thể deploy cùng lúc `yas-dev` và `yas-staging` do lỗi trùng lặp Ingress Rule hoặc sai cấu trúc YAML.
- **Nguyên nhân:** Các giá trị trong `values.yaml` của dev và staging trỏ cùng về một cấu trúc `ingress.hosts` không hợp lệ, đồng thời `swagger-ui` ở hai môi trường đụng độ nhau trên cùng một cluster.
- **Cách khắc phục:** 
  - Tắt Ingress của swagger-ui bằng cách set `swagger-ui.ingress.enabled: false`.
  - Chuẩn hóa lại các host riêng biệt (ví dụ `dev-storefront.yas.local.com` và `staging-storefront.yas.local.com`) trong từng file `values.yaml` của môi trường.

## 3. Các Pod bị lỗi CrashLoopBackOff / Connection Refused
- **Hiện tượng:** Sau khi ArgoCD sync, hàng loạt pod backend rơi vào trạng thái `0/2`, log báo lỗi `Readiness probe failed... connection refused` và restart liên tục.
- **Nguyên nhân:** Giới hạn tài nguyên (CPU/RAM) của Minikube. Khi ArgoCD bật cùng lúc 15 ứng dụng Spring Boot, CPU bị nghẽn (throttling), khiến các ứng dụng không kịp khởi động trong thời gian timeout của liveness/readiness probe.
- **Cách khắc phục:** Sử dụng script `scale-dev-sequential.sh` để scale toàn bộ deployment về 0, sau đó khởi động tuần tự từng dịch vụ một. Cách này giúp Minikube có thời gian thở và khởi động thành công 100% các pod.

## 4. ArgoCD báo trạng thái OutOfSync dù Pod vẫn Healthy
- **Hiện tượng:** Giao diện ArgoCD báo 6 tài nguyên bị `OutOfSync`, xem Diff thì thấy `replicas: 0` (đỏ) và `replicas: 1` (xanh).
- **Nguyên nhân:** Script `scale-dev-sequential.sh` đã thủ công nâng replica của tất cả deployment lên 1. Tuy nhiên, trên Git (`values.yaml`), một số dịch vụ không cần thiết (`rating`, `recommendation`, `webhook`, `sampledata`, `location`) đã được set cố định `replicaCount: 0` để tiết kiệm RAM.
- **Cách khắc phục:** Mặc kệ để tính năng Auto-Sync của ArgoCD tự động dọn dẹp, hoặc ấn nút Sync thủ công. ArgoCD sẽ tự động ép các dịch vụ thừa này về lại 0 đúng như cấu hình trên Git.

## 5. Lỗi "Bad substitution" trong pipeline Jenkins
- **Hiện tượng:** Lỗi `script.sh.copy: 25: Bad substitution` xuất hiện ở stage "Deploy to GitOps Branch" của Jenkins.
- **Nguyên nhân:** Do sai sót về cú pháp String interpolation giữa Groovy và Bash. Biến được viết là `\${env.COMMIT_ID}` trong chuỗi `"""`, khiến Groovy không dịch nó mà ném nguyên chuỗi `${env.COMMIT_ID}` sang cho Bash. Bash không chấp nhận biến có dấu chấm (`.`) nên báo lỗi.
- **Cách khắc phục:** Xóa dấu gạch chéo ngược, đổi thành `${env.COMMIT_ID}` để Groovy tự động dịch ra mã băm của commit trước khi ném lệnh `sed` sang cho Bash thực thi.

## 6. Luồng GitOps không tự động chạy khi push code
- **Hiện tượng:** Push code test lên nhánh `fix/argocd-ingress-staging-dev` nhưng ArgoCD không tự cập nhật image mới.
- **Nguyên nhân:** Trong `Jenkinsfile`, stage "Deploy to GitOps Branch" được đặt điều kiện `when { branch 'main' }`. Nên khi test trên nhánh feature, Jenkins đã âm thầm bỏ qua bước cập nhật GitOps.
- **Cách khắc phục:** Hiểu đúng luồng CI/CD: Tạo Pull Request và Merge nhánh tính năng vào nhánh `main` để kích hoạt toàn bộ chu trình chuẩn.
