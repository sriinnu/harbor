#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Harbor"
APP_IDENTITY="${CODE_SIGN_IDENTITY:-${HARBOR_CODE_SIGN_IDENTITY:-}}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/Config/version.env"
BUILD_ROOT="${ROOT}/build/macos"
SPM_BUILD_ROOT="${BUILD_ROOT}/.build"
ZIP_NAME="${BUILD_ROOT}/Harbor-${MARKETING_VERSION}.zip"
DSYM_ZIP="${BUILD_ROOT}/Harbor-${MARKETING_VERSION}.dSYM.zip"
mkdir -p "$BUILD_ROOT"

if [[ -z "$APP_IDENTITY" ]]; then
  echo "Set CODE_SIGN_IDENTITY (or HARBOR_CODE_SIGN_IDENTITY) for distribution signing." >&2
  exit 1
fi
if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY_FILE is required for release signing/verification." >&2
  exit 1
fi
if [[ ! -f "$SPARKLE_PRIVATE_KEY_FILE" ]]; then
  echo "Sparkle key file not found: $SPARKLE_PRIVATE_KEY_FILE" >&2
  exit 1
fi
key_lines=$(grep -v '^[[:space:]]*#' "$SPARKLE_PRIVATE_KEY_FILE" | sed '/^[[:space:]]*$/d')
if [[ $(printf "%s\n" "$key_lines" | wc -l) -ne 1 ]]; then
  echo "Sparkle key file must contain exactly one base64 line (no comments/blank lines)." >&2
  exit 1
fi

umask 077
API_KEY_FILE=$(mktemp "${TMPDIR:-/tmp}/harbor-api-key.XXXXXX.p8")
NOTARIZE_ZIP=$(mktemp "${TMPDIR:-/tmp}/harbor-notarize.XXXXXX.zip")
echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_FILE"
trap 'rm -f "$API_KEY_FILE" "$NOTARIZE_ZIP"' EXIT

swift build -c release --arch arm64 --arch x86_64 --build-path "${SPM_BUILD_ROOT}"
SKIP_BUILD=1 ./Scripts/package_app.sh release

# SwiftPM output locations vary (Xcode toolchain + SwiftPM version).
# Resolve the produced app bundle explicitly instead of assuming `./Harbor.app`.
APP_BUNDLE=""
for candidate in \
  "${SPM_BUILD_ROOT}/apple/Products/Release/${APP_NAME}.app" \
  "${SPM_BUILD_ROOT}/release/${APP_NAME}.app" \
  "${SPM_BUILD_ROOT}/arm64-apple-macosx/release/${APP_NAME}.app" \
  "${SPM_BUILD_ROOT}/x86_64-apple-macosx/release/${APP_NAME}.app"; do
  if [[ -d "$candidate" ]]; then
    APP_BUNDLE="$candidate"
    break
  fi
done
if [[ -z "$APP_BUNDLE" ]]; then
  echo "ERROR: app bundle not found (looked in common SwiftPM release locations)" >&2
  exit 1
fi

echo "Signing with $APP_IDENTITY"
./Scripts/codesign_app.sh "$APP_BUNDLE" "$APP_IDENTITY"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" -c -k --keepParent --sequesterRsrc "$APP_BUNDLE" "$NOTARIZE_ZIP"

echo "Submitting for notarization"
xcrun notarytool submit /tmp/HarborNotarize.zip \
  --key "$API_KEY_FILE" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

"$DITTO_BIN" -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"
stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
DSYM_PATH="${SPM_BUILD_ROOT}/apple/Products/Release/Harbor.dSYM"
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH="${SPM_BUILD_ROOT}/release/Harbor.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH="${SPM_BUILD_ROOT}/arm64-apple-macosx/release/Harbor.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  DSYM_PATH="${SPM_BUILD_ROOT}/x86_64-apple-macosx/release/Harbor.dSYM"
fi
if [[ ! -d "$DSYM_PATH" ]]; then
  echo "Missing dSYM at $DSYM_PATH" >&2
  exit 1
fi
"$DITTO_BIN" -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME"
