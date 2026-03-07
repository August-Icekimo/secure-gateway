# Secure Gateway

這是一個部署在 Synology DSM Container Manager 上的全方位資安閘道器專案。

This is a comprehensive security gateway project deployed on Synology DSM Container Manager.

## 🏗 架構總覽 / Architecture Overview

本專案整合了以下核心元件：

This project integrates the following core components:

- **Caddy (Custom Build):**
    - **Layer 4 Proxy:** 原本負責 `Port 443` 的 SSH 與 HTTPS 流量分流，但目前因模組匹配問題預設停用 (Commented out)。 
    
          Originally responsible for `Port 443` SSH and HTTPS traffic multiplexing, currently disabled by default due to module matching issue.
    - **Layer 7 Reverse Proxy:** 負責 Web 服務反向代理與 SSL 卸載 (SSL Termination). 

          Responsible for Web service reverse proxy and SSL termination.
    - **Security:** 整合 `Google OpenID Connect` (SSO) 進行身分驗證。 

          Integrates `Google OpenID Connect` (SSO) for authentication.
    - **WAF & IPS:** 整合 `Coraza WAF` 與 `CrowdSec` 進行入侵防禦。 

          Integrates `Coraza WAF` and `CrowdSec` for intrusion prevention.
    - **DNS:** 透過 `AWS Route53 API` 自動申請/續期憑證。 

          Automatically requests/renews certificates via `AWS Route53 API`.
- **CrowdSec:** 分析 Caddy 日誌，自動封鎖惡意 IP。 

        Analyzes Caddy logs to automatically block malicious IPs.
- **PostgreSQL:** 使用 Docker Volume 進行資料持久化儲存。 

        Uses Docker Volume for persistent data storage.
- **Guacamole:** 提供 HTML5 Web 介面的 SSH/VNC 跳板機 (支援 2FA)。 

        Provides an HTML5 Web interface SSH/VNC jump server (supports 2FA).

## 🗂️專案目錄結構 / File Layout 

請在 NAS 上 (例如 `/volume1/docker/secure-gateway`) 建立以下結構：

```
/secure-gateway
├── .env                 # [㊙🤐] 環境變數設定檔
├── check_volumes.sh     # 環境Volume設定檢查腳本
├── docker-compose.yml   # 堆疊啟動檔
├── build/
│   ├── Dockerfile       # Caddy 編譯腳本
│   └── initCheck.sh     # 啟動前環境檢查腳本
├── caddy_config/
│   ├── Caddyfile        # Caddy 核心設定
│   └── coraza.conf      # WAF 規則設定 (需下載)
├── caddy_data/          # Caddy SSL 憑證儲存區 (自動生成)
├── caddy_logs/          # Log 存放區
├── crowdsec_config/     # CrowdSec 設定
├── crowdsec_db/         # CrowdSec 資料庫
├── guac_extensions/     # [手動] 存放 Guacamole TOTP .jar 檔
├── postgres_data/       # Guacamole 資料庫
└── initdb.sql           # ß[首次] Guacamole 資料庫初始化 SQL
```

## 🔐 憑證與擴充套件取得詳細指南 / Detailed Guide for Certificates and Extensions

在填寫 `.env` 檔案前，請參考以下步驟取得必要的金鑰與檔案。

Before filling in the `.env` file, please refer to the following steps to obtain the necessary keys and files.

### 1. AWS Route 53 (DNS 驗證用 / For DNS Validation)

1. 登入 AWS Console，前往 IAM (Identity and Access Management)。 

    Log in to AWS Console, go to IAM.
1. 點擊 **Users** > **Create user** (名稱如 `caddy-dns-bot`)。 

    Click **Users** > **Create user** (e.g., `caddy-dns-bot`).
1. **Permissions options** 選擇 **Attach policies directly**。 

    Select **Attach policies directly** for **Permissions options**.
1. 搜尋並勾選 `AmazonRoute53FullAccess` (或自訂僅限特定 Zone 的權限)。 

    Search and check `AmazonRoute53FullAccess` (or customize permissions for specific Zones).
