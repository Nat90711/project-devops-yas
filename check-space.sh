#!/bin/bash

echo "=================================================="
echo "    KIỂM TRA DUNG LƯỢNG Ổ CỨNG VÀ JENKINS TỔNG THỂ"
echo "=================================================="

echo -e "\n[1] TRẠNG THÁI Ổ CỨNG HIỆN TẠI (df -h):"
echo "--------------------------------------------------"
# Hiển thị các phân vùng thực (bỏ qua các phân vùng ảo như snap/loop để dễ nhìn)
df -hT | grep -v 'loop\|tmpfs\|devtmpfs'

JENKINS_DIR="/var/jenkins_home"

echo -e "\n[2] KIỂM TRA CHI TIẾT THƯ MỤC JENKINS ($JENKINS_DIR):"
echo "--------------------------------------------------"
if [ -d "$JENKINS_DIR" ]; then
    echo "Đang tính toán dung lượng... (Quá trình này có thể mất vài giây)"
    
    echo -e "\n👉 Tổng dung lượng thư mục Jenkins:"
    du -sh "$JENKINS_DIR" 2>/dev/null

    echo -e "\n👉 Dung lượng Maven Cache (.m2):"
    if [ -d "$JENKINS_DIR/.m2" ]; then
        du -sh "$JENKINS_DIR/.m2" 2>/dev/null
    else
        echo "Không tìm thấy thư mục $JENKINS_DIR/.m2"
    fi

    echo -e "\n👉 Top 5 Workspaces nặng nhất:"
    if [ -d "$JENKINS_DIR/workspace" ]; then
        du -sh "$JENKINS_DIR/workspace"/* 2>/dev/null | sort -rh | head -n 5
    else
        echo "Không tìm thấy thư mục workspace"
    fi

    echo -e "\n👉 Top 5 Jobs có lịch sử build nặng nhất:"
    if [ -d "$JENKINS_DIR/jobs" ]; then
        du -sh "$JENKINS_DIR/jobs"/* 2>/dev/null | sort -rh | head -n 5
    else
        echo "Không tìm thấy thư mục jobs"
    fi

    echo -e "\n👉 Top 10 thư mục con 'ngốn' nhiều dung lượng nhất trong toàn bộ Jenkins:"
    # Tìm 10 thư mục nặng nhất tính từ thư mục gốc của Jenkins
    du -ah "$JENKINS_DIR" 2>/dev/null | sort -rh | head -n 10

else
    echo "[CẢNH BÁO] Không tìm thấy thư mục $JENKINS_DIR."
    echo "Nếu Jenkins của bạn cài ở đường dẫn khác, hãy sửa biến JENKINS_DIR trong script."
fi

echo -e "\n==================== HOÀN TẤT ===================="
