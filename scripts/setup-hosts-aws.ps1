#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Adds *.<domain> entries to the Windows hosts file for an AWS-domain deployment.
.PARAMETER Domain
    The domain suffix (e.g. "example.com").
.PARAMETER IP
    The IP address to point entries to. Defaults to 127.0.0.1.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Domain,

    [string]$IP = "127.0.0.1"
)

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$services = @("home", "gitlab", "nexus", "prometheus", "grafana", "traefik", "portainer", "registry", "minio", "s3", "vault")
$domains = $services | ForEach-Object { "$_.$Domain" }

$hostsContent = Get-Content $hostsPath -Raw

$blockStart = "# >>> Developer Workspace AWS ($Domain) >>>"
$blockEnd = "# <<< Developer Workspace AWS ($Domain) <<<"

# Remove existing block if present
if ($hostsContent -match [regex]::Escape($blockStart)) {
    $pattern = "(?s)" + [regex]::Escape($blockStart) + ".*?" + [regex]::Escape($blockEnd) + "\r?\n?"
    $hostsContent = $hostsContent -replace $pattern, ""
}

# Build new block
$newBlock = @($blockStart)
foreach ($d in $domains) {
    $newBlock += "$IP  $d"
}
$newBlock += $blockEnd
$newBlock += ""

$hostsContent = $hostsContent.TrimEnd() + "`r`n`r`n" + ($newBlock -join "`r`n")

Set-Content -Path $hostsPath -Value $hostsContent -NoNewline
Write-Host "Hosts file updated with AWS domain entries ($Domain):" -ForegroundColor Green
$domains | ForEach-Object { Write-Host "  $IP  $_" -ForegroundColor Cyan }
