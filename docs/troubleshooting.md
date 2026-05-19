# Harbor Troubleshooting Guide

This guide helps you diagnose and resolve common issues with Harbor.

## Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Authentication Issues](#authentication-issues)
- [Connection & Network Issues](#connection--network-issues)
- [Repository & Data Issues](#repository--data-issues)
- [Local Git Integration Issues](#local-git-integration-issues)
- [Performance Issues](#performance-issues)
- [UI & Display Issues](#ui--display-issues)
- [Platform-Specific Issues](#platform-specific-issues)
- [CLI Issues](#cli-issues)
- [Advanced Debugging](#advanced-debugging)

---

## Quick Diagnostics

Before diving into specific issues, try these quick checks:

### 1. Verify Harbor Version
```bash
# macOS
/Applications/Harbor.app/Contents/MacOS/harbor --version

# Windows
harbor --version
```

Ensure you're running the latest version from [releases](https://github.com/sriinnu/Harbor/releases/latest).

### 2. Check Authentication Status
```bash
harbor verify
```

If this fails, your GitHub token may be invalid or expired.

### 3. Check Internet Connection
```bash
# Test GitHub API access
curl -I https://api.github.com

# Should return: HTTP/2 200
```

### 4. Check Logs

**macOS**:
```bash
# View recent logs
log show --predicate 'processImagePath contains "Harbor"' --last 1h

# Stream live logs
log stream --predicate 'processImagePath contains "Harbor"' --level debug
```

**Windows**:
```powershell
# View event logs
Get-EventLog -LogName Application -Source Harbor -Newest 50

# Or check app data folder
explorer %APPDATA%\Harbor\logs
```

### 5. Restart Harbor

Sometimes the simplest solution works:
1. Quit Harbor completely
2. Wait 5 seconds
3. Launch Harbor again
4. Check if the issue persists

---

## Installation Issues

### macOS: "Harbor is damaged and can't be opened"

**Problem**: macOS Gatekeeper blocking unsigned app.

**Solution**:
```bash
# Remove quarantine attribute
xattr -cr /Applications/Harbor.app

# Or use GUI:
# System Preferences → Privacy & Security → "Open Anyway"
```

**Prevention**: Future releases will be properly notarized.

### macOS: "Harbor can't be installed because it is from an unidentified developer"

**Problem**: Gatekeeper security settings.

**Solutions**:

**Option 1 (Recommended)**:
1. Right-click Harbor.app in Applications
2. Select "Open"
3. Click "Open" in the dialog
4. This creates a security exception

**Option 2**:
```bash
# Temporarily allow apps from anywhere
sudo spctl --master-disable
# Install Harbor
# Re-enable protection
sudo spctl --master-enable
```

### macOS: Harbor won't launch after update

**Problem**: Cached data or permission issues.

**Solution**:
```bash
# Clear cache and preferences
rm -rf ~/Library/Caches/com.sriinnu.harbor
rm -rf ~/Library/Application\ Support/Harbor
rm ~/Library/Preferences/com.sriinnu.harbor.plist

# Relaunch Harbor
open /Applications/Harbor.app
```

### Windows: SmartScreen blocks installation

**Problem**: Installer not signed with code signing certificate.

**Solution**:
1. Click "More info" in SmartScreen dialog
2. Click "Run anyway"
3. Proceed with installation

**Alternative**:
```powershell
# Disable SmartScreen temporarily (not recommended)
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Off"
# Install Harbor
# Re-enable SmartScreen
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "SmartScreenEnabled" -Value "Warn"
```

### Windows: Installation fails with error code

**Common Error Codes**:

**Error 2502/2503**: Installer cannot write to temp folder
```powershell
# Run installer as administrator
Right-click Harbor-Windows-Setup.exe → Run as administrator
```

**Error 1603**: General installer failure
```powershell
# Clear Windows Installer cache
rd /s /q %TEMP%
# Try installation again
```

**Error 1722**: RPC server unavailable
```powershell
# Restart Windows Installer service
sc stop msiserver
sc start msiserver
# Retry installation
```

### Build from Source Fails

**macOS Build Errors**:

**Error**: "Command Line Tools not found"
```bash
# Install Xcode Command Line Tools
xcode-select --install
```

**Error**: "No such module 'Apollo'"
```bash
# Clean and rebuild dependencies
rm -rf .build
rm Package.resolved
swift package resolve
swift build
```

**Error**: Build fails with "Swift version mismatch"
```bash
# Check Swift version (need 6.0+)
swift --version

# Update Swift if needed
xcode-select --install
```

**Windows Build Errors**:

**Error**: "Rust not found"
```bash
# Install Rust
https://rustup.rs/
# Verify installation
rustc --version
cargo --version
```

**Error**: "Visual Studio Build Tools required"
```bash
# Install VS Build Tools with C++ workload
https://visualstudio.microsoft.com/downloads/
# Select "Desktop development with C++"
```

**Error**: npm install fails
```bash
# Clear npm cache
npm cache clean --force
# Delete node_modules
rm -rf node_modules
# Reinstall
npm install
```

---

## Authentication Issues

### Cannot Sign In - Browser Opens But Nothing Happens

**Problem**: OAuth callback not received.

**Diagnostic**:
```bash
# Check if port 53682 is available
# macOS:
lsof -i :53682

# Windows:
netstat -an | findstr "53682"
```

**Solutions**:

**If port is in use**:
```bash
# macOS: Find and kill the process
lsof -ti:53682 | xargs kill -9

# Windows: Find and kill the process
netstat -ano | findstr "53682"
taskkill /PID <PID> /F
```

**If port is blocked by firewall**:
- **macOS**: System Preferences → Security & Privacy → Firewall → Allow Harbor
- **Windows**: Windows Defender Firewall → Allow an app → Add Harbor

**If browser doesn't redirect**:
1. Check the URL in browser: Should redirect to `http://localhost:53682/callback?code=...`
2. If stuck on GitHub: Try a different browser
3. If redirects to error page: Copy the error message

### "Invalid OAuth Token" Error

**Problem**: Token expired or revoked.

**Solution**:
```bash
# Sign out and sign in again
harbor logout
harbor login
```

**If that doesn't work**:
1. Go to https://github.com/settings/applications
2. Find Harbor in "Authorized OAuth Apps"
3. Click "Revoke"
4. Sign in to Harbor again

### "Rate Limit Exceeded" Error

**Problem**: Too many GitHub API requests.

**Check Current Limit**:
```bash
curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/rate_limit
```

**Solutions**:

**Temporary** (wait for reset):
```bash
# Check when limit resets
harbor repos --json | jq '.rate_limit.reset'
# Returns Unix timestamp
```

**Permanent** (reduce API usage):
1. Settings → Advanced → Increase Refresh Interval to 10-15 minutes
2. Reduce number of pinned repositories
3. Hide repositories you don't actively monitor

### Cannot Authenticate with GitHub Enterprise

**Problem**: OAuth app not configured correctly.

**Checklist**:
1. ✓ GHE URL is correct (e.g., `https://github.company.com`)
2. ✓ OAuth app created in GHE (not GitHub.com)
3. ✓ Callback URL is exactly `http://localhost:53682/callback`
4. ✓ Client ID and Secret are from GHE OAuth app
5. ✓ Network can reach GHE server (not behind VPN/firewall)

**Test GHE Connectivity**:
```bash
# Test API access
curl -I https://github.company.com/api/v3

# Should return HTTP 200 or 301
```

### Token Stored in Keychain But Harbor Says "Not Authenticated"

**Problem**: Keychain access denied or corrupted.

**macOS Solution**:
```bash
# Open Keychain Access app
open /Applications/Utilities/Keychain\ Access.app

# Find "harbor" in search
# Check "Access Control" tab - should allow Harbor.app
# If not, delete and re-authenticate
```

**Windows Solution**:
```powershell
# Open Credential Manager
control keymgr.dll

# Find Harbor entry under "Generic Credentials"
# Delete it
# Sign in to Harbor again
```

---

## Connection & Network Issues

### "Cannot Connect to GitHub API" Error

**Diagnostic Steps**:

**1. Check Internet Connection**:
```bash
ping -c 3 api.github.com
```

**2. Check GitHub Status**:
Visit https://www.githubstatus.com/ to see if GitHub is experiencing issues.

**3. Test API Directly**:
```bash
curl -v https://api.github.com/zen

# Should return a zen quote
```

**4. Check DNS Resolution**:
```bash
nslookup api.github.com

# Should resolve to GitHub's IP addresses
```

**Solutions**:

**If DNS fails**:
```bash
# Try using Google DNS
# macOS: System Preferences → Network → Advanced → DNS → Add 8.8.8.8
# Windows: Network Settings → Change Adapter Options → IPv4 Properties → Use 8.8.8.8
```

**If firewall is blocking**:
- macOS: System Preferences → Security & Privacy → Firewall → Allow Harbor
- Windows: Windows Defender Firewall → Allow Harbor

**If proxy is required**:
```bash
# Set proxy environment variables
export HTTP_PROXY=http://proxy.company.com:8080
export HTTPS_PROXY=http://proxy.company.com:8080

# Launch Harbor from terminal
open /Applications/Harbor.app  # macOS
```

### Slow API Responses

**Problem**: GitHub API requests taking too long.

**Diagnostic**:
```bash
# Test API response time
time curl -H "Authorization: token YOUR_TOKEN" https://api.github.com/user

# Should complete in under 2 seconds
```

**Solutions**:

**If consistently slow**:
1. Check your internet speed
2. Check GitHub Status (https://www.githubstatus.com/)
3. Increase timeout in Settings → Advanced → API Timeout (default: 30s)

**If intermittent**:
1. Enable caching: Settings → Advanced → Cache → Enabled
2. Increase cache TTL: Settings → Advanced → Cache TTL (default: 300s)

### SSL/TLS Certificate Errors

**Problem**: Cannot verify GitHub's SSL certificate.

**Error Message**: "SSL certificate problem: unable to get local issuer certificate"

**macOS Solution**:
```bash
# Update root certificates
sudo security update-ca-certificates

# Restart Harbor
```

**Windows Solution**:
```powershell
# Update Windows certificates
certutil -generateSSTFromWU roots.sst
# Import using Certificates MMC
```

**Corporate Environment** (self-signed certs):
```bash
# Add company certificate to system trust store
# macOS: Keychain Access → System → Add certificate
# Windows: certmgr.msc → Trusted Root → Import
```

---

## Repository & Data Issues

### Repositories Not Appearing

**Problem**: Expected repositories don't show in Harbor.

**Diagnostic**:
```bash
# List all repositories
harbor repos --all --json

# Check if specific repo exists
harbor repos --all --json | jq '.[] | select(.name == "repo-name")'
```

**Common Causes**:

**1. Filter Settings**:
- Settings → Repositories → Show Forks (enable if repo is a fork)
- Settings → Repositories → Show Archived (enable if repo is archived)

**2. Access Permissions**:
- Ensure you have access to the repository on GitHub
- Check if it's a private repo requiring authentication
- Verify OAuth token has `repo` scope

**3. Organization Repositories**:
```bash
# Check if org access is granted
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/user/orgs

# Request org access if needed
# GitHub → Settings → Organizations → Grant Access
```

**4. Display Limit**:
- Settings → Repositories → Display Limit (increase to 12)

### Repository Data Not Updating

**Problem**: Stale data shown in Harbor.

**Quick Fix**:
```bash
# Manual refresh
# macOS: Cmd + R in Harbor menu
# Windows: Ctrl + R in Harbor menu

# Or from CLI
harbor repos --refresh
```

**If Manual Refresh Doesn't Work**:

**1. Clear Cache**:
- Settings → Advanced → Clear Cache
- Restart Harbor

**2. Check Refresh Interval**:
- Settings → Advanced → Refresh Interval
- Ensure it's not too high (recommend 5-10 minutes)

**3. Check Rate Limit**:
```bash
# If rate limited, data won't refresh
harbor repos --json | jq '.rate_limit'
```

### CI/CD Status Not Showing

**Problem**: No workflow status displayed.

**Checklist**:
1. ✓ Repository has GitHub Actions workflows
2. ✓ At least one workflow run exists
3. ✓ OAuth token has `repo` scope (includes Actions access)
4. ✓ Workflows are not disabled

**Diagnostic**:
```bash
# Check workflows via API
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/actions/workflows

# Check recent workflow runs
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/actions/runs
```

**If workflows exist but don't show**:
1. Check if workflows are in `.github/workflows/` directory
2. Ensure workflows have run at least once
3. Verify workflow files are valid YAML
4. Refresh Harbor (Cmd/Ctrl + R)

### Pull Requests or Issues Not Loading

**Problem**: PRs/Issues submenu is empty or shows errors.

**Diagnostic**:
```bash
# Check PRs via CLI
harbor pulls --repo OWNER/REPO

# Check issues via CLI
harbor issues --repo OWNER/REPO

# Check via API directly
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/repos/OWNER/REPO/pulls
```

**Solutions**:

**If API returns data but Harbor doesn't show it**:
1. Clear cache: Settings → Advanced → Clear Cache
2. Restart Harbor
3. Refresh manually

**If API returns errors**:
1. Check OAuth scopes (need `repo` for private repos)
2. Verify repository access on GitHub
3. Check if rate limited

---

## Local Git Integration Issues

### Local Repositories Not Detected

**Problem**: Harbor doesn't find your local Git repositories.

**Diagnostic**:
```bash
# Check configured projects folder
harbor config get projectsFolder

# List detected local projects
harbor local-projects

# Manually check if Git repos exist
cd ~/Projects  # or your projects folder
find . -name ".git" -type d
```

**Solutions**:

**1. Verify Projects Folder Path**:
- Settings → Repositories → Local Projects Folder
- Must be absolute path (e.g., `/Users/name/Projects`, not `~/Projects`)
- Folder must exist and be readable

**2. Check Folder Permissions**:
```bash
# macOS
ls -la ~/Projects

# Ensure Harbor has access
# System Preferences → Privacy & Security → Files and Folders → Grant access
```

**3. Verify Git Installation**:
```bash
# Check Git is installed
git --version

# Should return git version 2.x.x
```

**4. Check Repository Structure**:
```bash
# Each repo should have .git directory
ls -la ~/Projects/your-repo/.git

# Check remote URL
cd ~/Projects/your-repo
git remote -v

# Should show GitHub URL
```

### Local Repository Not Matched with GitHub Repository

**Problem**: Harbor finds local repo but doesn't match it with GitHub repo.

**Diagnostic**:
```bash
# Check remote URL
cd ~/Projects/your-repo
git remote -v

# Should show:
# origin  https://github.com/user/repo.git (fetch)
# or
# origin  git@github.com:user/repo.git (fetch)
```

**Solutions**:

**If remote URL is wrong**:
```bash
# Fix remote URL
git remote set-url origin https://github.com/user/repo.git

# Verify
git remote -v
```

**If remote name is not 'origin'**:
```bash
# Harbor looks for 'origin' or 'upstream'
# Rename remote if needed
git remote rename old-name origin

# Or add origin remote
git remote add origin https://github.com/user/repo.git
```

**If SSH URL is used**:
```bash
# Both HTTPS and SSH URLs should work
# But ensure format is correct:
# git@github.com:user/repo.git (SSH)
# https://github.com/user/repo.git (HTTPS)
```

### Auto-Sync Not Working

**Problem**: Repositories not syncing automatically.

**Diagnostic**:
```bash
# Check auto-sync settings
harbor config get autoSync
harbor config get syncInterval

# Try manual sync
harbor sync --repo repo-name
```

**Solutions**:

**1. Verify Auto-Sync is Enabled**:
- Settings → Repositories → Auto-Sync → Enabled

**2. Check Sync Interval**:
- Default: 900 seconds (15 minutes)
- Must be between 300-3600 seconds

**3. Ensure Repository is Clean**:
```bash
# Auto-sync only works on clean repos
cd ~/Projects/your-repo
git status

# Should say "working tree clean"
# If not, commit or stash changes
```

**4. Check for Merge Conflicts**:
```bash
# Harbor skips repos with conflicts
git status

# Resolve conflicts manually
git merge --abort  # or fix conflicts
```

**5. Review Logs**:
```bash
# macOS
log show --predicate 'processImagePath contains "Harbor"' --last 1h | grep -i sync

# Windows
Get-EventLog -LogName Application -Source Harbor | Where-Object {$_.Message -like "*sync*"}
```

### Git Status Shows Wrong Information

**Problem**: Branch, ahead/behind, or dirty status is incorrect.

**Diagnostic**:
```bash
# Check actual Git status
cd ~/Projects/your-repo
git status
git rev-list --left-right --count origin/main...HEAD
```

**Solutions**:

**1. Fetch Latest**:
```bash
# Harbor might be showing outdated remote state
git fetch origin

# Refresh Harbor
# Cmd/Ctrl + R
```

**2. Reset Repository Tracking**:
```bash
# Set upstream branch if not set
git branch --set-upstream-to=origin/main main

# Verify tracking
git branch -vv
```

**3. Clear Harbor Cache**:
- Settings → Advanced → Clear Cache
- Restart Harbor

---

## Performance Issues

### Harbor Uses Too Much CPU

**Problem**: High CPU usage, especially when idle.

**Diagnostic**:

**macOS**:
```bash
# Check CPU usage
ps aux | grep Harbor

# Use Activity Monitor for detailed view
open -a "Activity Monitor"
# Search for Harbor
```

**Windows**:
```powershell
# Check CPU usage
Get-Process harbor | Select-Object CPU,PM

# Use Task Manager for detailed view
taskmgr
```

**Solutions**:

**1. Reduce Refresh Frequency**:
- Settings → Advanced → Refresh Interval → Increase to 10-15 minutes

**2. Reduce Repository Count**:
- Unpin repositories you don't actively monitor
- Hide unused repositories

**3. Disable Auto-Sync**:
- Settings → Repositories → Auto-Sync → Disabled

**4. Check for Runaway Processes**:
```bash
# macOS: Kill stuck processes
pkill -9 Harbor

# Windows: Force quit from Task Manager
taskkill /IM harbor.exe /F
```

### Harbor Uses Too Much Memory

**Problem**: High memory usage (>500 MB).

**Diagnostic**:
```bash
# macOS
ps aux | grep Harbor | awk '{print $6/1024 " MB"}'

# Windows
Get-Process harbor | Select-Object PM | Format-Table @{Label="Memory (MB)"; Expression={$_.PM / 1MB}}
```

**Solutions**:

**1. Restart Harbor**:
```bash
# Quit and relaunch
# Memory should return to 80-150 MB (macOS) or 120-200 MB (Windows)
```

**2. Clear Cache**:
- Settings → Advanced → Clear Cache
- Restart Harbor

**3. Reduce Cache Size**:
- Settings → Advanced → Cache TTL → Lower to 60-120 seconds

**4. Limit Displayed Repositories**:
- Settings → Repositories → Display Limit → Reduce to 6 or fewer

### Slow Menu Opening

**Problem**: Menu takes several seconds to open.

**Solutions**:

**1. Enable Caching**:
- Settings → Advanced → Cache → Enabled
- Settings → Advanced → Cache TTL → 300 seconds

**2. Reduce Data Fetching**:
- Pin fewer repositories
- Increase refresh interval

**3. Use Compact Menu Density**:
- Settings → Appearance → Menu Density → Compact

**4. Disable Contribution Heatmap**:
- Settings → Appearance → Show Contribution Header → Hide

### API Rate Limit Reached Frequently

**Problem**: Constantly hitting GitHub's API rate limit.

**Diagnostic**:
```bash
# Check current rate limit status
curl -H "Authorization: token YOUR_TOKEN" \
  https://api.github.com/rate_limit

# Shows:
# - Limit: 5000 requests/hour
# - Remaining: how many left
# - Reset: when limit resets (Unix timestamp)
```

**Solutions**:

**1. Increase Refresh Interval**:
- Settings → Advanced → Refresh Interval → 15-30 minutes

**2. Reduce Repository Count**:
- Pin only actively monitored repos
- Hide inactive repositories

**3. Enable Aggressive Caching**:
- Settings → Advanced → Cache → Enabled
- Settings → Advanced → Cache TTL → 600 seconds (10 minutes)

**4. Check for Bugs**:
```bash
# Harbor should not make excessive requests
# If consistently hitting limit with few repos, report bug:
# https://github.com/sriinnu/Harbor/issues
```

---

## UI & Display Issues

### macOS: Harbor Icon Not Visible in Menu Bar

**Problem**: Menu bar icon missing.

**Solutions**:

**1. Menu Bar is Full**:
```bash
# macOS hides icons when menu bar is full
# Try: Quit other menu bar apps
# Or: Reduce screen resolution temporarily
# Or: Use a menu bar manager like Bartender
```

**2. Icon is Hidden**:
- Cmd + drag Harbor icon to visible area

**3. Harbor Not Running**:
```bash
# Check if running
ps aux | grep Harbor

# If not, launch it
open /Applications/Harbor.app
```

### Windows: Harbor Icon Not in System Tray

**Problem**: System tray icon missing.

**Solutions**:

**1. Show Hidden Icons**:
- Click the up arrow (^) in system tray
- Harbor icon should appear

**2. Pin to System Tray**:
- Click ^ in system tray
- Drag Harbor icon to visible area

**3. Harbor Not Running**:
```powershell
# Check if running
Get-Process harbor

# If not, launch it
Start-Process harbor
```

### UI Elements Not Rendering Correctly

**Problem**: Garbled text, missing graphics, or display glitches.

**macOS Solutions**:

**1. Reset Window Position**:
```bash
# Delete preferences
rm ~/Library/Preferences/com.sriinnu.harbor.plist

# Restart Harbor
```

**2. Check macOS Version**:
```bash
sw_vers

# Harbor requires macOS 15.0+
```

**3. Restart Display Server**:
```bash
# Restart WindowServer (warning: closes all windows)
sudo killall -HUP WindowServer
```

**Windows Solutions**:

**1. Reset UI Settings**:
```powershell
# Delete settings
Remove-Item $env:APPDATA\Harbor\settings.json

# Restart Harbor
```

**2. Update Graphics Drivers**:
```powershell
# Check Windows Update for driver updates
# Or download from manufacturer (NVIDIA, AMD, Intel)
```

### Dark/Light Mode Not Working

**Problem**: Theme doesn't match system or won't change.

**Solutions**:

**1. Check Theme Setting**:
- Settings → Appearance → Theme → Auto
- Manually switch to test: Light, Dark, Auto

**2. macOS - Reset Theme**:
```bash
# System Preferences → General → Appearance
# Toggle between Light and Dark
# Harbor should follow
```

**3. Windows - Reset Theme**:
```powershell
# Settings → Personalization → Colors
# Toggle between Light and Dark
# Harbor should follow (if theme is Auto)
```

**4. Force Restart**:
```bash
# Quit Harbor
# Change system theme
# Launch Harbor
```

### Liquid Glass Effect Not Showing

**Problem**: Background doesn't have frosted glass effect.

**Solutions**:

**1. Check System Settings**:
- **macOS**: System Preferences → Accessibility → Display → Reduce Transparency → OFF
- **Windows**: Settings → Personalization → Colors → Transparency effects → ON

**2. Graphics Requirements**:
- macOS: Requires Metal-capable GPU
- Windows: Requires Windows 10 1903+ or Windows 11

**3. Restart Harbor**:
- Quit and relaunch to reinitialize rendering

---

## Platform-Specific Issues

### macOS: Keychain Access Denied

**Problem**: Harbor can't access Keychain to store/retrieve token.

**Error**: "Keychain access denied" or "Cannot save credentials"

**Solution**:
```bash
# Grant Keychain access
security unlock-keychain ~/Library/Keychains/login.keychain-db

# Or reset Keychain Access Control for Harbor
# Open Keychain Access.app
# Find "harbor" entry
# Double-click → Access Control tab
# Add Harbor.app to allowed applications
```

### macOS: Permission Dialogs Keep Appearing

**Problem**: Repeated permission prompts for network, keychain, etc.

**Solution**:
```bash
# Reset privacy database
tccutil reset All com.sriinnu.harbor

# Restart Harbor
# Grant all permissions when prompted (once)
```

### macOS: Harbor Crashes on Launch

**Problem**: App crashes immediately after opening.

**Diagnostic**:
```bash
# View crash logs
open ~/Library/Logs/DiagnosticReports/

# Look for Harbor*.crash or Harbor*.ips files
```

**Solutions**:

**1. Check macOS Version**:
```bash
sw_vers
# Need macOS 15.0+ (Sequoia)
```

**2. Reinstall Harbor**:
```bash
# Delete app
rm -rf /Applications/Harbor.app

# Clear app data
rm -rf ~/Library/Application\ Support/Harbor
rm -rf ~/Library/Caches/com.sriinnu.harbor

# Download and install fresh copy
```

### Windows: Credential Manager Issues

**Problem**: Cannot save or retrieve GitHub token.

**Solution**:
```powershell
# Open Credential Manager
control keymgr.dll

# Find Harbor entry under "Generic Credentials"
# If it exists but doesn't work, delete it and sign in again

# Check if Credential Manager service is running
Get-Service -Name "VaultSvc"

# If stopped, start it
Start-Service -Name "VaultSvc"
```

### Windows: Tray Icon Context Menu Not Working

**Problem**: Right-click on tray icon doesn't show menu.

**Solution**:
```powershell
# Restart Windows Explorer
taskkill /F /IM explorer.exe
Start-Process explorer.exe

# Or restart Harbor
taskkill /IM harbor.exe /F
Start-Process harbor
```

### Windows: WSL Repositories Not Detected

**Problem**: Repositories in WSL filesystem not found.

**Current Limitation**: Harbor cannot directly access WSL-only paths (e.g., `/home/user/projects`).

**Workaround**:
```bash
# Clone repos to Windows-accessible location
# WSL can access: /mnt/c/Users/YourName/Projects
cd /mnt/c/Users/$USER/Projects
git clone https://github.com/user/repo.git

# Set Harbor projects folder to: C:\Users\YourName\Projects
```

**Future**: Full WSL integration is planned for a future release.

---

## CLI Issues

### CLI Not Found / Command Not Recognized

**macOS**:
```bash
# Add to PATH
sudo ln -s /Applications/Harbor.app/Contents/MacOS/harbor /usr/local/bin/harbor

# Verify
which harbor
harbor --version
```

**Windows**:
```powershell
# Check if in PATH
where harbor

# If not found, add to PATH:
# Control Panel → System → Advanced → Environment Variables
# Add: C:\Program Files\Harbor to PATH

# Or use full path:
& "C:\Program Files\Harbor\harbor.exe" --version
```

### CLI: "Not Authenticated" Error

**Problem**: CLI can't find GitHub token.

**Diagnostic**:
```bash
harbor verify
```

**Solution**:
```bash
# Sign in via CLI
harbor login

# Or verify GUI app is signed in
# Token is shared between GUI and CLI
```

### CLI: JSON Output Malformed

**Problem**: `harbor repos --json` returns invalid JSON.

**Diagnostic**:
```bash
# Validate JSON
harbor repos --json | jq .

# If error, check for:
# - Trailing commas
# - Unescaped quotes in repo names
# - Truncated output
```

**Solutions**:

**1. Use Plain Output**:
```bash
# If JSON is broken, use plain mode
harbor repos --plain
```

**2. Report Bug**:
```bash
# If consistently malformed, report issue:
# https://github.com/sriinnu/Harbor/issues
# Include: harbor version, OS, sample output
```

### CLI: Commands Hang/Timeout

**Problem**: CLI commands take too long or never complete.

**Solutions**:

**1. Check Network**:
```bash
# Test GitHub API
curl -I https://api.github.com
```

**2. Increase Timeout**:
```bash
# Not yet configurable in CLI
# Workaround: Use GUI settings to increase API timeout
```

**3. Check Rate Limit**:
```bash
harbor repos --json | jq '.rate_limit'
```

---

## Advanced Debugging

### Enable Debug Logging

**macOS**:
```bash
# Enable debug logging
defaults write com.sriinnu.harbor EnableDebugLogging -bool true

# Restart Harbor
killall Harbor
open /Applications/Harbor.app

# View debug logs
log stream --predicate 'processImagePath contains "Harbor"' --level debug

# Disable when done
defaults delete com.srinivaspendela.athena.harbor EnableDebugLogging
```

**Windows**:
```powershell
# Set debug environment variable
$env:RUST_LOG="debug"
$env:HARBOR_DEBUG="1"

# Launch Harbor
Start-Process harbor

# View logs in Event Viewer
eventvwr
# Windows Logs → Application → Filter by Source: Harbor
```

### Capture Network Traffic

**macOS**:
```bash
# Capture HTTP traffic to/from GitHub
sudo tcpdump -i any -w harbor-traffic.pcap host api.github.com

# Stop with Ctrl+C
# Analyze with Wireshark
wireshark harbor-traffic.pcap
```

**Windows**:
```powershell
# Use Fiddler or Wireshark
# Configure Harbor to use proxy (if needed)
$env:HTTP_PROXY="http://localhost:8888"
$env:HTTPS_PROXY="http://localhost:8888"
Start-Process harbor
```

### Inspect GraphQL Queries

Harbor uses GitHub's GraphQL API. To see exact queries:

**Method 1: Enable Debug Logging** (see above)

**Method 2: Network Inspection**:
```bash
# macOS: Use Charles Proxy or Proxyman
# Windows: Use Fiddler

# Look for POST requests to https://api.github.com/graphql
# Request body contains the GraphQL query
```

**Method 3: Check Source Code**:
```bash
# Clone Harbor repo
git clone https://github.com/sriinnu/Harbor.git
cd Harbor

# GraphQL queries are in:
# Sources/HarborCore/GraphQL/
```

### Reset Harbor to Factory Defaults

**macOS**:
```bash
# Quit Harbor
killall Harbor

# Delete all data
rm -rf ~/Library/Application\ Support/Harbor
rm -rf ~/Library/Caches/com.sriinnu.harbor
rm ~/Library/Preferences/com.sriinnu.harbor.plist

# Delete token from Keychain
security delete-generic-password -s "harbor" -a "github"

# Relaunch Harbor
open /Applications/Harbor.app
```

**Windows**:
```powershell
# Quit Harbor
taskkill /IM harbor.exe /F

# Delete all data
Remove-Item -Recurse -Force $env:APPDATA\Harbor
Remove-Item -Recurse -Force $env:LOCALAPPDATA\Harbor

# Delete token from Credential Manager
cmdkey /delete:LegacyGeneric:target=harbor

# Relaunch Harbor
Start-Process harbor
```

### Report a Bug

If none of these solutions work, please report a bug:

**Information to Include**:
1. Harbor version (`harbor --version`)
2. Operating system and version
3. Steps to reproduce
4. Expected vs actual behavior
5. Logs (see "Enable Debug Logging" above)
6. Screenshots (if UI issue)

**Where to Report**:
- GitHub Issues: https://github.com/sriinnu/Harbor/issues/new
- Include label: `bug`

**Before Reporting**:
1. Search existing issues
2. Verify you're on latest version
3. Try factory reset (see above)

---

## Still Having Issues?

If this guide doesn't solve your problem:

1. **Search GitHub Issues**: https://github.com/sriinnu/Harbor/issues
2. **Ask in Discussions**: https://github.com/sriinnu/Harbor/discussions
3. **Check FAQ**: [docs/faq.md](faq.md)
4. **Open an Issue**: https://github.com/sriinnu/Harbor/issues/new

Include:
- Harbor version
- Operating system
- What you've already tried
- Debug logs (if applicable)

We're here to help!
