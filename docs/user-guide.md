# Harbor User Guide

Welcome to Harbor! This comprehensive guide will help you get started and make the most of Harbor's features.

## Table of Contents

1. [Introduction](#introduction)
2. [Installation](#installation)
3. [Getting Started](#getting-started)
4. [Core Features](#core-features)
5. [Configuration](#configuration)
6. [CLI Usage](#cli-usage)
7. [Advanced Features](#advanced-features)
8. [Tips & Best Practices](#tips--best-practices)

---

## Introduction

Harbor is a native menu bar/system tray application that provides a calm, glanceable view of your GitHub repositories. Think of it as your home port for GitHub work - everything important in one place, always in sight, never noisy.

### What Harbor Does

- Displays live CI/CD status for your repositories
- Shows recent commits, pull requests, and issues
- Tracks releases and version information
- Syncs with your local Git repositories
- Provides a powerful CLI for automation
- Offers a beautiful liquid glass interface

### What Harbor Doesn't Do

Harbor is intentionally focused:
- Not a project management tool
- Not a code review platform
- Not a notification engine
- Not a communication app

It's designed to help you stay in flow without constant interruptions.

---

## Installation

### macOS

#### Method 1: Homebrew (Recommended)

The easiest way to install Harbor on macOS:

```bash
brew install --cask sriinnu/tap/harbor
```

To update Harbor later:
```bash
brew upgrade --cask harbor
```

#### Method 2: Direct Download

1. Visit the [releases page](https://github.com/sriinnu/Harbor/releases/latest)
2. Download `Harbor-macOS.dmg`
3. Open the DMG file
4. Drag Harbor.app to your Applications folder
5. Launch Harbor from Applications

**First Launch Security**:
On first launch, you may see a security prompt because the app is not yet notarized:
1. Go to System Preferences → Privacy & Security
2. Scroll down to the "Security" section
3. Click "Open Anyway" next to the Harbor message
4. This is a one-time step

#### Method 3: Build from Source

**Requirements**:
- macOS 15.0+ (Sequoia or later)
- Xcode 16.2+
- Swift 6.0+
- Command Line Tools: `xcode-select --install`

**Steps**:
```bash
# Clone the repository
git clone https://github.com/sriinnu/Harbor.git
cd Harbor

# Build using the provided script
./Scripts/build.sh

# Run the built app
open build/macos/Build/Products/Debug/Harbor.app
```

### Windows

#### Method 1: Download Installer (Recommended)

1. Visit the [releases page](https://github.com/sriinnu/Harbor/releases/latest)
2. Download `Harbor-Windows-Setup.exe`
3. Run the installer
4. Harbor will appear in your system tray after installation
5. Click the tray icon to get started

**First Launch Security**:
Windows may show a SmartScreen warning:
1. Click "More info"
2. Click "Run anyway"
3. This is a one-time step

#### Method 2: Build from Source

**Requirements**:
- Windows 10 (1809+) or Windows 11
- [Rust](https://rustup.rs/) (latest stable - 1.70+)
- [Node.js](https://nodejs.org/) 18+ (LTS recommended)
- [Visual Studio Build Tools](https://visualstudio.microsoft.com/downloads/) 2019 or later with "Desktop development with C++" workload

**Steps**:
```bash
# Clone the repository
git clone https://github.com/sriinnu/Harbor.git
cd Harbor/harbor-windows

# Install dependencies
npm install

# Build for production
npm run tauri build

# The installer will be in:
# src-tauri/target/release/bundle/nsis/Harbor_x.x.x_x64-setup.exe
```

---

## Getting Started

### Step 1: Launch Harbor

- **macOS**: Harbor appears in your menu bar (top-right corner)
- **Windows**: Harbor appears in your system tray (bottom-right corner)

Look for the Harbor anchor icon.

### Step 2: Sign In with GitHub

Harbor uses OAuth 2.0 for secure authentication.

1. Click the Harbor icon in your menu bar/tray
2. Click "Sign In with GitHub"
3. Your browser will open to GitHub's authorization page
4. Review the permissions Harbor is requesting:
   - Read repository information (repos, issues, PRs)
   - Read user profile (username, avatar)
   - Read notifications
5. Click "Authorize Harbor"
6. Browser redirects to `http://localhost:53682/callback`
7. Harbor will close the browser and confirm sign-in

**Security Notes**:
- Your token is stored securely:
  - **macOS**: In the macOS Keychain
  - **Windows**: In Windows Credential Manager
- Harbor never logs or transmits your token
- Your token never leaves your device
- You can revoke access anytime from GitHub settings

#### Using GitHub Enterprise

If you're using GitHub Enterprise Server:

1. Go to Harbor Settings → Advanced
2. Enable "Use custom GitHub server"
3. Enter your GHE server URL (e.g., `https://github.yourcompany.com`)
4. Create an OAuth App in your GHE instance:
   - Go to Settings → Developer Settings → OAuth Apps
   - Click "New OAuth App"
   - **Application Name**: Harbor (Your Machine)
   - **Homepage URL**: `http://localhost`
   - **Callback URL**: `http://localhost:53682/callback`
5. Copy the Client ID and Client Secret
6. Enter them in Harbor settings
7. Click "Sign In"

### Step 3: Pin Your Repositories

After signing in, you'll see your repositories:

1. **Browse**: Scroll through your repository list
2. **Search**: Use the search box to filter repositories
3. **Pin**: Click the pin icon next to important repositories
4. Pinned repositories appear at the top of your menu
5. Customize sorting in Settings (by activity, name, stars, etc.)

**Tips for Pinning**:
- Pin repositories you check frequently
- Pin active projects with CI/CD pipelines
- Pin repos with upcoming releases
- You can pin up to 12 repositories for quick access

### Step 4: Configure Local Projects (Optional)

Connect Harbor to your local Git repositories:

1. Click the Harbor icon → Settings (gear icon)
2. Navigate to "Repositories" section
3. Set "Local Projects Folder":
   - **macOS**: `~/Projects`, `~/Developer`, `~/Code`, etc.
   - **Windows**: `C:\Users\YourName\Projects`, `D:\Code`, etc.
4. Harbor will scan and match repositories automatically
5. You'll see local Git status alongside GitHub data

**What You'll See**:
- Current branch
- Commits ahead/behind remote
- Uncommitted changes indicator
- Quick actions: Open in Finder/Explorer, Terminal/CMD

---

## Core Features

### Live Repository Cards

Each repository card shows:

**Status Indicators**:
- CI/CD status (passing, failing, pending)
- Release version and date
- Open pull requests count
- Open issues count

**Quick Actions**:
- Open in browser
- View pull requests
- View issues
- View releases
- Open locally (if matched)

**Visual Cues**:
- Green checkmark: CI passing
- Red X: CI failing
- Yellow dot: CI pending
- Gray: No CI configured

### Rich Submenus

Click on any repository to access detailed submenus:

#### Pull Requests Submenu
- Lists all open PRs
- Shows PR status (approved, changes requested, pending)
- Displays review status
- Shows CI/CD check status
- Click to open in browser

#### Issues Submenu
- Lists open issues
- Shows labels, assignees, milestones
- Filters: open, closed, all
- Author filter available
- Click to open in browser

#### Releases Submenu
- Shows all releases (latest first)
- Version numbers and dates
- Release notes preview
- Download assets
- Compare versions

#### Workflow Runs Submenu
- Recent CI/CD pipeline runs
- Status of each workflow
- Run duration
- Triggered by info
- Click to view logs

#### Commits Submenu
- Recent commit history
- Author and message
- Commit SHA (short)
- Time ago
- Click to view diff

### Global Activity Feed

Track your contribution activity:

**Contribution Heatmap**:
- Visual calendar of your GitHub activity
- Color intensity shows activity level
- Hover for daily details
- Configurable time ranges (7/30/90 days, year)

**Per-Repository Graphs**:
- Activity trends for each repo
- Commit frequency
- PR and issue activity
- Customizable date ranges

**Activity Breakdown**:
- Total commits
- Pull requests created/merged
- Issues opened/closed
- Code reviews completed

### Local Git State Integration

When you configure a local projects folder, Harbor shows:

**Branch Information**:
- Current branch name
- Upstream tracking branch
- Branch status

**Sync Status**:
- Commits ahead of remote (unpushed)
- Commits behind remote (need pull)
- Clean/dirty working tree
- Untracked files indicator

**Quick Actions**:
- Open in Finder/Explorer
- Open in Terminal/CMD
- Pull from remote
- Push to remote
- Sync (pull + push)

**Auto-Sync Feature**:
- Enable in Settings → Repositories
- Automatically pulls updates
- Only syncs clean repositories
- Fast-forward merges only (safe)
- Never force-pulls or overwrites
- Configurable interval (default: 15 minutes)

### Smart Organization

**Pinning**:
- Pin important repos to the top
- Drag to reorder (custom sort)
- Up to 12 pinned repos

**Hiding**:
- Hide repositories you don't need
- Reduces clutter
- Hidden repos still accessible via search

**Filtering**:
- Show/hide forked repositories
- Show/hide archived repositories
- Filter by owner, language, topics

**Sorting Options**:
- By activity (most recent first)
- By name (alphabetical)
- By stars (most starred first)
- By last updated
- Custom order (manual drag)

**Search**:
- Fast repository search
- Search by name or description
- Filter as you type

---

## Configuration

Harbor stores settings in:
- **macOS**: `~/Library/Application Support/Harbor/settings.json`
- **Windows**: `%APPDATA%\Harbor\settings.json`

### General Settings

**Launch at Login**:
- Auto-start Harbor when you log in
- Default: Disabled
- Location: Settings → General

**Theme**:
- Light: Always use light theme
- Dark: Always use dark theme
- Auto: Follow system theme
- Default: Auto

**Menu Density**:
- Compact: More repos visible, less spacing
- Comfortable: Easier to read, more spacing
- Default: Comfortable

### Repository Settings

**Display Limit**:
- How many repos to show in the menu
- Options: 3, 6, 9, 12
- Default: 9
- Pinned repos don't count toward limit

**Sort Order**:
- Activity: Most recently active first
- Name: Alphabetical
- Stars: Most starred first
- Updated: Recently updated first
- Custom: Manual drag-and-drop order
- Default: Activity

**Fork Filtering**:
- Show forked repositories: On/Off
- Default: Off

**Archive Filtering**:
- Show archived repositories: On/Off
- Default: Off

### Sync Settings

**Local Projects Folder**:
- Path to your local Git repositories
- Harbor scans this folder recursively
- Example: `~/Projects`, `C:\Users\YourName\Code`

**Auto-Sync**:
- Enable automatic repository syncing
- Default: Disabled
- Recommended for active projects

**Sync Interval**:
- How often to sync (in seconds)
- Range: 300-3600 (5 minutes to 1 hour)
- Default: 900 (15 minutes)

**Sync Notifications**:
- Show notifications on successful sync
- Show warnings on conflicts/errors
- Default: Errors only

### Appearance Settings

**Show Contribution Header**:
- Display global contribution heatmap
- Options: Show, Hide, Pinned repos only
- Default: Show

**Activity Scope**:
- All: All repositories
- Pinned: Only pinned repositories
- Owned: Only repositories you own
- Default: All

**Heatmap Time Range**:
- 7 days, 30 days, 90 days, or year
- Default: 30 days

### Advanced Settings

**API Settings**:
- Refresh interval (default: 300 seconds / 5 minutes)
- Request timeout (default: 30 seconds)
- Max retries (default: 3)

**Cache Settings**:
- Enable caching (recommended)
- Cache TTL (default: 300 seconds)

**Custom OAuth Credentials**:
- Use your own OAuth app
- Required for corporate environments
- See "Authentication" section for setup

**GitHub Enterprise**:
- Use custom GitHub server
- Enter server URL
- Provide OAuth app credentials

---

## CLI Usage

Harbor includes a powerful command-line interface for automation and scripting.

### Installation

**macOS**:
```bash
# Add to PATH (one-time setup)
sudo ln -s /Applications/Harbor.app/Contents/MacOS/harbor /usr/local/bin/harbor

# Verify
harbor --version
```

**Windows**:
```bash
# Available in PATH automatically after install
harbor --version
```

### Authentication Commands

```bash
# Sign in with GitHub OAuth
harbor login

# Check authentication status
harbor verify

# Sign out and clear tokens
harbor logout
```

### Repository Commands

```bash
# List pinned repositories
harbor repos

# List all repositories
harbor repos --all

# Show repositories with release info
harbor repos --releases

# JSON output (for scripting)
harbor repos --json

# Plain text output (no colors/links)
harbor repos --plain
```

### Issue Commands

```bash
# List issues across pinned repos
harbor issues

# Issues for specific repository
harbor issues --repo owner/repo

# Filter by state
harbor issues --state open     # or closed, all
harbor issues --state closed

# Filter by author
harbor issues --author username

# Combine filters
harbor issues --repo owner/repo --state open --author myusername
```

### Pull Request Commands

```bash
# List PRs across pinned repos
harbor pulls

# PRs for specific repository
harbor pulls --repo owner/repo

# Filter by state
harbor pulls --state open      # or closed, all

# Filter by author
harbor pulls --author username

# Show PR details with JSON
harbor pulls --json
```

### Local Project Commands

```bash
# List local Git repositories
harbor local-projects

# Include Git status for each
harbor local-projects --status

# JSON output
harbor local-projects --json

# Example output shows:
# - Repository name
# - Current branch
# - Commits ahead/behind
# - Dirty status
```

### Sync Commands

```bash
# Sync all local repositories
harbor sync

# Sync specific repository
harbor sync --repo repository-name

# Fetch all repositories (no merge)
harbor fetch

# Fetch specific repository
harbor fetch --repo repository-name
```

### Configuration Commands

```bash
# Show current configuration
harbor config list

# Set configuration value
harbor config set key value

# Examples:
harbor config set theme dark
harbor config set refreshInterval 600

# Get configuration value
harbor config get theme
```

### Utility Commands

```bash
# Open repository in browser
harbor open owner/repo

# Clone repository to projects folder
harbor clone owner/repo

# Show help
harbor --help

# Command-specific help
harbor repos --help
harbor issues --help
```

### Scripting Examples

**Check for Failing CI**:
```bash
harbor repos --json | jq '.[] | select(.ci_status == "failed") | .name'
```

**List Repos with Open PRs**:
```bash
harbor pulls --state open --json | jq -r '.[] | .repository' | sort | uniq
```

**Find Repos Needing Sync**:
```bash
harbor local-projects --status --json | \
  jq '.[] | select(.ahead > 0 or .behind > 0)'
```

**Auto-Sync Script**:
```bash
#!/bin/bash
# sync-all.sh - Sync all repositories that are behind

REPOS=$(harbor local-projects --status --json | \
  jq -r '.[] | select(.behind > 0 and .dirty == false) | .name')

for repo in $REPOS; do
  echo "Syncing $repo..."
  harbor sync --repo "$repo"
  if [ $? -eq 0 ]; then
    echo "  ✓ Synced successfully"
  else
    echo "  ✗ Sync failed"
  fi
done
```

**Daily Report Script**:
```bash
#!/bin/bash
# daily-report.sh - Generate daily GitHub activity report

echo "=== Harbor Daily Report ==="
echo "Date: $(date)"
echo ""

echo "📊 Repository Summary:"
harbor repos --plain | head -10

echo ""
echo "🔥 Open Pull Requests:"
harbor pulls --state open --plain | wc -l

echo ""
echo "🐛 Open Issues:"
harbor issues --state open --plain | wc -l

echo ""
echo "🔄 Repositories Needing Sync:"
harbor local-projects --status --json | \
  jq -r '.[] | select(.behind > 0) | .name'
```

---

## Advanced Features

### Auto-Sync Configuration

Auto-sync keeps your local repositories up-to-date automatically:

**How It Works**:
1. Harbor checks configured interval (default: 15 minutes)
2. Scans local projects folder for Git repositories
3. Checks each repo's sync status (ahead/behind)
4. Syncs repositories that are behind and clean
5. Skips dirty repos (uncommitted changes)
6. Shows notifications for results

**Safety Features**:
- Only fast-forward merges (safe pulls)
- Never force-pulls or overwrites
- Skips repos with uncommitted changes
- Respects .gitignore and Git config
- Alerts on merge conflicts

**Configuration**:
1. Settings → Repositories → Auto-Sync
2. Enable "Auto-sync local repositories"
3. Set sync interval (15-60 minutes recommended)
4. Choose notification preferences:
   - All syncs (verbose)
   - Errors only (recommended)
   - Silent (no notifications)

**Best Practices**:
- Start with a longer interval (30+ minutes)
- Monitor notifications for conflicts
- Disable for repos with frequent local changes
- Use with clean, tracking branches

### Contribution Heatmap

Visual representation of your GitHub activity:

**Features**:
- Color-coded activity levels
- Daily contribution counts
- Hover for detailed stats
- Configurable time ranges

**Configuration**:
1. Settings → Appearance
2. "Show contribution heatmap": On/Off
3. "Heatmap time range": 7 days, 30 days, 90 days, year
4. "Activity scope": All repos, Pinned only, Owned only

**Understanding Colors**:
- No color: No activity
- Light green: 1-3 contributions
- Medium green: 4-7 contributions
- Dark green: 8+ contributions

### Keyboard Shortcuts

**macOS**:
- `Cmd + ,`: Open Settings
- `Cmd + R`: Refresh repositories
- `Cmd + F`: Focus search
- `Cmd + W`: Close menu
- `Cmd + Q`: Quit Harbor

**Windows**:
- `Ctrl + ,`: Open Settings
- `Ctrl + R`: Refresh repositories
- `Ctrl + F`: Focus search
- `Alt + F4`: Close menu
- `Ctrl + Q`: Quit Harbor

### Custom OAuth App

For corporate environments or custom setups:

1. Go to [GitHub Settings → Developer Settings → OAuth Apps](https://github.com/settings/developers)
2. Click "New OAuth App"
3. Fill in:
   - **Application Name**: Harbor (Your Machine)
   - **Homepage URL**: `http://localhost`
   - **Authorization callback URL**: `http://localhost:53682/callback`
4. Click "Register application"
5. Copy Client ID and generate Client Secret
6. In Harbor Settings → Advanced:
   - Enable "Use custom OAuth credentials"
   - Enter Client ID and Client Secret
   - Save and restart Harbor
7. Sign in again

**Why Use Custom OAuth?**:
- Corporate policies requiring app approval
- Audit API usage under your own app
- Testing OAuth flow changes
- Isolated from Harbor's default OAuth app

---

## Tips & Best Practices

### Repository Management

**Pin Strategically**:
- Pin your most active projects
- Pin repos with CI/CD you monitor
- Pin repositories with frequent releases
- Don't pin archived or inactive repos

**Use Hiding Effectively**:
- Hide forks you don't maintain
- Hide old archived repositories
- Hide experimental or one-off repos
- Keep your view focused on active work

**Organize with Sorting**:
- Use "Activity" sort for dynamic view
- Use "Name" sort for alphabetical order
- Use "Custom" sort for manual control
- Switch based on your workflow

### Performance Optimization

**Reduce API Calls**:
- Set appropriate refresh interval (5-10 minutes)
- Pin only repos you actively monitor
- Hide repositories you don't need
- Use cache (enabled by default)

**Local Sync Efficiency**:
- Set projects folder to specific directory, not home folder
- Exclude large nested directories
- Use longer sync intervals for stable projects
- Disable auto-sync if you prefer manual control

**Menu Responsiveness**:
- Limit displayed repos to 9 or fewer
- Use compact menu density if needed
- Enable caching for faster loads
- Close menu when not in use

### Workflow Integration

**Morning Routine**:
1. Open Harbor menu
2. Check CI status for pinned repos
3. Review overnight PR activity
4. Sync local repositories
5. Address any failing builds

**Before Commits**:
1. Check local repo status in Harbor
2. Verify you're on correct branch
3. Ensure you're up-to-date with remote
4. Check for conflicts before pushing

**Release Monitoring**:
1. Pin repos with dependencies you track
2. Enable release notifications
3. Review release notes in Harbor
4. Update your projects when needed

**CLI Automation**:
1. Create daily report script
2. Auto-sync script before work hours
3. CI status check in pre-commit hook
4. Issue/PR reports for standup meetings

### Privacy & Security

**Token Management**:
- Tokens stored in OS-native secure storage
- Never share your token or OAuth credentials
- Revoke old tokens from GitHub settings
- Use custom OAuth app for corporate environments

**Data Privacy**:
- Harbor doesn't collect analytics
- No tracking or telemetry
- All data stays on your device
- Open source for transparency

**Best Practices**:
- Use GitHub's fine-grained personal access tokens when available
- Regularly audit authorized applications
- Enable two-factor authentication on GitHub
- Keep Harbor updated for security patches

### Troubleshooting Quick Checks

**Harbor Won't Launch**:
- Check System Preferences → Privacy & Security
- Grant necessary permissions (network, keychain)
- Restart your computer
- Reinstall Harbor

**Can't Sign In**:
- Check internet connection
- Verify port 53682 is not in use
- Check firewall settings
- Try custom OAuth app

**Slow Performance**:
- Reduce refresh interval
- Lower display limit
- Clear cache (Settings → Advanced → Clear Cache)
- Hide unused repositories

**Local Sync Not Working**:
- Verify projects folder path is correct
- Check folder permissions
- Ensure Git is installed
- Check Git repository is valid

**Missing Repositories**:
- Check filter settings (forks, archived)
- Verify you have access on GitHub
- Refresh manually (Cmd/Ctrl + R)
- Sign out and sign in again

---

## Next Steps

Now that you're familiar with Harbor:

1. **Explore the CLI**: Try `harbor repos --help` to discover automation options
2. **Join the Community**: Visit [GitHub Discussions](https://github.com/sriinnu/Harbor/discussions)
3. **Report Issues**: Found a bug? [Open an issue](https://github.com/sriinnu/Harbor/issues)
4. **Read the FAQ**: Check [docs/faq.md](faq.md) for common questions
5. **Troubleshooting**: See [docs/troubleshooting.md](troubleshooting.md) for solutions

**Happy Harboring!**

Your GitHub work, safely docked in the menu bar.
