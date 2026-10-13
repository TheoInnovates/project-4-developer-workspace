# Caddy with caddy-docker-proxy (label-based routing, as the stock image provides)
# plus the Route53 DNS provider, so Caddy can solve ACME DNS-01 challenges itself
# and stop depending on manually exported ACM certificates.
FROM caddy:2-builder-alpine AS builder
RUN xcaddy build \
    --with github.com/lucaslorentz/caddy-docker-proxy/v2 \
    --with github.com/caddy-dns/route53

FROM caddy:2-alpine
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
# The stock caddy entrypoint runs `caddy run`; docker-proxy is what watches
# Docker labels and generates per-service config.
CMD ["caddy", "docker-proxy"]
