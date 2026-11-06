#!/usr/bin/env bash
# Checks a GitHub release carries Harbor-<ver>.zip and Harbor-<ver>.dSYM.zip.
#   Scripts/check-release-assets.sh [vX.Y.Z]   (default: latest tag)
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$ROOT/Scripts/release-lib.sh"

TAG=${1:-$(git describe --tags --abbrev=0)}
check_assets "$TAG"
