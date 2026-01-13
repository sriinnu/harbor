#!/bin/bash
#
# Harbor Homebrew Tap Automation
# Creates and updates Homebrew cask for Harbor
#
# Usage:
#   ./Scripts/update-homebrew.sh                    # Update cask with local build
#   ./Scripts/update-homebrew.sh --create-tap       # Create new tap repository
#   ./Scripts/update-homebrew.sh --github-actions   # Run in GitHub Actions
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build/macos"
TAP_REPO="${TAP_REPO:-}"  # Set via environment or pass as argument
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # For GitHub Actions

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
APP_NAME="Harbor"
CASK_NAME="harbor"
FORMULA_NAME="Harbor"
BUNDLE_ID="com.sriinnu.athena.harbor"
HOMEBREW_REPO="https://github.com/sriinnu/homebrew-tap"
TAP_DIR="$BUILD_DIR/homebrew-tap"

# Parse arguments
ACTION="update"
GITHUB_ACTIONS=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --create-tap)
            ACTION="create-tap"
            shift
            ;;
        --github-actions|-g)
            GITHUB_ACTIONS=true
            shift
            ;;
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --help|-h)
            echo "Harbor Homebrew Tap Automation"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --create-tap      Create new tap repository"
            echo "  --github-actions  Run in GitHub Actions mode"
            echo "  --dry-run         Show changes without committing"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Environment Variables:"
            echo "  TAP_REPO          Path to local tap repository"
            echo "  GITHUB_TOKEN      GitHub token for Actions"
            echo ""
            echo "Example:"
            echo "  TAP_REPO=~/homebrew-tap ./Scripts/update-homebrew.sh"
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            exit 1
            ;;
    esac
done

