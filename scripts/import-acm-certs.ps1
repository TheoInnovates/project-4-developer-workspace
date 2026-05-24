<#
.SYNOPSIS
    Imports ACM-exported certificates into the Traefik certs directory.
.DESCRIPTION
    Decrypts the ACM-encrypted private key and places cert + key as cert.pem / key.pem
    in traefik/certs/ for Traefik to load.
.PARAMETER CertFile
    Path to the certificate file (PEM format).
.PARAMETER KeyFile
    Path to the private key file (PEM format, possibly passphrase-encrypted).
.PARAMETER ChainFile
    Optional path to the certificate chain file (PEM format). If provided, it is
    concatenated after the certificate.
.PARAMETER Passphrase
    Passphrase for the encrypted private key. If omitted, the key is assumed to be unencrypted.
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$CertFile,

    [Parameter(Mandatory = $true)]
    [string]$KeyFile,

    [string]$ChainFile,

    [string]$Passphrase
)

$certsDir = Join-Path $PSScriptRoot "..\traefik\certs"

# Check openssl is available
if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: openssl is not installed or not in PATH." -ForegroundColor Red
    exit 1
}

# Validate input files exist
foreach ($f in @($CertFile, $KeyFile)) {
    if (-not (Test-Path $f)) {
        Write-Host "ERROR: File not found: $f" -ForegroundColor Red
        exit 1
    }
}
if ($ChainFile -and -not (Test-Path $ChainFile)) {
    Write-Host "ERROR: Chain file not found: $ChainFile" -ForegroundColor Red
    exit 1
}

# Ensure certs directory exists
if (-not (Test-Path $certsDir)) {
    New-Item -ItemType Directory -Path $certsDir -Force | Out-Null
}

$destCert = Join-Path $certsDir "cert.pem"
$destKey = Join-Path $certsDir "key.pem"

# Build cert.pem: certificate + optional chain
if ($ChainFile) {
    Write-Host "Concatenating certificate + chain..." -ForegroundColor Cyan
    $certContent = (Get-Content $CertFile -Raw) + "`n" + (Get-Content $ChainFile -Raw)
    Set-Content -Path $destCert -Value $certContent -NoNewline
} else {
    Write-Host "Copying certificate..." -ForegroundColor Cyan
    Copy-Item -Path $CertFile -Destination $destCert -Force
}

# Decrypt private key (or copy if no passphrase)
if ($Passphrase) {
    Write-Host "Decrypting private key..." -ForegroundColor Cyan
    openssl rsa -in $KeyFile -out $destKey -passin "pass:$Passphrase" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to decrypt private key. Check the passphrase." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "Copying private key (unencrypted)..." -ForegroundColor Cyan
    Copy-Item -Path $KeyFile -Destination $destKey -Force
}

Write-Host "Certificates imported successfully:" -ForegroundColor Green
Write-Host "  Certificate: $destCert" -ForegroundColor Cyan
Write-Host "  Private Key: $destKey" -ForegroundColor Cyan
