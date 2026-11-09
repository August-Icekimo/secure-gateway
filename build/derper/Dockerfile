# 自架 DERP 中繼（derp.DOMAIN）。官方沒有發佈 derper image，從原始碼編。
# 版本與 tailscale-gw 的 image 釘在同一版：--verify-clients 透過 LocalAPI 問 tailscaled，
# 兩邊版本差太多時 API 有可能對不上。升級時兩處一起改。
# Go 版本照 tailscale 該版 go.mod 的 `go` 指令（v1.104.4 要求 1.27.3）。
FROM golang:1.27.3-alpine AS builder

ARG TS_VER=v1.104.4
RUN CGO_ENABLED=0 go install -trimpath -ldflags="-s -w" tailscale.com/cmd/derper@${TS_VER}

FROM alpine:3.24.4

# 非 root 執行。/var/lib/derper 先建好並交給 derper，named volume 首次建立時會沿用這個擁有者
RUN addgroup -S -g 65532 derper && \
    adduser -S -D -H -u 65532 -G derper derper && \
    mkdir -p /var/lib/derper && chown derper:derper /var/lib/derper

COPY --from=builder /go/bin/derper /usr/local/bin/derper

USER derper
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/derper"]
