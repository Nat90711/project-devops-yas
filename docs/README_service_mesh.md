# Service Mesh – Istio trên YAS Microservices

## Tổng quan

Service Mesh sử dụng **Istio 1.20.0** để quản lý giao tiếp giữa các microservice trong hệ thống YAS. Istio cung cấp:
- **mTLS (mutual TLS)**: Mã hóa và xác thực 2 chiều tất cả traffic giữa các service
- **Authorization Policy**: Kiểm soát service nào được phép gọi service nào
- **Retry Policy**: Tự động retry khi service gặp lỗi tạm thời
- **Observability**: Kiali topology, Prometheus metrics, Jaeger tracing

## Kiến trúc

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                         │
│                                                               │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐       │
│  │  istiod      │    │  kiali      │    │  prometheus │       │
│  │  (control    │    │  (UI)       │    │  (metrics)  │       │
│  │   plane)     │    │             │    │             │       │
│  └──────┬───────┘    └─────────────┘    └─────────────┘       │
│         │                                                     │
│  ┌──────▼──────────────────────────────────────────────┐      │
│  │              Namespace: yas                          │      │
│  │                                                      │      │
│  │  ┌──────────┐  mTLS  ┌──────────┐  mTLS  ┌────────┐│      │
│  │  │ product  │◄──────►│inventory │◄──────►│ order  ││      │
│  │  │ +envoy   │        │ +envoy   │        │ +envoy ││      │
│  │  └──────────┘        └──────────┘        └───┬────┘│      │
│  │                                              │      │      │
│  │                              mTLS           │      │      │
│  │                                              ▼      │      │
│  │  ┌──────────┐        ┌──────────┐     ┌──────────┐ │      │
│  │  │promotion │        │  rating  │     │   tax    │ │      │
│  │  │ +envoy   │        │ +envoy   │     │  +envoy  │ │      │
│  │  └──────────┘        └──────────┘     └──────────┘ │      │
│  └──────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────┘
```

## Hướng dẫn triển khai từng bước

### Bước 1 – Cài đặt Istio

```bash
# Tải Istio 1.20.0
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.20.0 sh -
cd istio-1.20.0
export PATH="$PWD/bin:$PATH"

# Cài lên cluster (profile demo bao gồm ingress + egress gateway)
istioctl install --set profile=demo -y

# Verify
kubectl get pods -n istio-system
# Kỳ vọng: istiod, istio-ingressgateway, istio-egressgateway đều Running
```

### Bước 2 – Bật Sidecar Injection

```bash
# Label namespace yas
kubectl label namespace yas istio-injection=enabled

# Restart tất cả deployment để inject Envoy sidecar
kubectl rollout restart deployment -n yas

# Verify: mỗi pod phải có READY 2/2 (app container + istio-proxy)
kubectl get pods -n yas
```

### Bước 3 – Cài Observability Addons

```bash
# Kiali (Service Mesh UI)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/kiali.yaml

# Prometheus (Metrics)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/prometheus.yaml

# Jaeger (Distributed Tracing)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.20/samples/addons/jaeger.yaml

# Expose Kiali ra ngoài qua NodePort
kubectl patch svc kiali -n istio-system -p '{"spec": {"type": "NodePort"}}'
kubectl get svc kiali -n istio-system
# Truy cập: http://<IP>:<NodePort>/kiali
```

### Bước 4 – Bật mTLS toàn mesh (STRICT mode)

File: `k8s/service-mesh/peer-authentication.yaml`

```bash
kubectl apply -f k8s/service-mesh/peer-authentication.yaml

# Verify
kubectl get peerauthentication -n istio-system
istioctl authn tls-check <pod-name>.yas inventory.yas.svc.cluster.local
# Kỳ vọng: STATUS=OK, SERVER=mTLS, CLIENT=mTLS
```

### Bước 5 – Authorization Policy

File: `k8s/service-mesh/authorization-policy.yaml`

Các policy được cấu hình:
| Policy | Source → Destination | Mục đích |
|--------|---------------------|----------|
| `allow-product-to-inventory` | product, backoffice-bff, storefront-bff → inventory | Kiểm tra tồn kho |
| `allow-order-to-tax` | order, backoffice-bff → tax | Tính thuế đơn hàng |
| `allow-order-to-promotion` | order, backoffice-bff, storefront-bff → promotion | Áp dụng khuyến mãi |

> **Lưu ý:** Khi có ít nhất 1 ALLOW policy trên selector, Istio tự động deny tất cả request khác (implicit deny-all).

```bash
kubectl apply -f k8s/service-mesh/authorization-policy.yaml
```

### Bước 6 – Retry Policy

File: `k8s/service-mesh/virtual-service-retry.yaml`

Cấu hình retry cho `tax` và `inventory`:
- **3 lần retry** khi gặp lỗi
- **Timeout 5s** mỗi lần
- Retry trên các lỗi: `5xx`, `gateway-error`, `connect-failure`, `reset`

```bash
kubectl apply -f k8s/service-mesh/virtual-service-retry.yaml
```

## Kịch bản Test

### Test 1: mTLS
```bash
PRODUCT_POD=$(kubectl get pod -n yas -l app.kubernetes.io/name=product -o jsonpath='{.items[0].metadata.name}')
istioctl authn tls-check $PRODUCT_POD.yas inventory.yas.svc.cluster.local
```

### Test 2: Authorization ALLOW (HTTP 200)
```bash
kubectl exec -n yas deployment/product -c product -- curl -s -o /dev/null -w "%{http_code}" http://inventory:8080/api/inventories
```

### Test 3: Authorization DENY (HTTP 403)
```bash
kubectl exec -n yas deployment/rating -c rating -- curl -s -o /dev/null -w "%{http_code}" http://inventory:8080/api/inventories
```

### Test 4: Retry Policy
```bash
# Scale down tax service
kubectl scale deployment tax -n yas --replicas=0

# Gọi từ order → tax
kubectl exec -n yas deployment/order -c order -- curl -v http://tax:8080/api/taxes/calculate

# Xem Envoy logs cho retry
kubectl logs -n yas -l app.kubernetes.io/name=order -c istio-proxy --tail=50 | grep -E "tax|retry|503"

# Restore
kubectl scale deployment tax -n yas --replicas=1
```

## Files

| File | Mô tả |
|------|-------|
| `k8s/service-mesh/peer-authentication.yaml` | PeerAuthentication STRICT mTLS toàn cluster |
| `k8s/service-mesh/authorization-policy.yaml` | Authorization policies cho service-to-service |
| `k8s/service-mesh/virtual-service-retry.yaml` | VirtualService retry cho tax và inventory |
| `docs/README_service_mesh.md` | Hướng dẫn triển khai (file này) |