1. 建立使用者後，點擊該使用者進入 **Security credentials** 頁籤。 

    After creating the user, click the user to enter the **Security credentials** tab.
1. 點擊 **Create access key** > 選擇 **Command Line Interface (CLI)**。 

    Click **Create access key** > Select **Command Line Interface (CLI)**.
1. **務必複製 Access Key ID 與 Secret Access Key (只會顯示這一次)。** 

    **Make sure to copy the Access Key ID and Secret Access Key (shown only once).**
1. 前往 Route 53 服務，記下您的網域 Hosted zone 的 **Hosted Zone ID**。 

    Go to Route 53 service and note down the **Hosted Zone ID** of your domain's Hosted zone.

### 2. Google OAuth 2.0 (SSO 登入用 / For SSO Login)

1. 前往 Google Cloud Console。 

   Go to Google Cloud Console.
1. 建立一個新專案 (Project)。 

   Create a new Project.
1. 前往 **APIs & Services** > **OAuth consent screen**： 

   Go to **APIs & Services** > **OAuth consent screen**:

   - **User Type** 選擇 **External** (除非您擁有 Google Workspace 組織)。 

      Select **External** for **User Type** (unless you have a Google Workspace organization).
   - 填寫 App name (如 Secure Gateway) 與聯絡 Email，儲存並繼續。 

      Fill in App name (e.g., Secure Gateway) and contact Email, save and continue.
1. 前往 **Credentials** > **Create Credentials** > **OAuth client ID**。 

    Go to **Credentials** > **Create Credentials** > **OAuth client ID**.

   - **Application type** 選擇 **Web application**。 

      Select **Web application** for **Application type**.
   - **Authorized redirect URIs** 填入：`https://auth.YOUR_DOMAIN.com/oauth2/google/callback` (請將 `auth.YOUR_DOMAIN.com` 替換為實際設定的驗證網域)。 

      Fill in **Authorized redirect URIs**: `https://auth.YOUR_DOMAIN.com/oauth2/google/callback` (replace `auth.YOUR_DOMAIN.com` with your actual auth domain).
1. 建立後，複製顯示的 **Client ID** 與 **Client Secret**。 

    After creation, copy the displayed **Client ID** and **Client Secret**.
1. **JWT Token 生成**：打開終端機執行 `openssl rand -hex 32` 產生一組隨機字串作為 `JWT_SHARED_KEY`。 

    **JWT Token Generation**: Open terminal and run `openssl rand -hex 32` to generate a random string as `JWT_SHARED_KEY`.

### 3. Guacamole TOTP (2FA 擴充套件 / 2FA Extension)

1. 前往 Apache Guacamole Releases。 

    Go to Apache Guacamole Releases.
1. **重要**：確認版本號需與 `docker-compose.yml` 中的 Guacamole 映像檔版本一致 (例如 1.5.5)。 

    **Important**: Ensure the version matches the Guacamole image version in `docker-compose.yml` (e.g., 1.5.5).
1. 點擊該版本連結，找到 **Extensions** 區塊。 

    Click the version link, find the **Extensions** section.
1. 下載 `guacamole-auth-totp-x.x.x.tar.gz`。 

    Download `guacamole-auth-totp-x.x.x.tar.gz`.
1. 解壓縮該檔案，取出其中的 `.jar` 檔 (例如 `guacamole-auth-totp-1.5.5.jar`)。 

    Extract the file and take out the `.jar` file (e.g., `guacamole-auth-totp-1.5.5.jar`).
1. 將此 `.jar` 檔放入 NAS 的 `/secure-gateway/guac_extensions/` 資料夾。 

    Place this `.jar` file into the `/secure-gateway/guac_extensions/` folder on the NAS.

## 🚀 部署前手動準備步驟 / Pre-deployment Manual Steps

### 1. 建立 Macvlan 網路 (關鍵) / Create Macvlan Network (Critical)

由於 Caddy 需要佔用 Port 80/443，為避免與 DSM 衝突，需建立 Macvlan 網路給予獨立 IP。

Since Caddy needs to occupy Port 80/443, to avoid conflict with DSM, a Macvlan network must be created to assign an independent IP.

