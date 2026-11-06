#!/usr/bin/env bash
set -euo pipefail

PREV_TAG=${1:?'pass previous release tag (e.g. v0.1.0)'}
CUR_TAG=${2:?'pass current release tag (e.g. v0.1.1)'}
APP_NAME="Harbor"
PREV_VER=${PREV_TAG#v}

HARBOR_RELEASE_DOWNLOAD_PREFIX="${HARBOR_RELEASE_DOWNLOAD_PREFIX:-https://github.com/sriinnu/harbor/releases/download}"
if [[ "$HARBOR_RELEASE_DOWNLOAD_PREFIX" != https://* ]]; then
  echo "HARBOR_RELEASE_DOWNLOAD_PREFIX must use HTTPS." >&2
  exit 1
fi

TEST_DIR=${HARBOR_LIVE_UPDATE_TEST_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/harbor-live.XXXXXX")}
if [[ "$TEST_DIR" == "/" || "$TEST_DIR" == "/Applications" ]]; then
  echo "Refusing an unsafe live-update test directory." >&2
  exit 1
fi
mkdir -p "$TEST_DIR"
if [[ -z "${HARBOR_LIVE_UPDATE_TEST_DIR:-}" ]]; then
  trap 'rm -rf "$TEST_DIR"' EXIT
fi

ZIP_URL="${HARBOR_RELEASE_DOWNLOAD_PREFIX}/${PREV_TAG}/${APP_NAME}-${PREV_VER}.zip"
echo "Downloading previous release $PREV_TAG into an isolated test directory."
curl --fail --location --proto '=https' --tlsv1.2 --output "$TEST_DIR/previous.zip" "$ZIP_URL"
ditto -x -k "$TEST_DIR/previous.zip" "$TEST_DIR"
APP_BUNDLE="$TEST_DIR/${APP_NAME}.app"
if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "The downloaded release did not contain ${APP_NAME}.app." >&2
  exit 1
fi

echo "Launching isolated previous build…"
open -n "$APP_BUNDLE"
cat <<MSG
Manual step: use "Check for Updates…" in the isolated app and install the update.
Expected transition: ${PREV_TAG} → ${CUR_TAG}. This test never modifies /Applications.
MSG
read -rp "Did the update succeed? (y/N) " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Live update test was not confirmed." >&2
  exit 1
fi
echo "Live update test confirmed."
