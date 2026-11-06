#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Harbor"
BUILD_ROOT="${ROOT_DIR}/build/macos"
APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
log() { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

clean_root_intermediates() {
  find "${ROOT_DIR}" -maxdepth 1 -type f \( \
    -name "*.swiftmodule" -o \
    -name "*.swiftdeps" -o \
    -name "*.d" -o \
    -name "*.dia" -o \
    -name "*.o" \
  \) -delete 2>/dev/null || true
}

# Load signing defaults from Config/Local.xcconfig if present (xcconfig syntax);
# they reach xcodebuild as build-setting overrides below.
SIGNING_OVERRIDES=()
if [ -f "${ROOT_DIR}/Config/Local.xcconfig" ]; then
  # extract key/value pairs like KEY = value
  while IFS='=' read -r rawKey rawValue; do
    key="$(printf '%s' "$rawKey" | sed 's,//.*$,,' | xargs)"
    value="$(printf '%s' "$rawValue" | sed 's,//.*$,,' | xargs)"
    case "$key" in
      CODE_SIGN_IDENTITY|CODESIGN_IDENTITY) SIGNING_OVERRIDES+=("CODE_SIGN_IDENTITY=${value}") ;;
      DEVELOPMENT_TEAM) SIGNING_OVERRIDES+=("DEVELOPMENT_TEAM=${value}") ;;
      PROVISIONING_PROFILE_SPECIFIER) SIGNING_OVERRIDES+=("PROVISIONING_PROFILE_SPECIFIER=${value}") ;;
    esac
  done < <(grep -v '^[[:space:]]*//' "${ROOT_DIR}/Config/Local.xcconfig")
fi

kill_existing() {
  for _ in {1..10}; do
    pkill -f "${APP_PROCESS_PATTERN}" 2>/dev/null || true
    pkill -x "${APP_NAME}" 2>/dev/null || true
    pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null || pgrep -x "${APP_NAME}" >/dev/null || return 0
    sleep 0.2
  done
}

log "==> Killing existing ${APP_NAME} instances"
kill_existing

log "==> Cleaning root Swift intermediates"
clean_root_intermediates

log "==> Cleaning build folder"
rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}"

log "==> xcodebuild"
xcodebuild \
  -scheme "${APP_NAME}" \
  -destination 'platform=macOS,arch=arm64' \
  -configuration Debug \
  -derivedDataPath "${BUILD_ROOT}" \
  ${SIGNING_OVERRIDES[@]+"${SIGNING_OVERRIDES[@]}"} \
  build 2>&1 | grep -E "(error:|warning:|Build|Compiling\\ Swift|Linking)" || true

log "==> Cleaning root Swift intermediates (post-build)"
clean_root_intermediates

log "==> Launching debug build"
APP_BUNDLE="${BUILD_ROOT}/Build/Products/Debug/${APP_NAME}.app"
APP_BINARY="${BUILD_ROOT}/Build/Products/Debug/${APP_NAME}"
EXPECTED_PROCESS_RESOLVED=""

if [ -d "${APP_BUNDLE}" ]; then
  APP_PROCESS_PATTERN="${APP_NAME}.app/Contents/MacOS/${APP_NAME}"
  EXPECTED_PROCESS_RESOLVED="$(cd "${APP_BUNDLE}" && pwd -P)/Contents/MacOS/${APP_NAME}"
  # Launch via LaunchServices so the process has a proper bundle identifier (menubar item, single-instance, URL handlers).
  open -n -g "${APP_BUNDLE}"
elif [ -f "${APP_BINARY}" ]; then
  log "==> App bundle not found; launching binary directly"
  APP_PROCESS_PATTERN="${APP_BINARY}"
  EXPECTED_PROCESS_RESOLVED="$(cd "$(dirname "${APP_BINARY}")" && pwd -P)/${APP_NAME}"

  SPARKLE="${BUILD_ROOT}/Build/Products/Debug/Sparkle.framework/Versions/B/Sparkle"
  if [ -f "${SPARKLE}" ]; then
    mkdir -p "${BUILD_ROOT}/Build/Products/Debug/Frameworks"
    mkdir -p "${BUILD_ROOT}/Build/Products/Frameworks"
    cp -R "${BUILD_ROOT}/Build/Products/Debug/Sparkle.framework" \
          "${BUILD_ROOT}/Build/Products/Debug/Frameworks/" 2>/dev/null || true
    cp -R "${BUILD_ROOT}/Build/Products/Debug/Sparkle.framework" \
          "${BUILD_ROOT}/Build/Products/Frameworks/" 2>/dev/null || true
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${APP_BINARY}" 2>/dev/null || true
  fi

  "${APP_BINARY}" &
else
  fail "Build failed - app bundle or binary not found (expected ${APP_BUNDLE} or ${APP_BINARY})"
fi

sleep 1

if [ -n "${EXPECTED_PROCESS_RESOLVED}" ]; then
  proc_pidpath() {
    python3 - "$1" <<'PY'
import ctypes
import sys

pid = int(sys.argv[1])
buf = ctypes.create_string_buffer(4096)
lib = ctypes.CDLL("/usr/lib/libproc.dylib")
ret = lib.proc_pidpath(pid, buf, ctypes.sizeof(buf))
if ret <= 0:
    raise SystemExit(1)
print(buf.value.decode("utf-8", errors="replace"))
PY
  }

  launched_from_checkout=0
  for _ in {1..50}; do
    while read -r pid; do
      path="$(proc_pidpath "${pid}" 2>/dev/null || true)"
      if [ -n "${path}" ] && [ "${path}" = "${EXPECTED_PROCESS_RESOLVED}" ]; then
        launched_from_checkout=1
        break
      fi
    done < <(pgrep -x "${APP_NAME}" || true)

    if [ "${launched_from_checkout}" -eq 1 ]; then break; fi
    sleep 0.2
  done

  if [ "${launched_from_checkout}" -ne 1 ]; then
    log "ERROR: ${APP_NAME} did not launch from this checkout."
    log "Expected: ${EXPECTED_PROCESS_RESOLVED}"
    while read -r pid; do
      path="$(proc_pidpath "${pid}" 2>/dev/null || true)"
      if [ -n "${path}" ]; then
        log "Running: ${path}"
      fi
    done < <(pgrep -x "${APP_NAME}" || true)
    log "Hint: another Harbor build may be running from a different path; run:"
    log "  pgrep -af \"${APP_PROCESS_PATTERN}\""
    exit 1
  fi
fi

if pgrep -f "${APP_PROCESS_PATTERN}" >/dev/null 2>&1 || pgrep -x "${APP_NAME}" >/dev/null 2>&1; then
  log "OK: ${APP_NAME} is running."
else
  fail "App exited immediately."
fi
