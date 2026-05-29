.PHONY: up down restart status logs certs clean

# Start all services
up:
	docker compose up -d

# Stop all services
down:
	docker compose down

# Restart all services
restart:
	docker compose down
	docker compose up -d

# Show service status
status:
	docker compose ps

# Follow logs for all services (Ctrl+C to stop)
logs:
	docker compose logs -f

# Follow logs for a specific service: make log s=gitlab
log:
	docker compose logs -f $(s)

# Import exported ACM certs into caddy/certs/
certs:
	@echo "Import certs with:"
	@echo "  bash scripts/import-acm-certs.sh -c <cert> -k <key> [-C <chain>] [-p <passphrase>]"

# Validate docker-compose.yml
validate:
	docker compose config --quiet

# Pull latest images
pull:
	docker compose pull

# Show resource usage
top:
	docker stats --no-stream

# Register GitLab Runner manually (pass TOKEN=<token>)
# For automated registration, use: make gitlab-setup
register-runner:
	docker exec -it gitlab-runner gitlab-runner register \
		--url http://gitlab \
		--token $(TOKEN) \
		--executor docker \
		--docker-image alpine:latest \
		--docker-network-mode devstack

# Create GitLab group + theo user and register the runner (first run only)
gitlab-setup:
	bash scripts/gitlab-setup.sh

# Initialize Vault (first run only)
vault-init:
	docker exec vault vault operator init -key-shares=1 -key-threshold=1

# Unseal Vault (pass KEY=<unseal-key>)
vault-unseal:
	docker exec vault vault operator unseal $(KEY)

# Remove all data (destructive!)
clean:
	@echo "This will delete ALL persistent data. Press Ctrl+C to cancel."
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	docker compose down -v
	rm -rf volumes/*
