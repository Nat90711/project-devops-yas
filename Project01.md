# Đồ án 1: Triển khai hệ thống CI

---

## I. Mô tả

Trong môn học này các bạn được yêu cầu xây dựng một quy trình, hệ thống CI/CD và monitor để có thể deploy, vận hành và giám sát được hệ thống **"YAS: Yet Another Shop"** từ link sau: [https://github.com/nashtech-garage/yas](https://github.com/nashtech-garage/yas)

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

Đây là đồ án 1 trong chuỗi đồ án môn học DevOps, trong đồ án này các bạn cần phải sử dụng Jenkins để xây dựng pipeline cho quá trình CI (Continuous Integration) với những yêu cầu cụ thể sau:

1. Các bạn có thể dùng GitHub Actions, GitLab CI/CD... hoặc Jenkins.

2. Fork một repo mới từ GitHub [https://github.com/nashtech-garage/yas](https://github.com/nashtech-garage/yas) cho riêng nhóm của mình.

3. Cấu hình GitHub để không cho phép push trực tiếp vào `main` branch. Mỗi PR cần ít nhất **2 reviewer approve** và **CI pass** mới cho phép merge vào `main` branch.

4. Configure để Jenkins có thể quét và chạy pipeline cho từng branch.

5. Pipeline cần có ít nhất **2 phase: test và build**. Phase test cần upload test result và độ phủ của testcase.

6. Do hệ thống này đang sử dụng mô hình **monorepo**, các bạn cần phải cấu hình để GitHub Actions hoặc GitLab CI/CD hoặc Jenkins **chỉ kích hoạt pipeline cho service cụ thể** khi có thay đổi trong thư mục của service đó.

   > **Ví dụ:** Khi developer thay đổi trong `media-service` thì chỉ cần build và test lại `media-service`, chứ không build và test lại toàn bộ hệ thống.

### Yêu cầu nâng cao

a. Thêm unit test vào trong code để có thể tăng độ phủ của testcase. Trong yêu cầu này các bạn cần tạo branch mới để thêm testcase, mỗi branch sẽ ứng với mỗi service như Media, Product, Cart...

b. Điều chỉnh lại pipeline để **chỉ cho phép pass khi testcase có độ phủ > 70%**.

c. Sử dụng **Gitleaks, SonarQube, Snyk** để scan các lỗ hổng bảo mật và chất lượng của code.

---

## III. Quy định

1. Đồ án làm nhóm **4 sinh viên**.

2. Thời gian làm bài: **3 tuần** (17/3/2026).

3. Nộp bài: Các bạn tạo file báo cáo gồm các thông tin sau:

   a. Link tới GitHub repository của nhóm, trong repository này tối thiểu phải có **1 PR đang trong trạng thái open**.

   b. Chụp hình các bước các bạn cấu hình như Jenkins job, Gitleaks, SonarQube, Snyk...

   c. Đặt tên file theo format `<MSSV1>_<MSSV2>_<MSSV3>.docx`. Thứ tự MSSV cần được sắp xếp tăng dần.
      - Ví dụ nhóm có 3 SV là `23120000`, `23120001`, `23120002` thì đặt tên file là `23120000_23120001_23120002.docx`.
      - Nếu có 2 sinh viên thì đặt tên `23120000_23120001.docx`.
      - Nếu chỉ có 1 sinh viên thì đặt tên `23120000.docx`.
