#!/bin/bash

NAMESPACE="${1:-dev}"

# Danh sách các service cốt lõi cần bật (đã bỏ qua các service không cần thiết)
DEPLOYMENTS=(
  "product"
  "cart"
  "order"
  "customer"
  "inventory"
  "tax"
  "media"
  "search"
  "payment"
  "promotion"
  "storefront-bff"
  "storefront-ui"
  "backoffice-bff"
  "backoffice-ui"
  "swagger-ui"
)

echo "Bắt đầu scale từng deployment trong namespace ${NAMESPACE}..."

# Tắt toàn bộ trước để đưa về trạng thái sạch (nếu chúng đang cố khởi động cùng lúc)
echo "Đang tắt tất cả các pod hiện tại..."
kubectl scale deployment --all --replicas=0 -n ${NAMESPACE}
sleep 10

# Bật từng cái một
for DEPLOYMENT in "${DEPLOYMENTS[@]}"; do
  echo "---------------------------------------------------"
  echo "Đang scale deployment: ${DEPLOYMENT}..."
  
  # Scale lên 1
  kubectl scale deployment ${DEPLOYMENT} --replicas=1 -n ${NAMESPACE}
  
  # Chờ cho đến khi pod chuyển sang trạng thái READY (Timeout 3 phút)
  kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=180s
  
  if [[ $? -eq 0 ]]; then
    echo "✅ ${DEPLOYMENT} đã khởi động thành công!"
  else
    echo "❌ CẢNH BÁO: ${DEPLOYMENT} khởi động thất bại hoặc quá thời gian!"
  fi
done

echo "==================================================="
echo "🎉 Đã hoàn tất khởi động tuần tự cho namespace ${NAMESPACE}!"
