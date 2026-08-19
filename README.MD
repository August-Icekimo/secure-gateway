# Secure Gateway

這是一個部署在 Synology DSM Container Manager 上的全方位資安閘道器專案。

This is a comprehensive security gateway project deployed on Synology DSM Container Manager.

## 🏗 架構總覽 / Architecture Overview

本專案整合了以下核心元件：

This project integrates the following core components:

- **Caddy (Custom Build):** 容器 `secure-gateway`
    - **Networking:** 不持有任何對外埠。它以 `network_mode: service:tailscale-gw` 共用 sidecar 的網路命名空間，在其中監聽 `:80` 與 `:443`。

          Owns no host ports. It shares the sidecar's network namespace via `network_mode: service:tailscale-gw` and listens on `:80` / `:443` inside it.
    - **Layer 7 Reverse Proxy:** 負責 Web 服務反向代理與 SSL 卸載 (SSL Termination).

          Responsible for Web service reverse proxy and SSL termination.
    - **Security:** 整合 `Google OpenID Connect` (SSO) 進行身分驗證。

          Integrates `Google OpenID Connect` (SSO) for authentication.
    - **WAF & IPS:** 整合 `Coraza WAF` 與 `CrowdSec` 進行入侵防禦。

          Integrates `Coraza WAF` and `CrowdSec` for intrusion prevention.
    - **DNS:** 透過 `AWS Route53 API` 自動申請/續期憑證。

          Automatically requests/renews certificates via `AWS Route53 API`.
- **haproxy Mux:** 容器 `gateway-mux`。Port 443 的協議分流器，讀連線開頭幾個 byte 判斷是 SSH 還是 TLS，讓 443 同時承載兩者（用於封鎖 22 埠的網路環境）。以 `network_mode: host` 直接綁在 NAS 的 `:8443` 上——這是拿到真實 client IP 的關鍵，詳見下方「網路與埠」。

        Port 443 protocol splitter: inspects the first bytes to tell SSH from TLS, so 443 carries both (for networks that block port 22). Runs with `network_mode: host`, binding the NAS's `:8443` directly — this is what makes real client IPs visible; see "Networking & Ports" below.

    > 註：早期由 `caddy-l4` 模組負責分流，已改為獨立容器。分流邏輯與 L7 解耦後，改壞分流器不會連帶讓整座閘道（含 Cockpit 這條救援路徑）一起黑掉。
    >
    > Note: this was originally handled by the `caddy-l4` module. Splitting it into its own container decouples it from L7, so breaking the splitter can no longer take down the whole gateway (including Cockpit, the rescue path).
- **Tailscale Sidecar:** 容器 `tailscale-gw`。以 kernel-TUN 模式加入 tailnet，提供 Caddy 共用的網路命名空間，讓 Caddy 能連到 tailnet 上的後端（如 MLX 主機）。

        Joins the tailnet in kernel-TUN mode and provides the network namespace Caddy shares, letting Caddy reach tailnet backends (e.g. the MLX host).
- **CrowdSec:** 分析 Caddy 存取日誌 (`access.log`、`dsm.log`)，自動封鎖惡意 IP。

        Analyzes Caddy access logs (`access.log`, `dsm.log`) to automatically block malicious IPs.
- **PostgreSQL:** 使用 Docker Volume 進行資料持久化儲存。

        Uses Docker Volume for persistent data storage.
- **Guacamole:** 提供 HTML5 Web 介面的 SSH/VNC 跳板機 (支援 2FA)。

        Provides an HTML5 Web interface SSH/VNC jump server (supports 2FA).

## 🗂️專案目錄結構 / File Layout 

請在 NAS 上 (例如 `/volume1/docker/secure-gateway`) 建立以下結構：

