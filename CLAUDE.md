# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a **Docker Compose-based local developer workspace** running on Windows 11. It provisions a full self-hosted development infrastructure stack behind a Caddy reverse proxy with local TLS (`*.local` domains). All services share a single Docker bridge network called `devstack`.

## Commands

All scripts are PowerShell (`.ps1`) in `scripts/`.

```powershell
# First-time setup (run as Administrator)
powershell -File scripts/setup-hosts.ps1    # Add *.local entries to Windows hosts file
powershell -File scripts/generate-certs.ps1 # Generate TLS certs via mkcert

# Start / stop the stack
docker compose up -d
docker compose down

# Or use the wrapper scripts
powershell -File scripts/start.ps1
powershell -File scripts/stop.ps1

# View logs for a specific service
docker compose logs -f <service-name>

# Restart a single service
docker compose restart <service-name>
```

## Architecture

**Reverse Proxy:** Caddy (via the `caddy-docker-proxy` image) terminates TLS for all services. A small base `caddy/Caddyfile` holds global options (admin/metrics API on `:2019`) and a reusable `(tls_certs)` snippet; per-service routing is generated dynamically from `caddy.*` Docker labels on each service (`caddy: <host>`, `caddy.reverse_proxy: {{upstreams <port>}}`, `caddy.import: tls_certs`). HTTP auto-redirects to HTTPS.

**Services by function:**

| Layer | Services |
|---|---|
| Development | GitLab CE (source control, CI/CD), GitLab Runner, Nexus (artifact repo), Docker Registry |
| Monitoring | Prometheus, Grafana, Loki + Promtail (logs) |
| Storage | MinIO (S3-compatible object storage) |
| Security | HashiCorp Vault (secret management) |
| Infrastructure | Caddy, Portainer (container UI), Watchtower (auto-updates at 4 AM), Homepage (dashboard) |

**Networking:** All services resolve each other by container name on the `devstack` network. External access is through `*.local` domains mapped to `127.0.0.1` in the hosts file.

**Configuration pattern:** Each service with external config has a dedicated directory at the repo root (e.g., `caddy/`, `prometheus/`, `grafana/provisioning/`, `promtail/`, `vault/`, `homepage/config/`). Persistent data lives in `volumes/` (gitignored).

## Key Files

- `docker-compose.yml` — Single compose file defining all services, healthchecks, resource limits, and Caddy labels
- `.env` — Hostnames, credentials, and ports (gitignored — contains passwords)
- `caddy/Caddyfile` — Caddy base config (global options: admin/metrics API on `:2019`; the `(tls_certs)` snippet). Routes themselves come from per-service Docker labels.
- `prometheus/prometheus.yml` — Scrape targets for all services
- `grafana/provisioning/` — Datasource (Prometheus) and dashboard provisioning
- `homepage/config/` — Dashboard layout; services auto-discovered via Docker labels (`homepage.*`)

## Service Profiles

Services are grouped into Docker Compose profiles, controlled by the git-tracked `stack.env` file. Edit `COMPOSE_PROFILES` to enable/disable service groups:

| Profile | Services |
|---|---|
| `dev` | gitlab, gitlab-runner, nexus, registry |
| `monitoring` | prometheus, grafana, loki, promtail |
| `storage` | minio |
| `security` | vault |
| `infra` | portainer |

**Always on** (no profile): caddy, homepage, watchtower

To disable a group, remove it from `COMPOSE_PROFILES` in `stack.env` and redeploy. The wrapper scripts (`start.ps1`, `stop.ps1`, `deploy.sh`) automatically load `stack.env`.

## TLS Profiles

The stack supports three TLS/domain modes, controlled by `TLS_PROFILE` in `stack.env`:

| Profile | Env File | Domains | Cert Source |
|---------|----------|---------|-------------|
| `local` | `.env` | `*.local` | mkcert (`scripts/generate-certs.ps1`) |
| `cloud` | `.env.cloud` | `*.devstack` | Self-signed via cloud-init OpenSSL |
| `aws` | `.env.aws` | `*.example.com` | ACM-exported certs (`scripts/import-acm-certs.ps1`) |

All modes use standardized filenames `cert.pem` / `key.pem` in `caddy/certs/`.

**Quick start with AWS domain:**
```powershell
# 1. Import ACM certs (decrypts the passphrase-encrypted private key)
powershell -File scripts/import-acm-certs.ps1 -CertFile cert.pem -KeyFile key.enc.pem -ChainFile chain.pem -Passphrase "your-passphrase"

# 2. Create env file from template
cp .env.aws.example .env.aws   # Edit domain and passwords

# 3. Add DNS entries to hosts file (run as Admin)
powershell -File scripts/setup-hosts-aws.ps1 -Domain example.com

# 4. Set profile and start
# Edit stack.env: TLS_PROFILE=aws
powershell -File scripts/start.ps1
```

## Conventions

- Services expose themselves to Caddy via Docker labels (`caddy: ${HOST}` + `caddy.reverse_proxy: {{upstreams <port>}}` + `caddy.import: tls_certs`); only running containers get routed
- Homepage dashboard entries are also defined as Docker labels on each service
- Hostnames follow the pattern `<service>.local`, configured in `.env` and referenced as `${VAR}` in compose labels
- TLS certs are generated with `mkcert` and stored in `caddy/certs/` (gitignored)
- Resource limits (`deploy.resources.limits.memory`) are set on every service
- GitLab is the heaviest service (6 GB memory limit, 5-min start period); plan accordingly when starting the stack

## Cloud Deployment (OCI + Tailscale)

The stack can also be deployed to an OCI Always Free ARM instance (4 OCPUs, 24 GB RAM), fully private behind Tailscale (zero public ports).

**Infrastructure:** OpenTofu configs are in `infra/`. The stack uses an OCI `VM.Standard.A1.Flex` instance with Ubuntu 24.04 ARM64, provisioned via cloud-init.

**Security model:** OCI security list has zero ingress rules. OS-level iptables only accept traffic on `tailscale0` and `lo`. All access is via Tailscale SSH and Tailscale MagicDNS.

**Cloud commands:**
```bash
# Provision infrastructure
cd infra && tofu init && tofu plan && tofu apply

# SSH via Tailscale (after cloud-init completes)
tailscale ssh ubuntu@devstack

# Start services on the instance
cd /opt/devstack
cp .env.cloud .env.cloud  # Edit passwords first
docker compose -f docker-compose.yml -f docker-compose.cloud.yml --env-file .env.cloud up -d

# Deploy updates from Windows
bash scripts/deploy.sh

# Add *.devstack DNS entries to Windows hosts file (run as Admin)
powershell -File scripts/setup-hosts-cloud.ps1 -TailscaleIP 100.x.y.z
```

**Key cloud files:**
- `infra/` — OpenTofu configs (OCI provider, networking module, compute module, cloud-init)
- `docker-compose.cloud.yml` — Override file (localhost-only ports, cloud hostnames)
- `.env.cloud` — Cloud hostnames with `.devstack` suffix (gitignored)
- `scripts/deploy.sh` — Tailscale SSH deploy helper
- `scripts/setup-hosts-cloud.ps1` — Adds `*.devstack` entries to Windows hosts file

**DNS:** Services use `*.devstack` hostnames (e.g., `home.devstack`, `gitlab.devstack`). These resolve via Windows hosts file entries pointing to the Tailscale IP (`100.x.y.z`). No domain purchase needed.
