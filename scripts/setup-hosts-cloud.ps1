# setup-hosts-cloud.ps1
# Adds *.devstack entries to the Windows hosts file, pointing to the Tailscale IP.
# Run as Administrator.

param(
    [Parameter(Mandatory = $true)]
    [string]$TailscaleIP
)

$hostsFile = "$env:SystemRoot\System32\drivers\etc\hosts"
$domains = @(
    "home.devstack",
    "gitlab.devstack",
    "nexus.devstack",
    "prometheus.devstack",
    "grafana.devstack",
    "traefik.devstack",
    "portainer.devstack",
    "registry.devstack",
    "minio.devstack",
    "s3.devstack",
    "vault.devstack"
)

$marker = "# Developer Workspace Cloud (devstack)"
$existingContent = Get-Content $hostsFile -Raw

# Remove any previous devstack cloud entries
if ($existingContent -match [regex]::Escape($marker)) {
    $lines = Get-Content $hostsFile
    $newLines = @()
    $skip = $false
    foreach ($line in $lines) {
        if ($line -eq $marker) { $skip = $true; continue }
        if ($skip -and $line -match "^\s*$") { $skip = $false; continue }
        if ($skip -and $line -match "\.devstack") { continue }
        $skip = $false
        $newLines += $line
    }
    Set-Content -Path $hostsFile -Value ($newLines -join "`n") -NoNewline
}

# Append new entries
$entries = "`n$marker`n"
foreach ($domain in $domains) {
    $entries += "$TailscaleIP`t$domain`n"
}

Add-Content -Path $hostsFile -Value $entries
Write-Host "Added $($domains.Count) *.devstack entries pointing to $TailscaleIP"
Write-Host "Verify with: ping home.devstack"
