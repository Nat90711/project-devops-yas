# 📋 Member 3 – Bước 3: Tạo ArgoCD Applications
> **Tạo:** 2026-07-07  
> **Trạng thái:** Sẵn sàng thực hiện (Bước 2 đã xong, PR đã merge vào `main`)

---

## ✅ Kiểm tra điều kiện đầu vào (Pre-flight checklist)

| Điều kiện | Trạng thái | Chi tiết |
|---|---|---|
| PR `feat/argocd-gitops-environments` merge vào `main` | ✅ XONG | Commit `dea6482d` trên `main` |
| ArgoCD pods Running | ✅ XONG | 7/7 pods Running trong namespace `argocd` |
| Port-forward 8090:443 đang chạy | ✅ XONG | PID đang chạy, accessible qua `136.110.22.108:8090` |
| Files YAML trong repo | ✅ XONG | `app-dev.yaml`, `app-staging.yaml`, `dev/values.yaml`, `staging/values.yaml` |
| Namespace `dev` có ConfigMap + Secret | ✅ XONG | Đầy đủ (TV1 setup 11 ngày trước) |
| Namespace `staging` có ConfigMap + Secret | ✅ XONG | Đầy đủ (TV1 setup 9 ngày trước) → **STAGING CÓ THỂ APPLY NGAY!** |
| ArgoCD CLI đã cài | ❌ THIẾU | Cần cài trước khi chạy lệnh `argocd` |
| `app-dev.yaml` safe với RAM | ⚠️ CẦN SỬA | `selfHeal: true` và `values.yaml` thiếu giới hạn replicas |
| Umbrella Helm chart tồn tại | ❌ THIẾU | `k8s/charts/` không có umbrella chart – cần tạo |

> **CAUTION – Vấn đề kiến trúc Helm Chart quan trọng:**  
> `k8s/charts/` **KHÔNG** có umbrella chart. Mỗi service (`product`, `cart`, `order`...) là một chart riêng biệt.  
> File `app-dev.yaml` hiện tại trỏ `path: k8s/charts` → ArgoCD sẽ **báo lỗi** vì không có `Chart.yaml` ở root.  
> **Cần tạo umbrella chart `k8s/charts/yas-all/` trước khi apply.**

---

## ⚠️ Vấn đề #1 – RAM (Bắt buộc đọc QUY_TAC_RAM_K8S.md)

Theo `QUY_TAC_RAM_K8S.md`:
- `selfHeal: true` trong `app-dev.yaml` sẽ **tự động bật lại pods** khi ai đó tắt bằng `kubectl scale`, phá vỡ quy tắc "Đổi Ca RAM"
- Phải giới hạn replicas trong `values.yaml` để tránh OOM
- Tắt namespace `yas` (production) trước khi test ArgoCD

---

## ⚠️ Vấn đề #2 – Cấu trúc Helm Chart (Bắt buộc sửa)

`k8s/charts/` chứa **nhiều chart độc lập** (mỗi service 1 chart), không phải 1 umbrella chart.  
ArgoCD `path: k8s/charts` sẽ fail vì không có `Chart.yaml` tại root.

**Giải pháp: Tạo umbrella chart `k8s/charts/yas-all/`** chứa dependencies đến các core sub-chart.

---

## 🛠️ Bước 3 – Thực hiện (Theo thứ tự bắt buộc)

### Bước 3.0 – Cài ArgoCD CLI (Điều kiện tiên quyết)

```bash
# Cài ArgoCD CLI vào ~/bin (không cần sudo)
mkdir -p ~/bin
curl -sSL -o ~/bin/argocd \
  https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x ~/bin/argocd

# Thêm vào PATH nếu chưa có
export PATH="$HOME/bin:$PATH"
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc

# Kiểm tra
argocd version --client

# Đăng nhập (port-forward 8090 đang chạy sẵn)
argocd login localhost:8090 --username admin --password 2Pj2x3FilTzd055B --insecure
```

---

### Bước 3.1 – Kết nối ArgoCD với GitHub Repo

```bash
# Thêm repo vào ArgoCD (public repo, không cần token)
argocd repo add https://github.com/Nat90711/project-devops-yas \
  --name project-devops-yas

# Kiểm tra kết nối repo
argocd repo list
# → Kỳ vọng: STATUS=Successful, TYPE=git
```

---

### Bước 3.2 – Tạo Umbrella Chart `yas-all`

