# CẨM NANG QUẢN LÝ RAM (Dành cho Thành viên 2 & 3)

> **⚠️ CẢNH BÁO ĐỎ:** Máy ảo (VM) của dự án này chỉ có giới hạn **36GB RAM** cho Minikube. Hệ thống E-commerce YAS chạy bằng Java Spring Boot rất ngốn RAM. 
> Nếu bật quá nhiều pod cùng lúc, toàn bộ hệ thống sẽ sập (OOM Killer), gây ra lỗi `502 Bad Gateway`, `503 Service Unavailable` hoặc `TLS handshake timeout` làm gián đoạn đồ án của tất cả mọi người.

Để sống sót qua đồ án này, TẤT CẢ thành viên phải tuân thủ nghiêm ngặt **Quy tắc "Đổi Ca RAM"** dưới đây:

---

## 🚫 QUY TẮC TỐI THƯỢNG
**KHÔNG BAO GIỜ** được bật cùng lúc cả 3 namespace: `yas` (Production), `dev`, và `staging`. 
Luôn phải theo dõi RAM bằng lệnh:
```bash
docker stats minikube
```
*(Đảm bảo cột `MEM %` luôn dưới 85%. Nếu vượt quá 90%, phải tìm namespace không dùng và tắt ngay lập tức).*

---

## 👨‍💻 Dành cho Thành viên 2 (Jenkins CI/CD)

Task của bạn (Jenkins job `developer_build`) sẽ tạo ra một namespace tạm thời mới tinh (VD: `devbuild-tax`) để deploy code.

1. **Trước khi chạy Job Build:**
   Bạn BẮT BUỘC phải tắt các môi trường khác để lấy chỗ trống cho Jenkins build và chạy namespace tạm.
   ```bash
   kubectl scale deployment --all --replicas=0 -n yas
   kubectl scale deployment --all --replicas=0 -n dev
   kubectl scale deployment --all --replicas=0 -n staging
   ```
2. **Sau khi test xong:**
   Lập tức chạy Jenkins Job `cleanup_deployment` để xoá namespace tạm, trả lại RAM cho hệ thống.

---

## 👨‍💻 Dành cho Thành viên 3 (ArgoCD GitOps)

ArgoCD cực kỳ nguy hiểm về mặt RAM nếu cấu hình `selfHeal: true` (tự động phục hồi pod), vì nó sẽ tự động bật lại các pod mà chúng ta cố tình tắt để tiết kiệm RAM.

1. **Chuẩn bị trước khi test ArgoCD:**
   Tắt môi trường Production đi:
   ```bash
   kubectl scale deployment --all --replicas=0 -n yas
   ```
2. **Lưu ý CỰC KỲ QUAN TRỌNG khi code `values.yaml`:**
   Tuyệt đối **KHÔNG** deploy tất cả các service. Trong file `k8s/environments/dev/values.yaml` và `staging/values.yaml`, bạn phải set `replicas: 0` (hoặc disable) cho các service thừa thãi (như `location`, `rating`, `recommendation`, `webhook`, `sampledata`). Chỉ giữ lại các core service (như `product`, `order`, `cart`, `payment`...).
3. **Khi test tính năng Auto-Sync (Dev):**
   Hãy chắc chắn rằng `staging` đang bị tắt. Đừng bắt máy ảo gánh cả `dev` và `staging` cùng lúc.

---

## 🛠️ CÔNG CỤ HỖ TRỢ (Script khởi động an toàn)

Khi cần bật một namespace (như `yas` hoặc `dev`), việc dùng lệnh `kubectl scale --all --replicas=1` sẽ làm hàng chục pod khởi động cùng LÚC, gây spike CPU lên 500-600% và dễ dẫn đến sập máy.

Hãy sử dụng script khởi động tuần tự đã được cấp sẵn:
```bash
# Khởi động môi trường dev an toàn
./scale-dev-sequential.sh dev

# Hoặc khởi động môi trường staging an toàn
./scale-dev-sequential.sh staging
```
Script này sẽ bật từng pod một, chờ pod đó READY rồi mới bật pod tiếp theo, đảm bảo máy ảo chạy êm ru!

---
*Chúc team hoàn thành đồ án 10 điểm mà không bị cháy RAM!* 🔥
