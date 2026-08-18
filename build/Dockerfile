# 版本一律釘死。原本 caddy:builder / plugin / CRS 全抓浮動最新，但那不等於「最新」——
# 基底 image 一旦在本機快取住就不會再更新，實際跑出來的是「基底凍在舊版 + plugin 抓最新」
# 的隨機組合。2026-08-18 就因此 build 失敗：最新的 caddy-l4 要求 Caddy >= 2.11.4，
# 而快取了五個月的 caddy:builder 只提供 2.11.2。
#
# 升級請有意識地改下面的版本號、單獨驗證，不要靠 rebuild 撞運氣。
# 重建務必加 --pull，否則基底 image 仍會沿用本機舊快取。
FROM caddy:2.11.4-builder AS builder

RUN xcaddy build v2.11.4 \
    --with github.com/mholt/caddy-l4@v0.1.2 \
    --with github.com/corazawaf/coraza-caddy/v2@v2.5.0 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.14.1 \
    --with github.com/mholt/caddy-ratelimit@v0.1.0 \
    --with github.com/caddy-dns/route53@v1.6.2 \
    --with github.com/greenpau/caddy-security@v1.1.64

FROM caddy:2.11.4-alpine

# Coraza 專用 CRS，放在 @owasp_crs alias 對應路徑。
# 版本同樣釘死（原本抓 latest release，等於每次 rebuild 都可能換一整套 WAF 規則、
# 讓既有服務冒出無法歸因的新誤判）。
ARG CRS_VER=v4.25.0
RUN apk add --no-cache curl unzip && \
    curl -fsSL --retry 3 \
         "https://codeload.github.com/corazawaf/coraza-coreruleset/zip/refs/tags/${CRS_VER}" \
         -o /tmp/crs.zip && \
    unzip /tmp/crs.zip -d /tmp/crs && \
    cp -r /tmp/crs/coraza-coreruleset-*/rules/@owasp_crs /etc/caddy/@owasp_crs && \
    cp /tmp/crs/coraza-coreruleset-*/rules/@crs-setup.conf.example /etc/caddy/crs-setup.conf && \
    rm -rf /tmp/crs /tmp/crs.zip && \
    apk del curl unzip

    # 加入檢查腳本
COPY initCheck.sh /usr/bin/initCheck.sh
RUN chmod +x /usr/bin/initCheck.sh

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
