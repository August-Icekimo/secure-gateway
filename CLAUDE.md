# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

A Docker Compose-based security gateway deployed on Synology DSM. It sits between the internet and internal services, handling SSL termination, SSO authentication, WAF, and rate limiting.

**Traffic flow:** Router NAT (443→NAS:8443, 80→NAS:8080) → Caddy (custom build) → internal services via Docker bridge network.

## Core Components

| Service | Container | Role |
|---|---|---|
| Caddy (custom) | `secure-gateway` | Reverse proxy, SSL, WAF, auth, rate limiting |
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

### Subdomain Routing
- `auth.DOMAIN` — authentication portal (caddy-security)
- `gconsole.DOMAIN` — Guacamole (requires `authp/user`)
- `cockpit.DOMAIN` — Cockpit system manager (requires `authp/admin`)
- `cindy.DOMAIN` — isolated block, CrowdSec only, no WAF. `/webhook/*` paths stay unauthenticated (LINE/Telegram machine-to-machine); all other paths require Google OAuth (`sandboxview`/`authp/admin`) and proxy to the agent terminal view at `{$COCKPIT_SERVER_IP}:8000`

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
```

## Data Volumes

All persistent data is in Docker named volumes (not bind mounts):
- `caddy_data` — SSL certificates (back this up)
- `caddy_logs` — shared read-only with CrowdSec for log analysis
- `crowdsec_db` — CrowdSec state
- `postgres_data` — Guacamole database
