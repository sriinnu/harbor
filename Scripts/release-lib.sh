#!/usr/bin/env bash
# Shared release checks and steps. Sourced by release.sh; ported from Runic's
# Scripts/release-lib.sh (the template for every sriinnu macOS release).
set -euo pipefail

RELEASE_LIB_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RELEASE_APP_NAME="${RELEASE_APP_NAME:-Harbor}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-harbor}"

# Sparkle's CLI tools ship in its SwiftPM artifact, matching the bundled
# framework's version exactly. Prefer them over anything else on PATH.
for _sparkle_bin in "${RELEASE_LIB_ROOT}/build/macos/.build/artifacts/sparkle/Sparkle/bin" \
                    "${RELEASE_LIB_ROOT}/.build/artifacts/sparkle/Sparkle/bin"; do
  [[ -x "${_sparkle_bin}/sign_update" ]] && { PATH="${_sparkle_bin}:${PATH}"; break; }
done
unset _sparkle_bin

err() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || err "Required command not found in PATH: $cmd"
}

require_clean_worktree() {
  local status
  status=$(git status --porcelain)
  if [[ -n "$status" ]]; then
    echo "$status" >&2
    err "Git working tree must be clean before releasing."
  fi
}

require_main_up_to_date() {
  local branch
  branch=$(git branch --show-current)
  [[ "$branch" == "main" ]] || err "Release must run from branch 'main' (current: ${branch:-detached})."
  git fetch -q origin main
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || err "Local main is not origin/main. Pull first; a release tag must point at a commit on origin/main."
}

ensure_changelog_finalized() {
  local version="$1"
  local changelog="${2:-CHANGELOG.md}"

  [[ -f "$changelog" ]] || err "CHANGELOG not found: $changelog"

  local first_heading
  first_heading=$(awk '/^## /{print; exit}' "$changelog")
  [[ -n "$first_heading" ]] || err "Could not find a release heading in $changelog"

  if [[ "$first_heading" =~ [Uu]nreleased ]]; then
    err "Top changelog section is still Unreleased. Finalize CHANGELOG.md for $version first."
  fi
  if [[ "$first_heading" != *"$version"* ]]; then
    err "Top changelog section must match MARKETING_VERSION ($version). Found: $first_heading"
  fi
}

ensure_appcast_monotonic() {
  local appcast="$1"
  local version="$2"
  local build_number="$3"

  [[ -f "$appcast" ]] || err "Appcast not found: $appcast"
  [[ "$build_number" =~ ^[0-9]+$ ]] || err "BUILD_NUMBER must be numeric: $build_number"

  python3 - "$appcast" "$version" "$build_number" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast, target_version, target_build = sys.argv[1], sys.argv[2], int(sys.argv[3])
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(appcast).getroot()

max_build = -1
for item in root.findall("./channel/item"):
    short_version = item.findtext("sparkle:shortVersionString", default="", namespaces=ns).strip()
    if short_version == target_version:
        raise SystemExit(f"Appcast already contains version {target_version}")
    build_text = item.findtext("sparkle:version", default="", namespaces=ns).strip()
    try:
        max_build = max(max_build, int(build_text))
    except ValueError:
        continue

if max_build >= 0 and target_build <= max_build:
    raise SystemExit(f"BUILD_NUMBER must be greater than latest appcast build ({max_build}); got {target_build}")
PY
}

# package.json is private and never published, but its version is kept in step
# with Config/version.env so the two can't drift apart (they had: 0.2.0 vs 0.1.1).
ensure_package_version() {
  local version="$1"
  local manifest="${2:-package.json}"

  [[ -f "$manifest" ]] || return 0
  local current
  current=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("version",""))' "$manifest" 2>/dev/null || true)
  [[ -n "$current" ]] || err "Could not read a version from $manifest"
  [[ "$current" == "$version" ]] || err "$manifest says $current but Config/version.env says $version. Bump them together."
}

