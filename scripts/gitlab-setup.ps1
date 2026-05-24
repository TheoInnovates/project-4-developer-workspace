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
token = User.find_by_username('root').personal_access_tokens.create!(name: 'setup-script', scopes: ['api'], expires_at: 1.hour.from_now)
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
    if ($errBody -match "already a member") {
        Write-Host "  'theo' is already a member, skipping." -ForegroundColor Yellow
    } else {
        Write-Host "ERROR: Failed to add user to group. $errBody" -ForegroundColor Red
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
Write-Host "  Login:    $GitLabUrl" -ForegroundColor Cyan
