#!/usr/bin/env bash
# Builds Harbor.app from SwiftPM products.
#
#   Scripts/package_app.sh [debug|release]
#
# release: universal (arm64 + x86_64), Sparkle public key required, signed with
# APP_IDENTITY (a Developer ID); an ad-hoc seal is refused.
# debug:   host arch, signed with APP_IDENTITY if set, otherwise ad-hoc.
#
# The bundle lands at build/macos/Harbor.app (stable path for the release scripts).
set -euo pipefail

CONFIGURATION=${1:-debug}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="Harbor"
BUNDLE_ID="com.sriinnu.harbor"
FEED_URL="https://raw.githubusercontent.com/sriinnu/harbor/main/appcast.xml"
OUT_DIR="${ROOT}/build/macos"
SPM_BUILD_PATH="${OUT_DIR}/.build"
APP="${OUT_DIR}/${APP_NAME}.app"

source "$ROOT/Config/version.env"
for LOCAL_ENV in "${HOME}/.config/harbor/local.env" "${ROOT}/.harbor.local.env"; do
  # shellcheck disable=SC1090
  [[ -f "$LOCAL_ENV" ]] && { source "$LOCAL_ENV"; break; }
done

log() { printf '==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

case "$CONFIGURATION" in
  debug|release) ;;
  *) fail "Usage: $0 [debug|release]" ;;
esac

ARCH_FLAGS=()
if [[ "$CONFIGURATION" == "release" ]]; then
  for arch in ${ARCHES:-arm64 x86_64}; do ARCH_FLAGS+=(--arch "$arch"); done
fi

# Sparkle public key: required for release, optional for local debug builds.
SPARKLE_PUBLIC_KEY=""
if [[ -f "$ROOT/Config/sparkle-public-key" ]]; then
  SPARKLE_PUBLIC_KEY=$(tr -d '[:space:]' < "$ROOT/Config/sparkle-public-key")
