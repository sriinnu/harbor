#!/usr/bin/env bash
# Hot reload for the dev app: rebuild, re-sign and relaunch on every save.
#
#   Scripts/dev-watch.sh      or   pnpm dev:watch      (Ctrl-C to stop)
#
# Watches Sources/, Package.swift and Config/ (polling once a second; no extra
# tools needed). Each reload is a new labelled build ("Dev build 0.02.NNNN" in
# the menu), so you always know which build you're looking at. A failed build
# keeps the previous app running and waits for the next save.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
STAMP="$(mktemp "${TMPDIR:-/tmp}/harbor-watch.XXXXXX")"
trap 'rm -f "$STAMP"' EXIT

build() {
  touch "$STAMP"
  if "$ROOT/Scripts/dev-launch.sh" 2>&1 | grep -E "error:|ERROR|==> (Dev build|Running)"; then :; fi
  echo "==> Watching for changes (Ctrl-C to stop)"
}

changed() {
  [[ -n "$(find Sources Package.swift Config -newer "$STAMP" -type f \
    \( -name '*.swift' -o -name '*.json' -o -name '*.plist' -o -name '*.png' -o -name '*.icns' \
       -o -name '*.entitlements' -o -name '*.env' -o -name 'Package.swift' \) -print -quit 2>/dev/null)" ]]
}

build
while sleep 1; do
  if changed; then
    sleep 0.4 # let an editor finish writing a burst of files
    echo "==> Change detected, rebuilding"
    build
  fi
done
