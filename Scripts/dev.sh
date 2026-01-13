#!/bin/bash
#
# Harbor Development Script
# Build, test, and run Harbor for development
#
# Usage:
#   ./Scripts/dev.sh build        # Build CLI and app
#   ./Scripts/dev.sh cli          # Build CLI only
#   ./Scripts/dev.sh run          # Build and run app (via binary)
#   ./dev.sh xcode               # Open in Xcode
#   ./Scripts/dev.sh test         # Run tests
#   ./Scripts/dev.sh clean        # Clean build artifacts
#   ./Scripts/dev.sh deps         # Update dependencies
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
warn() { echo -e "${YELLOW}⚠️${NC} $1"; }
error() { echo -e "${RED}❌${NC} $1"; }
info() { echo -e "${BLUE}ℹ️${NC} $1"; }

# Parse command
CMD="${1:-build}"

case "$CMD" in
    build)
        log "Building Harbor (Debug)..."
        xcodebuild \
            -scheme Harbor \
            -destination 'platform=macOS,arch=arm64' \
            -configuration Debug \
            -derivedDataPath "$BUILD_DIR" \
            build 2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking)" || true

        if [ -f "$BUILD_DIR/Build/Products/Debug/Harbor" ]; then
            log "✅ Build complete: $BUILD_DIR/Build/Products/Debug/Harbor"
        else
            error "Build failed!"
            exit 1
        fi
        ;;

    cli)
        log "Building Harbor CLI..."
        xcodebuild \
            -scheme harbor \
            -destination 'platform=macOS,arch=arm64' \
            -configuration Debug \
            -derivedDataPath "$BUILD_DIR" \
            build 2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking)" || true

        if [ -f "$BUILD_DIR/Build/Products/Debug/harbor" ]; then
            log "✅ CLI build complete: $BUILD_DIR/Build/Products/Debug/harbor"
            echo ""
            info "Test the CLI:"
            echo "  $BUILD_DIR/Build/Products/Debug/harbor --help"
        else
            error "Build failed!"
            exit 1
        fi
        ;;

    run)
        log "Building and running Harbor..."

        # Build first
        xcodebuild \
            -scheme Harbor \
            -destination 'platform=macOS,arch=arm64' \
            -configuration Debug \
            -derivedDataPath "$BUILD_DIR" \
            build 2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking)" || true

        BINARY="$BUILD_DIR/Build/Products/Debug/Harbor"
        SPARKLE="$BUILD_DIR/Build/Products/Debug/Sparkle.framework/Versions/B/Sparkle"

        if [ -f "$BINARY" ]; then
            log "✅ Build complete. Preparing to launch Harbor..."

            # Fix Sparkle framework linking (SPM workaround)
            if [ -f "$SPARKLE" ]; then
                # Create Frameworks directories and copy Sparkle there
                mkdir -p "$BUILD_DIR/Build/Products/Debug/Frameworks"
                mkdir -p "$BUILD_DIR/Build/Products/Frameworks"

                cp -R "$BUILD_DIR/Build/Products/Debug/Sparkle.framework" \
                      "$BUILD_DIR/Build/Products/Debug/Frameworks/" 2>/dev/null || true
                cp -R "$BUILD_DIR/Build/Products/Debug/Sparkle.framework" \
                      "$BUILD_DIR/Build/Products/Frameworks/" 2>/dev/null || true

                # Add rpath for Frameworks lookup
                install_name_tool -add_rpath "@executable_path/../Frameworks" "$BINARY" 2>/dev/null || true
            fi

            echo ""
            "$BINARY" &
            log "Harbor started! Check your menu bar."

            sleep 2
            if pgrep -x "Harbor" > /dev/null; then
                log "✅ Harbor is running"
            else
                warn "Harbor may have failed to start. Check Console.app for errors."
            fi
        else
            error "Build failed!"
            exit 1
        fi
        ;;

    xcode)
        log "Opening Harbor in Xcode..."
        cd "$PROJECT_ROOT"
        open Package.swift
        info "Xcode should open. Press Cmd+U to build and run."
        ;;

    all)
        log "Running: Clean → Build → Run"
        "$SCRIPT_DIR/dev-all.sh" "$2"
        ;;

    test)
        log "Running tests..."
        xcodebuild \
            -scheme Harbor \
            -destination 'platform=macOS' \
            -configuration Debug \
            test 2>&1 | grep -E "(Test Case|passed|failed|error:)" || true
        ;;

    clean)
        log "Cleaning build artifacts..."
        rm -rf "$BUILD_DIR"
        rm -f "$PROJECT_ROOT"/*.swiftmodule "$PROJECT_ROOT"/*.d "$PROJECT_ROOT"/*.dia "$PROJECT_ROOT"/*.swiftdeps 2>/dev/null || true
        log "✅ Clean complete"
        ;;

    deps)
        log "Updating dependencies..."
        swift package update
        log "✅ Dependencies updated"
        ;;

    help|--help|-h)
        echo "Harbor Development Script"
        echo ""
        echo "Usage: $0 <command>"
        echo ""
        echo "Commands:"
        echo "  all [app|cli]  Clean → Build → Run (default: app)"
        echo "  build          Build the main Harbor app (binary only)"
        echo "  cli            Build the CLI tool only"
        echo "  run            Build and run Harbor (launches binary)"
        echo "  xcode          Open project in Xcode"
        echo "  test           Run tests"
        echo "  clean          Clean all build artifacts"
        echo "  deps           Update dependencies"
        echo "  help           Show this help"
        echo ""
        echo "Examples:"
        echo "  ./Scripts/dev.sh all           # Clean, build, run app"
        echo "  ./Scripts/dev.sh all cli       # Clean, build, run CLI"
        echo "  ./Scripts/dev.sh run           # Build and run app"
        echo ""
        echo "Build output: $BUILD_DIR"
        ;;

    *)
        error "Unknown command: $CMD"
        echo "Run '$0 help' for usage"
        exit 1
        ;;
esac
