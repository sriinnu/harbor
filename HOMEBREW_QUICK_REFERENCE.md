# Homebrew Tap Quick Reference

Quick commands for maintaining the Harbor Homebrew tap.

## Initial Setup

```bash
# 1. Create repository at GitHub
# Repository: homebrew-tap
# Owner: sriinnu
# URL: https://github.com/sriinnu/homebrew-tap

# 2. Clone and setup
git clone https://github.com/sriinnu/homebrew-tap.git
cd homebrew-tap
mkdir -p Casks
cp /path/to/Harbor/Casks/harbor.rb Casks/
git add .
git commit -m "Initial commit: Add Harbor cask formula"
git push origin main
```

## Releasing a New Version

```bash
# 1. Build and create DMG
VERSION="0.1.0-alpha"
# ... build process ...

# 2. Calculate SHA256
shasum -a 256 Harbor-${VERSION}.dmg

# 3. Create GitHub release
# Upload Harbor-${VERSION}.dmg to https://github.com/sriinnu/harbor/releases/new
# Tag: v${VERSION}

# 4. Update tap
cd /path/to/homebrew-tap
# Edit Casks/harbor.rb - update version and sha256
git add Casks/harbor.rb
git commit -m "Update Harbor to v${VERSION}"
git push origin main
```

## Testing

```bash
# Audit cask
brew audit --cask --online sriinnu/tap/harbor

# Style check
brew style --fix Casks/harbor.rb

# Test install
brew uninstall --cask harbor
brew install --cask --verbose sriinnu/tap/harbor
```

## User Commands

```bash
# Install
brew install --cask sriinnu/tap/harbor

# Upgrade
brew upgrade --cask harbor

# Uninstall
brew uninstall --cask harbor

# Complete removal
brew uninstall --zap --cask harbor

# Info
brew info --cask sriinnu/tap/harbor
```

## SHA256 Calculation

```bash
# For DMG file
shasum -a 256 Harbor-0.1.0-alpha.dmg

# For zip file (if used)
shasum -a 256 Harbor-0.1.0-alpha.zip
```

## Cask Formula Template

```ruby
cask "harbor" do
  version "VERSION_HERE"
  sha256 "SHA256_HERE"

  url "https://github.com/sriinnu/harbor/releases/download/v#{version}/Harbor-#{version}.dmg"
  name "Harbor"
  desc "GitHub menubar app - Your GitHub work, safely docked"
  homepage "https://github.com/sriinnu/harbor"

  depends_on macos: ">= :sequoia"

  app "Harbor.app"

  zap trash: [
    "~/Library/Application Support/com.sriinnu.athena.harbor",
    "~/Library/Caches/com.sriinnu.athena.harbor",
    "~/Library/Preferences/com.sriinnu.athena.harbor.plist",
    "~/Library/Saved Application State/com.sriinnu.athena.harbor.savedState",
  ]

  caveats <<~EOS
    Harbor is a menubar application. To run it:
    1. Open Applications folder
    2. Launch Harbor
    3. Look for the Harbor icon in your menubar

    The app will continue running in the background. You can access it
    from the menubar at any time.
  EOS
end
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| SHA256 mismatch | Recalculate with `shasum -a 256` and update formula |
| Download failed | Verify release exists and URL is correct |
| App not found | Ensure Harbor.app is at DMG root |
| Version mismatch | Match cask version to release tag (without 'v') |

## URLs

- Tap repository: https://github.com/sriinnu/homebrew-tap
- Harbor repository: https://github.com/sriinnu/harbor
- Homebrew docs: https://docs.brew.sh/Cask-Cookbook
