# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Docker Compose-based security gateway deployed on Synology DSM. It sits between the internet and internal services, handling SSL termination, SSO authentication, WAF, and rate limiting.

**Traffic flow:** Router NAT (443→NAS:8443, 80→NAS:8080) → Caddy (custom build) → internal services via Docker bridge network.

## Core Components

| Service | Container | Role |
|---|---|---|
| Caddy (custom) | `secure-gateway` | Reverse proxy, SSL, WAF, auth, rate limiting |
| Tailscale sidecar | `tailscale-gw` | Provides the tailnet netns Caddy shares (`network_mode: service:tailscale-gw`); the public 8080/8443 ports live here, and it's how Caddy routes to the MLX backend on the tailnet |
| CrowdSec | `crowdsec` | Reads Caddy logs, blocks malicious IPs |
| Guacamole | `guacamole` | HTML5 SSH/VNC jump server with TOTP 2FA |
| guacd | `guacd` | Guacamole protocol proxy |
| PostgreSQL | `guac_postgres` | Guacamole database |

## Key Configuration Files

- `caddy_config/Caddyfile` — all routing, auth, WAF, and rate limit rules; uses env vars via `{$VAR}`
- `caddy_config/coraza.conf` — Coraza WAF rules
- `caddy_config/coraza-exclusions.conf` — WAF rule exclusions
- `caddy_config/portal/users.json` — local identity store (fallback login, auto-written by Caddy on startup)
- `caddy_config/portal/custom.css` — Liquid Glass portal theme; light/dark via `light-dark()` tokens, follows system or manual override
- `caddy_config/portal/custom.js` — theme toggle: clicking the portal logo sets `data-theme` on `<html>` (persisted in localStorage)
- `caddy_config/portal/assets/` — swappable `background.svg` + SVG icons (`icons/ui/` tinted via CSS mask + currentColor, `icons/brand/` self-colored); each asset must be registered as a `static_asset` in the Caddyfile `ui` block, and assets are read into memory at startup, so restart Caddy after changing them (see the directory READMEs)
- `build/Dockerfile` — xcaddy build with plugins: `caddy-l4`, `coraza-caddy`, `caddy-crowdsec-bouncer`, `caddy-ratelimit`, `caddy-dns/route53`, `caddy-security`

## Common Operations

**Start / rebuild:**
```bash
docker-compose up -d --build
```

**Reload Caddy config (zero-downtime, see inode caveat below):**
```bash
docker exec secure-gateway caddy reload --config /etc/caddy/Caddyfile
```

**Restart Caddy (always works, a few seconds downtime):**
```bash
docker restart secure-gateway
```

**Check if reload actually applied** (if logs say `config is unchanged`, the inode changed — use restart instead):
```bash
docker logs --tail 20 secure-gateway
```

**Run environment check inside Caddy container:**
```bash
docker exec -it secure-gateway /usr/bin/initCheck.sh
```

**Add CrowdSec bouncer key (first-time setup):**
```bash
docker exec -it crowdsec cscli bouncers add caddy-bouncer
# Then set CROWDSEC_BOUNCER_KEY in .env and restart Caddy
```

**Reset a local user's password** — bcrypt hash only (cost 10), update `caddy_config/portal/users.json`, then reload Caddy.

## Critical Architecture Notes

### Docker Bind Mount Inode Trap
When editing `Caddyfile` or other bind-mounted files on the host, editors that write via a temp-file (most editors except `nano`) change the file's inode. Docker's container keeps the old inode, so `caddy reload` reports `config is unchanged` even though the file is different on the host. **Fix: use `docker restart secure-gateway` after editing on host, or edit inside the container to preserve the inode.** If using Vim, add `:set backupcopy=yes` to `~/.vimrc`.

### WAF Must Bypass WebSocket
Coraza WAF cannot handle WebSocket (HTTP Upgrade) connections and will break them. All WebSocket-using services (Guacamole, Cockpit) require the `@not_ws` matcher to skip WAF:
```caddyfile
@not_ws {
    not header Connection *Upgrade*
}
coraza_waf @not_ws {
    directives `Include /etc/caddy/coraza.conf`
}
```

### Authentication & RBAC
- `authp/user` — access to Guacamole
- `authp/admin` — access to Cockpit and admin services
- Google OAuth login matching `ALLOWEDE_GMAIL` auto-grants both roles
- Local `users.json` is a fallback/break-glass identity store; Caddy writes to it on startup, so track it with `git update-index --assume-unchanged caddy_config/portal/users.json` on production hosts to prevent `git pull` conflicts

### Layer 4 SSH Multiplexing
The `caddy-l4` SSH/HTTPS traffic splitter on port 443 is currently **commented out** in the Caddyfile due to module matching issues.

