# Kế Hoạch Triển Khai Hệ Thống Observability

## Mục tiêu
Triển khai stack Observability đầy đủ trên Kubernetes theo đúng thiết kế của dự án YAS (giống với screenshot `yas-grafana-metrics.png` và `yas-grafana-tracing.png`), bao gồm:
- **Metrics**: Grafana Dashboard hiển thị HTTP requests, JVM memory, CPU, DB connections
- **Tracing**: Distributed tracing qua Tempo với TraceQL query

---

## Phân Tích Hiện Trạng

### ✅ Đã có sẵn (Running)
| Component | Namespace | Status |
|---|---|---|
| `grafana-operator` | observability | Running |
| `grafana` (CRD) | observability | Stage: complete/success |
| `tempo` | observability | Running — nhận traces port 4317/4318 |
| `promtail` | observability | Running (nhưng bị restart 490 lần — cần điều tra) |
| `opentelemetry-operator` | observability | Running |

### ❌ Thiếu / Lỗi (Cần triển khai)
| Component | Vấn đề |
|---|---|
| `opentelemetry-collector` | Helm release ở trạng thái **FAILED** — OTel Collector chưa tạo được pod |
| **Prometheus** | Chưa deploy (chỉ có Prometheus của Istio, không phải của app) |
| **Loki** | Chưa deploy → Logs chưa có nơi lưu trữ |
| **Grafana UI** | Grafana trỏ vào `http://prometheus-grafana` không tồn tại → UI không truy cập được |
| **Datasources** | Prometheus và Loki chưa được kết nối vào Grafana |
| **Dashboards** | Dashboard metrics chưa được provisioning |

### Kiến trúc luồng dữ liệu (theo thiết kế)
```
[Spring Boot Apps] --OTLP--> [OTel Collector]
                                    |
                    ┌───────────────┼──────────────────┐
                    ▼               ▼                   ▼
               [Prometheus]      [Tempo]             [Loki]
               (Metrics)         (Traces)           (Logs)
                    └───────────────┼──────────────────┘
                                    ▼
                               [Grafana UI]
                      grafana.yas.local.com
```

**Promtail** thu thập logs từ tất cả các pod trong cluster và đẩy vào OTel Collector (port 3500), sau đó OTel Collector forward lên Loki.

---

## Kế Hoạch Thực Hiện (5 bước)

### Bước 1: Deploy Prometheus (kube-prometheus-stack)
Prometheus là trung tâm lưu trữ metrics. File `prometheus.values.yaml` đã có sẵn.

**Lệnh cần chạy:**
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n observability \
  -f k8s/deploy/observability/prometheus.values.yaml \
  --set grafana.enabled=true \
  --wait --timeout 5m
```

**Kết quả mong đợi:**
- Pods: `prometheus-kube-prometheus-prometheus-0`, `prometheus-grafana-xxx`
- Service: `prometheus-kube-prometheus-prometheus:9090`, `prometheus-grafana:80`
- Ingress: `grafana.yas.local.com` → Grafana UI

> [!IMPORTANT]
> Cần thêm `grafana.yas.local.com` vào file `/etc/hosts` của máy tính (client) để truy cập Grafana qua trình duyệt.

---

### Bước 2: Deploy Loki (Distributed Log Storage)
File `loki.values.yaml` đã có sẵn.

**Lệnh cần chạy:**
```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki grafana/loki \
  -n observability \
  -f k8s/deploy/observability/loki.values.yaml \
  --wait --timeout 5m
```

**Kết quả mong đợi:**
- Pods: `loki-read-0`, `loki-write-0`, `loki-backend-0`
- Service: `loki-gateway:80` (endpoint mà OTel Collector sẽ đẩy logs vào)

---

### Bước 3: Fix & Deploy OpenTelemetry Collector
Helm release hiện tại bị **FAILED** do thiếu Loki ở bước trước. Sau khi Loki sẵn sàng, upgrade lại release này.

**Lệnh cần chạy:**
```bash
helm upgrade opentelemetry-collector k8s/deploy/observability/opentelemetry \
  -n observability \
  --wait --timeout 3m
```

OTel Collector sẽ:
- Nhận **traces** từ Spring Boot apps (OTLP gRPC port 4317/4318) → forward sang Tempo
- Nhận **logs** từ Promtail (Loki protocol port 3500) → forward sang Loki

---

### Bước 4: Cập nhật backend apps để gửi traces lên OTel Collector
Các Spring Boot apps cần biết địa chỉ của OTel Collector để gửi traces (OTLP).

**Cần kiểm tra trong `yas-configuration` values:**
- Env var `OTEL_EXPORTER_OTLP_ENDPOINT` phải trỏ tới `http://opentelemetry-collector.observability:4317`
- Nếu chưa có, thêm vào `k8s/charts/yas-configuration/values.yaml` và apply lại

---

### Bước 5: Cấu hình Grafana Datasources & Import Dashboards

Sau khi tất cả các thành phần chạy, cần:

**5a. Cập nhật Grafana Operator CRD** để kết nối đúng Prometheus và Loki:
- Sửa file `k8s/deploy/observability/grafana/templates/loki-datasource.yaml` → URL `http://loki-gateway/loki/api/v1/push`
- Sửa file `k8s/deploy/observability/grafana/templates/tempo-datasource.yaml` → URL `http://tempo.observability:3200`
- Thêm mới `prometheus-datasource.yaml` → URL `http://prometheus-kube-prometheus-prometheus:9090`

**5b. Import Dashboard "Observability Dashboard"**:
- Dùng Dashboard ID từ Grafana Community hoặc tạo mới từ file JSON hiện có trong `docker/grafana/provisioning/dashboards/`

---

## Thứ tự ưu tiên và rủi ro

> [!WARNING]
> **Loki dùng MinIO** (được bật trong loki.values.yaml). MinIO cần ~500MB RAM. Cần kiểm tra RAM của Minikube trước khi deploy. Nếu cluster đang bị quá tải (như hiện tại với CPU 584%), cần scale down một số service dev trước khi triển khai.

> [!NOTE]
> Sau khi triển khai xong, cần thêm `grafana.yas.local.com` vào `/etc/hosts` của máy client trỏ tới `136.110.22.108`.

## Thứ tự thực hiện đề xuất

```
1️⃣ Prometheus → 2️⃣ Loki → 3️⃣ OTel Collector (fix) → 4️⃣ Config Apps → 5️⃣ Grafana Datasources & Dashboards
```

Ước tính thời gian: **1–2 giờ** (phụ thuộc vào tốc độ pull image và tài nguyên cluster)
