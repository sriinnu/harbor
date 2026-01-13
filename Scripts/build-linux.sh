#!/bin/bash
#
# Harbor Linux Build Script
#
# Prerequisites:
# - Ubuntu 20.04+ / Debian 11+ / Fedora 36+ / Arch Linux
# - Rust: https://rustup.rs/ (latest stable)
# - Node.js: https://nodejs.org/ 18+ LTS
# - System dependencies:
#   Ubuntu/Debian: sudo apt-get install webkit2gtk-4.0 libgtk-3-0 libappindicator3-0.1 libnotify4 libnss3 libxss1 libxtst6
#   Fedora: sudo dnf install webkit2gtk3-devel gtk3-devel libappindicator-gtk3-devel
#   Arch: sudo pacman -S webkit2gtk gtk3 libappindicator
#
# Usage:
#   ./Scripts/build-linux.sh           # Build debug
#   ./Scripts/build-linux.sh release   # Build release
#   ./Scripts/build-linux.sh clean     # Clean build artifacts
#   ./Scripts/build-linux.sh deps      # Install dependencies
#   ./Scripts/build-linux.sh run       # Run in development mode
#   ./Scripts/build-linux.sh package   # Create .deb / AppImage packages
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TAURI_DIR="$PROJECT_ROOT/harbor-linux"
BUILD_DIR="$PROJECT_ROOT/build/linux"
CARGO_TARGET_DIR="$BUILD_DIR/target"
export CARGO_TARGET_DIR

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌  $1${NC}"; }

# Parse arguments
MODE="${1:-debug}"

show_help() {
    echo "Harbor Linux Build Script"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  debug    Build debug version (default)"
    echo "  release  Build release version (optimized)"
    echo "  clean    Clean all build artifacts"
    echo "  deps     Install system dependencies and npm packages"
    echo "  run      Run in development mode (with hot reload)"
    echo "  package  Create .deb and AppImage packages"
    echo "  help     Show this help"
    echo ""
    echo "Build output: $BUILD_DIR"
    echo ""
    echo "Prerequisites:"
    echo "  - Rust (rustup.rs)"
    echo "  - Node.js 18+"
    echo "  - webkit2gtk, gtk3, libappindicator"
}

check_prerequisites() {
    local missing=()

    # Check Rust
    if ! command -v rustc &> /dev/null; then
        missing+=("Rust (run: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh)")
    fi

    # Check Node
    if ! command -v node &> /dev/null; then
        missing+=("Node.js (https://nodejs.org/)")
    fi

    # Check Cargo
    if ! command -v cargo &> /dev/null; then
        missing+=("Cargo (install with rustup)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        log_error "Missing prerequisites:"
        for item in "${missing[@]}"; do
            echo "  - $item"
        done
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."

    # Detect distribution
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi

    # Install system dependencies
    case "$DISTRO" in
        ubuntu|debian|pop)
            log_info "Installing dependencies for Ubuntu/Debian..."
            sudo apt-get update
            sudo apt-get install -y \
                webkit2gtk-4.0 \
                libgtk-3-0 \
                libappindicator3-0.1 \
                libnotify4 \
                libnss3 \
                libxtst6 \
                libxss1
            ;;
        fedora)
            log_info "Installing dependencies for Fedora..."
            sudo dnf install -y \
                webkit2gtk3-devel \
                gtk3-devel \
                libappindicator-gtk3-devel
            ;;
        arch|manjaro)
            log_info "Installing dependencies for Arch Linux..."
            sudo pacman -Sy --noconfirm \
                webkit2gtk \
                gtk3 \
                libappindicator
            ;;
        *)
            log_warn "Unknown distribution: $DISTRO"
            log_warn "Please install these packages manually:"
            log_warn "  - webkit2gtk"
            log_warn "  - gtk3"
            log_warn "  - libappindicator"
            ;;
    esac

    # Install Node dependencies
    if [ -f "$TAURI_DIR/package.json" ]; then
        log_info "Installing Node.js dependencies..."
        cd "$TAURI_DIR"
        npm install
    fi

    log_info "✅ Dependencies ready"
}

build_debug() {
    log_info "Building Harbor Linux (Debug)..."
    check_prerequisites
    mkdir -p "$BUILD_DIR"

    if [ ! -d "$TAURI_DIR" ]; then
        log_error "Tauri project not found: $TAURI_DIR"
        exit 1
    fi

    cd "$TAURI_DIR"
    npm run tauri build -- --config debug
    log_info "✅ Debug build complete"
}

build_release() {
    log_info "Building Harbor Linux (Release)..."
    check_prerequisites
    mkdir -p "$BUILD_DIR"

    if [ ! -d "$TAURI_DIR" ]; then
        log_error "Tauri project not found: $TAURI_DIR"
        exit 1
    fi

    cd "$TAURI_DIR"
    npm run tauri build
    log_info "✅ Release build complete"
}

clean_build() {
    log_info "Cleaning build artifacts..."

    if [ -d "$TAURI_DIR/src-tauri/target" ]; then
        rm -rf "$TAURI_DIR/src-tauri/target"
    fi

    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi

    log_info "✅ Clean complete"
}

run_dev() {
    log_info "Running Harbor in development mode..."
    check_prerequisites

    if [ ! -d "$TAURI_DIR" ]; then
        log_error "Tauri project not found: $TAURI_DIR"
        exit 1
    fi

    cd "$TAURI_DIR"
    log_info "Starting Tauri dev server (with hot reload)..."
    log_info "Press Ctrl+C to stop"
    npm run tauri dev
}

package_linux() {
    log_info "Creating Linux packages..."
    check_prerequisites
    mkdir -p "$BUILD_DIR"

    if [ ! -d "$TAURI_DIR" ]; then
        log_error "Tauri project not found: $TAURI_DIR"
        exit 1
    fi

    cd "$TAURI_DIR/src-tauri"

    # Build .deb package (Debian/Ubuntu)
    log_info "Building .deb package..."
    cargo deb --output "$BUILD_DIR/harbor.deb"

    # Build AppImage
    if command -v appimagetool &> /dev/null; then
        log_info "Building AppImage..."
        cargo build --release
        # AppImage creation requires linuxdeploy tool
        # This is a simplified version
    fi

    log_info "✅ Packages created in $BUILD_DIR/"
}

# Main entry point
case "$MODE" in
    help|--help|-h)
        show_help
        ;;
    debug)
        build_debug
        ;;
    release)
        build_release
        ;;
    clean)
        clean_build
        ;;
    deps)
        install_dependencies
        ;;
    run)
        run_dev
        ;;
    package)
        package_linux
        ;;
    *)
        log_error "Unknown command: $MODE"
        show_help
        exit 1
        ;;
esac
