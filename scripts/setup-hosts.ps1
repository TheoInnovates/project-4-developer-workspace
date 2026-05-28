#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Adds *.local domains to the Windows hosts file.
.DESCRIPTION
    Maps all Developer Workspace service hostnames to 127.0.0.1.
    Must be run as Administrator.
#>

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$domains = @(
    "home.local",
    "gitlab.local",
    "nexus.local",
    "prometheus.local",
    "grafana.local",
    "portainer.local",
    "registry.local",
    "minio.local",
    "s3.local",
    "vault.local"
)

$hostsContent = Get-Content $hostsPath -Raw

$blockStart = "# >>> Developer Workspace >>>"
$blockEnd = "# <<< Developer Workspace <<<"

# Remove existing block if present
if ($hostsContent -match [regex]::Escape($blockStart)) {
    $pattern = "(?s)" + [regex]::Escape($blockStart) + ".*?" + [regex]::Escape($blockEnd) + "\r?\n?"
    $hostsContent = $hostsContent -replace $pattern, ""
}

# Build new block
$newBlock = @($blockStart)
foreach ($domain in $domains) {
    $newBlock += "127.0.0.1  $domain"
}
$newBlock += $blockEnd
$newBlock += ""

$hostsContent = $hostsContent.TrimEnd() + "`r`n`r`n" + ($newBlock -join "`r`n")

Set-Content -Path $hostsPath -Value $hostsContent -NoNewline
Write-Host "Hosts file updated with Developer Workspace entries:" -ForegroundColor Green
$domains | ForEach-Object { Write-Host "  127.0.0.1  $_" -ForegroundColor Cyan }
