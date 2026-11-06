#!/usr/bin/env bash
# Builds, signs (Developer ID, hardened runtime), notarizes and staples Harbor,
# then produces Harbor-<ver>.zip and Harbor-<ver>.dSYM.zip in the repo root.
# Ported from Runic's Scripts/sign-and-notarize.sh.
#
# Secrets come from ~/.config/harbor/local.env or ./.harbor.local.env (gitignored),
# never from the repo:
#   APP_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
#   APP_STORE_CONNECT_KEY_ID=...  APP_STORE_CONNECT_ISSUER_ID=...
#   APP_STORE_CONNECT_API_KEY_P8="<the full text of your AuthKey_<KEYID>.p8 file>"
set -euo pipefail

APP_NAME="Harbor"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
for LOCAL_ENV in "${HOME}/.config/harbor/local.env" "${ROOT}/.harbor.local.env"; do
  # shellcheck disable=SC1090
  [[ -f "$LOCAL_ENV" ]] && { source "$LOCAL_ENV"; break; }
done
source "$ROOT/Config/version.env"

APP_BUNDLE="${ROOT}/build/macos/${APP_NAME}.app"
ZIP_NAME="${APP_NAME}-${MARKETING_VERSION}.zip"
DSYM_ZIP="${APP_NAME}-${MARKETING_VERSION}.dSYM.zip"

[[ -n "${APP_IDENTITY:-}" ]] || { echo "APP_IDENTITY is not set (see header)." >&2; exit 1; }
if [[ -z "${APP_STORE_CONNECT_API_KEY_P8:-}" || -z "${APP_STORE_CONNECT_KEY_ID:-}" || -z "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "Missing APP_STORE_CONNECT_* env vars (API key, key id, issuer id)." >&2
  exit 1
fi

API_KEY_FILE=$(mktemp "${TMPDIR:-/tmp}/harbor-api-key.XXXXXX")
NOTARIZE_ZIP=$(mktemp "${TMPDIR:-/tmp}/${APP_NAME}Notarize.XXXXXX")
NOTARY_LOG=$(mktemp "${TMPDIR:-/tmp}/harbor-notary.XXXXXX")
chmod 600 "$API_KEY_FILE"
printf '%s\n' "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > "$API_KEY_FILE"
trap 'rm -f "$API_KEY_FILE" "$NOTARIZE_ZIP" "$NOTARY_LOG"' EXIT

# Universal release build, signed by package_app.sh via codesign_app.sh.
ARCHES="${ARCHES:-arm64 x86_64}" APP_IDENTITY="$APP_IDENTITY" "$ROOT/Scripts/package_app.sh" release
ARCH_FLAGS=()
for arch in ${ARCHES:-arm64 x86_64}; do ARCH_FLAGS+=(--arch "$arch"); done
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --build-path "${ROOT}/build/macos/.build" --show-bin-path)"

DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$NOTARIZE_ZIP"

notary_submit() {
  xcrun notarytool submit "$NOTARIZE_ZIP" \
    --key "$API_KEY_FILE" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait "$@"
}

echo "Submitting for notarization"
# S3 Transfer Acceleration can stall to `abortedUpload`. Only an aborted upload
# is retried, once, straight to S3; a rejected build is never resubmitted.
if ! notary_submit 2>&1 | tee "$NOTARY_LOG"; then
  grep -q "abortedUpload" "$NOTARY_LOG" || exit 1
  echo "Notary upload aborted; retrying without S3 acceleration"
  notary_submit --no-s3-acceleration 2>&1 | tee "$NOTARY_LOG"
fi
# notarytool exits 0 even for an "Invalid" verdict; read the status.
grep -q "status: Accepted" "$NOTARY_LOG" || { echo "Notarization was not accepted (see log above)." >&2; exit 1; }

echo "Stapling ticket"
xcrun stapler staple "$APP_BUNDLE"

xattr -cr "$APP_BUNDLE"
find "$APP_BUNDLE" -name '._*' -delete
rm -f "$ZIP_NAME"
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$ZIP_NAME"

spctl -a -t exec -vv "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "Packaging dSYM"
DSYM_PATH="${BIN_DIR}/${APP_NAME}.dSYM"
[[ -d "$DSYM_PATH" ]] || { echo "Missing dSYM at $DSYM_PATH" >&2; exit 1; }
# The dSYM and the signed binary must come from the same link: identical UUIDs
# for every arch. A mismatch means the bundle holds a binary from another build.
APP_UUIDS=$(dwarfdump --uuid "$APP_BUNDLE/Contents/MacOS/${APP_NAME}" | awk '{print $2, $3}' | sort)
DSYM_UUIDS=$(dwarfdump --uuid "$DSYM_PATH" | awk '{print $2, $3}' | sort)
if [[ "$APP_UUIDS" != "$DSYM_UUIDS" ]]; then
  echo "ERROR: app binary and dSYM UUIDs differ; the bundle is not from this build." >&2
  printf 'app:  %s\ndSYM: %s\n' "$APP_UUIDS" "$DSYM_UUIDS" >&2
  exit 1
fi
rm -f "$DSYM_ZIP"
"$DITTO_BIN" --norsrc -c -k --keepParent "$DSYM_PATH" "$DSYM_ZIP"

echo "Done: $ZIP_NAME, $DSYM_ZIP"
