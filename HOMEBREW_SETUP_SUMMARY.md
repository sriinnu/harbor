# Homebrew Tap Setup Summary

This document provides a complete overview of the Homebrew tap setup for Harbor.

## Files Created

1. **Casks/harbor.rb** - The Homebrew cask formula
2. **HOMEBREW_TAP_SETUP.md** - Complete setup and maintenance guide
3. **HOMEBREW_QUICK_REFERENCE.md** - Quick reference for common commands
4. **.github/workflows/update-homebrew-tap.yml** - GitHub Actions automation

## Quick Start Guide

### 1. Create the Homebrew Tap Repository

Go to GitHub and create a new repository:

- URL: https://github.com/new
- Repository name: `homebrew-tap`
- Owner: `sriinnu`
- Description: `Homebrew tap for Harbor - GitHub menubar app`
- Visibility: **Public**
- Initialize with README: **Yes**

### 2. Setup the Tap Repository

```bash
# Clone the repository
git clone https://github.com/sriinnu/homebrew-tap.git
cd homebrew-tap

# Create directory structure
mkdir -p Casks

# Copy the cask formula from Harbor repo
cp /path/to/Harbor/Casks/harbor.rb Casks/

# Create README
cat > README.md << 'EOF'
# Homebrew Tap for Harbor

Official Homebrew tap for [Harbor](https://github.com/sriinnu/harbor) - GitHub menubar app for macOS.

## Installation

\`\`\`bash
brew install --cask sriinnu/tap/harbor
\`\`\`

## Requirements

- macOS 15.0 (Sequoia) or later
- GitHub account

## Support

Visit [Harbor repository](https://github.com/sriinnu/harbor) for issues and questions.
EOF

# Commit and push
git add .
git commit -m "Initial commit: Add Harbor cask formula"
git push origin main
```

### 3. Setup GitHub Actions (Optional but Recommended)

To enable automatic tap updates on releases:

1. Create a Personal Access Token on GitHub:
   - Go to: https://github.com/settings/tokens/new
   - Name: `Homebrew Tap Updates`
   - Scopes: `repo` (full control)
   - Generate token and save it

2. Add the token as a secret to Harbor repository:
   - Go to: https://github.com/sriinnu/harbor/settings/secrets/actions
   - Click "New repository secret"
   - Name: `TAP_GITHUB_TOKEN`
   - Value: Paste your token
   - Save

3. The workflow file is already created at `.github/workflows/update-homebrew-tap.yml`

## First Release Process

### Step 1: Build and Package

```bash
cd /path/to/Harbor

# Build for release
xcodebuild -scheme Harbor -configuration Release \
  -archivePath build/Harbor.xcarchive archive

# Export the app
xcodebuild -exportArchive \
  -archivePath build/Harbor.xcarchive \
  -exportPath build/Release \
  -exportOptionsPlist ExportOptions.plist

# Create DMG (install create-dmg first: brew install create-dmg)
create-dmg \
  --volname "Harbor" \
  --volicon "Icon.icns" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --icon "Harbor.app" 175 190 \
  --hide-extension "Harbor.app" \
  --app-drop-link 425 185 \
  "Harbor-0.1.0-alpha.dmg" \
  "build/Release/Harbor.app"
```

### Step 2: Calculate SHA256

```bash
shasum -a 256 Harbor-0.1.0-alpha.dmg
```

Copy the checksum - you'll need it!

### Step 3: Create GitHub Release

1. Go to: https://github.com/sriinnu/harbor/releases/new
2. Fill in:
   - Tag version: `v0.1.0-alpha`
   - Release title: `Harbor v0.1.0-alpha`
   - Description: Add your release notes
3. Upload the `Harbor-0.1.0-alpha.dmg` file
4. Publish the release

### Step 4: Update Tap Formula

If you set up GitHub Actions, this happens automatically!

Otherwise, manually update:

```bash
cd /path/to/homebrew-tap

# Edit Casks/harbor.rb
# Replace:
#   sha256 :no_check  # TODO: Replace with actual SHA256 after first release
# With:
#   sha256 "your_actual_sha256_here"

git add Casks/harbor.rb
git commit -m "Update Harbor to v0.1.0-alpha with SHA256 checksum"
git push origin main
```

## User Installation

Once everything is set up, users can install Harbor with:

```bash
# Method 1: Add tap first
brew tap sriinnu/tap
brew install --cask harbor

# Method 2: One command
brew install --cask sriinnu/tap/harbor
```

## Updating for New Releases

### Manual Process

1. Build and create new DMG
2. Calculate SHA256: `shasum -a 256 Harbor-X.Y.Z.dmg`
3. Create GitHub release with DMG attached
4. Update tap repository:
   ```bash
   cd /path/to/homebrew-tap
   # Edit Casks/harbor.rb - update version and sha256
   git add Casks/harbor.rb
   git commit -m "Update Harbor to vX.Y.Z"
   git push
   ```