# Get version info
get_version() {
    local dmg="$1"
    # Extract version from DMG name or Info.plist
    local version=$(echo "$dmg" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [[ -z "$version" ]]; then
        version=$(grep -E "CFBundleShortVersionString" "$PROJECT_ROOT/Sources/Harbor/Resources/Info.plist" | head -1 | sed 's/.*<string>\(.*\)<\/string>/\1/')
    fi
    echo "$version"
}

# Calculate SHA256 for DMG
calculate_sha256() {
    local dmg="$1"
    shasum -a 256 "$dmg" | cut -d' ' -f1
}

# Find latest DMG
find_dmg() {
    local dmg=$(ls -t "$BUILD_DIR"/Harbor-*.dmg 2>/dev/null | head -1)
    if [[ -z "$dmg" ]]; then
        log_error "No DMG file found in $BUILD_DIR"
        log_info "Build the app first: ./Scripts/build-release.sh"
        exit 1
    fi
    echo "$dmg"
}

# Generate cask file
generate_cask() {
    local version="$1"
    local sha256="$2"
    local dmg_name=$(basename "$3")

    cat << EOF
cask "${CASK_NAME}" do
  version "${version}"
  sha256 "${sha256}"

  url "https://github.com/sriinnu/Harbor/releases/download/v${version}/${dmg_name}"
  name "${FORMULA_NAME}"
  desc "GitHub menubar app - Your GitHub work, safely docked"
  homepage "https://github.com/sriinnu/Harbor"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Harbor.app"

  zap trash: [
    "~/Library/Application Support/Harbor",
    "~/Library/Caches/com.sriinnu.athena.harbor",
    "~/Library/Preferences/com.sriinnu.athena.harbor.plist",
  ]
end
EOF
}

# Generate auto-update check Ruby file
generate_autoupdate() {
    local version="$1"

    cat << EOF
require 'yaml'

class ${CASK_NAME^} < Cask
  version '${version}'
  sha256 :no_check

  url "https://github.com/sriinnu/Harbor/releases/download/v#{version}/Harbor-#{version}-macOS.dmg"
  name '${FORMULA_NAME}'
  desc 'GitHub menubar app'
  homepage 'https://github.com/sriinnu/Harbor'

  app 'Harbor.app'

  zap trash: [
    '~/Library/Application Support/Harbor',
    '~/Library/Caches/com.sriinnu.athena.harbor',
    '~/Library/Preferences/com.sriinnu.athena.harbor.plist',
  ]
end
EOF
}

# Clone or update tap repository
setup_tap_repo() {
    if [[ -z "$TAP_REPO" ]]; then
        TAP_REPO="$BUILD_DIR/homebrew-tap"
    fi

    log_step "Setting up tap repository at $TAP_REPO..."

    if [[ -d "$TAP_REPO/.git" ]]; then
        cd "$TAP_REPO"
        log_info "Pulling latest changes..."
        git pull --ff-only origin main 2>/dev/null || true
    else
        log_info "Cloning tap repository..."
        git clone "$HOMEBREW_REPO" "$TAP_REPO"
        cd "$TAP_REPO"
    fi
}

# Create new tap repository
create_tap() {
    log_step "Creating new Homebrew tap..."

    local tap_name="${1:-sriinnu/tap}"
    local tap_owner=$(echo "$tap_name" | cut -d'/' -f1)
    local tap_slug=$(echo "$tap_name" | cut -d'/' -f2)

    # Create directories
    mkdir -p "$BUILD_DIR/$tap_slug/Casks"
    mkdir -p "$BUILD_DIR/$tap_slug/Formula"

    # Create README
    cat > "$BUILD_DIR/$tap_slug/README.md" << EOF
# Homebrew Tap for Harbor

This is the official Homebrew tap for [Harbor](https://github.com/sriinnu/Harbor).

## Installing Harbor

\`\`\`bash
brew install --cask sriinnu/tap/harbor
\`\`\`

## Updating

\`\`\`bash
brew update
brew upgrade
\`\`\`

## Manual Installation

Download the latest DMG from [GitHub Releases](https://github.com/sriinnu/Harbor/releases/latest).
EOF

    # Create initial cask file placeholder
    cat > "$BUILD_DIR/$tap_slug/Casks/harbor.rb" << 'EOF'
cask "harbor" do
  version "0.2.0"
  sha256 "sha256_here"

  url "https://github.com/sriinnu/Harbor/releases/download/v#{version}/Harbor-#{version}-macOS.dmg"
  name "Harbor"
  desc "GitHub menubar app"
  homepage "https://github.com/sriinnu/Harbor"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Harbor.app"

  zap trash: [
    "~/Library/Application Support/Harbor",
    "~/Library/Caches/com.sriinnu.athena.harbor",
    "~/Library/Preferences/com.sriinnu.athena.harbor.plist",
  ]
end
EOF

    log_success "Tap structure created at $BUILD_DIR/$tap_slug"
    log_info "Next steps:"
    log_info "1. Create GitHub repository: $tap_owner/$tap_slug"
    log_info "2. Push the tap:"
    log_info "   cd $BUILD_DIR/$tap_slug"
    log_info "   git init"
    log_info "   git add ."
    log_info "   git commit -m 'Initial commit'"
    log_info "   git remote add origin https://github.com/$tap_owner/$tap_slug.git"
    log_info "   git push -u origin main"
}

# Update cask with new version
update_cask() {
    local dmg="$1"
    local version=$(get_version "$dmg")
    local sha256=$(calculate_sha256 "$dmg")
    local dmg_name=$(basename "$dmg")

    log_step "Updating cask to version $version..."
    log_info "SHA256: $sha256"

    # Setup tap repo
    setup_tap_repo

    # Generate new cask file
    generate_cask "$version" "$sha256" "$dmg_name" > "$TAP_REPO/Casks/harbor.rb"

    log_info "Updated Casks/harbor.rb"

    # Show changes
    echo ""
    log_step "Changes:"
    git diff "$TAP_REPO/Casks/harbor.rb"
    echo ""

    if [[ "$DRY_RUN" == true ]]; then
        log_warn "Dry run - not committing changes"
        return 0
    fi

    # Commit and push
    log_step "Committing changes..."
    git add Casks/harbor.rb
    git commit -m "Update Harbor to v${version}

🤖 Generated by Harbor release automation"

    log_step "Pushing to GitHub..."
    git push origin main

    log_success "Cask updated to v${version}"
    log_info "Homebrew will pick up the new version on next 'brew update'"
}

# Run in GitHub Actions
run_github_actions() {
    log_step "Running in GitHub Actions mode..."

    # Validate environment
    if [[ -z "$GITHUB_TOKEN" ]]; then
        log_error "GITHUB_TOKEN required"
        exit 1
    fi

    # Configure git
    git config --global user.name "github-actions[bot]"
    git config --global user.email "github-actions[bot]@users.noreply.github.com"

    # Clone tap repo
    TAP_REPO="$BUILD_DIR/homebrew-tap"
    git clone "https://x-access-token:$GITHUB_TOKEN@github.com/sriinnu/homebrew-tap.git" "$TAP_REPO"

    # Find DMG and update cask
    local dmg=$(find_dmg)
    local version=$(get_version "$dmg")
    local sha256=$(calculate_sha256 "$dmg")
    local dmg_name=$(basename "$dmg")

    log_info "Found DMG: $dmg_name"
    log_info "Version: $version"
    log_info "SHA256: $sha256"

    # Generate cask
    generate_cask "$version" "$sha256" "$dmg_name" > "$TAP_REPO/Casks/harbor.rb"

    # Commit and push
    cd "$TAP_REPO"
    git add Casks/harbor.rb
    git commit -m "Update Harbor to v${version}

🤖 Automated update by GitHub Actions
- Version: ${version}
- SHA256: ${sha256}"

    git push origin main

    log_success "GitHub Actions workflow complete!"
}

# Main execution
main() {
    log_step "Harbor Homebrew Tap Automation"
    echo ""

    case "$ACTION" in
        create-tap)
            create_tap
            ;;
        update)
            if [[ "$GITHUB_ACTIONS" == true ]]; then
                run_github_actions
            else
                local dmg=$(find_dmg)
                update_cask "$dmg"
            fi
            ;;
    esac
}

main