請 SSH 進入 NAS 執行：

Please SSH into the NAS and execute:

```bash
# 假設您的主介面是 eth0 (或是 ovs_eth0)，請依實際情況調整
# Assuming your main interface is eth0 (or ovs_eth0), please adjust accordingly
# subnet: 您的區網網段
# subnet: Your LAN subnet
# gateway: 您的路由器 IP
# gateway: Your router IP
# ip-range: 希望分配給 Docker 的 IP 範圍 (避免與 DHCP 衝突)
# ip-range: IP range to assign to Docker (avoid conflict with DHCP)

docker network create -d macvlan \
  --subnet=192.168.1.0/24 \
  --gateway=192.168.1.1 \
  --ip-range=192.168.1.5/32 \
  -o parent=eth0 \
  macvlan_net
```

> ⚠️ **Known Limitation:** With Macvlan, the NAS host itself cannot directly reach the Caddy container's IP. This is a Linux kernel Macvlan restriction. To access Caddy from the NAS host, you need either: (1) Router-level hairpin NAT, or (2) an additional `macvlan` bridge interface on the host. Normal LAN clients are unaffected.

### 2. 設定環境變數 / Set Environment Variables

此專案依賴多個環境變數，您可以透過 **Synology Container Manager 的網頁介面 (Environment)** 直接注入，或是建立一個傳統的 `.env` 檔案。

This project relies on several environment variables. You can inject them directly via the **Synology Container Manager Web UI (Environment)**, or create a traditional `.env` file.

請準備好下列變數清單：
Please prepare the following variables:

```env
AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID_NO_TYPOS_PLEASE
AWS_SECRET_ACCESS_KEY=YOUR_SUPER_SECRET_KEY_KEEP_IT_SAFE_LIKE_THE_ONE_RING
AWS_HOSTED_ZONE_ID=YOUR_ROUTE53_ZONE_ID_LOOKS_LIKE_ALIEN_CODE
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID_COPY_PASTE_MASTER
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_SECRET_SHHH_DONT_TELL_ANYONE
JWT_SHARED_KEY=YOUR_RANDOMLY_GENERATED_GIBBERISH_FROM_OPENSSL
POSTGRES_PASSWORD=YOUR_DB_PASSWORD_STRONGER_THAN_YOUR_COFFEE
SSH_SERVER_IP=192.168.1.10
PVE_SERVER_IP=192.168.1.10
DOMAIN_NAME=yourdomain.com
CROWDSEC_BOUNCER_KEY=YOUR_CROWDSEC_BOUNCER_API_KEY
```

### 3. 其他檔案準備/ Other File Preparation

- **Coraza Conf:** 從 Coraza 官方 Repo 下載推薦設定，更名為 `coraza.conf` 並放入 `caddy_config/`。

    Download the recommended configuration from the official Coraza Repo, rename it to `coraza.conf`, and place it in `caddy_config/`.
- **CrowdSec Acquis:** 建立 `crowdsec_config/acquis.yaml` (內容如下) 以讀取 Caddy 日誌。

    Create `crowdsec_config/acquis.yaml` (content below) to read Caddy logs.

```
filenames:
  - /var/log/caddy/access.log
labels:
  type: caddy
```

- **CrowdSec Whitelist:** 建立 `crowdsec_config/parsers/s02-enrich/whitelist.yaml` (內容如下) 以防止封鎖內網 IP。

    Create `crowdsec_config/parsers/s02-enrich/whitelist.yaml` (content below) to prevent banning internal IPs.

```
name: icekimo/whitelist
description: "Whitelist private IP ranges"
whitelist:
  reason: "private-ip"
  ip:
    - "127.0.0.1"
    - "::1"
  cidr:
    - "192.168.0.0/16"
    - "10.0.0.0/8"
    - "172.16.0.0/12"
```

### 4. 整合 initCheck.sh

若要讓 Caddy 映像檔包含檢查腳本，請修改 `build/Dockerfile`，在 `FROM caddy:alpine` 之後加入：

To include the check script in the Caddy image, please modify `build/Dockerfile` and add the following after `FROM caddy:alpine`:

