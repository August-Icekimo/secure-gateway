FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-l4 \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/caddy-dns/route53 \
    --with github.com/greenpau/caddy-security

FROM caddy:alpine

# 下載 Coraza 專用 CRS（不能用原版 owasp/modsecurity-crs，語法不相容）
RUN apk add --no-cache curl unzip && \
    mkdir -p /etc/caddy/owasp_crs && \
    curl -sL https://github.com/corazawaf/coraza-coreruleset/releases/download/v4.11.0/coraza-coreruleset-4.11.0.zip \
         -o /tmp/crs.zip && \
    unzip /tmp/crs.zip -d /tmp/crs && \
    cp -r /tmp/crs/rules/. /etc/caddy/owasp_crs/ && \
    rm -rf /tmp/crs /tmp/crs.zip && \
    apk del curl unzip

    # 加入檢查腳本
COPY initCheck.sh /usr/bin/initCheck.sh
RUN chmod +x /usr/bin/initCheck.sh

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
