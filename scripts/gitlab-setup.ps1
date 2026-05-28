<#
.SYNOPSIS
    Creates initial GitLab group and users via the API.
.DESCRIPTION
    Requires GitLab to be running and healthy.
    Creates a temporary root PAT via rails console, then uses the API.
#>

$GitLabUrl = "https://gitlab.local"

# Read root password from .env
$envFile = Join-Path $PSScriptRoot "..\.env"
$RootPassword = (Get-Content $envFile | Where-Object { $_ -match "^GITLAB_ROOT_PASSWORD=" }) -replace "^GITLAB_ROOT_PASSWORD=", ""

# Skip TLS verification for local mkcert certs
Add-Type -ErrorAction SilentlyContinue @"
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;
public class TrustAll {
    public static void Enable() {
        ServicePointManager.ServerCertificateValidationCallback = delegate { return true; };
    }
}
"@
[TrustAll]::Enable()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Create a temporary root PAT via rails console ---
Write-Host "Creating temporary root API token via rails console..." -ForegroundColor Cyan
docker exec gitlab bash -c @"
cat > /tmp/create_token.rb << 'RUBY'
token = User.find_by_username('root').personal_access_tokens.create!(name: 'setup-script', scopes: ['api', 'create_runner'], expires_at: 1.day.from_now)
puts token.token
RUBY
"@
$token = (docker exec gitlab bash -c "gitlab-rails runner /tmp/create_token.rb" 2>&1) | Select-Object -Last 1

if (-not $token -or $token -match "error" -or $token.Length -lt 10) {
    Write-Host "ERROR: Failed to create API token." -ForegroundColor Red
    Write-Host "  $token" -ForegroundColor Yellow
    exit 1
}
Write-Host "  Token created." -ForegroundColor Green

$headers = @{ "PRIVATE-TOKEN" = $token }

# --- Create group: developers ---
Write-Host "Creating group 'developers'..." -ForegroundColor Cyan
$groupBody = @{
    name       = "developers"
    path       = "developers"
    visibility = "internal"
} | ConvertTo-Json
try {
    $group = Invoke-RestMethod -Uri "$GitLabUrl/api/v4/groups" -Method POST -Headers $headers -Body $groupBody -ContentType "application/json"
    Write-Host "  Group 'developers' created (ID: $($group.id))." -ForegroundColor Green
} catch {
    $errBody = $_.ErrorDetails.Message
    if ($errBody -match "has already been taken") {
        Write-Host "  Group 'developers' already exists, skipping." -ForegroundColor Yellow
        $groups = Invoke-RestMethod -Uri "$GitLabUrl/api/v4/groups?search=developers" -Method GET -Headers $headers
        $group = $groups | Where-Object { $_.path -eq "developers" } | Select-Object -First 1
    } else {
        Write-Host "ERROR: Failed to create group. $errBody" -ForegroundColor Red
        exit 1
    }
}

# --- Create user: theo ---
Write-Host "Creating user 'theo'..." -ForegroundColor Cyan
$userBody = @{
    email              = "theo@local.dev"
    username           = "theo"
    name               = "Theo"
    password           = "Th3o_Dev!2026"
    skip_confirmation  = $true
} | ConvertTo-Json
try {
    $user = Invoke-RestMethod -Uri "$GitLabUrl/api/v4/users" -Method POST -Headers $headers -Body $userBody -ContentType "application/json"
    Write-Host "  User 'theo' created (ID: $($user.id))." -ForegroundColor Green
} catch {
    $errBody = $_.ErrorDetails.Message
    if ($errBody -match "has already been taken") {
        Write-Host "  User 'theo' already exists, skipping." -ForegroundColor Yellow
        $users = Invoke-RestMethod -Uri "$GitLabUrl/api/v4/users?username=theo" -Method GET -Headers $headers
        $user = $users | Select-Object -First 1
    } else {
        Write-Host "ERROR: Failed to create user. $errBody" -ForegroundColor Red
        exit 1
    }
}

# --- Add theo to developers group as Maintainer ---
Write-Host "Adding 'theo' to 'developers' group as Maintainer..." -ForegroundColor Cyan
$memberBody = @{
    user_id      = $user.id
    access_level = 40  # 40 = Maintainer
} | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$GitLabUrl/api/v4/groups/$($group.id)/members" -Method POST -Headers $headers -Body $memberBody -ContentType "application/json" | Out-Null
    Write-Host "  Done." -ForegroundColor Green
} catch {
    $errBody = $_.ErrorDetails.Message
    if ($errBody -match "already a member|Member already exists") {
        Write-Host "  'theo' is already a member, skipping." -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: Failed to add user to group. $errBody" -ForegroundColor Red
    }
}

# --- Register GitLab Runner ---
Write-Host "Checking GitLab Runner registration..." -ForegroundColor Cyan
$configContent = docker exec gitlab-runner cat /etc/gitlab-runner/config.toml 2>$null
if ($LASTEXITCODE -eq 0 -and $configContent -match "\[\[runners\]\]") {
    Write-Host "  Runner already registered, skipping." -ForegroundColor Yellow
} else {
    Write-Host "  Creating instance runner via API..." -ForegroundColor Cyan
    $runnerBody = @{
        runner_type  = "instance_type"
        description  = "devstack-runner"
        tag_list     = @("docker", "devstack")
        run_untagged = $true
    } | ConvertTo-Json
    try {
        $runner = Invoke-RestMethod -Uri "$GitLabUrl/api/v4/user/runners" -Method POST -Headers $headers -Body $runnerBody -ContentType "application/json"
        $runnerToken = $runner.token
        Write-Host "  Runner created (ID: $($runner.id))." -ForegroundColor Green
    } catch {
        $errBody = $_.ErrorDetails.Message
        Write-Host "ERROR: Failed to create runner. $errBody" -ForegroundColor Red
        # Continue to revoke token even if runner creation fails
        $runnerToken = $null
    }

    if ($runnerToken) {
        Write-Host "  Registering runner in container..." -ForegroundColor Cyan
        docker exec gitlab-runner gitlab-runner register `
            --non-interactive `
            --url "http://gitlab" `
            --token "$runnerToken" `
            --executor docker `
            --docker-image "alpine:latest" `
            --docker-network-mode "devstack"
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Runner registered successfully." -ForegroundColor Green
        } else {
            Write-Host "ERROR: Runner registration failed." -ForegroundColor Red
        }
    }
}

# --- Revoke the temporary token ---
Write-Host "Revoking temporary API token..." -ForegroundColor Cyan
docker exec gitlab bash -c "gitlab-rails runner ""PersonalAccessToken.find_by_name('setup-script')&.revoke!""" 2>&1 | Out-Null
Write-Host "  Revoked." -ForegroundColor Green

Write-Host ""
Write-Host "Setup complete!" -ForegroundColor Green
Write-Host "  User:     theo" -ForegroundColor Cyan
Write-Host "  Password: Th3o_Dev!2026 (change on first login)" -ForegroundColor Cyan
Write-Host "  Group:    developers (Maintainer role)" -ForegroundColor Cyan
Write-Host "  Runner:   devstack-runner (docker executor)" -ForegroundColor Cyan
Write-Host "  Login:    $GitLabUrl" -ForegroundColor Cyan
