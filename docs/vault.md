# Vault Operations Runbook

Vault runs with file storage (`vault/config.hcl`, data in
`${VOLUMES_BASE}/vault-data`). TLS is terminated by Caddy; the listener itself
is plaintext (`tls_disable = 1`), which is acceptable because the only path to
it is the `devstack` bridge network on a Tailscale-only host. `disable_mlock`
is set because memory locking isn't useful inside an unprivileged container.

## First-time initialization

```bash
make vault-init
# = docker exec vault vault operator init -key-shares=1 -key-threshold=1
```

This prints **one unseal key and one root token, exactly once**. They cannot
be recovered if lost — losing the unseal key means losing every secret.

**Where to keep them (and where not):**
- Put both in a password manager (1Password/Bitwarden/KeePassXC) immediately.
- Never in this repo, the env files, shell history, or on the host itself —
  an unseal key stored next to `vault-data` defeats the seal.
- Consider printing the unseal key and storing it offline as a second copy.

## Unsealing (required after every restart)

Vault starts **sealed**: the process is up and the UI loads, but every API
call returns 503 until it is unsealed. After a host reboot, `docker compose
restart vault`, or a Watchtower-style recreate:

```bash
make vault-unseal KEY=<unseal-key>
# = docker exec vault vault operator unseal <key>
```

Check status with:

```bash
docker exec vault vault status    # "Sealed: false" when ready
```

The Prometheus `vault` scrape target also returns errors while sealed — a
`ServiceDown`-style alert after a reboot usually just means "unseal me".

## Backup and restore

File storage has no online snapshot mechanism (that's a Raft feature), so
back up the data directory. `scripts/backup.sh` (or `make backup`) already
archives `vault-data` with the other volumes.

For a guaranteed-consistent copy, seal Vault first:

```bash
docker exec vault vault operator seal
make backup            # or: tar -czf vault-data.tar.gz -C "$VOLUMES_BASE" vault-data
make vault-unseal KEY=<unseal-key>
```

**A backup of `vault-data` is useless without the unseal key** — the on-disk
data is encrypted. The unseal key in your password manager *is* part of the
backup.

Restore = stop vault, replace `${VOLUMES_BASE}/vault-data` with the archived
copy, start vault, unseal with the key that was current when the backup was
taken.

## Day-2 basics

```bash
# Login (root token, or create lesser tokens/policies after setup)
docker exec -it vault vault login

# Enable the KV v2 engine and store/read a secret
docker exec -it vault vault secrets enable -path=secret kv-v2
docker exec -it vault vault kv put secret/myapp db_password=hunter2
docker exec -it vault vault kv get secret/myapp
```

UI: `https://vault.<domain>` (e.g. https://vault.devhub.ninja).
