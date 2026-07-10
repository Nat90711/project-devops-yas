# Đồ án 2: Xây dựng hệ thống CD

---

## I. Mô tả

Trong môn học này các bạn được yêu cầu xây dựng một quy trình, hệ thống ci/cd và monitor để có thể deploy, vận hành và giám sát được hệ thống **"YAS: Yet Another Shop"** từ link sau: [https://github.com/nashtech-garage/yas](https://github.com/nashtech-garage/yas)

YAS là một dự án cá nhân nhằm mục đích thực hành xây dựng một ứng dụng microservice điển hình bằng Java.

### Các công nghệ và framework

- Java 21
- Spring Boot 3.2
- Testcontainers
- Next.js
- Keycloak
- Kafka
- Elasticsearch
- K8s
- GitHub Actions
- SonarCloud
- OpenTelemetry
- Grafana, Loki, Prometheus, Tempo

---

## II. Yêu cầu

Đây là đồ án 1 trong chuỗi đồ án môn học DevOps, trong đồ án này các bạn cần sử dụng Jenkins/Github Actions/... để xây dựng pipeline cho quá trình CD với những yêu cầu cụ thể sau **(6đ)**:

- Mặc định, các bạn sẽ có 1 image cho tất cả các service với tag là `main` hoặc `latest`, bạn không cần triển khai Grafana và Prometheus (Observability) trong đồ án này.

- Xây dựng K8S cluster với 1 Master node và 1 Worker Node (hoặc **Minikube, hoặc bất kỳ mô hình K8S nào**).

- Phần CI: với mỗi branch của user tạo, sau khi user commit code thay đổi, bạn phải build ra một image với tag là commit id cuối cùng của branch đó, và push image đó lên Docker Hub.

- Tạo Job CD cho developer làm việc với tên `developer_build`. Với job này developer có thể input parameter là branch muốn deploy.

  > **Ví dụ:** developer đang làm việc ở branch `dev_tax_service` và update code trong service này. Developer cần biết được sau khi sửa code, thì muốn test thử. Lúc này developer sẽ vào `developer_build` job để điền phần `tax-service` parameter là `dev_tax_service`, còn các branch còn lại là `main`. Khi đó bạn sẽ deploy code của tất cả các service còn lại theo default là tag `main` hoặc `latest`, còn `dev_tax_service` sẽ là image với tag ở mục 3.
  >
  > Sau khi deploy, bạn cung cấp `domain name:port` (dạng service là NodePort), để developer có thể truy cập và test code của mình trực tiếp. Phần domain name, do mình không có DNS, vì vậy developer sẽ tự thêm vào file `hosts` của mình trên máy để chỉ đến Worker node của K8s cluster.

- Tạo Jenkins job để xóa phần triển khai ở mục 4.

- **Bỏ qua phần này nếu làm phần Nâng Cao:** Tương tự, trên Jenkins tạo ra 2 job CI/CD để deploy `dev` và `staging`:
  - `main` thay đổi, auto sẽ deploy đè liên tục vào trong namespace `dev`.
  - `staging`: trên `main` branch sẽ có dạng tag để có dạng release, ví dụ tag `v1.2.3`, thì job CI/CD sẽ phát hiện và build image với tag cuối cùng, ví dụ tag `v1.2.3` (hoặc tách branch `rc_v1.2.3`, hoặc vừa tag và tách branch), sau đó push images này lên Docker Hub và deploy vào trong namespace `staging`.

### Nâng cao

- **(2đ):** Sử dụng ArgoCD để handle được `dev` và `staging`.
- **(2đ):** Thực hành cấu hình Service Mesh (mTLS, chính sách kết nối) trên K8S cho ứng dụng microservices:
  1. Enable TLS (mTLS) giữa các service deploy trên K8S cho ứng dụng YAS.
  2. Vẽ flow chart/Topology của các service (sử dụng Kiali để quan sát).
  3. Chuẩn bị kịch bản test:
     - **Retryable:** nếu service trả lỗi 500 thì retry tự động (định nghĩa retry policy trong service mesh).
     - **Setup policy:** chỉ những service nào được phép giao tiếp với nhau mới connect được (authorization policy).
     - **Test:** vào pod khác trong cluster, thực hiện `curl` tới service để kiểm tra xem policy cho phép hay chặn kết nối.

### Gợi ý triển khai (Service Mesh)

- Option phổ biến: **Istio** (cài trên K8S) + **Kiali** để visualize.
- Bật mTLS toàn mesh hoặc cho từng namespace bằng `PeerAuthentication`/`DestinationRule`.
- Dùng `AuthorizationPolicy` / `RequestAuthentication` (Istio) để giới hạn service-to-service access.
- Cấu hình retry bằng `VirtualService` (policy retry, timeout).
- Lệnh kiểm tra mẫu:
  ```bash
  kubectl exec -n <ns> <pod> -- curl -v http://<service>.<ns>:<port>/
  ```

### Deliverables (Service Mesh)

- YAML manifest cấu hình mTLS và authorization policy.
- Screenshot Kiali topology và giải thích flow.
- Test plan + logs (kết quả curl, retry evidence).
- README hướng dẫn cách triển khai từng bước.

---

## III. Quy định

1. Đồ án làm nhóm **4 sinh viên**.

2. Nộp bài: Các bạn tạo file báo cáo gồm các thông tin sau:
   - Chụp hình các bước các bạn cấu hình.
   - Đặt tên file theo format `<MSSV1>_<MSSV2>_<MSSV3>.docx`. Thứ tự MSSV cần được sắp xếp tăng dần.
     - Ví dụ nhóm có 3 SV là `23120000`, `23120001`, `23120002` thì đặt tên file là `23120000_23120001_23120002.docx`.
     - Nếu có 2 sinh viên thì đặt tên `23120000_23120001.docx`.
     - Nếu chỉ có 1 sinh viên thì đặt tên `23120000.docx`.
