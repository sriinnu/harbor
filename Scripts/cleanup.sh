#!/bin/bash
#
# Harbor Cleanup Script
# Removes all build artifacts and temporary files
#
# Usage:
#   ./Scripts/cleanup.sh            # Standard cleanup
#   ./Scripts/cleanup.sh full       # Full cleanup (including dependencies)
#   ./Scripts/cleanup.sh help       # Show help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }

show_help() {
    echo "Harbor Cleanup Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  (none)   Remove build artifacts (default)"
    echo "  full     Remove build + dependencies + caches"
    echo "  help     Show this help"
    echo ""
    echo "Cleans:"
    echo "  - build/<platform>/ directories"
    echo "  - *.swiftmodule, *.d, *.dia, *.swiftdeps files"
    echo "  - .swiftpm/xcode/ (Xcode project cache)"
    echo "  - ModuleCache/"
    echo "  - DerivedData/"
}

MODE="${1:-standard}"

case "$MODE" in
    help|--help|-h)
        show_help
        exit 0
        ;;
    full)
        log_info "Full cleanup - removing everything..."
        ;;
    standard)
        log_info "Cleaning build artifacts..."
        ;;
esac

# Build artifacts
if [ -d "$BUILD_DIR" ]; then
    rm -rf "$BUILD_DIR"
    log_info "Removed: $BUILD_DIR"
fi

# Swift build intermediate files
find "$PROJECT_ROOT" -maxdepth 2 -type f \( \
    -name "*.swiftmodule" -o \
    -name "*.d" -o \
    -name "*.dia" -o \
    -name "*.swiftdeps" -o \
    -name "*.o" \
    \) -delete 2>/dev/null || true

log_info "Removed Swift intermediate files"

# Xcode/SwiftPM caches
if [ -d "$PROJECT_ROOT/.swiftpm" ]; then
    rm -rf "$PROJECT_ROOT/.swiftpm/xcode"
    log_info "Removed: .swiftpm/xcode (Xcode cache)"
fi

if [ -d "$PROJECT_ROOT/ModuleCache" ]; then
    rm -rf "$PROJECT_ROOT/ModuleCache"
    log_info "Removed: ModuleCache"
fi

if [ -d "$PROJECT_ROOT/DerivedData" ]; then
    rm -rf "$PROJECT_ROOT/DerivedData"
    log_info "Removed: DerivedData"
fi

# Xcode user data
if [ -d "$PROJECT_ROOT/xcuserdata" ]; then
    rm -rf "$PROJECT_ROOT/xcuserdata"
    log_info "Removed: xcuserdata"
fi

# .build directory (if exists from old builds)
if [ -d "$PROJECT_ROOT/.build" ]; then
    rm -rf "$PROJECT_ROOT/.build"
    log_info "Removed: .build"
fi

# Index Store
if [ -d "$PROJECT_ROOT/Index.noindex" ]; then
    rm -rf "$PROJECT_ROOT/Index.noindex"
    log_info "Removed: Index.noindex"
fi

# SDK stat caches
if [ -d "$PROJECT_ROOT/SDKStatCaches.noindex" ]; then
    rm -rf "$PROJECT_ROOT/SDKStatCaches.noindex"
    log_info "Removed: SDKStatCaches.noindex"
fi

if [ "$MODE" = "full" ]; then
    # Node modules
    if [ -d "$PROJECT_ROOT/harbor-windows/node_modules" ]; then
        rm -rf "$PROJECT_ROOT/harbor-windows/node_modules"
        log_info "Removed: harbor-windows/node_modules"
    fi

    # Cargo registry
    if [ -d "$HOME/.cargo/registry" ]; then
        # Don't remove, just log
        log_info "Tip: Full cargo cache at ~/.cargo/registry (manual cleanup if needed)"
    fi

    # SPM checkouts
    if [ -d "$PROJECT_ROOT/build/SourcePackages" ]; then
        rm -rf "$PROJECT_ROOT/build/SourcePackages"
        log_info "Removed: build/SourcePackages (SPM checkouts)"
    fi
fi

echo ""
log_info "✅ Cleanup complete!"
log_info "Project root is now clean."
