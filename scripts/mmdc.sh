#!/usr/bin/env bash
# Render a Mermaid diagram to PNG/SVG/PDF via the mermaid-cli Docker image
# (no local node/chromium needed — npm on this host is broken anyway).
#
# Usage:
#   scripts/mmdc.sh diagram.mmd               # -> diagram.png
#   scripts/mmdc.sh diagram.mmd diagram.svg   # output format from extension
#   scripts/mmdc.sh diagram.mmd out.png -b white -s 2   # extra mmdc flags
#
# Typical doc workflow: paste the mermaid block from OpenWebUI into a .mmd
# file, render it, then reference the image from Markdown before pandoc:
#   ![Install flow](install-flow.png)
set -euo pipefail

[[ $# -ge 1 ]] || { echo "usage: $0 <input.mmd> [output.png|svg|pdf] [extra mmdc flags]" >&2; exit 1; }
IN="$1"; shift
OUT="${IN%.*}.png"
if [[ $# -gt 0 && "$1" != -* ]]; then OUT="$1"; shift; fi

IN_DIR="$(cd "$(dirname "$IN")" && pwd)"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
[[ "$IN_DIR" == "$OUT_DIR" ]] || { echo "ERROR: input and output must be in the same directory" >&2; exit 1; }

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -v "$IN_DIR:/data" \
  minlag/mermaid-cli \
  -i "/data/$(basename "$IN")" -o "/data/$(basename "$OUT")" "$@"

echo "rendered: $OUT"
