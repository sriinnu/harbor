#!/bin/bash
#
# Harbor Appcast Generator
# Generates Sparkle-compatible appcast.xml for auto-updates
#
# Usage:
#   ./Scripts/generate-appcast.sh           # Generate from build directory
#   ./Scripts/generate-appcast.sh ./path    # Generate from specific DMG
#   ./Scripts/generate-appcast.sh --sign    # Generate and sign updates
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/macos"
RELEASES_DIR="$BUILD_DIR/releases"
APPCAST_FILE="$RELEASES_DIR/appcast.xml"
ED_KEY_FILE="$PROJECT_ROOT/SparkleEdKey.txt"

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

# Configuration
APP_NAME="Harbor"
BUNDLE_ID="com.sriinnu.athena.harbor"
APP_CAST_URL="https://sriinnu.github.io/Harbor/appcast.xml"

# Parse arguments
DMG_PATH=""
DO_SIGN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --sign|-s)
            DO_SIGN=true
            shift
            ;;
        --help|-h)
            echo "Harbor Appcast Generator"
            echo ""
            echo "Usage: $0 [options] [dmg_path]"
            echo ""
            echo "Options:"
            echo "  --sign, -s    Sign updates with EDKey"
            echo "  --help, -h    Show this help"
            echo ""
            echo "Arguments:"
            echo "  dmg_path      Path to DMG file (default: $BUILD_DIR/Harbor-*.dmg)"
            exit 0
            ;;
        *)
            if [[ -z "$DMG_PATH" ]]; then
                DMG_PATH="$1"
            else
                log_error "Unknown argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# Find DMG file if not provided
find_dmg() {
    if [[ -n "$DMG_PATH" ]]; then
        if [[ -f "$DMG_PATH" ]]; then
            echo "$DMG_PATH"
        else
            log_error "DMG file not found: $DMG_PATH"
            exit 1
        fi
    else
        local dmg=$(ls -t "$BUILD_DIR"/Harbor-*.dmg 2>/dev/null | head -1)
        if [[ -z "$dmg" ]]; then
            log_error "No DMG file found in $BUILD_DIR"
            log_info "Build the app first: ./Scripts/build.sh release"
            exit 1
        fi
        echo "$dmg"
    fi
}

# Get version from DMG
get_version() {
    local dmg="$1"
    # Mount DMG temporarily and get version
    local version=$(hdiutil attach -readonly "$dmg" 2>/dev/null | \
        grep -E "^\/dev\/disk" | awk '{print $3}' | xargs -I{} sh -c \
        "ls '{}/Harbor.app/Contents/Info.plist' 2>/dev/null && defaults read '{}/Harbor.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null" | head -1)
    hdiutil detach "$(hdiutil attach -readonly "$dmg" 2>/dev/null | grep -E "^\/dev\/disk" | awk '{print $1}' | head -1)" 2>/dev/null || true
    echo "$version"
}

# Get build number from DMG
get_build() {
    local dmg="$1"
    local build=$(hdiutil attach -readonly "$dmg" 2>/dev/null | \
        grep -E "^\/dev\/disk" | awk '{print $3}' | xargs -I{} sh -c \
        "defaults read '{}/Harbor.app/Contents/Info.plist CFBundleVersion 2>/dev/null" | head -1)
    hdiutil detach "$(hdiutil attach -readonly "$dmg" 2>/dev/null | grep -E "^\/dev\/disk" | awk '{print $1}' | head -1)" 2>/dev/null || true
    echo "$build"
}

# Calculate SHA-256 for signature
calculate_signature() {
    local file="$1"
    local ed_key="$2"

    if [[ -z "$ed_key" ]]; then
        log_warn "No EDKey provided, skipping signature"
        return 1
    fi

    # Generate EdDSA signature using the file hash and EDKey
    local file_hash=$(shasum -a 256 "$file" | cut -d' ' -f1)
    local signature=$(echo "$file_hash" | openssl pkeyutl -sign -inkey <(echo "$ed_key") -pubin 2>/dev/null | base64 -w0)

    if [[ -n "$signature" ]]; then
        echo "$signature"
        return 0
    fi
    return 1
}