# The public key baked into Info.plist must be the real one: a placeholder ships
# an app that rejects every update it is ever offered.
ensure_sparkle_public_key() {
  local key_file="${1:-Config/sparkle-public-key}"
  [[ -f "$key_file" ]] || err "Sparkle public key not found: $key_file (run Scripts/generate-keys.sh, paste the public key there)."
  local key
  key=$(tr -d '[:space:]' < "$key_file")
  [[ "$key" =~ ^[A-Za-z0-9+/]{43}=$ ]] || err "$key_file must hold one base64 Ed25519 public key (44 chars)."
}

clean_key() {
  local key_file="$1"
  [[ -f "$key_file" ]] || err "Sparkle key file not found: $key_file"

  local key_lines line_count
  key_lines=$(grep -v '^[[:space:]]*#' "$key_file" | sed '/^[[:space:]]*$/d')
  line_count=$(printf "%s\n" "$key_lines" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  [[ "$line_count" == "1" ]] || err "Sparkle key file must contain exactly one base64 line."

  local tmp
  tmp=$(mktemp "${TMPDIR:-/tmp}/harbor-sparkle-key.XXXXXX")
  chmod 600 "$tmp"
  printf "%s" "$key_lines" > "$tmp"
  echo "$tmp"
}

probe_sparkle_key() {
  local key_file="$1"
  require_command sign_update

  local probe_file signature
  probe_file=$(mktemp "${TMPDIR:-/tmp}/harbor-sparkle-probe.XXXXXX")
  printf "harbor-sparkle-probe" > "$probe_file"
  signature=$(sign_update "$probe_file" --ed-key-file "$key_file" 2>/dev/null || true)
  rm -f "$probe_file"
  [[ -n "$signature" ]] || err "Failed to sign with SPARKLE_PRIVATE_KEY_FILE. Check key format."

}

# The Keychain's Sparkle key (what Scripts/generate-keys.sh created) must be the
# one whose public half ships in Info.plist; otherwise every update is rejected.
ensure_sparkle_keypair_matches() {
  local pub_file="${1:-${RELEASE_LIB_ROOT}/Config/sparkle-public-key}"
  require_command generate_keys
  [[ -f "$pub_file" ]] || err "Sparkle public key not found: $pub_file"
  local keychain_pub shipped_pub
  # generate_keys prints "ERROR: …" on stdout when the account has no key, so
  # only a well-formed key counts as an answer.
  keychain_pub=$(generate_keys --account "$SPARKLE_KEY_ACCOUNT" -p 2>/dev/null | tr -d '[:space:]' || true)
  [[ "$keychain_pub" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
    || err "No Sparkle key under Keychain account \"$SPARKLE_KEY_ACCOUNT\" (run Scripts/generate-keys.sh)."
  shipped_pub=$(tr -d '[:space:]' < "$pub_file")
  [[ "$keychain_pub" == "$shipped_pub" ]] \
    || err "Keychain Sparkle public key differs from $pub_file. Updates signed now would be rejected."
}

clear_sparkle_caches() {
  local bundle_id="$1"
  local paths=(
    "$HOME/Library/Caches/${bundle_id}.Sparkle"
    "$HOME/Library/Application Support/${bundle_id}/Sparkle"
  )
  for path in "${paths[@]}"; do
    [[ -e "$path" ]] || continue
    rm -rf "$path"
  done
}

extract_notes_from_changelog() {
  local version="$1"
  local output="$2"
  local changelog="${3:-CHANGELOG.md}"

  [[ -f "$changelog" ]] || err "CHANGELOG not found: $changelog"

  python3 - "$changelog" "$version" "$output" <<'PY'
import re, sys

changelog_path, version, output_path = sys.argv[1], sys.argv[2], sys.argv[3]
pattern = re.compile(rf"^##\s*\[?{re.escape(version)}\]?(?:\s|$|-)")
lines = open(changelog_path, encoding="utf-8").read().splitlines()

start = next((i + 1 for i, line in enumerate(lines) if pattern.search(line)), None)
if start is None:
    raise SystemExit(f"Could not find changelog section for {version}")
end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))

section = lines[start:end]
while section and not section[0].strip():
    section.pop(0)
while section and not section[-1].strip():
    section.pop()
if not section:
    raise SystemExit(f"Changelog section for {version} is empty")

open(output_path, "w", encoding="utf-8").write("\n".join(section) + "\n")
PY
}

verify_appcast_entry() {
  local appcast="$1"
  local version="$2"
  local key_file="$3"
  local zip="${4:-}"
  local verify_script="${RELEASE_LIB_ROOT}/Scripts/verify_appcast.sh"

  [[ -f "$appcast" ]] || err "Appcast not found: $appcast"
  [[ -x "$verify_script" ]] || err "verify_appcast.sh not executable: $verify_script"

  SPARKLE_PRIVATE_KEY_FILE="$key_file" "$verify_script" "$version" ${zip:+"$zip"}
}

check_assets() {
  local tag="$1"
  local version="${tag#v}"
  local app_zip="${RELEASE_APP_NAME}-${version}.zip"
  local dsym_zip="${RELEASE_APP_NAME}-${version}.dSYM.zip"

  require_command gh
  local assets
  assets=$(gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null || true)
  [[ -n "$assets" ]] || err "No assets found for release tag $tag"

  local missing=()
  printf "%s\n" "$assets" | grep -Fxq "$app_zip" || missing+=("$app_zip")
  printf "%s\n" "$assets" | grep -Fxq "$dsym_zip" || missing+=("$dsym_zip")
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Release assets for $tag:" >&2
    printf "%s\n" "$assets" >&2
    err "Missing expected assets: ${missing[*]}"
  fi
  echo "Release assets verified for $tag: $app_zip, $dsym_zip"
}

# generate_appcast writes <App><new>-<old>.delta files next to the zip and the
# appcast points at them; `gh release create` uploads only the zip and dSYM.
upload_deltas() {
  local tag="$1"
  require_command gh
  shopt -s nullglob
  local deltas=("${RELEASE_APP_NAME}"*.delta)
  shopt -u nullglob
  if [[ ${#deltas[@]} -eq 0 ]]; then
    echo "No deltas generated for $tag (clients get the full zip)."
    return 0
  fi
  gh release upload "$tag" "${deltas[@]}" --clobber
  echo "Uploaded ${#deltas[@]} delta(s) to $tag: ${deltas[*]}"
}

check_appcast_deltas() {
  local appcast="$1"
  local tag="$2"
  local build="$3"

  require_command gh
  local referenced
  referenced=$(grep -oE "${RELEASE_APP_NAME}${build}-[0-9]+\.delta" "$appcast" | sort -u || true)
  [[ -n "$referenced" ]] || return 0

  local assets missing=()
  assets=$(gh release view "$tag" --json assets --jq '.assets[].name' 2>/dev/null || true)
  while IFS= read -r delta; do
    [[ -n "$delta" ]] || continue
    printf "%s\n" "$assets" | grep -Fxq "$delta" || missing+=("$delta")
  done <<<"$referenced"
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "WARN: appcast references deltas missing from $tag: ${missing[*]}" >&2
    echo "WARN: clients fall back to the full zip. Fix: gh release upload $tag ${missing[*]}" >&2
    return 0
  fi
  echo "Appcast deltas verified against $tag."
}

# main only takes signed commits through PRs, so the appcast goes through one.
# Branch first, commit there, return to main: local main never gains a commit
# that origin/main will only get later as a squash (which would fail the next
# release's "main equals origin/main" gate).
push_appcast_commit() {
  local version="$1"
  local appcast="$2"
  local branch="sriinnu/appcast-${version}"
  require_command gh
  git switch -q -c "$branch"
  git add "$appcast"
  signed "appcast commit" git commit -q -S -m "docs: update appcast for ${version}"
  git push -q -u origin "$branch"
  gh pr create --head "$branch" --base main \
    --title "docs: update appcast for ${version}" \
    --body "Signed Sparkle appcast entry for ${RELEASE_APP_NAME} ${version}. Merge this PR to publish the update feed; the release assets are already live."
  git switch -q main
  git checkout -q -- "$appcast" 2>/dev/null || true
  echo "Appcast PR opened from $branch; merge it to finish the release." >&2
}