### Automated Process (with GitHub Actions)

Just create a GitHub release - the workflow will:
1. Detect the new release
2. Download the DMG
3. Calculate SHA256 automatically
4. Update the tap repository
5. Commit and push changes

## Testing the Cask

Before releasing, always test:

```bash
# Audit the cask
brew audit --cask --online sriinnu/tap/harbor

# Style check
brew style --fix Casks/harbor.rb

# Test installation
brew uninstall --cask harbor  # if already installed
brew install --cask --verbose sriinnu/tap/harbor

# Verify
ls -la /Applications/Harbor.app
```

## Common Issues and Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| SHA256 mismatch | Checksum doesn't match DMG | Recalculate: `shasum -a 256 file.dmg` |
| Download failed | Release or file doesn't exist | Verify GitHub release is published |
| App not found | DMG structure incorrect | Ensure Harbor.app is at root of DMG |
| Permission denied | Token has wrong permissions | Check token has `repo` scope |
| Version mismatch | Cask version doesn't match tag | Update version in cask (without 'v') |

## Important URLs

- Harbor Repository: https://github.com/sriinnu/harbor
- Tap Repository: https://github.com/sriinnu/homebrew-tap
- Create New Repo: https://github.com/new
- Create Token: https://github.com/settings/tokens/new
- Homebrew Docs: https://docs.brew.sh/Cask-Cookbook

## Cask Formula Structure

The cask formula (`Casks/harbor.rb`) contains:

```ruby
cask "harbor" do
  version "0.1.0-alpha"                    # Version number
  sha256 :no_check                         # SHA256 checksum (placeholder)

  url "https://github.com/sriinnu/harbor/releases/download/v#{version}/Harbor-#{version}.dmg"
  name "Harbor"                            # Display name
  desc "GitHub menubar app - Your GitHub work, safely docked"
  homepage "https://github.com/sriinnu/harbor"

  depends_on macos: ">= :sequoia"          # macOS 15.0+ required

  app "Harbor.app"                         # App to install

  zap trash: [                             # Files to remove on uninstall
    "~/Library/Application Support/com.sriinnu.athena.harbor",
    "~/Library/Caches/com.sriinnu.athena.harbor",
    "~/Library/Preferences/com.sriinnu.athena.harbor.plist",
    "~/Library/Saved Application State/com.sriinnu.athena.harbor.savedState",
  ]

  caveats <<~EOS                           # Post-install message
    Harbor is a menubar application...
  EOS
end
```

## SHA256 Placeholder

The initial cask uses `sha256 :no_check` as a placeholder. This allows testing before the first release.

**Important**: Replace this with the actual SHA256 checksum after creating your first GitHub release!

```ruby
# Before first release:
sha256 :no_check  # TODO: Replace with actual SHA256 after first release

# After first release:
sha256 "abc123def456..."  # Your actual checksum
```

## File Locations in Harbor Repository

```
Harbor/
├── Casks/
│   └── harbor.rb                              # Homebrew cask formula
├── .github/
│   └── workflows/
│       └── update-homebrew-tap.yml            # Auto-update workflow
├── HOMEBREW_TAP_SETUP.md                      # Complete setup guide
├── HOMEBREW_QUICK_REFERENCE.md                # Quick command reference
└── HOMEBREW_SETUP_SUMMARY.md                  # This file
```

## Next Steps

1. Create the `homebrew-tap` repository on GitHub
2. Follow the Quick Start Guide above to set it up
3. Build and release your first version of Harbor
4. Update the cask formula with the actual SHA256
5. Test the installation
6. Announce to users!

## User Commands Reference

```bash
# Installation
brew install --cask sriinnu/tap/harbor

# Update
brew upgrade --cask harbor

# Uninstall
brew uninstall --cask harbor

# Complete removal (including data)
brew uninstall --zap --cask harbor

# Get info
brew info --cask sriinnu/tap/harbor

# List installed casks
brew list --cask
```

## Maintenance Checklist

- [ ] Test cask before each release
- [ ] Verify SHA256 checksum
- [ ] Update version number in cask
- [ ] Create GitHub release
- [ ] Verify download URL works
- [ ] Test installation on clean system (if possible)
- [ ] Update release notes
- [ ] Announce to users

## Support

For detailed information, refer to:
- **HOMEBREW_TAP_SETUP.md** - Complete setup and maintenance guide
- **HOMEBREW_QUICK_REFERENCE.md** - Quick command reference
- **Homebrew Documentation** - https://docs.brew.sh/Cask-Cookbook

For issues or questions:
- Harbor Issues: https://github.com/sriinnu/harbor/issues
- Homebrew Discussion: https://github.com/Homebrew/discussions