### Tailscale Sidecar netns (reaching tailnet backends)
The NAS Synology Tailscale package runs `tailscaled --tun=userspace-networking`, so there is **no kernel `tailscale0` device and no host route to `100.64.0.0/10`** — neither the host nor any bridge container can reach a tailnet peer (this is *not* a docker-bridge issue; the bridge works for LAN/internet). To reach the MLX backend, a `tailscale-gw` sidecar runs Tailscale in kernel-TUN mode (`TS_USERSPACE=false`, `/dev/net/tun`, `NET_ADMIN`) and Caddy joins its netns via `network_mode: service:tailscale-gw`. Consequences:
- The public **8080/8443 ports and `internal_bridge` membership live on `tailscale-gw`**, not on the Caddy service.
- Caddy depends on `tailscale-gw` with `condition: service_started` (deliberately *not* `service_healthy`) so a tailnet outage can't take the whole gateway down — only MLX requests 502 until the link is up.
- `--accept-routes` is intentionally **not** set (we only need the peer's node IP `100.88.136.117`); accepting subnet routes could clash with the NAS's own LAN/subnet-router role.
- If `tailscale-gw` is recreated, Caddy's networking drops with it — restart Caddy too.

### Subdomain Routing
- `auth.DOMAIN` — authentication portal (caddy-security)
- `gconsole.DOMAIN` — Guacamole (requires `authp/user`)
- `cockpit.DOMAIN` — Cockpit system manager (requires `authp/admin`)
- `cindy.DOMAIN` — isolated block, CrowdSec only, no WAF. `/webhook/*` paths stay unauthenticated (LINE/Telegram machine-to-machine); all other paths require Google OAuth (`sandboxview`/`authp/admin`) and proxy to the agent terminal view at `{$COCKPIT_SERVER_IP}:8000`
- `dsm7.DOMAIN` — Synology DSM 管理主控台。獨立 block，CrowdSec + 專屬 rate limit（600/1m），**無 WAF**：DSM webapi 的 JSON payload 誤判率高，且 WAF 只擋得到已被 `authorize` 攔下的未登入流量。需 `authp/user`（`user_policy`），通過後仍要輸入 DSM 自己的帳密 → 雙層認證。反代到 `{$DSM_SERVER_IP}:5000`（http，流量不出 NAS，省去自簽憑證問題）。DSM 端需在「控制台 → 安全性 → 信任的代理伺服器」加入 `172.16.0.0/12`，否則自動封鎖會看到橋接位址而非真實 client IP。另外 `/` 會無條件 302 到 `/?forceDesktop=desktop`：DSM 7 仍會依 User-Agent 送出行動版 bootstrap，但該 UI 的 `sencha-touch-2.4.1/*` 資源已被移除、全部 404，手機/平板會永遠卡在 `Loading...` 遮罩（DSM 自身缺陷，直連 `:5000` 一樣壞）
- `mlx.DOMAIN` — OpenAI-compatible LLM API. Machine-to-machine API-key auth (not OAuth): requests must carry `Authorization: Bearer {$MLX_API_KEY}` **or** `X-API-Key: {$MLX_API_KEY}`, else `401`. Isolated block, CrowdSec only, no WAF (streaming/SSE incompatible with Coraza); proxies to the Tailscale backend `100.88.136.117:8000` (`chrysoberyl`, an MLX host) with `flush_interval -1` for token streaming. Reachable only because Caddy shares the `tailscale-gw` sidecar's netns (see Critical Architecture Notes)

### Post-login Redirect (auto-forward)
The `my_portal` block sets `trust login redirect uri domain suffix {$DOMAIN_NAME} path prefix /`. The `authorize` plugin auto-appends `redirect_url`, but caddy-security **silently drops** it unless the target matches a trusted-redirect rule — without this directive, every protected subdomain (cindy/gconsole/cockpit) strands the user on the portal landing page after login instead of forwarding to the originally requested URL.

## Required Environment Variables

All set in `.env` (or via Synology Container Manager UI):

```
AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_HOSTED_ZONE_ID  # Route53 DNS for certs
GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET                         # Google OAuth SSO
JWT_SHARED_KEY                                                  # caddy-security token signing (openssl rand -hex 32)
POSTGRES_PASSWORD                                               # Guacamole DB
SSH_SERVER_IP, COCKPIT_SERVER_IP                               # LAN IPs of backend servers
DOMAIN_NAME                                                    # Root domain
CROWDSEC_BOUNCER_KEY                                           # Generated by cscli on first run
ALLOWEDE_GMAIL                                                 # Google account granted authp/admin
SANDBOXVIEW_GMAIL_1, _2, _3                                    # Google accounts granted sandboxview (cindy agent terminal, view-only)
MLX_API_KEY                                                    # API key for mlx.DOMAIN OpenAI-compatible gateway (openssl rand -hex 32)
DSM_SERVER_IP                                                  # NAS 自身 LAN IP，dsm7.DOMAIN 反代 DSM :5000 用
TS_AUTHKEY                                                     # Tailscale auth key for the tailscale-gw sidecar to join the tailnet (reusable + tagged recommended)
```

## Data Volumes

All persistent data is in Docker named volumes (not bind mounts):
- `caddy_data` — SSL certificates (back this up)
- `caddy_logs` — shared read-only with CrowdSec for log analysis
- `crowdsec_db` — CrowdSec state
- `postgres_data` — Guacamole database
- `tailscale_state` — `tailscale-gw` node identity/state (so it re-auths from saved state instead of needing the auth key on every restart)
