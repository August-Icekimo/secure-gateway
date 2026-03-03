FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/mholt/caddy-l4 \
    --with github.com/corazawaf/coraza-caddy/v2 \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/caddy-dns/route53 \
    --with github.com/greenpau/caddy-security

FROM caddy:alpine

# 加入檢查腳本
COPY initCheck.sh /usr/bin/initCheck.sh
RUN chmod +x /usr/bin/initCheck.sh

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
