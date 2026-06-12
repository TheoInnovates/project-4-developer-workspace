# Architecture

## Service Topology

The workspace runs 14 services organized into five functional layers, all behind a Caddy reverse proxy on a single Docker bridge network.

```
                         +-----------------------+
                         |    Host Machine       |
                         |  hosts: *.local ->    |
                         |         127.0.0.1     |
                         +----------+------------+
                                    |
                              :80  :443
                         +----------+------------+
                         |        Caddy          |
                         |  - TLS termination    |
                         |  - Host-based routing |
                         |  - HTTP -> HTTPS      |
                         |  - Metrics on :2019   |
                         +----------+------------+
                                    |
               +--------------------------------------------+
               |          devstack (bridge network)         |
               |                                            |
  +------------+------------+    +------------+------------+
  |     Development         |    |     Monitoring          |
  |                         |    |                         |
  |  gitlab.local           |    |  prometheus.local       |
  |   -> GitLab CE (:80)    |    |   -> Prometheus (:9090) |
  |                         |    |                         |
  |  gitlab-runner          |    |  grafana.local          |
  |   -> CI executor        |    |   -> Grafana (:3000)    |
  |                         |    |                         |
  |  nexus.local            |    |  Loki (:3100)           |
  |   -> Nexus (:8081)      |    |   -> Log aggregation    |
  |                         |    |                         |
  |  registry.local         |    |  Promtail               |
  |   -> Registry (:5000)   |    |   -> Log collector      |
  +-------------------------+    +-------------------------+

  +------------+------------+    +------------+------------+
  |     Storage             |    |     Security            |
  |                         |    |                         |
  |  minio.local            |    |  vault.local            |
  |   -> Console (:9001)    |    |   -> Vault (:8200)      |
  |  s3.local               |    |                         |
  |   -> S3 API (:9000)     |    |                         |
  +-------------------------+    +-------------------------+

  +----------------------------------------------------+
  |     Infrastructure (always on)                     |
  |                                                    |
  |  home.local      -> Homepage (:3000)               |
  |  portainer.local -> Portainer (:9000)              |
  |  Watchtower      -> Auto-updates (4 AM daily)      |
  +----------------------------------------------------+
```

## Network Flow

1. **DNS Resolution:** service hostnames resolve to the host — `127.0.0.1` for `*.local` (via `/etc/hosts`), or a public Route53 record pointing at the host's Tailscale IP for a real domain (e.g. `*.devhub.ninja`)
2. **TLS Termination:** Caddy receives all traffic on `:443`, terminates TLS using certificates from `caddy/certs/`, and routes based on the host + upstream defined as `caddy.*` Docker labels on each service
3. **HTTP Redirect:** Port `:80` automatically redirects to `:443`
4. **Internal Communication:** Services communicate by container name on the `devstack` bridge network (e.g., Prometheus scrapes `grafana:3000`)

## Data Flow

```
                    Metrics                     Logs
                      |                           |
   Services -----> Prometheus -----> Grafana <--- Loki <--- Promtail
                      |                                        |
                   alerts.yml                          Docker socket
                   (alerting)                         (container logs)
```

## Cloud Deployment (OCI + Tailscale)

```
  Windows Workstation                   OCI ARM Instance
  +------------------+                 +-------------------+
  |  Tailscale       | --- WireGuard --| Tailscale         |
  |  100.x.y.z      |    (encrypted)  | 100.a.b.c        |
  +------------------+                 +-------------------+
                                       | Docker Compose    |
  Browser ----> *.devstack             | (same services)   |
  (hosts file   resolves to            | iptables: only    |
   entry)       100.a.b.c             |  tailscale0 + lo  |
                                       +-------------------+
                                       OCI Security List:
                                         0 ingress rules
```

- **ARM64 native** &mdash; all container images are multi-arch and run natively on the OCI ARM instance
- **Zero public ports** &mdash; OCI security list has no ingress rules
- **OS firewall** &mdash; iptables only accepts traffic on `tailscale0` and loopback
- **Access** &mdash; Tailscale SSH + MagicDNS for administration
- **Domains** &mdash; `*.devstack` hostnames, no domain purchase required

## Resource Allocation

| Service | Memory Limit | Notes |
|---------|-------------|-------|
| GitLab CE | 6 GB | Heaviest service; 5-min start period |
| Nexus | 2 GB | JVM with -Xmx1536m |
| Prometheus | 512 MB | 30-day retention |
| GitLab Runner | 512 MB | |
| MinIO | 512 MB | |
| Grafana | 256 MB | |
| Loki | 256 MB | |
| Vault | 256 MB | |
| Caddy | 128 MB | |
| Registry | 128 MB | |
| Portainer | 128 MB | |
| Promtail | 128 MB | |
| Homepage | 128 MB | |
| Watchtower | 64 MB | |
