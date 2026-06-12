# Docker Compose Developer Workspace

A self-hosted development infrastructure stack with 20 services, managed by Docker Compose and fronted by Caddy with TLS. Deployed on Linux hosts over Tailscale (e.g. `*.devhub.ninja`), locally with mkcert, or on an OCI Always Free instance (via OpenTofu + Tailscale).

![Docker Compose](https://img.shields.io/badge/Docker_Compose-v2-2496ED?logo=docker)
![OpenTofu](https://img.shields.io/badge/OpenTofu-IaC-844FBA?logo=opentofu)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- **20 integrated services** across dev, monitoring, storage, security, AI, and infrastructure layers
- **Caddy reverse proxy** (label-driven via `caddy-docker-proxy`) with HTTPS routing for your domain (`*.devhub.ninja`, `*.local`, ...)
- **Three TLS profiles** &mdash; local (mkcert), cloud (self-signed), AWS (ACM certificates)
- **Service profiles** &mdash; enable/disable service groups via `stack.env`
- **Full monitoring stack** &mdash; Prometheus + Grafana + Loki/Promtail with pre-built alerts and dashboards
- **OCI cloud deployment** &mdash; OpenTofu IaC for Oracle Cloud Always Free tier, zero public ports via Tailscale
- **Homepage dashboard** &mdash; auto-discovered service catalog via Docker labels
- **Resource-constrained** &mdash; memory limits on every service for predictable local performance

## Architecture

```
                          Linux Host (Tailscale)
                 *.devhub.ninja --> Tailscale IP (Route53)
                     or *.local --> 127.0.0.1 (hosts file)
                                 |
                    +------------+------------+
                    |      Caddy (TLS)        |
                    |   :80 (redirect) :443   |
                    +------------+------------+
                                 |
            +--------------------+--------------------+
            |          devstack bridge network         |
            |                                          |
  +---------+---------+   +----------+----------+      |
  |   Development     |   |    Monitoring       |      |
  |  GitLab CE        |   |  Prometheus         |      |
  |  GitLab Runner    |   |  Grafana            |      |
  |  Nexus            |   |  Loki               |      |
  |  Docker Registry  |   |  Promtail           |      |
  +-------------------+   +---------------------+      |
                                                       |
  +---------+---------+   +----------+----------+      |
  |   Storage         |   |    Security         |      |
  |  MinIO (S3)       |   |  HashiCorp Vault    |      |
  +-------------------+   +---------------------+      |
                                                       |
  +----------------------------------------------------+
  |   Infrastructure (always on)                       |
  |  Caddy    |  Homepage  |  Watchtower  |  Portainer |
  +----------------------------------------------------+
```

See [docs/architecture.md](docs/architecture.md) for detailed network topology and data flow, and [docs/vault.md](docs/vault.md) for Vault init/unseal/backup procedures.

## Quick Start

### Prerequisites

- Docker Engine with Compose v2 (Linux)
- bash; Tailscale on the hosts/clients for private access
- A TLS cert for your domain — an exported ACM wildcard, or `mkcert` for `*.local`

### Setup

```bash
# 1. Clone the repository
git clone https://github.com/your-username/developer-workspace.git
cd developer-workspace

# 2. Copy and edit the environment file
cp .env.example .env   # Edit passwords and hostnames

# 3. Provide TLS certs in caddy/certs/ as cert.pem + key.pem
#    e.g. import an exported ACM wildcard cert:
#    bash scripts/import-acm-certs.sh -c cert.pem -k key.enc.pem -C chain.pem -p <passphrase>

# 4. Point DNS at the host (public Route53 record for a real domain,
#    or /etc/hosts entries for *.local) — for Tailscale, use the node's 100.x IP

# 5. Choose which service groups to enable
#    Edit stack.env to set COMPOSE_PROFILES

# 6. Start the stack (single host) or deploy a Spark target
make up
#    or: bash scripts/deploy.sh spark-d5dd

# 7. Open the dashboard
#    https://home.<your-domain>   (e.g. https://home.devhub.ninja, or https://home.local)
```

> **Note:** GitLab requires ~6 GB RAM and takes up to 5 minutes to start. Monitor with `make log s=gitlab`.

## Service Profiles

Control which services are deployed by editing `COMPOSE_PROFILES` in `stack.env`:

| Profile | Services | Default |
|---------|----------|---------|
| `dev` | GitLab CE, GitLab Runner, Nexus, Docker Registry | Enabled |
| `monitoring` | Prometheus, Alertmanager, Grafana, Loki, Promtail | Enabled |
| `storage` | MinIO (S3-compatible) | Enabled |
| `security` | HashiCorp Vault | Enabled |
| `infra` | Portainer | Enabled |
| `nemotron` | vLLM Nemotron 3 Super 120B (GPU) | Enabled |
| `coder` | vLLM Qwen3-Coder (GPU, spark-06ad) | Disabled |
| `webui` | OpenWebUI | Enabled |
| `search` | SearXNG | Enabled |
| `ide` | code-server | Enabled |
| `status` | Uptime Kuma | Enabled |

**Always on** (no profile required): Caddy, Homepage, Watchtower

## TLS Profiles

| Profile | Domains | Certificate Source | Setup |
|---------|---------|-------------------|-------|
| `local` | `*.local` | mkcert (trusted locally) | `make certs` |
| `cloud` | `*.devstack` | Self-signed via cloud-init | Automatic |
| `aws` | your domain (e.g. `*.devhub.ninja`) | ACM-exported certificates | `scripts/import-acm-certs.sh` |

Set `TLS_PROFILE` in `stack.env` to switch between profiles.

## Cloud Deployment

The stack deploys to an **OCI Always Free** ARM64 instance (4 OCPUs, 24 GB RAM) with zero public ports &mdash; all access is via Tailscale. All container images are multi-arch and run natively on ARM64.

```bash
cd infra && tofu init && tofu apply    # Provision OCI instance
tailscale ssh ubuntu@devstack          # Connect via Tailscale
```

See [`infra/SETUP.md`](infra/SETUP.md) for the full deployment walkthrough, and [`infra/`](infra/) for OpenTofu configuration and cloud-init details.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make up` | Start all enabled services |
| `make down` | Stop all services |
| `make restart` | Full restart |
| `make status` | Show service status |
| `make logs` | Follow all service logs |
| `make log s=<name>` | Follow logs for one service |
| `make validate` | Validate compose config |
| `make pull` | Pull latest images |
| `make top` | Show resource usage |
| `make backup` | Back up GitLab + stateful volumes (cron-friendly: `scripts/backup.sh -d <dir> -k <keep>`) |
| `make certs` | Print the ACM cert-import command |
| `make register-runner` | Register GitLab Runner (manual; or `make gitlab-setup`) |
| `make vault-init` | Initialize Vault |
| `make clean` | Remove all data (destructive) |

## Project Structure

```
.
├── docker-compose.yml          # Main compose file (all services)
├── docker-compose.cloud.yml    # Cloud overrides (OCI deployment)
├── stack.env                   # Profile and TLS mode selection
├── .env                        # Hostnames and credentials (gitignored)
├── Makefile                    # Common operations
├── caddy/
│   ├── Caddyfile               # Base config (global options + tls_certs snippet)
│   └── certs/                  # TLS certificates (gitignored)
├── prometheus/
│   ├── prometheus.yml          # Scrape targets
│   ├── alertmanager.yml        # Alert routing (ntfy/email/Slack receivers)
│   └── alerts/alerts.yml       # Alert rules
├── loki/config.yml             # Log storage + 30d retention
├── grafana/provisioning/
│   ├── datasources/            # Prometheus + Loki datasources
│   └── dashboards/             # Dashboard provisioning + JSON
├── promtail/promtail.yml       # Log collection config
├── vault/config.hcl            # Vault server config
├── homepage/config/            # Dashboard layout
├── scripts/                    # Setup and deployment scripts
├── infra/                      # OpenTofu IaC (OCI cloud)
└── volumes/                    # Persistent data (gitignored)
```

## License

This project is licensed under the [MIT License](LICENSE).
