# Caddy 設定重載標準作業流程與除錯紀錄 (Reload SOP)

## 核心發現 (Great Findings)

在設定 Cockpit 與 Coraza WAF 的過程中，我們遇到了一個經典的 **Docker Bind Mount (掛載點) 與 Inode (索引節點)** 陷阱。

### 發生了什麼事？
1. 我們在宿主機 (Host) 上修改了 `./caddy_config/Caddyfile`，以加入 `@not_ws` 規則來讓 WebSocket 繞過 WAF。
2. 接著執行了 `docker exec secure-gateway caddy reload --config /etc/caddy/Caddyfile`。
3. Caddy logs 回報 `config is unchanged` (設定未改變)，導致新規則沒有生效，WebSocket 依然被擋。

### 為什麼會這樣？
在 Linux / Synology DSM 環境中，Docker 的 Volume Bind Mount 是透過檔案的 **Inode** 來追蹤的。
許多編輯器（或自動化修改工具）在儲存檔案時，會採用「建立暫存檔 -> 覆蓋舊檔」的機制。這會導致檔案的 Inode 改變。
一旦 Host 上的檔案 Inode 改變，Docker 容器**依然會咬住舊的 Inode**，繼續讀取原本（已經不會更新的快取）的檔案內容！

## 標準作業流程 (Correct SOP)

為了確保未來修改 `Caddyfile` 或其他掛載的設定檔時，設定能 100% 生效，請遵循以下 SOP：

### 方法一：最保險的重啟方式 (推薦)
如果你在 Host (宿主機) 上直接編輯了 `Caddyfile`，最穩妥的作法是直接重啟容器，這會強制 Docker 重新掛載所有檔案：
```bash
docker restart secure-gateway
```
*(注意：在多數輕量反向代理場景，重啟 Caddy 容器只需幾秒鐘，通常是可接受的)*

### 方法二：保持 Inode 不變的 Reload 方式
如果你希望做到「Zero-Downtime Reload」(不中斷連線重載)，請確保在 Host 上編輯時**不會改變 Inode** (例如使用 `nano` 等不會替換檔案的編輯器，或是在容器內部進行修改)。確認 Inode 沒有跑掉後，再執行：
```bash
docker exec secure-gateway caddy reload --config /etc/caddy/Caddyfile
```

> [!TIP]
> **如何在 Vim / Vi 中保持檔案 Inode 不變？**
> 如果你習慣使用 `vi` 或 `vim` 編輯檔案，它預設可能會採用「重新命名舊檔並寫入新檔」的安全機制，導致 Inode 改變。如果你希望強制 Vim / Vi **原地覆蓋檔案 (覆寫模式)** 以保留 Inode，可以在編輯器內輸入這行指令，或加入 `~/.vimrc` 中：
> ```vim
> :set backupcopy=yes
> ```
> 這樣 Vim 就會直接覆寫原始檔案內容，確保 Docker 容器同步追蹤到改變！


### 驗證設定是否真的套用
如果下了 `caddy reload` 指令，請務必養成習慣檢查 Log：
```bash
docker logs --tail 20 secure-gateway
```
如果看到 `config is unchanged`，就代表容器根本沒讀到新檔案，請立刻改用**方法一 (重啟容器)**。

---

## 另一種「改了沒生效」：新增環境變數

Caddyfile 裡新出現的 `{$VAR}` 不是靠重啟就會生效的。這一類問題的症狀比 inode 陷阱更兇——
不是安靜地「沒生效」，而是 **Caddy 直接 crash loop**，連帶 auth / guacamole / cockpit 一起掛掉。

### 為什麼？
1. Caddy 的環境變數是在 `docker-compose.yml` 的 `environment:` **逐條明列**注入的（`- VAR=${VAR}`）。
   沒列進去的變數，容器裡根本看不到，即使 `.env` 寫了也一樣。
2. `docker restart` 沿用容器**建立當下**捕獲的環境，**不會重讀 `.env`**。

任一步漏掉，`{$VAR}` 就會展開成空字串。典型的失敗訊息是 caddy-security 收到空的 `match` 值：

```
invalid rule syntax ... matcher values not found
```

### 三步流程（缺一不可）
1. 在 `docker-compose.yml` 的 caddy `environment:` 補上 `- VAR=${VAR}`（這步進版控）。
2. 把實際值寫進 NAS 端的 `.env`（密鑰不進版控）。
3. **重建**容器，不是 restart：

```bash
docker compose up -d caddy
```

## 速查：改了什麼、該用哪個指令

| 改動內容 | 套用方式 |
|---|---|
| `caddy_config/*`，且**未**引入新的 `{$VAR}` | `docker restart secure-gateway` |
| `caddy_config/*`，且引入新的 `{$VAR}` | 上述三步，最後 `docker compose up -d caddy` |
| `caddy_config/portal/assets/*` | `docker restart secure-gateway`（asset 在啟動時讀進記憶體） |
| `docker-compose.yml` | `docker compose up -d` |
| `build/Dockerfile` 或 plugin 版本 | `docker compose build --pull caddy && docker compose up -d caddy` |
| `haproxy_config/haproxy.cfg` | `docker restart gateway-mux` |
| `crowdsec_config/*` | `docker restart crowdsec` |

> 註：`docker compose` 指令一律在 NAS 端執行（bind mount 的相對路徑會以執行端的工作目錄解析）。
> 容器層級操作（`ps` / `logs` / `restart` / `exec`）則可從本機透過 docker context 直接下。

---

## 附錄：WebSocket 與 Coraza WAF 的衝突解法

因為 WAF 引擎的核心邏輯是去攔截並檢查標準的 HTTP 請求與回應「主體(Body)」；但 WebSocket 是一種由 HTTP 「升級 (Upgrade)」後的持續雙向 TCP 串流，這會導致 WAF 引擎因為無法完整讀取 Body 而阻斷連線 (例如發生 `NS_ERROR_WEBSOCKET_CONNECTION_REFUSED`)。

未來若有新增其他需要 WebSocket 的應用 (如 Guacamole, 遠端打字機等)，必須在 `Caddyfile` 中將 WebSocket 的流量繞過 WAF：

```caddyfile
@not_ws {
    not header Connection *Upgrade*
}
coraza_waf @not_ws {
    directives `Include /etc/caddy/coraza.conf`
}
```
