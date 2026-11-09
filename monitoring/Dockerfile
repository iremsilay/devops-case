FROM alpine:3.23

RUN apk add --no-cache \
    bash \
    python3 \
    kubectl \
    curl \
    ca-certificates

RUN addgroup -S -g 10001 monitor \
    && adduser -S -D -H -u 10001 -G monitor monitor

USER 10001:10001

WORKDIR /opt/monitoring

CMD ["bash", "/opt/monitoring/check-health.sh"]