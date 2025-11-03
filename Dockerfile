FROM golang:latest AS builder
WORKDIR /app

ARG DERP_VERSION=latest
RUN go install tailscale.com/cmd/derper@${DERP_VERSION}

FROM debian:12.12-slim
WORKDIR /app

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends apt-utils && \
    apt-get install -y ca-certificates curl wget && \
    apt-get install -y netcat-openbsd && \
    mkdir /app/certs

ENV DERP_DOMAIN your-hostname.com
ENV DERP_CERT_MODE letsencrypt
ENV DERP_CERT_DIR /app/certs
ENV DERP_ADDR :443
ENV DERP_STUN true
ENV DERP_STUN_PORT 3478
ENV DERP_HTTP_PORT 80
ENV DERP_VERIFY_CLIENTS false
ENV DERP_VERIFY_CLIENT_URL ""


# 创建健康检查脚本
RUN echo '#!/bin/bash\n\
# 检查 sock 文件是否存在且可连接\n\
if [ ! -S /var/run/tailscale/tailscaled.sock ]; then\n\
  echo "Sock file missing"\n\
  exit 1\n\
fi\n\
\n\
# 测试真正的 tailscale API 连接\n\
if ! curl -s --unix-socket /var/run/tailscale/tailscaled.sock http://localhost/localapi/v0/status > /dev/null; then\n\
  echo "Tailscale daemon not responsive"\n\
  exit 1\n\
fi\n\
\n\
# 检查 derper 服务\n\
if ! wget -q --no-check-certificate -O - https://localhost:${DERP_ADDR#:}/debug/varz > /dev/null; then\n\
  echo "Derper service not responding"\n\
  exit 1\n\
fi\n\
\necho "All checks passed"\n\
exit 0' > /healthcheck.sh && chmod +x /healthcheck.sh

COPY --from=builder /go/bin/derper .

CMD /app/derper --hostname=$DERP_DOMAIN \
    --certmode=$DERP_CERT_MODE \
    --certdir=$DERP_CERT_DIR \
    --a=$DERP_ADDR \
    --stun=$DERP_STUN  \
    --stun-port=$DERP_STUN_PORT \
    --http-port=$DERP_HTTP_PORT \
    --verify-clients=$DERP_VERIFY_CLIENTS \
    --verify-client-url=$DERP_VERIFY_CLIENT_URL