fi
if [[ "$CONFIGURATION" == "release" ]]; then
  [[ "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
    || fail "Config/sparkle-public-key must hold the real Ed25519 public key for a release build."
fi

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  # Resource bundles of removed dependencies linger in the bin dir and would be
  # copied into the app; clear them so the build writes only current ones.
  STALE_BIN="$(swift build -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --build-path "$SPM_BUILD_PATH" --show-bin-path)"
  rm -rf "${STALE_BIN:?}"/*.bundle
  log "Building ${APP_NAME} + harborcli (${CONFIGURATION})"
  swift build -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --build-path "$SPM_BUILD_PATH" --product "$APP_NAME"
  swift build -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --build-path "$SPM_BUILD_PATH" --product harborcli
fi
BIN_DIR="$(swift build -c "$CONFIGURATION" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --build-path "$SPM_BUILD_PATH" --show-bin-path)"
[[ -f "${BIN_DIR}/${APP_NAME}" ]] || fail "Missing executable: ${BIN_DIR}/${APP_NAME}"
[[ -f "${BIN_DIR}/harborcli" ]] || fail "Missing CLI: ${BIN_DIR}/harborcli"

log "Creating ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Frameworks" "$APP/Contents/Resources"

cp "${BIN_DIR}/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/${APP_NAME}" 2>/dev/null || true
cp "${BIN_DIR}/harborcli" "$APP/Contents/Helpers/harborcli"

# SwiftPM leaves absolute build-machine rpaths (PackageFrameworks, toolchain
# dirs under this Mac's paths). A shipped binary must not search them.
strip_absolute_rpaths() {
  local bin="$1" rp
  while IFS= read -r rp; do
    [[ "$rp" == /* && "$rp" != /usr/lib/* && "$rp" != /System/* ]] || continue
    install_name_tool -delete_rpath "$rp" "$bin"
  done < <(otool -l "$bin" | awk '/LC_RPATH/{getline; getline; print $2}' | sort -u)
}
strip_absolute_rpaths "$APP/Contents/MacOS/${APP_NAME}"
strip_absolute_rpaths "$APP/Contents/Helpers/harborcli"

if [[ -d "${BIN_DIR}/Sparkle.framework" ]]; then
  ditto "${BIN_DIR}/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  chmod -R a+rX "$APP/Contents/Frameworks/Sparkle.framework"
else
  fail "Sparkle.framework not found in ${BIN_DIR}"
fi

# SwiftPM resource bundles (Harbor_Harbor.bundle, dependencies' bundles).
shopt -s nullglob
for bundle in "${BIN_DIR}/"*.bundle; do
  ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
shopt -u nullglob
# Bundle.main lookups (menu-bar logo, icon) read Contents/Resources directly.
# SwiftPM writes macOS resource bundles as <name>.bundle/Contents/Resources/.
for res in logo.png AppIcon.icns; do
  src="${BIN_DIR}/${APP_NAME}_${APP_NAME}.bundle/Contents/Resources/${res}"
  [[ -f "$src" ]] || fail "missing resource ${res} in ${APP_NAME}_${APP_NAME}.bundle"
  cp "$src" "$APP/Contents/Resources/${res}"
done

# The app icon is Sources/Harbor/Resources/AppIcon.icns (built from assets/harbor-icon*.svg),
# copied above; Info.plist names it.

SPARKLE_KEYS=""
if [[ -n "$SPARKLE_PUBLIC_KEY" ]]; then
  SPARKLE_KEYS="<key>SUFeedURL</key><string>${FEED_URL}</string>
    <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
    <key>SUEnableAutomaticChecks</key><true/>"
fi

# Dev builds (Scripts/dev-launch.sh) carry their own counter and a visible label.
BUILD_LABEL_KEY=""
if [[ "$CONFIGURATION" == "debug" && -n "${HARBOR_DEV_BUILD_NUMBER:-}" ]]; then
  BUILD_NUMBER="$HARBOR_DEV_BUILD_NUMBER"
  BUILD_LABEL_KEY="<key>HarborBuildLabel</key><string>${HARBOR_BUILD_LABEL:?}</string>"
fi
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
git diff --quiet HEAD 2>/dev/null || GIT_COMMIT="${GIT_COMMIT}-dirty"
BUILD_TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log "Writing Info.plist (${MARKETING_VERSION} build ${BUILD_NUMBER})"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>HarborGitCommit</key><string>${GIT_COMMIT}</string>
    <key>HarborBuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    ${BUILD_LABEL_KEY}
    <key>NSAppleEventsUsageDescription</key><string>Harbor opens a repository in your terminal app when you ask it to.</string>
    ${SPARKLE_KEYS}
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>${BUNDLE_ID}</string>
            <key>CFBundleURLSchemes</key><array><string>harbor</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Generated Info.plist is invalid"

chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete

IDENTITY="${APP_IDENTITY:-}"
if [[ "$CONFIGURATION" == "release" ]]; then
  [[ -n "$IDENTITY" && "$IDENTITY" != "-" ]] \
    || fail "APP_IDENTITY (Developer ID Application) is required for a release build; ad-hoc is refused."
elif [[ -z "$IDENTITY" ]]; then
  IDENTITY="-"
fi
"${ROOT}/Scripts/codesign_app.sh" "$APP" "$IDENTITY"

# Capture first: `codesign | grep -q` under pipefail reports SIGPIPE as "no match".
if [[ "$CONFIGURATION" == "release" ]]; then
  SIGNATURE_INFO=$(codesign -dvv "$APP" 2>&1 || true)
  if grep -q "^Signature=adhoc" <<<"$SIGNATURE_INFO" || ! grep -q "^TeamIdentifier=[A-Z0-9]\{10\}$" <<<"$SIGNATURE_INFO"; then
    fail "$APP is not signed with a Developer ID (ad-hoc or no team); refusing a release bundle."
  fi
fi

log "Created ${APP}"
