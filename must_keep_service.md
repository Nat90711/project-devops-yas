# Phân Loại Services: GIỮ

## PHẢI GIỮ — Cốt lõi cho demo E-commerce + Service Mesh

| Service | Lý do giữ |
|---|---|
| product | Sản phẩm — trung tâm của shop |
| cart | Giỏ hàng — demo flow mua hàng |
| order | Đơn hàng — demo flow đặt hàng, test retry policy (order→cart/payment/inventory/tax) |
| customer | Thông tin khách hàng |
| inventory | Kho hàng — order phụ thuộc |
| tax | Thuế — order phụ thuộc, demo VirtualService retry |
| media | Upload hình ảnh sản phẩm |
| search | Tìm kiếm — phụ thuộc product, demo AuthorizationPolicy |
| storefront-bff | BFF cho giao diện người dùng |
| storefront-ui | Giao diện cửa hàng — demo cho giảng viên |
| backoffice-bff | BFF cho quản trị |
| backoffice-ui | Giao diện quản trị |
| swagger-ui | API documentation |
| sampledata | Dữ liệu mẫu — chỉ chạy 1 lần, sau khi chạy có data thì bạn có thể tắt đi |

**Tổng: 14 services - 1 service (sample data - chạy 1 lần)**
