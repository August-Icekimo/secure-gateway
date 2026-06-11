---
name: deploy
description: 將 secure-gateway 的變更佈署到 Synology DSM（katharine → GitHub → NAS）。涵蓋驗證、git 同步、選擇 restart/reload/rebuild、佈署後健康檢查。當使用者要求「佈署」「deploy」「上線」「套用設定到 NAS」時使用。
---

# secure-gateway 佈署流程（katharine → DSM）

## 拓撲

- **開發機 katharine**：`/home/icekimo/gitWrk/secure-gateway`（本 repo）
- **佈署目標 NAS (DSM)**：`icekimo@192.168.68.69`，repo 同步在 `/volume1/docker/secure-gateway`
- **程式碼傳遞**：只透過 GitHub（`August-Icekimo/secure-gateway`，main branch）。不要 rsync/scp 檔案到 NAS。
- **Docker 操作**：本機已設 docker context `syno`（`ssh://icekimo@192.168.68.69`），且為預設 context。

## ⚠️ 鐵則

1. **`docker compose` 指令一律在 NAS 端執行**（`ssh ... 'cd /volume1/docker/secure-gateway && docker compose ...'`）。
   絕不可在 katharine 的 repo 目錄下對 syno context 跑 compose——相對路徑 bind mount 會被解析成本機路徑字串送到遠端 daemon，造成掛載錯誤或在 NAS 上建立空目錄。
2. **容器層級操作**（`ps`、`logs`、`restart`、`exec`、`inspect`）可直接用 `docker --context syno ...`，不必 ssh。
3. **絕不 commit 任何密鑰**：`.env`、`crowdsec_config/local_api_credentials.yaml` 不得進版本庫。
4. NAS 端的 `caddy_config/portal/users.json` 與 runtime 變動檔已設 `assume-unchanged`，git pull 前不要去動它們。

## 佈署步驟

### 1. 佈署前驗證（本機）

```bash
git status --short            # 工作區要乾淨
git log origin/main..HEAD     # 確認待推送的 commit
```

若 Caddyfile 有改動，先做語法驗證再推送（容器內驗證最準）：

```bash
docker --context syno exec secure-gateway caddy validate --config /etc/caddy/Caddyfile  # 驗證「現行」設定
```

（新設定的驗證會在第 3 步重啟時由 Caddy 啟動程序把關；若想先驗證，可推送後在 NAS pull、再執行上述 validate。）

### 2. 推送並同步到 NAS

```bash
git push origin main
ssh icekimo@192.168.68.69 'cd /volume1/docker/secure-gateway && git pull --ff-only'
```

若 pull 失敗顯示本地變更衝突：先檢視 NAS 端 `git status`，runtime 檔（crowdsec hub、.env）用 `git stash` 或 `git checkout --` 處理後重試，**不要** `reset --hard`（會毀掉 NAS 端 .env 的真實密鑰——確認 .env 未被追蹤前不可動它）。

### 3. 依變更類型選擇套用方式

| 變更內容 | 動作 |
|---|---|
| 只有 `caddy_config/*`（Caddyfile、coraza、portal） | `docker --context syno restart secure-gateway` |
| `build/Dockerfile` 或 plugin 版本 | `ssh icekimo@192.168.68.69 'cd /volume1/docker/secure-gateway && docker compose up -d --build caddy'` |
| `docker-compose.yml` | `ssh ... 'cd /volume1/docker/secure-gateway && docker compose up -d'` |
| `crowdsec_config/*` | `docker --context syno restart crowdsec` |

**為什麼用 restart 而非 reload**：git pull 會改變檔案 inode，容器內看到的仍是舊內容，`caddy reload` 會回報 `config is unchanged` 而沒有實際生效（詳見 Reload_SOP.md 的 inode 陷阱）。restart 強制重新掛載，只有幾秒中斷，是 git-pull 流程下唯一可靠的方式。

### 4. 佈署後健康檢查（必做）

```bash
docker --context syno ps --filter name=secure-gateway --format '{{.Status}}'   # 應為 Up，且未反覆重啟
docker --context syno logs --tail 30 secure-gateway                            # 不應有 error / config is unchanged
```

對外驗證（任一）：

```bash
curl -sI https://auth.${DOMAIN_NAME}/ | head -3        # 認證入口應回 200/302
```

若 Caddy 起不來：`docker --context syno logs secure-gateway` 找錯誤行，修正後從第 1 步重來。緊急回滾：NAS 端 `git checkout HEAD~1 -- <壞掉的檔案>` 後再 restart（不要 reset 整個 tree）。

### 5. 完整環境自檢（可選）

```bash
docker --context syno exec secure-gateway /usr/bin/initCheck.sh
```
