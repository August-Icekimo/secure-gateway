#!/bin/sh

# 定義顏色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Starting Secure Gateway Initialization Check ===${NC}"

# 1. 檢查必要的環境變數
echo -e "\n${YELLOW}[1] Checking Environment Variables...${NC}"
MISSING_VAR=0

check_var() {
    if [ -z "$2" ]; then
        echo -e "${RED}[FAIL] $1 is missing or empty!${NC}"
        MISSING_VAR=1
    else
        echo -e "${GREEN}[OK] $1 is set.${NC}"
    fi
}

check_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
check_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"
check_var "GOOGLE_CLIENT_ID" "$GOOGLE_CLIENT_ID"
check_var "JWT_SHARED_KEY" "$JWT_SHARED_KEY"
check_var "DOMAIN_NAME" "$DOMAIN_NAME"
check_var "POSTGRES_PASSWORD" "$POSTGRES_PASSWORD"
check_var "CROWDSEC_BOUNCER_KEY" "$CROWDSEC_BOUNCER_KEY"
check_var "ALLOWEDE_GMAIL" "$ALLOWEDE_GMAIL"

if [ $MISSING_VAR -eq 1 ]; then
    echo -e "${RED}!!! Critical Environment Variables Missing. Please check your .env file or docker-compose.yml !!!${NC}"
    # 不強制退出，繼續檢查其他項目
fi

# 2. 檢查設定檔是否存在
echo -e "\n${YELLOW}[2] Checking Configuration Files...${NC}"
if [ -f "/etc/caddy/Caddyfile" ]; then
    echo -e "${GREEN}[OK] Caddyfile found.${NC}"
else
    echo -e "${RED}[FAIL] Caddyfile NOT found at /etc/caddy/Caddyfile${NC}"
fi

if [ -f "/etc/caddy/coraza.conf" ]; then
    echo -e "${GREEN}[OK] coraza.conf found.${NC}"
else
    echo -e "${RED}[FAIL] coraza.conf NOT found at /etc/caddy/coraza.conf (WAF might fail)${NC}"
fi

# 3. 檢查內部容器連線 (Internal Bridge)
echo -e "\n${YELLOW}[3] Checking Internal Container Connectivity...${NC}"
# 檢查 CrowdSec (Port 8080)
nc -z -w 2 crowdsec 8080
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Connected to CrowdSec (crowdsec:8080)${NC}"
else
    echo -e "${RED}[FAIL] Cannot connect to CrowdSec! Is the container running?${NC}"
fi

# 檢查 Guacamole (Port 8080)
nc -z -w 2 guacamole 8080
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Connected to Guacamole (guacamole:8080)${NC}"
else
    echo -e "${RED}[FAIL] Cannot connect to Guacamole! Is the container running?${NC}"
fi

# 4. 檢查外部服務連線 (External Services)
# 注意：若使用 Macvlan，容器可能無法直接連線到 Host IP (需 Router 支援 Hairpin NAT 或 Bridge 模式)
echo -e "\n${YELLOW}[4] Checking External Services Connectivity...${NC}"
# dsm7 子網域用的專屬變數優先；SSH_SERVER_IP 只是向後相容的退路
# （兩者目前恰好都是 NAS 自身，但語意不同，別再靠巧合）
DSM_IP="${DSM_SERVER_IP:-${SSH_SERVER_IP:-192.168.1.10}}"
nc -z -w 2 $DSM_IP 5000
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Connected to DSM ($DSM_IP:5000)${NC}"
else
    echo -e "${RED}[FAIL] Cannot connect to DSM ($DSM_IP:5000). Check Host routing or IP firewall.${NC}"
fi

# 檢查 Caddy 自身 Port 綁定
# 註：8080 是 tailscale-gw 在 host 側的映射（8080:80），容器內 Caddy 綁的是 :80 與 :443。
#     舊版檢查 127.0.0.1:8080 永遠 FAIL，是誤報。
for PORT in 80 443; do
    nc -z -w 2 127.0.0.1 $PORT
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK] Caddy is listening on :$PORT${NC}"
    else
        echo -e "${RED}[FAIL] Caddy is NOT listening on :$PORT${NC}"
    fi
done

# 檢查 Google (驗證對外網路)
nc -z -w 2 google.com 443
if [ $? -eq 0 ]; then
    echo -e "${GREEN}[OK] Internet Connectivity (google.com:443)${NC}"
else
    echo -e "${RED}[FAIL] No Internet Access! DNS validation will fail.${NC}"
fi

echo -e "\n${YELLOW}=== Check Complete ===${NC}"

