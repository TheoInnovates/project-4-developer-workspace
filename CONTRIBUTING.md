# Contributing

Contributions are welcome! Here's how to get started.

## Development Workflow

1. Fork the repository and create a feature branch:
   ```bash
   git checkout -b feature/my-change
   ```

2. Make your changes and validate:
   ```bash
   make validate          # Validates docker-compose.yml
   docker compose up -d   # Test locally
   ```

3. Commit with a clear message describing the change.

4. Open a pull request against `master` with a description of what changed and why.

## Guidelines

- **Test locally** before submitting &mdash; run `make validate` at minimum
- **Keep compose labels consistent** &mdash; every service exposed via Caddy needs the standard label set (`caddy` host, `caddy.reverse_proxy` upstream, `caddy.import tls_certs`, plus homepage labels)
- **Set resource limits** &mdash; every new service must have `deploy.resources.limits.memory`
- **Add healthchecks** &mdash; every new service should include a healthcheck
- **Update documentation** &mdash; if you add a service, update `CLAUDE.md`, `README.md`, and `prometheus/prometheus.yml` (add a scrape target)
- **Use profiles** &mdash; new services should belong to a compose profile unless they are core infrastructure

## Adding a New Service

1. Add the service definition to `docker-compose.yml` with Caddy labels, healthcheck, resource limits, and a profile
2. Add the hostname variable to `.env.example`
3. Add the DNS entry to `scripts/setup-hosts.ps1`
4. Add a Prometheus scrape target to `prometheus/prometheus.yml` (if the service exposes metrics)
5. Run `make validate` to verify

## Reporting Issues

Use the GitHub issue templates for bug reports and feature requests.