Tạo chart gộp chỉ chứa **core services**, bỏ qua các service ngốn RAM không cần thiết.

**Tạo file `k8s/charts/yas-all/Chart.yaml`:**
```yaml
apiVersion: v2
name: yas-all
description: Umbrella chart for YAS core services (RAM-optimized)
type: application
version: 0.1.0
appVersion: "1.0.0"

dependencies:
  - name: yas-configuration
    version: 0.1.0
    repository: "file://../yas-configuration"
  - name: product
    version: 0.1.0
    repository: "file://../product"
  - name: order
    version: 0.1.0
    repository: "file://../order"
  - name: cart
    version: 0.1.0
    repository: "file://../cart"
  - name: customer
    version: 0.1.0
    repository: "file://../customer"
  - name: payment
    version: 0.1.0
    repository: "file://../payment"
  - name: payment-paypal
    version: 0.1.0
    repository: "file://../payment-paypal"
  - name: search
    version: 0.1.0
    repository: "file://../search"
  - name: tax
    version: 0.1.0
    repository: "file://../tax"
  - name: media
    version: 0.1.0
    repository: "file://../media"
  - name: inventory
    version: 0.1.0
    repository: "file://../inventory"
  - name: promotion
    version: 0.1.0
    repository: "file://../promotion"
  - name: backoffice-bff
    version: 0.1.0
    repository: "file://../backoffice-bff"
  - name: storefront-bff
    version: 0.1.0
    repository: "file://../storefront-bff"
  - name: backoffice-ui
    version: 0.1.0
    repository: "file://../backoffice-ui"
  - name: storefront-ui
    version: 0.1.0
    repository: "file://../storefront-ui"
  - name: swagger-ui
    version: 0.1.0
    repository: "file://../swagger-ui"
```

Các service **BỊ BỎ** để tiết kiệm RAM: `rating`, `recommendation`, `webhook`, `sampledata`, `location`

**Test local trước khi commit:**
```bash
cd k8s/charts/yas-all
helm dependency update .
helm template . -f ../../environments/dev/values.yaml --debug 2>&1 | head -50
# → Nếu không có lỗi → OK commit
cd ../../..
```

---

### Bước 3.3 – Cập nhật `dev/values.yaml` (Kiểm soát RAM)

**Cập nhật `k8s/environments/dev/values.yaml`:**
```yaml
# Image tag mặc định cho môi trường dev
# File này sẽ được Jenkins CI Bot tự động cập nhật sau mỗi lần build thành công trên branch main
global:
  imageTag: "latest"
  imageRepository: "tuandaklak"

# Kiểm soát RAM theo QUY_TAC_RAM_K8S.md
rating:
  backend:
    replicaCount: 0

recommendation:
  backend:
    replicaCount: 0

webhook:
  backend:
    replicaCount: 0

sampledata:
  backend:
    replicaCount: 0

location:
  backend:
    replicaCount: 0
```

---

### Bước 3.4 – Cấu hình ArgoCD (Kiến trúc Enterprise - Nhánh gitops)

**Sửa `k8s/environments/argocd/app-dev.yaml` và `app-staging.yaml`:**
- Thay đổi `targetRevision: main` thành `targetRevision: gitops`
- Cấu hình này giúp ArgoCD đọc các file `.tgz` (đã được đóng gói đầy đủ dependencies) từ nhánh `gitops` do Jenkins tạo ra, tránh triệt để lỗi "Nested Local Dependencies".

---

### Bước 3.5 – Cấu hình CI/CD Jenkins cho GitOps

Cập nhật `Jenkinsfile` để thêm stage **Deploy to GitOps Branch**:
- Jenkins sẽ dùng lệnh `helm dependency build` để sinh ra các file `.tgz` cho toàn bộ service.
- Checkout sang nhánh `gitops`.
- Commit và Force push các file `.tgz` lên nhánh `gitops`.

**⚠️ ĐIỀU KIỆN BẮT BUỘC TRÊN JENKINS:**
Bạn cần tạo Credential chứa Token GitHub trên Jenkins để CI có quyền push code.
- **Kind:** Username with password
- **Username:** `<Tên đăng nhập Github>`
- **Password:** `<Personal Access Token>`
- **ID:** `github-token-new` (Bắt buộc phải khớp với `Jenkinsfile`)

---

### Bước 3.6 – Commit, PR và Kích hoạt Pipeline

