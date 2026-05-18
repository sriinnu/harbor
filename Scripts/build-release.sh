#!/bin/bash
#
# Harbor Release Build Script
# Builds a signed, notarized DMG for distribution
#
# Usage:
#   ./Scripts/build-release.sh              # Build release (interactive)
#   ./Scripts/build-release.sh --sign       # Sign only
#   ./Scripts/build-release.sh --notarize   # Notarize only
#   ./Scripts/build-release.sh --all        # Build, sign, and notarize
#   ./Scripts/build-release.sh --clean      # Clean build artifacts
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/macos"
ARCHIVE_DIR="$BUILD_DIR/Harbor.xcarchive"
DMG_DIR="$BUILD_DIR/dmg"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}ℹ️  $1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌  $1${NC}"; }
log_step() { echo -e "${BLUE}🔧 $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }

# Configuration
VERSION=$(grep -E "CFBundleShortVersionString" "$PROJECT_ROOT/Sources/Harbor/Resources/Info.plist" | head -1 | sed 's/.*<string>\(.*\)<\/string>/\1/')
BUILD_NUMBER=$(grep -E "CFBundleVersion" "$PROJECT_ROOT/Sources/Harbor/Resources/Info.plist" | head -1 | sed 's/.*<string>\(.*\)<\/string>/\1/')
APP_NAME="Harbor"
BUNDLE_ID="com.sriinnu.harbor"
TEAM_ID="${TEAM_ID:-}"  # Set via environment or pass as argument
APPLE_ID="${APPLE_ID:-}"  # For notarization
APP_SPECIFIC_PASSWORD="${APP_SPECIFIC_PASSWORD:-}"  # For notarization

# Parse arguments
ACTION="build"
DO_SIGN=false
DO_NOTARIZE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sign|-s)
            DO_SIGN=true
            ACTION="sign"
            shift
            ;;
        --notarize|-n)
            DO_NOTARIZE=true
            ACTION="notarize"
            shift
            ;;
        --all|-a)
            DO_SIGN=true
            DO_NOTARIZE=true
            ACTION="all"
            shift
            ;;
        --clean|-c)
            log_info "Cleaning build artifacts..."
            rm -rf "$BUILD_DIR/Harbor.xcarchive"
            rm -rf "$BUILD_DIR/dmg"
            rm -rf "$BUILD_DIR/Build"
            rm -f "$BUILD_DIR"/*.dmg
            log_success "Cleaned build artifacts"
            exit 0
            ;;
        --help|-h)
            echo "Harbor Release Build Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --sign, -s      Sign the app (requires TEAM_ID)"
            echo "  --notarize, -n  Notarize the app (requires APPLE_ID and APP_SPECIFIC_PASSWORD)"
            echo "  --all, -a       Build, sign, and notarize"
            echo "  --clean, -c     Clean build artifacts"
            echo "  --help, -h      Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  TEAM_ID              Your Apple Developer Team ID"
            echo "  APPLE_ID             Your Apple ID for notarization"
            echo "  APP_SPECIFIC_PASSWORD  App-specific password for notarization"
            echo ""
            echo "Example:"
            echo "  TEAM_ID=ABC123 ./Scripts/build-release.sh --all"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Get version from command line or environment
VERSION="${HARBOR_VERSION:-$VERSION}"

# Find available signing identity
find_signing_identity() {
    local team_id="$1"
    if [[ -n "$team_id" ]]; then
        security find-identity -v -p codesigning | grep "Developer ID Application.*$team_id" | head -1 | sed 's/.*"\(.*\)"/\1/'
    else
        security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/'
    fi
}

# Build the archive
build_archive() {
    log_step "Building Harbor $VERSION (build $BUILD_NUMBER)..."

    # Clean previous build
    rm -rf "$ARCHIVE_DIR"

    # Build archive
    xcodebuild \
        -scheme Harbor \
        -destination 'platform=macOS,arch=arm64' \
        -configuration Release \
        -derivedDataPath "$BUILD_DIR" \
        clean archive \
        -archivePath "$ARCHIVE_DIR" \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        2>&1 | grep -E "(error:|warning:|Build|Compiling\ Swift|Linking|ARCHIVE SUCCEEDED)" || true

    if [[ -d "$ARCHIVE_DIR/Products/Applications/Harbor.app" ]]; then
        log_success "Archive created: $ARCHIVE_DIR"
        return 0
    else
        log_error "Archive creation failed"
        return 1
    fi
}

# Code sign the app
sign_app() {
    local identity="$1"

    log_step "Code signing Harbor..."

    # Sign the app bundle
    codesign --force --deep --sign "$identity" \
        --timestamp \
        --options=runtime \
        --entitlements "$PROJECT_ROOT/Sources/Harbor/Resources/Harbor.entitlements" \
        "$ARCHIVE_DIR/Products/Applications/Harbor.app"

    # Verify signature
    log_step "Verifying signature..."
    if codesign --verify --verbose=4 "$ARCHIVE_DIR/Products/Applications/Harbor.app"; then
        log_success "Signature verified"
    else
        log_warn "Signature verification failed"
    fi

    # Check notarization status
    log_step "Checking notarization status..."
    if spctl --assess --verbose=4 --type open --context context:primary-signature "$ARCHIVE_DIR/Products/Applications/Harbor.app" 2>&1; then
        log_success "Notarization assessment passed"
    else
        log_warn "Notarization assessment failed (may need stapling)"
    fi
}

# Create DMG
create_dmg() {
    log_step "Creating DMG..."

    rm -rf "$DMG_DIR"
    mkdir -p "$DMG_DIR"

    # Copy app to DMG folder
    cp -R "$ARCHIVE_DIR/Products/Applications/Harbor.app" "$DMG_DIR/"

    # Create symbolic link to Applications folder
    ln -s /Applications "$DMG_DIR/Applications"

    # Create the DMG
    local dmg_name="Harbor-${VERSION}-macOS.dmg"
    rm -f "$BUILD_DIR/$dmg_name"

    hdiutil create -volname "Harbor $VERSION" \
        -srcfolder "$DMG_DIR" \
        -ov -format UDZO \
        -imagekey zlib-level=9 \
        "$BUILD_DIR/$dmg_name"

    if [[ -f "$BUILD_DIR/$dmg_name" ]]; then
        log_success "DMG created: $BUILD_DIR/$dmg_name"
    else
        log_error "DMG creation failed"
        return 1
    fi
}

# Notarize the app
notarize_app() {
    local dmg_path="$1"

    if [[ -z "$APPLE_ID" || -z "$APP_SPECIFIC_PASSWORD" ]]; then
        log_error "APPLE_ID and APP_SPECIFIC_PASSWORD required for notarization"
        return 1
    fi

    if [[ -z "$TEAM_ID" ]]; then
        log_error "TEAM_ID required for notarization"
        return 1
    fi

    log_step "Notarizing $dmg_path..."

    # Submit for notarization
    local request_id=$(xcrun notarytool submit "$dmg_path" \
        --apple-id "$APPLE_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait \
        2>&1 | grep -oE "id: [a-f0-9-]+" | cut -d' ' -f2)

    if [[ -n "$request_id" ]]; then
        log_success "Notarization request submitted: $request_id"

        # Staple the notarization ticket
        log_step "Stapling notarization ticket..."
        xcrun stapler staple "$dmg_path"

        log_success "Notarization complete"
    else
        log_error "Notarization failed"
        return 1
    fi
}

# Print build summary
print_summary() {
    local dmg_name="Harbor-${VERSION}-macOS.dmg"
    local dmg_path="$BUILD_DIR/$dmg_name"

    echo ""
    echo "============================================"
    echo "  Harbor Release Build Complete"
    echo "============================================"
    echo ""
    echo "Version: $VERSION (build $BUILD_NUMBER)"
    echo ""
    echo "Files:"
    echo "  - Archive: $ARCHIVE_DIR"
    echo "  - DMG: $dmg_path"
    echo ""
    echo "File size: $(du -h "$dmg_path" | cut -f1)"
    echo "SHA256: $(shasum -a 256 "$dmg_path" | cut -d' ' -f1)"
    echo ""
    echo "Next steps:"
    echo "  1. Test the app before distribution"
    echo "  2. Upload to GitHub Releases"
    echo "  3. Update Homebrew cask"
    echo ""
    log_success "Build complete!"
}

# Main execution
main() {
    log_step "Harbor Release Build Script"
    echo ""
    log_info "Version: $VERSION (build $BUILD_NUMBER)"
    echo ""

    # Determine what to do
    case "$ACTION" in
        build)
            build_archive || exit 1
            create_dmg
            ;;
        sign)
            if [[ -z "$TEAM_ID" ]]; then
                log_warn "TEAM_ID not set, searching for available identity..."
            fi
            local identity=$(find_signing_identity "$TEAM_ID")
            if [[ -z "$identity" ]]; then
                log_error "No valid signing identity found"
                log_info "Make sure you have a Developer ID certificate installed"
                exit 1
            fi
            log_info "Using identity: $identity"
            sign_app "$identity"
            ;;
        notarize)
            local dmg_name="Harbor-${VERSION}-macOS.dmg"
            local dmg_path="$BUILD_DIR/$dmg_name"
            if [[ ! -f "$dmg_path" ]]; then
                log_error "DMG not found: $dmg_path"
                log_info "Build the DMG first: ./Scripts/build-release.sh"
                exit 1
            fi
            notarize_app "$dmg_path"
            ;;
        all)
            build_archive || exit 1
            if [[ "$DO_SIGN" == true ]]; then
                local identity=$(find_signing_identity "$TEAM_ID")
                if [[ -n "$identity" ]]; then
                    sign_app "$identity"
                else
                    log_warn "Skipping signing - no identity found"
                fi
            fi
            create_dmg
            if [[ "$DO_NOTARIZE" == true ]]; then
                local dmg_name="Harbor-${VERSION}-macOS.dmg"
                notarize_app "$BUILD_DIR/$dmg_name"
            fi
            print_summary
            ;;
    esac
}

main
