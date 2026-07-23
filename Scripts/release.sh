#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if [[ "${HARBOR_RELEASE_CONFIRM:-}" != "publish" ]]; then
  echo "Release publishing is disabled. Set HARBOR_RELEASE_CONFIRM=publish after completing release verification." >&2
  exit 1
fi

source "$ROOT/Config/version.env"
source "$HOME/Projects/agent-scripts/release/sparkle_lib.sh"

BUILD_ROOT="$ROOT/build/macos"
APPCAST="$ROOT/appcast.xml"
APP_NAME="Harbor"
ARTIFACT_PREFIX="Harbor-"
BUNDLE_ID="com.sriinnu.harbor"
TAG="v${MARKETING_VERSION}"

err() { echo "ERROR: $*" >&2; exit 1; }

require_clean_worktree
ensure_changelog_finalized "$MARKETING_VERSION"
ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"

swiftformat Sources Tests >/dev/null
swiftlint --strict
swift test

# Note: run this script in the foreground; do not background it so it waits to completion.
"$ROOT/Scripts/sign-and-notarize.sh"

KEY_FILE=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE")
probe_sparkle_key "$KEY_FILE"
clear_sparkle_caches "$BUNDLE_ID"

NOTES_MD=$(mktemp /tmp/harbor-notes.XXXX.md)
"$ROOT/Scripts/generate-release-notes.sh" "$MARKETING_VERSION" "$NOTES_MD"
trap 'rm -f "$KEY_FILE" "$NOTES_MD"' EXIT

git rev-parse "$TAG" >/dev/null 2>&1 && err "Tag already exists: $TAG"
git tag -a "$TAG" -m "Harbor $MARKETING_VERSION"
git push origin "$TAG"

gh release create "$TAG" "${BUILD_ROOT}/${APP_NAME}-${MARKETING_VERSION}.zip" "${BUILD_ROOT}/${APP_NAME}-${MARKETING_VERSION}.dSYM.zip" \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes-file "$NOTES_MD"

SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
  "$ROOT/Scripts/make_appcast.sh" \
  "${BUILD_ROOT}/${APP_NAME}-${MARKETING_VERSION}.zip" \
  "${SPARKLE_FEED_URL:?Set SPARKLE_FEED_URL before publishing an appcast}"

verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

git add "$APPCAST"
git commit -m "docs: update appcast for ${MARKETING_VERSION}"
git push origin main

if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -z "$PREV_TAG" ]] && err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "v${MARKETING_VERSION}"
fi

check_assets "$TAG" "$ARTIFACT_PREFIX"

git push origin --tags

echo "Release ${MARKETING_VERSION} complete."
