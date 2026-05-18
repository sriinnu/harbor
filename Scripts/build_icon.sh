#!/usr/bin/env bash
#
# Generate Icon.icns from a single master PNG.
# Bypasses Icon Composer (which applies platform masks that clip custom artwork).
#
# Usage: build_icon.sh <master.png> [out_dir] [basename]
set -euo pipefail

MASTER="${1:-assets/logo.png}"
OUT_DIR="${2:-build/macos/icon}"
BASENAME="${3:-Icon}"

[[ -f "$MASTER" ]] || { echo "Master PNG not found: $MASTER" >&2; exit 1; }

ICONSET="$OUT_DIR/${BASENAME}.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# size:filename pairs — macOS expects both 1x and 2x for each base size
for spec in 16:icon_16x16.png 32:icon_16x16@2x.png 32:icon_32x32.png \
            64:icon_32x32@2x.png 128:icon_128x128.png 256:icon_128x128@2x.png \
            256:icon_256x256.png 512:icon_256x256@2x.png 512:icon_512x512.png \
            1024:icon_512x512@2x.png; do
  sz="${spec%%:*}"
  name="${spec#*:}"
  sips -z "$sz" "$sz" "$MASTER" --out "$ICONSET/$name" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$OUT_DIR/${BASENAME}.icns"
echo "Generated: $OUT_DIR/${BASENAME}.icns"
