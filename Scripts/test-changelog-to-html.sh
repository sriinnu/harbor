#!/usr/bin/env bash
# Exact-output check for changelog-to-html.sh: Sparkle shows release notes as HTML, so
# Markdown `code` and **bold** must become <code> and <strong>, and text stays escaped.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/CHANGELOG.md" <<'MD'
# Changelog

## 9.9.9 — 2026-01-01

Intro with `a<b` & more.

### Fixes
- **Heads up**: `harborcli` follows the
  active account.
- Plain *single* stars and a ` lone backtick stay as they are.

## 9.9.8 — 2025-12-31
- Older.
MD

expected='<p>Intro with <code>a&lt;b</code> &amp; more.</p><h3>Fixes</h3><ul><li><strong>Heads up</strong>: <code>harborcli</code> follows the active account.</li><li>Plain *single* stars and a ` lone backtick stay as they are.</li></ul>'
actual="$("$ROOT_DIR/Scripts/changelog-to-html.sh" 9.9.9 "$TMP/CHANGELOG.md")"

if [[ "$actual" != "$expected" ]]; then
  echo "changelog-to-html: unexpected output" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi
echo "changelog-to-html: ok"
