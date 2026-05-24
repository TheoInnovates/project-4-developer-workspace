<#
.SYNOPSIS
    Starts the Developer Workspace stack.
    Reads stack.env for enabled service profiles and TLS profile.
#>

$repoRoot = Join-Path $PSScriptRoot ".."
$composeFile = Join-Path $repoRoot "docker-compose.yml"
$stackEnv = Join-Path $repoRoot "stack.env"

# Load variables from stack.env
if (Test-Path $stackEnv) {
    Get-Content $stackEnv | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
        }
    }
    Write-Host "Enabled profiles: $env:COMPOSE_PROFILES" -ForegroundColor Yellow
    Write-Host "TLS profile: $env:TLS_PROFILE" -ForegroundColor Yellow
} else {
    Write-Host "Warning: stack.env not found, no optional services will start." -ForegroundColor Red
}

# Select env file based on TLS_PROFILE
$envFile = switch ($env:TLS_PROFILE) {
    "aws"   { Join-Path $repoRoot ".env.aws" }
    "cloud" { Join-Path $repoRoot ".env.cloud" }
    default { Join-Path $repoRoot ".env" }
}

if (-not (Test-Path $envFile)) {
    Write-Host "ERROR: Env file not found: $envFile" -ForegroundColor Red
    exit 1
}

Write-Host "Using env file: $envFile" -ForegroundColor Yellow
Write-Host "Starting Developer Workspace..." -ForegroundColor Cyan
docker compose -f $composeFile --env-file $envFile up -d

Write-Host ""
Write-Host "Services started. Check your env file for hostnames." -ForegroundColor Green
