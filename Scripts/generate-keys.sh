#!/bin/bash
#
# Harbor Signing Key Generator
# Generates EdDSA signing keys for Sparkle updates
#
# IMPORTANT: Keep the private key secure! Only the public key (EDKey) goes in Info.plist
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PRIVATE_KEY_FILE="$PROJECT_ROOT/SparklePrivateKey.pem"
PUBLIC_KEY_FILE="$PROJECT_ROOT/SparklePublicKey.pem"
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

echo ""
log_step "Harbor Signing Key Generator"
echo ""
echo "This script generates EdDSA signing keys for Sparkle auto-updates."
echo ""

# Check if keys already exist
if [[ -f "$PRIVATE_KEY_FILE" ]]; then
    log_warn "Private key already exists at: $PRIVATE_KEY_FILE"
    read -p "Do you want to generate new keys? This will invalidate existing updates. (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Keeping existing keys"
        exit 0
    fi
    log_warn "Backing up existing keys..."
    mv "$PRIVATE_KEY_FILE" "$PRIVATE_KEY_FILE.backup.$(date +%Y%m%d%H%M%S)"
    mv "$PUBLIC_KEY_FILE" "$PUBLIC_KEY_FILE.backup.$(date +%Y%m%d%H%M%S)"
    if [[ -f "$ED_KEY_FILE" ]]; then
        mv "$ED_KEY_FILE" "$ED_KEY_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi
fi

log_step "Generating EdDSA signing keys..."

# Generate EdDSA private key (Ed25519)
openssl genpkey -algorithm ED25519 -out "$PRIVATE_KEY_FILE" 2>/dev/null

if [[ ! -f "$PRIVATE_KEY_FILE" ]]; then
    log_error "Failed to generate private key"
    exit 1
fi

log_info "Generated private key: $PRIVATE_KEY_FILE"

# Extract public key from private key
openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_KEY_FILE" 2>/dev/null

log_info "Generated public key: $PUBLIC_KEY_FILE"

# Convert to Sparkle EDKey format (base64 without PEM headers)
local ed_key=$(openssl pkey -in "$PRIVATE_KEY_FILE" -outform der 2>/dev/null | tail -c 32 | base64 | tr -d '\n')

# Actually, we need the public key in the right format
# Sparkle expects the base64-encoded public key
local pub_der=$(openssl pkey -in "$PRIVATE_KEY_FILE" -pubout -outform der 2>/dev/null)
local ed_public=$(echo "$pub_der" | base64 | tr -d '\n')

echo "$ed_public" > "$ED_KEY_FILE"

log_info "Generated EDKey for Info.plist: $ED_KEY_FILE"

echo ""
echo "============================================"
echo "IMPORTANT NEXT STEPS:"
echo "============================================"
echo ""
echo "1. Add the EDKey to Info.plist (already done for new keys):"
echo "   SUPublicEDKey=$(cat "$ED_KEY_FILE")"
echo ""
echo "2. KEEP THE PRIVATE KEY SAFE!"
echo "   - Store it in a secure location (password manager, etc.)"
echo "   - Never commit it to version control"
echo "   - You'll need it to sign updates"
echo ""
echo "3. For CI/CD, set up the private key as a secret environment variable"
echo ""
echo "4. To sign updates, use:"
echo "   ./Scripts/generate-appcast.sh --sign path/to/Harbor.dmg"
echo ""
log_info "Key generation complete!"