```dockerfile
COPY initCheck.sh /usr/bin/initCheck.sh
RUN chmod +x /usr/bin/initCheck.sh
```

## 🛠 啟動與初始化/ Startup and Initialization

### 啟動服務/ Start Service

```bash
docker-compose up -d --build
```

### 驗證 Docker Volumes (Host 端) /Verify Docker Volumes (Host Side)

確認所有資料卷是否已正確建立： 

Verify if all data volumes are correctly created:

```bash
chmod +x check_volumes.sh 
# 預設檢查 secure-gateway_* / Default check secure-gateway_*
./check_volumes.sh 
# 若資料夾名稱不同，請指定： ./check_volumes.sh my_project_name
# If the folder name is different, please specify: ./check_volumes.sh my_project_name
```

### 執行環境檢查 (推薦)/ Execute Environment Check (Recommended)

進入 Caddy 容器執行檢查腳本，確認變數與連線是否正常。

Enter the Caddy container to execute the check script and verify if variables and connections are normal.

```bash
docker exec -it secure-gateway /usr/bin/initCheck.sh
```

### CrowdSec 連動 (首次)/ CrowdSec Integration (First Time)

```bash
docker exec -it crowdsec cscli bouncers add caddy-bouncer
# 將產生的 API Key 填回 `.env` 中的 `CROWDSEC_BOUNCER_KEY`，並重啟 Caddy
# Fill the generated API Key back into `.env` as `CROWDSEC_BOUNCER_KEY` and restart Caddy
```

### Guacamole 資料庫初始化 (首次)/ Guacamole Database Initialization (First Time)

```bash
# 產生 SQL / Generate SQL
docker run --rm guacamole/guacamole /opt/guacamole/bin/initdb.sh --postgres > initdb.sql
# 匯入 DB / Import DB
cat initdb.sql | docker exec -i guac_postgres psql -U guacamole_user -d guacamole_db
```

## 💾 資料備份與還原 (Docker Volumes)/Data Backup and Restore (Docker Volumes) 

本專案使用 Docker Volumes 儲存資料庫與憑證，以確保資料安全與權限正確。若需備份資料 (例如遷移或異地備份)，請使用以下指令。

This project uses Docker Volumes to store databases and certificates to ensure data security and correct permissions. If you need to backup data (e.g., migration or off-site backup), please use the following commands. 

> 注意：以下指令假設您的專案資料夾名稱為 secure-gateway，因此 Volume 名稱前綴為 secure-gateway_。若有不同請自行調整。
>
> Note: The following commands assume your project folder name is secure-gateway, so the Volume name prefix is secure-gateway_. Please adjust if different.

### 1. 備份 (Backup)

執行後，會在當前目錄產生 .tar.gz 備份檔。

```bash
# 備份 Guacamole 資料庫 / Backup Guacamole Database
docker run --rm -v secure-gateway_postgres_data:/volume -v $(pwd):/backup alpine tar -czf /backup/postgres_data_backup.tar.gz -C /volume ./
```

### 2. 備份 Caddy 憑證 (建議備份) / Backup Caddy Certificates (Recommended)

```bash
docker run --rm -v secure-gateway_caddy_data:/volume -v $(pwd):/backup alpine tar -czf /backup/caddy_data_backup.tar.gz -C /volume ./
```

### 3. 備份 CrowdSec 資料庫 (選填) / Backup CrowdSec Database (Optional)

```bash
docker run --rm -v secure-gateway_crowdsec_db:/volume -v $(pwd):/backup alpine tar -czf /backup/crowdsec_db_backup.tar.gz -C /volume ./
```

### 4. 還原 (Restore)

> 警告：還原操作將會覆蓋現有 Volume 內的資料。
>
> Warning: The restore operation will overwrite existing data in the Volume.

```bash
# 還原 Guacamole 資料庫 / Restore Guacamole Database
docker run --rm -v secure-gateway_postgres_data:/volume -v $(pwd):/backup alpine sh -c "rm -rf /volume/* && tar -xzf /backup/postgres_data_backup.tar.gz -C /volume"
```