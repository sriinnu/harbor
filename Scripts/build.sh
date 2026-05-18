#!/bin/bash
#
# Harbor Build Script
# Ensures all build artifacts go to the build/macos/ directory
#
# Usage:
#   ./Scripts/build.sh              # Build debug
#   ./Scripts/build.sh release      # Build release
#   ./Scripts/build.sh clean        # Clean build directory
#   ./Scripts/build.sh cli          # Build CLI only
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/macos"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌  $1${NC}"; }

# Parse arguments
MODE="${1:-debug}"
CONFIG="Debug"
PRODUCT="Harbor"

case "$MODE" in
    release|--release|-r)
        CONFIG="Release"
        ;;
    debug|--debug|-d)
        CONFIG="Debug"
        ;;
    cli|--cli|-c)
        PRODUCT="harborcli"
        ;;
    clean|--clean|-C)
        log_info "Cleaning build directory..."
        rm -rf "$BUILD_DIR"
        log_info "Build directory cleaned: $BUILD_DIR"
        exit 0
        ;;
    help|--help|-h)
        echo "Harbor Build Script"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  (none)      Build debug version"
        echo "  release     Build release version"
        echo "  cli         Build CLI tool only"
        echo "  clean       Clean build directory"
        echo "  help        Show this help"
        echo ""
        echo "Build artifacts location: $BUILD_DIR"
        exit 0
        ;;
esac

log_info "🔨 Building Harbor ($CONFIG)..."
log_info "📁 Build artifacts will be in: $BUILD_DIR"

# Ensure build directory exists
mkdir -p "$BUILD_DIR"

# Use xcodebuild with SPM (Swift 6 compatible)
# The key is using -derivedDataPath which puts ALL artifacts in build/macos/
xcodebuild \
    -scheme "$PRODUCT" \
    -destination 'platform=macOS,arch=arm64' \
    -configuration "$CONFIG" \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking)" || true

# Check if build succeeded
if [ -f "$BUILD_DIR/Build/Products/$CONFIG/$PRODUCT" ] || [ -f "$BUILD_DIR/Build/Products/Debug/$PRODUCT" ]; then
    log_info "✅ Build complete!"
    if [ "$PRODUCT" = "harborcli" ]; then
        log_info "🚀 CLI tool: $BUILD_DIR/Build/Products/Debug/harborcli"
    else
        log_info "🚀 Harbor: $BUILD_DIR/Build/Products/Debug/Harbor"
    fi
else
    log_error "Build failed - artifacts not found!"
    exit 1
fi
