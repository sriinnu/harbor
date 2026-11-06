#!/usr/bin/env bash
# Build and launch a dev Harbor with a visible, ever-increasing build label.
#
#   Scripts/dev-launch.sh   or   pnpm dev   or   Scripts/dev.sh launch
#
# Label: <major>.<minor, 2 digits>.<counter, 4 digits>, e.g. 0.02.0007 for the
# 7th dev build of 0.2.x. It shows in the menu ("Dev build 0.02.0007") and in
# Settings → About. The counter lives in build/dev-build-number (not tracked).
#
# Signed with your Apple Development identity when there is one, so the
# Keychain trusts every rebuild the same way (an ad-hoc seal changes per build
# and makes macOS ask again). Never touches /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/Config/version.env"

COUNTER_FILE="$ROOT/build/dev-build-number"
mkdir -p "$ROOT/build"
n=$(( $(cat "$COUNTER_FILE" 2>/dev/null || echo 0) + 1 ))

IFS=. read -r major minor _ <<<"$MARKETING_VERSION"
LABEL=$(printf '%d.%02d.%04d' "$major" "$minor" "$n")

if [[ -z "${APP_IDENTITY:-}" ]]; then
  APP_IDENTITY=$(security find-identity -v -p codesigning \
    | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p' | head -1)
fi
export APP_IDENTITY
export HARBOR_DEV_BUILD_NUMBER="$n" HARBOR_BUILD_LABEL="$LABEL"

echo "==> Dev build ${LABEL} (signing: ${APP_IDENTITY:-ad-hoc})"
"$ROOT/Scripts/package_app.sh" debug
echo "$n" >"$COUNTER_FILE"   # only count builds that succeeded

APP="$ROOT/build/macos/Harbor.app"
# Quit the previous dev build (this checkout's bundle only), then launch the new one.
pkill -f "${APP}/Contents/MacOS/Harbor" 2>/dev/null || true
for _ in {1..20}; do pgrep -f "${APP}/Contents/MacOS/Harbor" >/dev/null || break; sleep 0.2; done
open -n "$APP"
echo "==> Running Harbor dev build ${LABEL}"
