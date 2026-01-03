# Homebrew Tap Setup Guide for Harbor

This guide provides complete instructions for setting up and maintaining a Homebrew tap for Harbor.

## Table of Contents

1. [Initial Tap Repository Setup](#initial-tap-repository-setup)
2. [Cask Formula Structure](#cask-formula-structure)
3. [Publishing Your First Release](#publishing-your-first-release)
4. [Installation Instructions for Users](#installation-instructions-for-users)
5. [Updating the Cask for New Releases](#updating-the-cask-for-new-releases)
6. [Testing the Cask](#testing-the-cask)
7. [Troubleshooting](#troubleshooting)

---

## Initial Tap Repository Setup

### Step 1: Create the Homebrew Tap Repository

1. Go to GitHub: https://github.com/new
2. Create a new repository with the following details:
   - **Repository name**: `homebrew-tap` (must start with `homebrew-`)
   - **Owner**: `sriinnu`
   - **Description**: `Homebrew tap for Harbor - GitHub menubar app`
   - **Visibility**: Public
   - **Initialize**: Add a README.md

3. Clone the repository locally:
   ```bash
   git clone https://github.com/sriinnu/homebrew-tap.git
   cd homebrew-tap
   ```

### Step 2: Set Up the Repository Structure

```bash
# Create the Casks directory
mkdir -p Casks

# Copy the harbor.rb cask formula
cp /path/to/Harbor/Casks/harbor.rb Casks/

# Create a README
cat > README.md << 'EOF'
# Homebrew Tap for Harbor

This is the official Homebrew tap for [Harbor](https://github.com/sriinnu/harbor), a GitHub menubar app for macOS.

## Installation

```bash
brew install --cask sriinnu/tap/harbor
```

## About Harbor

Harbor is a macOS menubar application that helps you manage your GitHub work efficiently. It provides quick access to your pull requests, issues, notifications, and more - all safely docked in your menubar.

## Requirements

- macOS 15.0 (Sequoia) or later
- GitHub account

## Support

For issues, feature requests, or questions, please visit the [main Harbor repository](https://github.com/sriinnu/harbor).
EOF

# Commit and push
git add .
git commit -m "Initial commit: Add Harbor cask formula"
git push origin main
```

---

## Cask Formula Structure

The cask formula is located at `Casks/harbor.rb`. Here's what each section does:

```ruby
cask "harbor" do
  version "0.1.0-alpha"                    # App version
  sha256 :no_check                         # SHA256 checksum (placeholder initially)

  url "https://github.com/sriinnu/harbor/releases/download/v#{version}/Harbor-#{version}.dmg"
  name "Harbor"                            # Human-readable name
  desc "GitHub menubar app - Your GitHub work, safely docked"
  homepage "https://github.com/sriinnu/harbor"

  depends_on macos: ">= :sequoia"          # macOS 15.0+ required

  app "Harbor.app"                         # Main app to install

  zap trash: [                             # Files to remove on uninstall
    "~/Library/Application Support/com.sriinnu.athena.harbor",
    "~/Library/Caches/com.sriinnu.athena.harbor",
    "~/Library/Preferences/com.sriinnu.athena.harbor.plist",
    "~/Library/Saved Application State/com.sriinnu.athena.harbor.savedState",
  ]

  caveats <<~EOS                           # Post-install instructions
    Harbor is a menubar application...
  EOS
end
```

---

## Publishing Your First Release

### Step 1: Build and Package the App

1. Build your app for release:
   ```bash
   cd /path/to/Harbor
   xcodebuild -scheme Harbor -configuration Release -archivePath build/Harbor.xcarchive archive
   xcodebuild -exportArchive -archivePath build/Harbor.xcarchive -exportPath build/Release -exportOptionsPlist ExportOptions.plist
   ```

2. Create a DMG file:
   ```bash
   # Install create-dmg if you don't have it
   brew install create-dmg

   # Create the DMG
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

### Step 2: Calculate SHA256 Checksum

```bash
shasum -a 256 Harbor-0.1.0-alpha.dmg
```

Save this checksum - you'll need it for the cask formula.

### Step 3: Create GitHub Release

1. Go to: https://github.com/sriinnu/harbor/releases/new
2. Fill in the details:
   - **Tag version**: `v0.1.0-alpha`
   - **Release title**: `Harbor v0.1.0-alpha`
   - **Description**: Add release notes
   - **Attach**: Upload the `Harbor-0.1.0-alpha.dmg` file

3. Publish the release

### Step 4: Update the Cask Formula

1. Navigate to your tap repository:
   ```bash
   cd /path/to/homebrew-tap
   ```

2. Edit `Casks/harbor.rb` and replace:
   ```ruby
   sha256 :no_check
   ```

   With the actual SHA256:
   ```ruby
   sha256 "abc123def456..."  # Your actual checksum
   ```

3. Commit and push:
   ```bash
   git add Casks/harbor.rb
   git commit -m "Update Harbor to v0.1.0-alpha with SHA256 checksum"
   git push origin main
   ```

---

## Installation Instructions for Users

Once your tap is set up, users can install Harbor with:

```bash
# Add the tap
brew tap sriinnu/tap

# Install Harbor
brew install --cask harbor
```

Or in one command:
```bash
brew install --cask sriinnu/tap/harbor
```

### Updating Harbor

```bash
brew upgrade --cask harbor
```

### Uninstalling Harbor

```bash
# Standard uninstall
brew uninstall --cask harbor

# Complete removal including app data
brew uninstall --zap --cask harbor
```

---

## Updating the Cask for New Releases

When you release a new version of Harbor, follow these steps:

### 1. Build and Release the New Version

```bash
# Example for version 0.2.0
VERSION="0.2.0"

# Build and create DMG (see "Publishing Your First Release")
# Then upload to GitHub releases
```

### 2. Calculate the New SHA256

```bash
shasum -a 256 Harbor-${VERSION}.dmg
```

### 3. Update the Cask Formula

```bash
cd /path/to/homebrew-tap

# Edit Casks/harbor.rb
# Update version and sha256
```

Update these lines:
```ruby
version "0.2.0"                           # New version
sha256 "new_checksum_here"                # New SHA256
```

### 4. Commit and Push

```bash
git add Casks/harbor.rb
git commit -m "Update Harbor to v${VERSION}"
git push origin main
```

### 5. Test the Update

```bash
# Update the tap
brew update

# Upgrade Harbor
brew upgrade --cask harbor

# Verify the version
/Applications/Harbor.app/Contents/MacOS/Harbor --version
```

---

## Testing the Cask

Before publishing updates, always test your cask:

### Audit the Cask

```bash
brew audit --cask --online sriinnu/tap/harbor
```

This checks for:
- Proper cask syntax
- Valid URLs
- Correct formatting
- Common issues

### Style Check

```bash
brew style --fix Casks/harbor.rb
```

### Install Test

```bash
# Uninstall if already installed
brew uninstall --cask harbor

# Fresh install
brew install --cask --verbose --debug sriinnu/tap/harbor

# Verify installation
ls -la /Applications/Harbor.app
```

### Local Testing

Before pushing changes, test locally:

```bash
# Install from local file
brew install --cask /path/to/homebrew-tap/Casks/harbor.rb
```

---

## Troubleshooting

### Common Issues

#### Issue: SHA256 Mismatch
```
Error: SHA256 mismatch
Expected: abc123...
Actual: def456...
```

**Solution**: Recalculate the checksum and update the formula:
```bash
shasum -a 256 Harbor-0.1.0-alpha.dmg
# Update sha256 in Casks/harbor.rb
```

#### Issue: Download URL Not Found
```
Error: Download failed on Cask 'harbor'
```

**Solution**:
1. Verify the release exists on GitHub
2. Check the URL format in the cask matches: `https://github.com/sriinnu/harbor/releases/download/v0.1.0-alpha/Harbor-0.1.0-alpha.dmg`
3. Ensure the DMG filename matches exactly

#### Issue: App Not Found in DMG
```
Error: It seems the App source is not there
```

**Solution**: Ensure the DMG contains `Harbor.app` at the root level, not in a subfolder.

#### Issue: Version Mismatch
```
Warning: Version mismatch
```

**Solution**: Ensure the version in the cask formula matches the tag version (without the 'v' prefix).

### Useful Commands

```bash
# Check cask info
brew info --cask sriinnu/tap/harbor

# List all casks in tap
brew tap-info sriinnu/tap

# Force reinstall
brew reinstall --cask harbor

# Clean cache
brew cleanup --cask harbor
```

---

## Best Practices

1. **Always test locally** before pushing to the tap repository
2. **Use semantic versioning** (e.g., 1.0.0, 1.1.0, 2.0.0)
3. **Keep release notes** updated on GitHub releases
4. **Verify checksums** before each release
5. **Test on clean system** if possible
6. **Update README** with any breaking changes
7. **Tag releases** consistently (v1.0.0, v1.1.0, etc.)

---

## Automation Ideas

For future automation, consider:

1. **GitHub Actions** to automatically update the cask on release
2. **Automated checksum calculation** in CI/CD
3. **Automated DMG creation** on tag push
4. **Automated tap PR** creation on new releases

Example GitHub Action workflow (save as `.github/workflows/update-homebrew.yml` in Harbor repo):

```yaml
name: Update Homebrew Tap

on:
  release:
    types: [published]

jobs:
  update-tap:
    runs-on: macos-latest
    steps:
      - name: Checkout tap repository
        uses: actions/checkout@v4
        with:
          repository: sriinnu/homebrew-tap
          token: ${{ secrets.TAP_GITHUB_TOKEN }}

      - name: Get release info
        id: release
        run: |
          VERSION="${{ github.event.release.tag_name }}"
          echo "version=${VERSION#v}" >> $GITHUB_OUTPUT

      - name: Download and calculate SHA256
        id: sha
        run: |
          URL="https://github.com/sriinnu/harbor/releases/download/${{ github.event.release.tag_name }}/Harbor-${{ steps.release.outputs.version }}.dmg"
          curl -sL "$URL" -o harbor.dmg
          SHA=$(shasum -a 256 harbor.dmg | awk '{print $1}')
          echo "sha256=$SHA" >> $GITHUB_OUTPUT

      - name: Update cask formula
        run: |
          sed -i '' 's/version ".*"/version "${{ steps.release.outputs.version }}"/' Casks/harbor.rb
          sed -i '' 's/sha256 ".*"/sha256 "${{ steps.sha.outputs.sha256 }}"/' Casks/harbor.rb

      - name: Commit and push
        run: |
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add Casks/harbor.rb
          git commit -m "Update Harbor to v${{ steps.release.outputs.version }}"
          git push
```

---

## Additional Resources

- [Homebrew Cask Documentation](https://docs.brew.sh/Cask-Cookbook)
- [Creating Homebrew Taps](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
- [Homebrew Formula Cookbook](https://docs.brew.sh/Formula-Cookbook)
- [Homebrew Style Guide](https://docs.brew.sh/Homebrew-Cask-Style-Guide)

---

## Support

For issues with the Homebrew tap, please open an issue at:
https://github.com/sriinnu/harbor/issues