```
/secure-gateway
├── .env                 # [㊙🤐] 環境變數設定檔（不進版控）
├── check_volumes.sh     # 環境 Volume 設定檢查腳本
├── docker-compose.yml   # 堆疊啟動檔
├── build/
│   ├── Dockerfile       # Caddy 編譯腳本（版本已釘死，見下方說明）
│   └── initCheck.sh     # 環境自檢腳本（build 時 COPY 進 image）
├── caddy_config/
│   ├── Caddyfile        # Caddy 核心設定：路由、認證、WAF、速率限制
│   ├── coraza.conf      # WAF 規則設定
│   ├── coraza-exclusions.conf  # WAF 規則例外
│   └── portal/          # 認證入口的身分庫與 UI
│       ├── users.json   # 本機身分庫（備援登入，Caddy 啟動時會自動寫入）
│       ├── custom.css   # 登入頁面自訂樣式（Liquid Glass 主題）
│       ├── custom.js    # 主題切換
│       └── assets/      # 背景圖與 SVG 圖示，見該目錄的 README
├── haproxy_config/
│   └── haproxy.cfg      # Port 443 SSH/HTTPS 分流器設定
├── crowdsec_config/     # CrowdSec 設定（含 acquis.yaml）
├── guac_extensions/     # [手動] 存放 Guacamole TOTP .jar 檔
└── initdb.sql           # [首次] Guacamole 資料庫初始化 SQL
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

### 1. 路由器 Port Forward 設定 / Router Port Forward Setup

對外流量由路由器 NAT 進 NAS。閘道對外只用兩個主機埠：

External traffic reaches the NAS via router NAT. The gateway uses only two host ports:

| 外部 Port / External Port | 內部目標 / Internal Target | 說明 / Note |
|---|---|---|
| 443 (TCP) | NAS-IP : 8443 | HTTPS 與 SSH，由 `gateway-mux` 分流 / HTTPS and SSH, split by `gateway-mux` |
| 80 (TCP) | NAS-IP : 8080 | HTTP → 轉址至 443 / redirected to 443 |

#### 網路與埠 / Networking & Ports

| 主機埠 / Host port | 持有者 / Owner | 方式 / How |
|---|---|---|
| `:8443` | `gateway-mux` (haproxy) | `network_mode: host`，直接綁在主機上 / binds the host directly |
| `:8080` | `tailscale-gw` | docker 發佈埠 `8080:80` / docker published port |
| `127.0.0.1:8444` | `tailscale-gw` | 僅限 loopback，供 `gateway-mux` 回連 Caddy / loopback only, for `gateway-mux` to reach Caddy |

`gateway-mux` 走 host 網路是刻意的：Synology 的 dockerd 使用預設的 `userland-proxy: true`，**發佈埠會把來源位址改寫成橋接閘道**，導致 CrowdSec 看不到真實攻擊來源、`rate_limit` 塌成全世界共用一個水桶。分流器直接綁主機埠才拿得到真實 client IP，再經 PROXY protocol 交給 Caddy。成因、實測證據與刻意未修的部分詳見 `CLAUDE.md`。

`gateway-mux` uses host networking on purpose: Synology's dockerd runs with the default
`userland-proxy: true`, so **published ports rewrite the source address to the bridge gateway** — leaving
CrowdSec blind to real attackers and collapsing `rate_limit` into a single global bucket. Binding the host
port directly is what preserves the real client IP, which is then handed to Caddy over PROXY protocol.
See `CLAUDE.md` for the evidence and the parts deliberately left unfixed.

> ℹ️ DSM nginx 仍持有主機的 80/443，不會衝突——閘道用的是 8080/8443。
>
> DSM nginx continues to own ports 80/443 on the host; there is no conflict because the gateway uses 8080/8443.

### 2. 設定環境變數 / Set Environment Variables

此專案依賴多個環境變數，您可以透過 **Synology Container Manager 的網頁介面 (Environment)** 直接注入，或是建立一個傳統的 `.env` 檔案。

This project relies on several environment variables. You can inject them directly via the **Synology Container Manager Web UI (Environment)**, or create a traditional `.env` file.

請準備好下列變數清單：
Please prepare the following variables:

> Note: `SSH_SERVER_IP`, `COCKPIT_SERVER_IP` and `DSM_SERVER_IP` should reflect the actual LAN IP of each target machine. `DSM_SERVER_IP` is the NAS itself.

```env
AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID_NO_TYPOS_PLEASE
AWS_SECRET_ACCESS_KEY=YOUR_SUPER_SECRET_KEY_KEEP_IT_SAFE_LIKE_THE_ONE_RING
AWS_HOSTED_ZONE_ID=YOUR_ROUTE53_ZONE_ID_LOOKS_LIKE_ALIEN_CODE
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID_COPY_PASTE_MASTER
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_SECRET_SHHH_DONT_TELL_ANYONE
JWT_SHARED_KEY=YOUR_RANDOMLY_GENERATED_GIBBERISH_FROM_OPENSSL
POSTGRES_PASSWORD=YOUR_DB_PASSWORD_STRONGER_THAN_YOUR_COFFEE
SSH_SERVER_IP=192.168.1.10
COCKPIT_SERVER_IP=192.168.1.10
DSM_SERVER_IP=192.168.1.10
DOMAIN_NAME=yourdomain.com
CROWDSEC_BOUNCER_KEY=YOUR_CROWDSEC_BOUNCER_API_KEY
ALLOWEDE_GMAIL=your_gmail_account@gmail.com
SANDBOXVIEW_GMAIL_1=viewer1@gmail.com
SANDBOXVIEW_GMAIL_2=viewer2@gmail.com
SANDBOXVIEW_GMAIL_3=viewer3@gmail.com
MLX_API_KEY=YOUR_MLX_GATEWAY_KEY_FROM_OPENSSL_RAND_HEX_32
TS_AUTHKEY=tskey-auth-XXXXXXXXXX
```

> ⚠️ **新增環境變數時，光改 `.env` 再 `restart` 是不夠的。** compose 裡 caddy 的 `environment:` 是逐條明列注入的，而 `docker restart` 沿用容器建立時的舊環境、不會重讀 `.env`。三步缺一就會讓 `{$VAR}` 展開成空字串、Caddy provision 失敗而 crash loop：(1) 在 compose 補 `- VAR=${VAR}`；(2) 把值寫進 `.env`；(3) `docker compose up -d caddy` **重建**容器。
>
> **Adding an env var takes more than editing `.env` and restarting.** The caddy service lists each variable explicitly under `environment:`, and `docker restart` reuses the environment captured at container creation — it does not re-read `.env`. Miss any of the three steps and `{$VAR}` expands to an empty string, Caddy fails to provision and crash-loops: (1) add `- VAR=${VAR}` to compose; (2) write the value into `.env`; (3) `docker compose up -d caddy` to **recreate** the container.

### 3. 其他檔案準備/ Other File Preparation

- **Coraza Conf:** 從 Coraza 官方 Repo 下載推薦設定，更名為 `coraza.conf` 並放入 `caddy_config/`。

    Download the recommended configuration from the official Coraza Repo, rename it to `coraza.conf`, and place it in `caddy_config/`.
- **CrowdSec Acquis:** `crowdsec_config/acquis.yaml` 指定要分析哪些 Caddy 日誌。

    `crowdsec_config/acquis.yaml` selects which Caddy logs to analyse.

```yaml
filenames:
  - /var/log/caddy/access.log   # *.DOMAIN（auth / gconsole / cockpit）與 mlx
  - /var/log/caddy/dsm.log      # dsm7
