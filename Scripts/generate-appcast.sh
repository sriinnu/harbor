#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ZIP=${1:?'Usage: generate-appcast.sh Harbor-<version>.zip'}
: "${SPARKLE_FEED_URL:?Set SPARKLE_FEED_URL to the public HTTPS appcast URL}"

exec "$SCRIPT_DIR/make_appcast.sh" "$ZIP" "$SPARKLE_FEED_URL"
