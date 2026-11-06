#!/usr/bin/env bash
# Signs Harbor.app inside-out with hardened runtime and a secure timestamp.
#
#   Scripts/codesign_app.sh <Harbor.app> <identity>
#
# <identity> is "Developer ID Application: <Name> (<TEAMID>)" for releases, or
# "-" for a local ad-hoc build. Any signing failure stops the script: nothing
# here is allowed to fail quietly.
set -euo pipefail

APP_PATH="${1:?usage: codesign_app.sh <Harbor.app> <identity>}"
IDENTITY="${2:?usage: codesign_app.sh <Harbor.app> <identity>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTITLEMENTS="${ROOT}/Sources/Harbor/Resources/Harbor.entitlements"

[[ -d "$APP_PATH" ]] || { echo "ERROR: app bundle not found: $APP_PATH" >&2; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "ERROR: entitlements not found: $ENTITLEMENTS" >&2; exit 1; }
plutil -lint "$ENTITLEMENTS" >/dev/null

ARGS=(--force --options runtime --sign "$IDENTITY")
# Ad-hoc signatures can't carry a secure timestamp; Developer ID ones must.
[[ "$IDENTITY" != "-" ]] && ARGS+=(--timestamp)

sign() { codesign "${ARGS[@]}" "$@"; }

echo "Signing with: $IDENTITY"

SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE" ]]; then
  V="$SPARKLE/Versions/B"
  # Innermost first, then the containers that seal them.
  for path in \
    "$V/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$V/XPCServices/Downloader.xpc" \
    "$V/XPCServices/Installer.xpc/Contents/MacOS/Installer" \
    "$V/XPCServices/Installer.xpc" \
    "$V/Updater.app/Contents/MacOS/Updater" \
    "$V/Updater.app" \
    "$V/Autoupdate" \
    "$V/Sparkle" \
    "$SPARKLE"
  do
    [[ -e "$path" ]] && sign "$path"
  done
fi

for helper in "$APP_PATH/Contents/Helpers/"*; do
  [[ -f "$helper" ]] && sign "$helper"
done

sign --entitlements "$ENTITLEMENTS" "$APP_PATH"

codesign --verify --deep --strict --verbose=1 "$APP_PATH"
echo "Signed and verified: $APP_PATH"
