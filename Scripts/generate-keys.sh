#!/usr/bin/env bash
set -euo pipefail

if [[ "${HARBOR_KEY_SETUP_CONFIRM:-}" != "generate" ]]; then
  echo "Key generation is disabled by default. Read docs/release.md, then set HARBOR_KEY_SETUP_CONFIRM=generate." >&2
  exit 1
fi
if ! command -v generate_keys >/dev/null 2>&1; then
  echo "The official Sparkle generate_keys tool is required and was not found in PATH." >&2
  exit 1
fi

cat <<'MSG'
Generating a Sparkle signing key with the official Sparkle tool.

Do not store private signing keys in this repository, its build artifacts, or GitHub variables.
Store the private material in the approved secret/key-management system, record the public key
in the signed release configuration, and run the complete release checklist before enabling Sparkle.
MSG

generate_keys