labels:
  type: caddy
```

> ⚠️ **檔名必須與 `Caddyfile` 中各 site block 的 `log` 指令一致。** Caddy 對「沒有 `log` 指令」的站台是完全不寫存取記錄的（會被列進 server 的 `skip_hosts`）。這份清單若指向不存在的檔案，CrowdSec 不會報錯，只會安靜地什麼都沒分析——形同只靠 CAPI 社群黑名單在跑。
>
> **Filenames must match the `log` directives in `Caddyfile`.** Caddy writes no access log at all for sites without a `log` directive (they land in the server's `skip_hosts`). If this list points at a non-existent file, CrowdSec does not error — it silently analyses nothing, leaving only the CAPI community blocklist active.

- **CrowdSec Whitelist:** Hub 的 `crowdsecurity/whitelists` 預設已載入於 `crowdsec_config/parsers/s02-enrich/whitelists.yaml`，涵蓋 `127.0.0.0/8`、`192.168.0.0/16`、`10.0.0.0/8`、`172.16.0.0/12`，一般不需另外新增。

    The hub's `crowdsecurity/whitelists` is already loaded at `crowdsec_config/parsers/s02-enrich/whitelists.yaml` and covers those private ranges; normally nothing extra is needed.

> ℹ️ 白名單**只有放在 `parsers/s02-enrich/` 底下才會被載入**。放在 `crowdsec_config/` 根目錄的 `whitelist.yaml` 不會生效，卻很容易讓人誤以為已經設好了。
>
> A whitelist is **only loaded from `parsers/s02-enrich/`**. A `whitelist.yaml` sitting at the root of `crowdsec_config/` has no effect, while looking like it does.

### 4. 版本釘選 / Version Pinning

`build/Dockerfile` 把 Caddy 本體、六個 plugin 與 CRS 規則的版本全部釘死，`initCheck.sh` 也在 build 時 `COPY` 進 image，不需要手動加。

`build/Dockerfile` pins the Caddy binary, all six plugins and the CRS ruleset to exact versions; `initCheck.sh` is `COPY`ed into the image at build time, no manual step needed.

> ⚠️ 早期版本抓浮動的 `caddy:builder` 與 `latest` plugin。那不等於「最新」：基底 image 一旦在本機快取住就不再更新，實際產出是「基底凍在舊版 + plugin 抓最新」的隨機組合，兩者相依關係對不上時 build 會直接失敗。
>
> Earlier versions used the floating `caddy:builder` tag and `latest` plugins. That is not "latest": once the base image is cached locally it never updates, so you get a random mix of an old base and new plugins — which fails outright when their requirements diverge.

升級時請有意識地改版本號，並記得加 `--pull`（否則基底 image 仍會沿用本機舊快取）：

When upgrading, bump the version numbers deliberately and remember `--pull` (otherwise the base image is still taken from the local cache):

```bash
docker compose build --pull caddy && docker compose up -d caddy
```

## 🛡️ 身分認證與權限管理 / Authentication & Authorization

本專案使用 `Caddy-Security` (AuthP) 模組提供穩固的身分驗證與基於角色的存取控制 (RBAC)。

This project uses the `Caddy-Security` module to provide robust authentication and Role-Based Access Control (RBAC).

### 1. 存取控制策略 (RBAC)

系統根據角色 (`Roles`) 來限制使用者能存取的服務：
The system limits user access to services based on `Roles`:

*   **`authp/user` (一般使用者 / regular user)**: 可存取 Guacamole、DSM 等一般服務。
*   **`authp/admin` (系統管理員 / administrator)**: 可額外存取 Cockpit 等核心設施介面。
*   **`sandboxview` (唯讀檢視 / view-only)**: 只能看 cindy 的 agent terminal，不連帶開放 Guacamole。

若您使用 Google OAuth 登入，且信箱完全符合 `.env` 中的 `ALLOWEDE_GMAIL`，系統會在您登入時自動賦予 `authp/admin` 與 `authp/user`；`SANDBOXVIEW_GMAIL_1` ~ `_3` 則只會拿到 `sandboxview`。

If you log in via Google OAuth with an address exactly matching `ALLOWEDE_GMAIL`, you are granted both `authp/admin` and `authp/user`. `SANDBOXVIEW_GMAIL_1`–`_3` receive only `sandboxview`.

### 1b. 子網域與所需權限 / Subdomains and Required Roles

| 子網域 / Subdomain | 服務 / Service | 需要的角色 / Required role | WAF |
|---|---|---|---|
| `auth.DOMAIN` | 認證入口 / auth portal | —（公開 / public） | ✔ |
| `gconsole.DOMAIN` | Guacamole | `authp/user` | ✔ |
| `cockpit.DOMAIN` | Cockpit | `authp/admin` | ✔ |
| `dsm7.DOMAIN` | Synology DSM | `authp/user` | ✘ |
| `cindy.DOMAIN` | agent terminal | `sandboxview` 或 `authp/admin` | ✘ |
| `cindy.DOMAIN/webhook/*` | LINE / Telegram 機對機 | —（不驗證 / unauthenticated） | ✘ |
| `mlx.DOMAIN` | OpenAI 相容 LLM API | API key（非 OAuth / not OAuth） | ✘ |

> 未掛 WAF 的區塊都是刻意的：DSM 的 webapi、MLX 的 SSE 串流、webhook 的 JSON payload 都會被 Coraza 誤判或直接破壞。這些路徑仍保有 CrowdSec。
>
> The blocks without WAF are deliberate: DSM's webapi, MLX's SSE streaming and webhook JSON payloads are either broken or false-flagged by Coraza. CrowdSec still applies to all of them.

### 2. 本機身分白名單 (users.json)

除了 Google OAuth 外，系統提供一個本地端的身分庫作為備用登入管道 (儲存於 `caddy_config/portal/users.json`)。這可用於緊急救援 (Break-Glass) 或是分配臨時帳號給外部廠商。
In addition to Google OAuth, the system provides a local identity directory as a fallback login method.

**初始化與避免 Git 合併衝突 (Important!)**:
Caddy 啟動時會自動寫入活動時間戳記與預設資訊至此檔案。為避免正式環境執行 `git pull` 時發生衝突，**強烈建議在正式環境執行以下指令，忽略追蹤該檔案的本地修改**：
```bash
git update-index --assume-unchanged caddy_config/portal/users.json
```

**空白初始化範例 (Green Path)**:
如果您想要清空並讓系統自動重新建立預設管理員 (`webadmin`) 與官方的 JSON Schema，可以將檔案內容清空並填入此空白陣列，然後重啟 Caddy：
```json
{
  "users": []
}
```

### 3. 變更本機密碼與生效方式 (Password Reset & Reload)

Caddy 身分庫僅接受 `bcrypt` 加密過後的雜湊值 (Hash)，不接受明文密碼。若要幫本機使用者新增或重置密碼：
Caddy identity store only accepts `bcrypt` hashes. To reset a local user's password:

1.  使用線上的 `bcrypt` 產生器 (Cost 建議設定為 10) 將新密碼轉換成 Hash (例如 `$2a$10$...`)。
2.  打開 `caddy_config/portal/users.json`，找到該使用者的 `passwords` 區塊並覆蓋 `hash` 欄位的值。
3.  **讓新密碼生效 (Apply the change)**:
    修改完 JSON 並存檔後，Caddy 不會馬上讀取。**在主機上編輯過的檔案請用 restart，不要用 reload**——編輯器多半以「暫存檔覆蓋」的方式儲存，會改變檔案 inode，容器仍咬著舊的那個，`caddy reload` 會回報 `config is unchanged` 而實際沒有生效（詳見 `Reload_SOP.md`）：

    After editing and saving the JSON, Caddy does not pick it up automatically. **Use restart, not reload, for files edited on the host** — most editors save via a temp file, which changes the inode; the container keeps the old one and `caddy reload` reports `config is unchanged` without applying anything (see `Reload_SOP.md`).

```bash
docker restart secure-gateway
```

    只有在確定 inode 沒變（例如用 `nano` 編輯、或直接在容器內修改）時，才能用零中斷的 reload：

    Only when the inode is known to be unchanged (e.g. edited with `nano`, or edited inside the container) is the zero-downtime reload safe:

```bash
docker exec secure-gateway caddy reload --config /etc/caddy/Caddyfile
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

# 將產生的 API Key 填回 `.env` 的 CROWDSEC_BOUNCER_KEY，然後「重建」Caddy 容器。
# 這裡是 up -d 而不是 restart：restart 不會重讀 .env（見上方「設定環境變數」的警告）。
# Put the generated API key into CROWDSEC_BOUNCER_KEY in `.env`, then RECREATE the Caddy
# container. Use up -d, not restart: restart does not re-read `.env` (see the warning above).
docker compose up -d caddy
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