#!/bin/bash
set -x

# Auto restart when change configmap or secret
helm repo add stakater https://stakater.github.io/stakater-charts
helm repo update

read -rd '' DOMAIN \
< <(yq -r '.domain' ./cluster-config.yaml)

# Tên miền cho staging
STAGING_DOMAIN="staging.$DOMAIN"

# 1. Deploy cấu hình dùng chung
helm dependency build ../charts/yas-configuration
helm upgrade --install yas-configuration ../charts/yas-configuration \
--namespace staging --create-namespace

sleep 10

# 2. Deploy Backoffice
helm dependency build ../charts/backoffice-bff
helm upgrade --install backoffice-bff ../charts/backoffice-bff \
--namespace staging --create-namespace \
--set backend.ingress.host="backoffice.$STAGING_DOMAIN"

helm dependency build ../charts/backoffice-ui
helm upgrade --install backoffice-ui ../charts/backoffice-ui \
--namespace staging --create-namespace \
--set ingress.host="backoffice.$STAGING_DOMAIN"

sleep 30

# 3. Deploy Storefront
helm dependency build ../charts/storefront-bff
helm upgrade --install storefront-bff ../charts/storefront-bff \
--namespace staging --create-namespace \
--set backend.ingress.host="storefront.$STAGING_DOMAIN"

helm dependency build ../charts/storefront-ui
helm upgrade --install storefront-ui ../charts/storefront-ui \
--namespace staging --create-namespace \
--set ingress.host="storefront.$STAGING_DOMAIN"

sleep 30

# 4. Deploy Swagger API
helm upgrade --install swagger-ui ../charts/swagger-ui \
--namespace staging --create-namespace \
--set ingress.host="api.$STAGING_DOMAIN"

sleep 20

# 5. Deploy tất cả các Backend Services tuần tự
for chart in {"cart","customer","inventory","location","media","order","payment","payment-paypal","product","promotion","rating","search","tax","recommendation","webhook","sampledata"} ; do
    helm dependency build ../charts/"$chart"
    helm upgrade --install "$chart" ../charts/"$chart" \
    --namespace staging --create-namespace \
    --set backend.ingress.host="api.$STAGING_DOMAIN"
    
    # Đợi 20s giữa mỗi lần deploy để giảm tải CPU
    sleep 20
done
