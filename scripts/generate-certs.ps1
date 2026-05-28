<#
.SYNOPSIS
    Generates TLS certificates for *.local domains using mkcert.
.DESCRIPTION
    Requires mkcert to be installed (e.g. via `choco install mkcert` or `scoop install mkcert`).
    Generates a wildcard certificate covering all workspace domains.
#>

$certsDir = Join-Path $PSScriptRoot "..\caddy\certs"

# Ensure certs directory exists
if (-not (Test-Path $certsDir)) {
    New-Item -ItemType Directory -Path $certsDir -Force | Out-Null
}

# Check if mkcert is available
if (-not (Get-Command mkcert -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: mkcert is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Install it with: choco install mkcert  OR  scoop install mkcert" -ForegroundColor Yellow
    exit 1
}

# Install local CA if not already done
Write-Host "Installing mkcert local CA (if not already installed)..." -ForegroundColor Cyan
mkcert -install

# Generate certificate
$certFile = Join-Path $certsDir "cert.pem"
$keyFile = Join-Path $certsDir "key.pem"

$domains = @(
    "*.local",
    "home.local",
    "gitlab.local",
    "nexus.local",
    "prometheus.local",
    "grafana.local",
    "caddy.local",
    "portainer.local",
    "registry.local",
    "minio.local",
    "s3.local",
    "vault.local"
)

Write-Host "Generating certificates for: $($domains -join ', ')" -ForegroundColor Cyan

Push-Location $certsDir
mkcert -cert-file "cert.pem" -key-file "key.pem" @domains
Pop-Location

if (Test-Path $certFile) {
    Write-Host "Certificates generated successfully:" -ForegroundColor Green
    Write-Host "  Certificate: $certFile" -ForegroundColor Cyan
    Write-Host "  Private Key: $keyFile" -ForegroundColor Cyan
} else {
    Write-Host "ERROR: Certificate generation failed." -ForegroundColor Red
    exit 1
}
