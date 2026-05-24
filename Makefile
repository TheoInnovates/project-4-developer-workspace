.PHONY: up down restart status logs certs hosts clean

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

# Generate TLS certificates (requires mkcert)
certs:
	powershell -ExecutionPolicy Bypass -File scripts/generate-certs.ps1

# Update Windows hosts file (requires admin)
hosts:
	powershell -ExecutionPolicy Bypass -File scripts/setup-hosts.ps1

# Validate docker-compose.yml
validate:
	docker compose config --quiet

# Pull latest images
pull:
	docker compose pull

# Show resource usage
top:
	docker stats --no-stream

# Register GitLab Runner (interactive — pass TOKEN=<token>)
register-runner:
	docker exec -it gitlab-runner gitlab-runner register \
		--url https://gitlab.local \
		--token $(TOKEN) \
		--executor docker \
		--docker-image alpine:latest \
		--docker-network-mode devstack

# Create GitLab group and users (first run only)
gitlab-setup:
	powershell -ExecutionPolicy Bypass -File scripts/gitlab-setup.ps1

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
