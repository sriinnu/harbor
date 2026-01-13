#!/usr/bin/env bash
#
# Harbor GitHub Release Creation Script
#
# This script creates a GitHub release using the gh CLI.
# It handles both alpha/beta releases and stable releases.
#
# Usage:
#   ./Scripts/create-release.sh [VERSION] [--prerelease]
#
# Examples:
#   ./Scripts/create-release.sh v0.1.0-alpha --prerelease
#   ./Scripts/create-release.sh v1.0.0
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log() { echo -e "${BLUE}==>${NC} $*"; }
success() { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
error() { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT_DIR"

# Parse arguments
VERSION="${1:-}"
PRERELEASE_FLAG=""

if [[ "$#" -ge 2 && "$2" == "--prerelease" ]]; then
    PRERELEASE_FLAG="--prerelease"
fi

# Validate version argument
if [[ -z "$VERSION" ]]; then
    error "Usage: $0 <version> [--prerelease]\nExample: $0 v0.1.0-alpha --prerelease"
fi

# Ensure version starts with 'v'
if [[ ! "$VERSION" =~ ^v ]]; then
    VERSION="v${VERSION}"
fi

# Extract version number (remove 'v' prefix)
VERSION_NUMBER="${VERSION#v}"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    error "GitHub CLI (gh) is not installed. Install with: brew install gh"
fi

# Check if authenticated with gh
if ! gh auth status &> /dev/null; then
    error "Not authenticated with GitHub CLI. Run: gh auth login"
fi

log "Creating GitHub release for Harbor $VERSION"

# Check if tag exists
if git rev-parse "$VERSION" >/dev/null 2>&1; then
    warn "Tag $VERSION already exists"
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Deleting existing tag..."
        git tag -d "$VERSION" || true
        git push origin ":refs/tags/$VERSION" || true
    else
        error "Aborted. Please use a different version or delete the tag manually."
    fi
fi

# Check if release already exists on GitHub
if gh release view "$VERSION" &> /dev/null; then
    warn "Release $VERSION already exists on GitHub"
    read -p "Do you want to delete and recreate it? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Deleting existing release..."
        gh release delete "$VERSION" --yes || true
    else
        error "Aborted. Please use a different version or delete the release manually."
    fi
fi

# Check for release notes file
RELEASE_NOTES_FILE="RELEASE_NOTES_${VERSION}.md"
if [[ ! -f "$RELEASE_NOTES_FILE" ]]; then
    warn "Release notes file not found: $RELEASE_NOTES_FILE"
    warn "Using default release notes from CHANGELOG.md"

    # Extract section from CHANGELOG.md for this version
    TEMP_NOTES=$(mktemp)
    if grep -q "## $VERSION_NUMBER" CHANGELOG.md 2>/dev/null; then
        # Extract notes between this version and next version header
        sed -n "/## $VERSION_NUMBER/,/## [0-9]/p" CHANGELOG.md | sed '$d' > "$TEMP_NOTES"
        RELEASE_NOTES_FILE="$TEMP_NOTES"
    else
        warn "Version $VERSION_NUMBER not found in CHANGELOG.md"
        echo "Release notes for Harbor $VERSION" > "$TEMP_NOTES"
        echo "" >> "$TEMP_NOTES"
        echo "Please see CHANGELOG.md for details." >> "$TEMP_NOTES"
        RELEASE_NOTES_FILE="$TEMP_NOTES"
    fi
    trap "rm -f $TEMP_NOTES" EXIT
fi

# Check for release artifacts
ARTIFACTS=()
ARTIFACTS_DIR="releases/$VERSION_NUMBER"

# Look for macOS DMG
if [[ -f "$ARTIFACTS_DIR/Harbor-macOS-$VERSION.dmg" ]]; then
    ARTIFACTS+=("$ARTIFACTS_DIR/Harbor-macOS-$VERSION.dmg")
    success "Found macOS DMG: $ARTIFACTS_DIR/Harbor-macOS-$VERSION.dmg"
elif [[ -f "Harbor-$VERSION_NUMBER.zip" ]]; then
    ARTIFACTS+=("Harbor-$VERSION_NUMBER.zip")
    success "Found macOS ZIP: Harbor-$VERSION_NUMBER.zip"
elif [[ -f "build/macos/Harbor-$VERSION_NUMBER-macOS.dmg" ]]; then
    ARTIFACTS+=("build/macos/Harbor-$VERSION_NUMBER-macOS.dmg")
    success "Found macOS DMG: build/macos/Harbor-$VERSION_NUMBER-macOS.dmg"
elif [[ -f "build/macos/Harbor-$VERSION_NUMBER.zip" ]]; then
    ARTIFACTS+=("build/macos/Harbor-$VERSION_NUMBER.zip")
    success "Found macOS ZIP: build/macos/Harbor-$VERSION_NUMBER.zip"
else
    warn "No macOS artifacts found (expected: $ARTIFACTS_DIR/Harbor-macOS-$VERSION.dmg or Harbor-$VERSION_NUMBER.zip)"
fi

# Look for macOS dSYM
if [[ -f "$ARTIFACTS_DIR/Harbor-$VERSION_NUMBER.dSYM.zip" ]]; then
    ARTIFACTS+=("$ARTIFACTS_DIR/Harbor-$VERSION_NUMBER.dSYM.zip")
    success "Found dSYM: $ARTIFACTS_DIR/Harbor-$VERSION_NUMBER.dSYM.zip"
elif [[ -f "Harbor-$VERSION_NUMBER.dSYM.zip" ]]; then
    ARTIFACTS+=("Harbor-$VERSION_NUMBER.dSYM.zip")
    success "Found dSYM: Harbor-$VERSION_NUMBER.dSYM.zip"
elif [[ -f "build/macos/Harbor-$VERSION_NUMBER.dSYM.zip" ]]; then
    ARTIFACTS+=("build/macos/Harbor-$VERSION_NUMBER.dSYM.zip")
    success "Found dSYM: build/macos/Harbor-$VERSION_NUMBER.dSYM.zip"
fi

# Look for Windows installer
if [[ -f "$ARTIFACTS_DIR/Harbor-Windows-$VERSION-setup.exe" ]]; then
    ARTIFACTS+=("$ARTIFACTS_DIR/Harbor-Windows-$VERSION-setup.exe")
    success "Found Windows installer: $ARTIFACTS_DIR/Harbor-Windows-$VERSION-setup.exe"
else
    warn "No Windows artifacts found (expected: $ARTIFACTS_DIR/Harbor-Windows-$VERSION-setup.exe)"
fi

# Check if we have any artifacts
if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
    warn "No release artifacts found"
    warn "Expected artifacts in: $ARTIFACTS_DIR/"
    warn "  - Harbor-macOS-$VERSION.dmg (or Harbor-$VERSION_NUMBER.zip)"
    warn "  - Harbor-$VERSION_NUMBER.dSYM.zip (optional)"
    warn "  - Harbor-Windows-$VERSION-setup.exe (optional)"
    echo
    read -p "Continue without artifacts? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        error "Aborted. Please build release artifacts first."
    fi
fi

# Display summary
log "Release Summary:"
echo "  Version: $VERSION"
echo "  Version Number: $VERSION_NUMBER"
echo "  Release Notes: $RELEASE_NOTES_FILE"
echo "  Prerelease: ${PRERELEASE_FLAG:-no}"
echo "  Artifacts: ${#ARTIFACTS[@]}"
for artifact in "${ARTIFACTS[@]}"; do
    echo "    - $(basename "$artifact")"
done
echo

# Confirm before proceeding
read -p "Create this release? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    error "Aborted by user"
fi

# Create git tag
log "Creating git tag $VERSION..."
if git tag -a "$VERSION" -m "Release $VERSION"; then
    success "Tag created"
else
    error "Failed to create tag"
fi

# Push tag to GitHub
log "Pushing tag to GitHub..."
if git push origin "$VERSION"; then
    success "Tag pushed"
else
    error "Failed to push tag. Rolling back local tag..."
    git tag -d "$VERSION"
    exit 1
fi

# Create GitHub release
log "Creating GitHub release..."

RELEASE_TITLE="Harbor $VERSION"
if [[ "$VERSION" =~ -alpha ]]; then
    RELEASE_TITLE="$RELEASE_TITLE (Alpha)"
elif [[ "$VERSION" =~ -beta ]]; then
    RELEASE_TITLE="$RELEASE_TITLE (Beta)"
fi

# Build gh release create command
GH_CMD=(gh release create "$VERSION")
GH_CMD+=(--title "$RELEASE_TITLE")
GH_CMD+=(--notes-file "$RELEASE_NOTES_FILE")

# Add prerelease flag if specified
if [[ -n "$PRERELEASE_FLAG" ]]; then
    GH_CMD+=(--prerelease)
fi

# Add artifacts
for artifact in "${ARTIFACTS[@]}"; do
    GH_CMD+=("$artifact")
done

# Execute release creation
if "${GH_CMD[@]}"; then
    success "GitHub release created successfully!"
    echo
    log "Release URL:"
    gh release view "$VERSION" --web
    echo
    success "Done! Release $VERSION is now available."
else
    error "Failed to create GitHub release"
fi

# Cleanup
if [[ -n "${TEMP_NOTES:-}" && -f "$TEMP_NOTES" ]]; then
    rm -f "$TEMP_NOTES"
fi

# Final notes
echo
log "Next Steps:"
echo "  1. Verify the release on GitHub"
echo "  2. Update documentation if needed"
echo "  3. Announce the release"
if [[ "$VERSION" =~ -alpha|^-beta ]]; then
    echo "  4. Gather feedback from testers"
else
    echo "  4. Update Homebrew cask (if applicable)"
    echo "  5. Update appcast.xml for Sparkle updates"
fi
