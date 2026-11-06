#!/usr/bin/env bash
# The local gate: what CI runs, runnable before every push (and the only gate
# while the repo is private and hosted CI is skipped).
#
#   Scripts/verify.sh        or   pnpm verify
#
# 1. strict build: every compiler warning in Harbor's targets is an error
# 2. SwiftLint, warnings included
# 3. tests: the exit code, no crashed runner, and every runner actually ran tests
# 4. dependency vulnerabilities: pnpm audit and cargo audit (fails closed)
# 5. shellcheck on Scripts/ (when installed)
#
# Its own build directory, so strict flags never invalidate the dev build cache.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BUILD="$ROOT/build/verify"
LOG="$(mktemp "${TMPDIR:-/tmp}/harbor-verify.XXXXXX")"
trap 'rm -f "$LOG"' EXIT
export HARBOR_STRICT=1

step() { printf '\n==> %s\n' "$*"; }
fail() { printf '\nFAIL: %s\n' "$*" >&2; exit 1; }

step "Build (warnings are errors)"
swift build --build-tests --build-path "$BUILD" 2>&1 | tee "$LOG" | grep -E "error:|warning:" || true
grep -q "Build complete" "$LOG" || fail "build failed (see errors above)"

step "SwiftLint"
command -v swiftlint >/dev/null || fail "swiftlint not installed (brew install swiftlint)"
swiftlint lint --quiet --strict || fail "SwiftLint violations"

step "Tests"
set +e
swift test --build-path "$BUILD" >"$LOG" 2>&1
rc=$?
set -e
grep -E "Executed [0-9]+ tests, with|Test run with [0-9]+ tests" "$LOG" | sort -u | tail -6
if grep -q "unexpected signal code" "$LOG"; then
  grep "unexpected signal code" "$LOG" | sed 's/^/  /' | cut -c1-240
  fail "a test runner crashed; its remaining tests never ran (check ~/Library/Logs/DiagnosticReports)"
fi
grep -E "recorded an issue|error: -\[|failed \(" "$LOG" | head -20 || true
(( rc == 0 )) || fail "swift test exited $rc"
# A runner that ran nothing passes vacuously; refuse it.
if grep -qE "Test run with 0 tests" "$LOG"; then fail "a Swift Testing run executed 0 tests"; fi
xctest=$(grep -E "Executed [0-9]+ tests, with" "$LOG" | sed -E 's/.*Executed ([0-9]+) tests.*/\1/' | sort -n | tail -1)
(( ${xctest:-0} > 0 )) || fail "XCTest executed 0 tests"

step "Dependency vulnerabilities"
# Any known vulnerability fails the gate. So does an audit that couldn't run
# (offline counts as failure unless HARBOR_OFFLINE=1): silence is not "clean".
audit_failed=0
audit() { # <label> <dir> <command...>
  local label="$1" dir="$2"; shift 2
  local out rc
  out=$(cd "$dir" && "$@" 2>&1); rc=$?
  if (( rc == 0 )); then
    echo "  clean  $label"
  elif grep -qiE "vulnerabilit(y|ies) found|severity|RUSTSEC-" <<<"$out"; then
    printf '%s\n' "$out" | tail -25
    echo "  VULNERABLE  $label"; audit_failed=1
  elif [[ "${HARBOR_OFFLINE:-0}" == "1" ]]; then
    echo "  skipped (HARBOR_OFFLINE=1)  $label"
  else
    printf '%s\n' "$out" | tail -3
    echo "  AUDIT DID NOT RUN  $label"; audit_failed=1
  fi
}
set +e
for dir in . harbor-web harbor-windows harbor-linux; do
  [[ -f "$dir/pnpm-lock.yaml" ]] && audit "npm   $dir" "$dir" pnpm audit
done
for lock in harbor-*/src-tauri/Cargo.lock; do
  [[ -f "$lock" ]] || continue
  if command -v cargo-audit >/dev/null; then
    audit "cargo $(dirname "$lock")" "$(dirname "$lock")" cargo audit -q
  else
    echo "  cargo-audit not installed (cargo install cargo-audit --locked)"; audit_failed=1
  fi
done
set -e
(( audit_failed == 0 )) || fail "vulnerable (or unaudited) dependencies"

if command -v shellcheck >/dev/null; then
  step "shellcheck"
  shellcheck -S warning Scripts/*.sh Scripts/lib/*.sh || fail "shellcheck"
else
  echo "(shellcheck not installed; skipped)"
fi

printf '\nverify: all gates passed\n'