```bash
git checkout -b feature/gitops-branch-separation
# ... (add và commit các file cấu hình)
git push origin feature/gitops-branch-separation
```

Tạo PR và merge vào `main`. **Sau khi merge, Jenkins sẽ tự động chạy và sinh ra nhánh `gitops`.**

---

### Bước 3a – Apply `app-dev.yaml` lên cluster

**Chuẩn bị RAM (Tắt Production để nhường RAM cho Dev):**
Bắt buộc phải chạy lệnh này trước để tránh server bị sập (OOM):
```bash
kubectl scale deployment --all --replicas=0 -n yas
```

**Apply cấu hình ArgoCD Application:**
```bash
git checkout main && git pull
kubectl apply -f k8s/environments/argocd/app-dev.yaml
```

**Kích hoạt Sync từ nhánh `gitops`:**
Vì cấu hình đã trỏ sang nhánh `gitops`, bạn cần đảm bảo Jenkins đã chạy xong và nhánh `gitops` đã tồn tại trên Github. Sau đó:
```bash
argocd app sync yas-dev
```

**Theo dõi trạng thái deploy các Pod:**
```bash
watch kubectl get pods -n dev
```

**Kết quả kỳ vọng:**
Toàn bộ các Pods của backend (`product`, `order`, `cart`...) sẽ được tạo ra thành công và trạng thái ArgoCD là **Synced + Healthy**.

---

### Bước 3b – Apply `app-staging.yaml` lên cluster

**Chuẩn bị RAM (Tắt Dev để bật Staging):**
```bash
kubectl scale deployment --all --replicas=0 -n dev
# Đảm bảo MEM% < 70%
```

**Apply và Sync:**
```bash
kubectl apply -f k8s/environments/argocd/app-staging.yaml
argocd app sync yas-staging
watch kubectl get pods -n staging
```

> 📸 Screenshot: `yas-staging` Synced trong ArgoCD UI

---

## 🔍 Troubleshooting – Các lỗi thường gặp

### Lỗi: ArgoCD không kết nối được repo
```bash
argocd repo list
argocd repo add https://github.com/Nat90711/project-devops-yas
```

### Lỗi: helm template fail / ComparisonError
```bash
ls k8s/charts/yas-all/Chart.yaml
cd k8s/charts/yas-all && helm dependency update && helm template . | head -30
```

### Lỗi: OOM / Pod bị evict (MEM% > 85%)
```bash
kubectl scale deployment --all --replicas=0 -n yas
kubectl scale deployment rating recommendation webhook sampledata location --replicas=0 -n dev
```

### Lỗi: "valueFiles not permitted" trong ArgoCD
```bash
# Dùng helm set thay vì valueFiles
argocd app set yas-dev --helm-set global.imageTag=latest --helm-set global.imageRepository=tuandaklak
```

### Lỗi: port-forward bị mất kết nối
```bash
kubectl port-forward svc/argocd-server -n argocd 8090:443 --address=0.0.0.0 &
argocd login localhost:8090 --username admin --password 2Pj2x3FilTzd055B --insecure
```

---

## 📊 Checklist hoàn thành Bước 3

- [ ] ArgoCD CLI cài xong, đăng nhập thành công
- [ ] Repo GitHub add vào ArgoCD (`argocd repo list` STATUS=Successful)
- [ ] Umbrella chart `k8s/charts/yas-all/Chart.yaml` tạo xong + `helm dependency update` OK
- [ ] `dev/values.yaml` đã có `replicaCount: 0` cho các service ngốn RAM
- [ ] `app-dev.yaml` đã sửa `path: k8s/charts/yas-all` và `selfHeal: false`
- [ ] Đã commit + push + merge PR mới
- [ ] `yas-dev` STATUS=Synced, HEALTH=Healthy ✅
- [ ] `yas-staging` STATUS=Synced ✅
- [ ] Screenshot ArgoCD UI chụp xong

---

## ➡️ Bước tiếp theo → Bước 4: GitHub Webhook

```
Webhook URL  : https://136.110.22.108:8090/api/webhook
Content type : application/json
Secret       : (để trống)
Events       : Just the push event
Active       : ✅ checked
```

Kiểm tra port-forward đang chạy:
```bash
ps aux | grep port-forward | grep -v grep
# Nếu không thấy → chạy lại:
kubectl port-forward svc/argocd-server -n argocd 8090:443 --address=0.0.0.0 &
```
