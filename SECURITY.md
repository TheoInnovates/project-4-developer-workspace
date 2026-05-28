# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in this project, please report it responsibly:

1. **Do not** open a public issue
2. Email the maintainer directly or use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
3. Include a description of the vulnerability, steps to reproduce, and potential impact

You should receive a response within 48 hours.

## Security Considerations

This project is designed as a **local development workspace**. Keep the following in mind:

- **Credentials** are stored in `.env` (gitignored) &mdash; never commit secrets
- **TLS certificates** in `caddy/certs/` are gitignored
- **Docker socket** is mounted read-only where possible, but services with socket access (Caddy, Portainer, Watchtower, Promtail) have elevated privileges
- **Vault** should be initialized and unsealed manually; never store unseal keys in version control
- **Cloud deployments** use Tailscale for zero-trust networking with no public ingress ports

## Supported Versions

Only the latest version on the `master` branch is actively maintained.