# Generate appcast entry for a release
generate_item() {
    local dmg="$1"
    local version="$2"
    local build="$3"
    local signature="$4"
    local release_notes="$5"

    local item_date=$(date -u +"%a, %d %b %Y %H:%M:%S GMT")
    local file_size=$(stat -f%z "$dmg" 2>/dev/null || stat -c%s "$dmg" 2>/dev/null)
    local file_name=$(basename "$dmg")
    local download_url="https://github.com/sriinnu/Harbor/releases/download/v${version}/${file_name}"

    # Generate release notes path (can be a .md file in the releases folder)
    local release_notes_path="$RELEASES_DIR/CHANGELOG-${version}.md"
    local release_notes_html=""
    if [[ -f "$release_notes_path" ]]; then
        release_notes_html=$(cat "$release_notes_path")
    fi

    local sparkle_update_url=""
    if [[ -n "$signature" ]]; then
        sparkle_update_url="sparkle:edSignature=\"$signature\""
    fi

    cat << EOF
        <item>
            <title>Harbor $version</title>
            <pubDate>$item_date</pubDate>
            <description><![CDATA[$release_notes_html]]></description>
            <enclosure url="$download_url"
                       sparkle:version="$version"
                       sparkle:build="$build"
                       sparkle:shortVersionString="$version"
                       $sparkle_update_url
                       type="application/x-apple-diskimage"
                       length="$file_size" />
        </item>
EOF
}

# Generate the appcast XML
generate_appcast() {
    local dmg="$1"
    local version="$2"
    local build="$3"
    local signature="$4"

    log_step "Generating appcast.xml..."

    # Ensure releases directory exists
    mkdir -p "$RELEASES_DIR"

    # Generate new item for this version
    local new_item=$(generate_item "$dmg" "$version" "$build" "$signature")

    # Check if appcast exists, if so, insert after XML declaration
    if [[ -f "$APPCAST_FILE" ]]; then
        log_info "Updating existing appcast.xml..."
        # Keep existing items and prepend new one at the top
        local existing_items=$(sed -n '/<item>/,/<\/item>/p' "$APPCAST_FILE" | grep -v '^[[:space:]]*$' | head -50)

        cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Harbor Changelog</title>
        <link>$APP_CAST_URL</link>
        <description>Harbor update feed</description>
        <language>en</language>
$new_item
$existing_items
    </channel>
</rss>
EOF
    else
        log_info "Creating new appcast.xml..."
        cat > "$APPCAST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Harbor Changelog</title>
        <link>$APP_CAST_URL</link>
        <description>Harbor update feed</description>
        <language>en</language>
$new_item
    </channel>
</rss>
EOF
    fi

    log_info "Appcast generated: $APPCAST_FILE"
}

# Main execution
main() {
    log_step "Harbor Appcast Generator"
    echo ""

    # Find DMG file
    local dmg=$(find_dmg)
    log_info "Using DMG: $dmg"

    # Get version info
    local version=$(get_version "$dmg")
    if [[ -z "$version" ]]; then
        version=$(echo "$dmg" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    fi
    log_info "Version: $version"

    local build=$(get_build "$dmg")
    if [[ -z "$build" ]]; then
        build="1"
    fi
    log_info "Build: $build"

    # Handle signing
    local signature=""
    if [[ "$DO_SIGN" == true ]]; then
        log_step "Signing update..."

        # Read or generate EDKey
        local ed_key=""
        if [[ -f "$ED_KEY_FILE" ]]; then
            ed_key=$(cat "$ED_KEY_FILE" | tr -d '\n')
        else
            log_warn "EDKey file not found: $ED_KEY_FILE"
            log_warn "Run './Scripts/generate-keys.sh' first to generate signing keys"
        fi

        if [[ -n "$ed_key" ]]; then
            signature=$(calculate_signature "$dmg" "$ed_key")
            log_info "Generated signature: ${signature:0:20}..."
        fi
    fi

    # Generate appcast
    generate_appcast "$dmg" "$version" "$build" "$signature"

    echo ""
    log_info "Done!"
    log_info "Upload $APPCAST_FILE to your web server or GitHub Pages"
    log_info "Appcast URL: $APP_CAST_URL"
}

main
