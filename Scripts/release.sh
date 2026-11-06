#!/usr/bin/env bash
# Harbor release. Ported from Runic's Scripts/release.sh; runbook: docs/release.md.
#
#   Scripts/release.sh --check   preflight: report every gate, change nothing
#   Scripts/release.sh           release Config/version.env's MARKETING_VERSION
#
# Run from a clean `main` equal to origin/main, in the foreground, with the
# security key at hand (the tag and the appcast commit are signed).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

source "$ROOT/Config/version.env"
source "$ROOT/Scripts/release-lib.sh"
source "$ROOT/Scripts/lib/signing.sh"
for LOCAL_ENV in "${HOME}/.config/harbor/local.env" "${ROOT}/.harbor.local.env"; do
  # shellcheck disable=SC1090
  [[ -f "$LOCAL_ENV" ]] && { source "$LOCAL_ENV"; break; }
done

APPCAST="$ROOT/appcast.xml"
APP_NAME="Harbor"
BUNDLE_ID="com.sriinnu.harbor"
FEED_URL="https://raw.githubusercontent.com/sriinnu/harbor/main/appcast.xml"
TAG="v${MARKETING_VERSION}"

# ── Preflight ────────────────────────────────────────────────────────────────
# Each gate runs in a subshell so one failure doesn't hide the rest.
preflight() {
  local failed=0
  gate() {
    local name="$1"; shift
    local out
    if out=$("$@" 2>&1); then
      printf '  PASS  %s\n' "$name"
    else
      printf '  FAIL  %s\n' "$name"
      [[ -n "$out" ]] && printf '        %s\n' "$(printf '%s' "$out" | tail -2 | sed 's/^ERROR: //')"
      failed=$((failed + 1))
    fi
  }
  has_tools() {
    local t missing=()
    for t in git gh swift swiftlint sign_update generate_appcast generate_keys; do
      command -v "$t" >/dev/null 2>&1 || missing+=("$t")
    done
    xcrun --find notarytool >/dev/null 2>&1 || missing+=("notarytool")
    [[ ${#missing[@]} -eq 0 ]] || { echo "missing: ${missing[*]}"; return 1; }
  }
  signing_configured() {
    [[ -n "$(git config user.signingkey || true)" ]] || { echo "git user.signingkey is not set"; return 1; }
  }
  identity_in_keychain() {
    [[ -n "${APP_IDENTITY:-}" ]] || { echo "APP_IDENTITY not set (~/.config/harbor/local.env)"; return 1; }
    security find-identity -v -p codesigning | grep -Fq "\"${APP_IDENTITY}\"" \
      || { echo "\"${APP_IDENTITY}\" is not a valid signing identity in the keychain"; return 1; }
  }
  notary_env() {
    [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] \
      || { echo "APP_STORE_CONNECT_{API_KEY_P8,KEY_ID,ISSUER_ID} not all set"; return 1; }
  }
  private_key_signs() {
    [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]] || { echo "SPARKLE_PRIVATE_KEY_FILE not set"; return 1; }
    local k; k=$(clean_key "$SPARKLE_PRIVATE_KEY_FILE"); probe_sparkle_key "$k"; local rc=$?; rm -f "$k"; return $rc
  }
  tag_is_free() {
    ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "tag $TAG exists locally"; return 1; }
    ! git ls-remote --tags origin "$TAG" | grep -q "refs/tags/$TAG$" || { echo "tag $TAG exists on origin"; return 1; }
  }

  echo "Preflight for ${APP_NAME} ${MARKETING_VERSION} (build ${BUILD_NUMBER}):"
  gate "release tools on PATH" has_tools
  gate "clean working tree" require_clean_worktree
  gate "on main, equal to origin/main" require_main_up_to_date
  gate "package.json matches version.env" ensure_package_version "$MARKETING_VERSION"
  gate "CHANGELOG top section is ${MARKETING_VERSION}" ensure_changelog_finalized "$MARKETING_VERSION"
  appcast_tracked() { git ls-files --error-unmatch appcast.xml >/dev/null 2>&1 || { echo "appcast.xml is not tracked by git (check .gitignore); the feed URL would 404"; return 1; }; }
  gate "appcast.xml tracked (feed is served from main)" appcast_tracked
  gate "appcast: new version, higher build" ensure_appcast_monotonic "$APPCAST" "$MARKETING_VERSION" "$BUILD_NUMBER"
  gate "Sparkle public key in Config/" ensure_sparkle_public_key
  gate "Keychain Sparkle key matches Config/" ensure_sparkle_keypair_matches
  gate "SPARKLE_PRIVATE_KEY_FILE signs" private_key_signs
  gate "Developer ID identity in keychain" identity_in_keychain
  gate "notary API key env" notary_env
  gate "git commit/tag signing configured" signing_configured
  gate "tag ${TAG} is free" tag_is_free

  if (( failed > 0 )); then
    echo "${failed} gate(s) failed. Nothing was changed."
    return 1
  fi
  echo "All gates pass."
}

if [[ "${1:-}" == "--check" ]]; then
  preflight
  exit $?
fi
[[ $# -eq 0 ]] || err "Usage: $0 [--check]"

# ── Release ──────────────────────────────────────────────────────────────────
preflight || err "Preflight failed; fix the gates above and rerun."

KEY_FILE=$(clean_key "${SPARKLE_PRIVATE_KEY_FILE:-}")
NOTES_FILE=$(mktemp "${TMPDIR:-/tmp}/harbor-notes.XXXXXX")
trap 'rm -f "$KEY_FILE" "$NOTES_FILE"' EXIT

# Strict build, SwiftLint, tests (crashed or empty runners fail), shellcheck.
"$ROOT/Scripts/verify.sh"

# Foreground on purpose: it waits on notarization.
"$ROOT/Scripts/sign-and-notarize.sh"

clear_sparkle_caches "$BUNDLE_ID"
extract_notes_from_changelog "$MARKETING_VERSION" "$NOTES_FILE"

# Release tags are always signed, whatever tag.gpgSign says, and verified
# before they leave the machine.
signed "release tag" git tag --sign "$TAG" --message "${APP_NAME} ${MARKETING_VERSION}"
git tag --verify "$TAG" >/dev/null 2>&1 || err "Tag $TAG has no valid signature"
git push origin "$TAG"

# Published releases are immutable: start as a draft, attach everything, then publish.
gh release create "$TAG" "${APP_NAME}-${MARKETING_VERSION}.zip" "${APP_NAME}-${MARKETING_VERSION}.dSYM.zip" \
  --verify-tag \
  --draft \
  --title "${APP_NAME} ${MARKETING_VERSION}" \
  --notes-file "$NOTES_FILE"

SPARKLE_PRIVATE_KEY_FILE="$KEY_FILE" \
  "$ROOT/Scripts/make_appcast.sh" "${APP_NAME}-${MARKETING_VERSION}.zip" "$FEED_URL"

# Still a draft, so its URLs aren't public: check the appcast against the local zip.
verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE" "${APP_NAME}-${MARKETING_VERSION}.zip"

upload_deltas "$TAG"
check_appcast_deltas "$APPCAST" "$TAG" "$BUILD_NUMBER"
check_assets "$TAG"

gh release edit "$TAG" --draft=false

# The public URL must now serve the same bytes before the appcast points at it.
verify_appcast_entry "$APPCAST" "$MARKETING_VERSION" "$KEY_FILE"

push_appcast_commit "$MARKETING_VERSION" "$APPCAST"

if [[ "${RUN_SPARKLE_UPDATE_TEST:-0}" == "1" ]]; then
  PREV_TAG=$(git tag --sort=-v:refname | sed -n '2p')
  [[ -n "$PREV_TAG" ]] || err "RUN_SPARKLE_UPDATE_TEST=1 set but no previous tag found"
  "$ROOT/Scripts/test_live_update.sh" "$PREV_TAG" "$TAG"
fi

# Best-effort: the tag and release already exist, so a tap hiccup must not hide them.
"$ROOT/Scripts/update-homebrew-cask.sh" "$MARKETING_VERSION" || \
  echo "WARN: Homebrew cask bump failed; the release IS published. Re-run Scripts/update-homebrew-cask.sh." >&2

cat <<DONE
Release ${MARKETING_VERSION} is published. To finish:
  1. Merge the appcast PR (sriinnu/appcast-${MARKETING_VERSION}).
  2. Verify live: spctl, stapler, brew fetch --cask sriinnu/tap/harbor.
  3. Add or update Harbor's row in harness-docs websites/harness/VERSIONS.md.
DONE
