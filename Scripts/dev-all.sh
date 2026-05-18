#!/bin/bash
#
# Harbor All-in-One: Clean → Build → Run
#
# Usage:
#   ./Scripts/dev.sh all    # Clean, build, and run
#   ./Scripts/dev.sh all cli # Clean, build CLI, and run CLI
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/macos"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}→${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌  $1${NC}"; }
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

# Parse arguments
MODE="${1:-app}"
case "$MODE" in
    cli)
        PRODUCT="harborcli"
        ;;
    app|"")
        PRODUCT="Harbor"
        ;;
    help|--help|-h)
        echo "Harbor: Clean → Build → Run"
        echo ""
        echo "Usage: $0 <target>"
        echo ""
        echo "Targets:"
        echo "  app     Clean, build, and run Harbor app (default)"
        echo "  cli     Clean, build, and run CLI tool"
        echo ""
        echo "Shortcuts:"
        echo "  ./Scripts/dev.sh all    # Same as app"
        echo "  ./Scripts/dev.sh all cli # Same as cli"
        ;;
    *)
        error "Unknown target: $MODE"
        exit 1
        ;;
esac

log "🔨 Harbor: Clean → Build → Run ($PRODUCT)"
echo ""

# Step 1: Clean
log "Step 1/3: Cleaning..."
"$SCRIPT_DIR/cleanup.sh" > /dev/null 2>&1 || true
echo ""

# Step 2: Build
log "Step 2/3: Building $PRODUCT..."

xcodebuild \
    -scheme "$PRODUCT" \
    -destination 'platform=macOS,arch=arm64' \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking)" || true

BINARY="$BUILD_DIR/Build/Products/Debug/$PRODUCT"
SPARKLE="$BUILD_DIR/Build/Products/Debug/Frameworks/Sparkle.framework/Versions/B/Sparkle"

if [ ! -f "$BINARY" ]; then
    error "Build failed! Binary not found: $BINARY"
    exit 1
fi

log "✅ Build complete"

# Fix Sparkle framework linking (SPM workaround for app only)
if [ "$PRODUCT" = "Harbor" ] && [ -f "$SPARKLE" ]; then
    mkdir -p "$BUILD_DIR/Build/Products/Frameworks"
    ln -sf "$BUILD_DIR/Build/Products/Debug/Frameworks/Sparkle.framework" \
           "$BUILD_DIR/Build/Products/Frameworks/Sparkle.framework" 2>/dev/null || true
    install_name_tool -change "@rpath/Sparkle.framework/Versions/B/Sparkle" \
        "@executable_path/../Frameworks/Sparkle.framework/Versions/B/Sparkle" \
        "$BINARY" 2>/dev/null || true
fi

echo ""

# Step 3: Run
log "Step 3/3: Launching $PRODUCT..."

if [ "$PRODUCT" = "harborcli" ]; then
    info "CLI Command: $BINARY"
    info "Try: $BINARY --help"
    echo ""
    "$BINARY" --help
else
    # Setup Sparkle path for app
    SPARKLE="$BUILD_DIR/Build/Products/Debug/Sparkle.framework/Versions/B/Sparkle"
    if [ -f "$SPARKLE" ]; then
        ln -sf "$SPARKLE" "$BUILD_DIR/Build/Products/Debug/Sparkle" 2>/dev/null || true
        export DYLD_LIBRARY_PATH="$BUILD_DIR/Build/Products/Debug:$DYLD_LIBRARY_PATH"
    fi

    "$BINARY" &
    sleep 2

    if pgrep -x "$PRODUCT" > /dev/null; then
        log "✅ $PRODUCT is running! Check your menu bar."
    else
        warn "$PRODUCT may have failed to start."
        warn "Check Console.app for errors."
        info "Try running manually:"
        echo "  DYLD_LIBRARY_PATH=\"$BUILD_DIR/Build/Products/Debug\" $BINARY &"
    fi
fi

echo ""
log "Done! 🎉"
