#!/usr/bin/env bash
# Import ACM-exported certificates into caddy/certs/ on the cloud instance.
# Usage: bash scripts/import-acm-certs.sh -c cert.pem -k key.enc.pem [-C chain.pem] [-p passphrase]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="$SCRIPT_DIR/../caddy/certs"

usage() {
  echo "Usage: $0 -c <cert-file> -k <key-file> [-C <chain-file>] [-p <passphrase>]"
  exit 1
}

CERT_FILE="" KEY_FILE="" CHAIN_FILE="" PASSPHRASE=""

while getopts "c:k:C:p:" opt; do
  case $opt in
    c) CERT_FILE="$OPTARG" ;;
    k) KEY_FILE="$OPTARG" ;;
    C) CHAIN_FILE="$OPTARG" ;;
    p) PASSPHRASE="$OPTARG" ;;
    *) usage ;;
  esac
done

[[ -z "$CERT_FILE" || -z "$KEY_FILE" ]] && usage

for f in "$CERT_FILE" "$KEY_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: File not found: $f"; exit 1; }
done
[[ -n "$CHAIN_FILE" && ! -f "$CHAIN_FILE" ]] && { echo "ERROR: Chain file not found: $CHAIN_FILE"; exit 1; }

mkdir -p "$CERTS_DIR"

# Build cert.pem: certificate + optional chain
if [[ -n "$CHAIN_FILE" ]]; then
  echo "Concatenating certificate + chain..."
  cat "$CERT_FILE" "$CHAIN_FILE" > "$CERTS_DIR/cert.pem"
else
  echo "Copying certificate..."
  cp "$CERT_FILE" "$CERTS_DIR/cert.pem"
fi

# Decrypt private key (or copy if no passphrase)
if [[ -n "$PASSPHRASE" ]]; then
  echo "Decrypting private key..."
  openssl rsa -in "$KEY_FILE" -out "$CERTS_DIR/key.pem" -passin "pass:$PASSPHRASE"
else
  echo "Copying private key (unencrypted)..."
  cp "$KEY_FILE" "$CERTS_DIR/key.pem"
fi

echo "Certificates imported to $CERTS_DIR/cert.pem and $CERTS_DIR/key.pem"
