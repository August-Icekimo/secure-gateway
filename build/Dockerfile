FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-l4 \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/caddy-dns/route53 \
    --with github.com/greenpau/caddy-security

FROM caddy:alpine

# 下載 Coraza 專用 CRS (自動取最新 release)，放在 @owasp_crs alias 對應路徑
RUN apk add --no-cache curl unzip jq && \
    CRS_VER=$(curl -sSL https://api.github.com/repos/corazawaf/coraza-coreruleset/releases/latest | jq -r '.tag_name') && \
    curl -fsSL --retry 3 \
         "https://codeload.github.com/corazawaf/coraza-coreruleset/zip/refs/tags/${CRS_VER}" \
         -o /tmp/crs.zip && \
    unzip /tmp/crs.zip -d /tmp/crs && \
    cp -r /tmp/crs/coraza-coreruleset-*/rules/@owasp_crs /etc/caddy/@owasp_crs && \
    cp /tmp/crs/coraza-coreruleset-*/rules/@crs-setup.conf.example /etc/caddy/crs-setup.conf && \
    rm -rf /tmp/crs /tmp/crs.zip && \
    apk del curl unzip jq

    # 加入檢查腳本
COPY initCheck.sh /usr/bin/initCheck.sh
RUN chmod +x /usr/bin/initCheck.sh

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
