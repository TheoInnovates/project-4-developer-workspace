<#
.SYNOPSIS
    Stops the Developer Workspace stack.
    Reads stack.env for enabled service profiles and TLS profile.
#>

$repoRoot = Join-Path $PSScriptRoot ".."
$composeFile = Join-Path $repoRoot "docker-compose.yml"
$stackEnv = Join-Path $repoRoot "stack.env"

# Load variables from stack.env so compose knows which profiled services to stop
if (Test-Path $stackEnv) {
    Get-Content $stackEnv | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), "Process")
        }
    }
}

# Select env file based on TLS_PROFILE
$envFile = switch ($env:TLS_PROFILE) {
    "aws"   { Join-Path $repoRoot ".env.aws" }
    "cloud" { Join-Path $repoRoot ".env.cloud" }
    default { Join-Path $repoRoot ".env" }
}

Write-Host "Stopping Developer Workspace..." -ForegroundColor Cyan
docker compose -f $composeFile --env-file $envFile down

Write-Host "All services stopped." -ForegroundColor Green
