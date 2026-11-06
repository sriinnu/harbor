#!/usr/bin/env bash
# One-time Sparkle key setup for Harbor. Uses Sparkle's official generate_keys
# under its own Keychain account ("harbor"), so it never reuses another app's
# key (Runic's sits in the default account).
#
#   HARBOR_KEY_SETUP_CONFIRM=generate Scripts/generate-keys.sh
#
# Afterwards:
#   - the private key stays in your login Keychain;
#   - the public key is written to Config/sparkle-public-key (commit it);
#   - export a copy for release signing, outside the repo, mode 0600:
#       generate_keys --account harbor -x ~/.config/harbor/sparkle_private_key
#     and set SPARKLE_PRIVATE_KEY_FILE to that path in ~/.config/harbor/local.env.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/release-lib.sh"   # puts Sparkle's bundled tools on PATH

if [[ "${HARBOR_KEY_SETUP_CONFIRM:-}" != "generate" ]]; then
  echo "Key generation is disabled by default. Read docs/release.md, then set HARBOR_KEY_SETUP_CONFIRM=generate." >&2
  exit 1
fi
require_command generate_keys

# Creates the key if the account has none; prints the existing one otherwise.
generate_keys --account "$SPARKLE_KEY_ACCOUNT"
PUB=$(generate_keys --account "$SPARKLE_KEY_ACCOUNT" -p | tr -d '[:space:]')
[[ "$PUB" =~ ^[A-Za-z0-9+/]{43}=$ ]] || err "Unexpected public key output: $PUB"
printf '%s\n' "$PUB" > "$ROOT/Config/sparkle-public-key"
echo "Public key written to Config/sparkle-public-key. Commit it; the private key never leaves the Keychain except as the 0600 export described above."
