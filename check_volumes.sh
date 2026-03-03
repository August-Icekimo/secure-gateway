#!/bin/bash

# 專案名稱預設為 secure-gateway，可透過第一個參數傳入
PROJECT_NAME=${1:-secure-gateway}

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "🔍 正在檢查 Docker Volumes (專案: $PROJECT_NAME)..."
echo "==================================================="

# 定義 docker-compose.yml 中預期的 Volume 後綴
EXPECTED_VOLUMES="caddy_data caddy_logs crowdsec_db postgres_data"
ALL_EXIST=true

for VOL in $EXPECTED_VOLUMES; do
    # 組合完整的 Volume 名稱 (Docker Compose 預設命名規則: 專案名_Volume名)
    FULL_VOL_NAME="${PROJECT_NAME}_${VOL}"
    
    if docker volume inspect "$FULL_VOL_NAME" > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Volume 已建立: $FULL_VOL_NAME${NC}"
    else
        echo -e "${RED}❌ Volume 未找到: $FULL_VOL_NAME${NC}"
        ALL_EXIST=false
    fi
done

echo "==================================================="

if [ "$ALL_EXIST" = true ]; then
    echo -e "${GREEN}🎉 所有必要的 Volume 都已存在。${NC}"
else
    echo -e "${RED}⚠️  部分 Volume 缺失。請確認是否已執行 'docker-compose up'。${NC}"
    echo -e "${RED}   若您的專案資料夾名稱不是 '$PROJECT_NAME'，請執行: ./check_volumes.sh <您的資料夾名稱>${NC}"
    exit 1
fi
