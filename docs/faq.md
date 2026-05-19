# Harbor FAQ (Frequently Asked Questions)

Common questions and answers about Harbor.

## Table of Contents

- [General Questions](#general-questions)
- [Installation & Setup](#installation--setup)
- [Authentication & Security](#authentication--security)
- [Features & Functionality](#features--functionality)
- [Local Git Integration](#local-git-integration)
- [Performance & Resources](#performance--resources)
- [Platform-Specific Questions](#platform-specific-questions)
- [Advanced Topics](#advanced-topics)

---

## General Questions

### What is Harbor?

Harbor is a native menu bar (macOS) and system tray (Windows) application that provides a calm, glanceable view of your GitHub repositories. It shows CI/CD status, pull requests, issues, releases, and integrates with your local Git repositories.

### What platforms does Harbor support?

Currently:
- **macOS**: 15.0+ (Sequoia or later) - Fully supported
- **Windows**: 10 (1809+) and 11 - Fully supported
- **Linux**: Planned for future release
- **Web**: Planned for future release

### Is Harbor free?

Yes, Harbor is completely free and open source under the MIT license. There are no paid tiers, subscriptions, or premium features.

### Does Harbor collect my data?

No. Harbor does not collect any analytics, telemetry, or usage data. Your GitHub token stays on your device in secure storage. All API calls go directly from your machine to GitHub. Harbor is open source, so you can verify this yourself.

### How is Harbor different from GitHub Desktop?

GitHub Desktop is a Git client focused on managing repositories and commits. Harbor is a monitoring and overview tool focused on providing quick status checks without opening a browser. They serve different purposes and can be used together.

### Why does Harbor require so many permissions?

Harbor requests these GitHub OAuth scopes:
- `repo`: Read repository data, issues, PRs, CI status
- `user`: Read your profile (username, avatar)
- `notifications`: Read notifications for activity tracking

These are read-only permissions. Harbor cannot modify your repositories, create commits, or make changes on your behalf.

### Can I use Harbor without GitHub?

No, Harbor is specifically designed for GitHub (both GitHub.com and GitHub Enterprise). Support for GitLab, Azure DevOps, and Bitbucket is planned for future releases.

---

## Installation & Setup

### How do I install Harbor on macOS?

**Homebrew (recommended)**:
```bash
brew install --cask sriinnu/tap/harbor
```

**Direct download**:
1. Download `Harbor-macOS.dmg` from [releases](https://github.com/sriinnu/Harbor/releases/latest)
2. Open DMG and drag to Applications
3. Launch from Applications folder

### How do I install Harbor on Windows?

**Direct download (recommended)**:
1. Download `Harbor-Windows-Setup.exe` from [releases](https://github.com/sriinnu/Harbor/releases/latest)
2. Run the installer
3. Harbor appears in system tray

**Build from source**: See the [README.md](../README.md#windows) for details.

### Why does macOS say the app is damaged or from an unidentified developer?

The current release is not yet notarized by Apple. To open:
1. Go to System Preferences → Privacy & Security
2. Find the message about Harbor
3. Click "Open Anyway"
4. This is a one-time step

Future releases will be properly signed and notarized.

### Why does Windows SmartScreen block Harbor?

The current release is not yet signed with a Windows code signing certificate. To proceed:
1. Click "More info" when SmartScreen appears
2. Click "Run anyway"
3. This is a one-time step

Future releases will be properly signed.

### Can I install Harbor on multiple computers?

Yes! Install Harbor on as many devices as you like. Each installation uses its own GitHub OAuth token stored locally. Your settings are device-specific and don't sync (yet).

### How do I update Harbor?

**macOS (Homebrew)**:
```bash
brew upgrade --cask harbor
```

**macOS (Manual)**:
1. Download latest DMG from releases
2. Replace old app with new one in Applications folder

**Windows**:
1. Download latest installer from releases
2. Run installer (it will update existing installation)

**Note**: Auto-updates are planned for future releases.

### How do I uninstall Harbor?

**macOS (Homebrew)**:
```bash
brew uninstall --cask harbor
```

**macOS (Manual)**:
1. Quit Harbor
2. Move Harbor.app to Trash from Applications
3. Optional: Remove settings from `~/Library/Application Support/Harbor`

**Windows**:
1. Control Panel → Programs → Uninstall a program
2. Find Harbor and click Uninstall
3. Optional: Remove settings from `%APPDATA%\Harbor`

---

## Authentication & Security

### How does Harbor authenticate with GitHub?

Harbor uses OAuth 2.0 Authorization Code Flow with PKCE. When you sign in:
1. Harbor opens your browser to GitHub
2. You authorize Harbor
3. GitHub redirects to `http://localhost:53682/callback`
4. Harbor receives and securely stores the access token

### Where is my GitHub token stored?

- **macOS**: Stored in the macOS Keychain (the same secure storage used by Safari, Mail, etc.)
- **Windows**: Stored in Windows Credential Manager (the same secure storage used by Windows for passwords)

Your token never leaves your device and is never sent to any server except GitHub's API.

### Can I use Harbor with GitHub Enterprise?

Yes! Harbor fully supports GitHub Enterprise Server 3.0+.

To configure:
1. Settings → Advanced → "Use custom GitHub server"
2. Enter your GHE URL (e.g., `https://github.yourcompany.com`)
3. Create an OAuth app in your GHE instance
4. Enter Client ID and Client Secret in Harbor
5. Sign in

### Can I use my own OAuth app credentials?

Yes! For corporate environments or custom setups:

1. Create OAuth app at https://github.com/settings/developers
2. Set callback URL to `http://localhost:53682/callback`
3. In Harbor Settings → Advanced → "Use custom OAuth credentials"
4. Enter your Client ID and Client Secret
5. Sign in

### How do I revoke Harbor's access to GitHub?

**In Harbor**:
1. Click Harbor icon → Sign Out
2. This deletes your local token

**On GitHub**:
1. Go to https://github.com/settings/applications
2. Find Harbor in "Authorized OAuth Apps"
3. Click "Revoke"

**In Keychain/Credential Manager**:
- macOS: Open Keychain Access, search for "harbor", delete entry
- Windows: Open Credential Manager, find Harbor, remove

### Is my code/data secure?

Yes. Harbor:
- Only reads data (cannot modify repositories)
- Stores tokens in OS-native secure storage
- Makes direct API calls to GitHub (no intermediary servers)
- Does not collect or transmit any analytics
- Is open source for transparency

### What happens if my computer is compromised?

If someone gains access to your computer:
- They could access your Harbor token from Keychain/Credential Manager
- However, they'd need your system password to do so
- The token only grants read access to repositories
- Revoke the token from GitHub settings if concerned

We recommend:
- Enable two-factor authentication on GitHub
- Use a strong system password
- Lock your computer when away
- Regularly review authorized apps on GitHub

---

## Features & Functionality

### What information does Harbor show for each repository?

For each repository, Harbor displays:
- CI/CD status (latest workflow run)
- Open pull requests count
- Open issues count
- Latest release version
- Recent commits
- Local Git status (if configured)

### Can I customize which repositories appear?

Yes! You can:
- **Pin** important repositories (appear at top)
- **Hide** repositories you don't need
- **Filter** by forks and archived repos
- **Sort** by activity, name, stars, updated, or custom order
- **Search** to find specific repositories
- **Limit** how many repos appear (3, 6, 9, or 12)

### How often does Harbor refresh data from GitHub?

Default: Every 5 minutes

You can configure this in Settings → Advanced → Refresh Interval (1-60 minutes).

To manually refresh: Click Harbor icon → Refresh (or Cmd/Ctrl + R)

### Does Harbor send notifications?

Harbor is intentionally calm and doesn't push notifications for most events. Notifications are only shown for:
- Auto-sync completions (if enabled in settings)
- Auto-sync errors or conflicts
- Critical errors

This aligns with Harbor's philosophy: glanceable information, not intrusive alerts.

### Can I see pull request details without opening GitHub?

Yes! Click on any repository → Pull Requests submenu to see:
- PR title and number
- Author
- Review status (approved, changes requested, pending)
- CI/CD check status
- Age of PR

Click on a PR to open it in your browser.

### Can I manage issues and PRs from Harbor?

No. Harbor is a read-only monitoring tool. To create, edit, or comment on issues/PRs, you'll need to open GitHub in your browser or use GitHub CLI.

This is intentional - Harbor is focused on providing quick status checks, not replacing GitHub's full interface.

### Does Harbor support GitHub Actions?

Yes! Harbor shows:
- Latest workflow run status (success, failure, pending)
- Workflow runs submenu with recent runs
- Run duration and trigger information
- Click to view logs on GitHub

### Can I track private repositories?

Yes! Harbor works with both public and private repositories. Your OAuth token grants access to all repositories you can access on GitHub.

### Does Harbor work offline?

Partially:
- **GitHub data**: Requires internet connection to fetch updates
- **Local Git features**: Work completely offline (branch info, status, etc.)
- **Cached data**: Previously loaded data remains visible offline
- **CLI**: Most commands require internet except local-projects

---

## Local Git Integration

### How does local Git integration work?

Harbor scans your configured "Local Projects Folder" for Git repositories and matches them with your GitHub repositories. It then shows:
- Current branch
- Commits ahead/behind remote
- Uncommitted changes (dirty status)
- Quick actions (open, pull, push, sync)

### What should I set as my Local Projects Folder?

Set it to the parent directory containing your Git repositories. Examples:
- **macOS**: `~/Projects`, `~/Developer`, `~/Code`
- **Windows**: `C:\Users\YourName\Projects`, `D:\Code`

Harbor will scan subdirectories to find Git repositories.

### How does Harbor match local repos with GitHub repos?

Harbor reads the Git remote URL from your local repository and matches it with your GitHub repositories. It looks for remotes named `origin` or `upstream`.

Example:
```bash
# Local repo with this remote:
git remote -v
# origin  https://github.com/user/repo.git (fetch)

# Matches with GitHub repo: user/repo
```

### What is auto-sync and how does it work?

Auto-sync automatically pulls updates for your local repositories at a configured interval (default: 15 minutes).

**Safety features**:
- Only syncs repositories with no uncommitted changes
- Only performs fast-forward merges (safe pulls)
- Never force-pulls or overwrites local changes
- Skips repositories with merge conflicts
- Shows notifications for errors

**To enable**: Settings → Repositories → Auto-Sync

### Is auto-sync safe for repositories I'm actively working on?

Auto-sync is designed to be safe:
- It won't sync if you have uncommitted changes
- It only does fast-forward merges (won't lose work)
- It skips repos with conflicts

However, if you're frequently making commits, you might want to:
- Increase the sync interval
- Disable auto-sync for specific repos (not yet implemented)
- Use manual sync instead

### Can I disable local Git integration?

Yes. Simply don't configure a "Local Projects Folder" in Settings. Without this, Harbor will only show GitHub data.

### Does Harbor work with Git worktrees?

Yes, Harbor detects and works with Git worktrees. Each worktree is treated as a separate working directory, and Harbor will show the status for each.

### Can Harbor work with submodules?

Yes, Harbor detects the parent repository. Submodule status is not currently shown separately but is included in the dirty/clean status of the parent repo.

---

## Performance & Resources

### How much memory does Harbor use?

Typical usage:
- **macOS**: 80-150 MB RAM (native SwiftUI app)
- **Windows**: 120-200 MB RAM (Tauri/React app)

Memory usage may increase with:
- Large number of repositories
- Frequent refreshes
- Extensive caching

### Does Harbor run constantly in the background?

Yes, Harbor runs as a menu bar/system tray app. It:
- Uses minimal CPU when idle
- Refreshes data at configured intervals (default: 5 minutes)
- Scans local repos if auto-sync is enabled
- Can be quit like any other app

### Will Harbor slow down my computer?

No. Harbor is designed to be lightweight:
- Minimal CPU usage when idle
- Efficient API calls with caching
- Debounced refresh to prevent API spam
- Optional: Reduce refresh frequency in settings

### Does Harbor use a lot of network bandwidth?

No. Harbor uses GitHub's GraphQL API which is efficient. Typical usage:
- ~50-200 KB per refresh (depending on repo count)
- Refreshes every 5 minutes by default
- ~600-2400 KB per hour with default settings

You can reduce network usage by:
- Increasing refresh interval
- Pinning fewer repositories
- Hiding repositories you don't monitor

### How many GitHub API requests does Harbor make?

Harbor is rate-limit aware:
- Uses GraphQL for efficient batched queries
- GitHub allows 5,000 API requests/hour for authenticated users
- Harbor typically uses 10-30 requests per hour with default settings
- Rate limit status shown in Harbor menu

If you approach the rate limit, Harbor will:
- Show a warning
- Automatically back off
- Resume when limit resets

### Can I run Harbor on a low-powered device?

Yes, Harbor is designed to be efficient and works well on:
- Older Macs (2015+ recommended)
- Budget Windows laptops
- Low-powered devices

For best performance on older devices:
- Reduce refresh interval to 10-15 minutes
- Limit displayed repos to 6 or fewer
- Disable auto-sync if not needed
- Use compact menu density

---

## Platform-Specific Questions

### macOS: Why doesn't Harbor appear in my menu bar?

Possible reasons:
1. **Menu bar is hidden**: Move cursor to top of screen
2. **Menu bar is full**: macOS hides icons when space is limited
   - Try: Quit other menu bar apps
   - Or: Reduce screen resolution temporarily
3. **Permissions issue**: Check Privacy & Security settings

### macOS: Can I use Harbor on Intel Macs?

Yes, Harbor supports both Apple Silicon (M1/M2/M3) and Intel (x86_64) Macs running macOS 15.0 (Sequoia) or later.

### macOS: How do I prevent Harbor from launching at login?

Settings → General → Launch at Login → Off

Or: System Preferences → Users & Groups → Login Items → Remove Harbor

### macOS: Does Harbor work with Bartender/Hidden Bar?

Yes! Harbor works with menu bar management apps like Bartender and Hidden Bar. You can configure these apps to show/hide Harbor's icon as desired.

### Windows: Why does Harbor appear in my system tray but not taskbar?

This is intentional. Harbor is a system tray app (not a taskbar app) to stay out of your way. Click the system tray icon (bottom-right) to access Harbor.

### Windows: Can I pin Harbor to my taskbar?

Harbor is designed as a system tray app, but you can:
1. Right-click the Harbor tray icon
2. Select "Show Harbor" (if available)
3. Right-click the taskbar window → Pin to taskbar

However, the main interface is the tray icon menu.

### Windows: Does Harbor work with WSL (Windows Subsystem for Linux)?

Partial support:
- Harbor can detect WSL repositories if they're in your Windows filesystem
- Repositories in WSL-only paths (e.g., `/home/user/projects`) are not currently detected
- Workaround: Clone repos to Windows-accessible paths or use symlinks

Full WSL integration is planned for a future release.

### Windows: How do I stop Harbor from running?

Right-click the system tray icon → Quit

Or: Task Manager → Find Harbor → End Task

---

## Advanced Topics

### Can I use Harbor with multiple GitHub accounts?

Not currently. Harbor supports one GitHub account at a time. To switch accounts:
1. Sign out from current account
2. Sign in with different account

Multi-account support is planned for a future release.

### Can I use Harbor with both GitHub.com and GitHub Enterprise?

Not simultaneously. You can configure Harbor for either GitHub.com or GitHub Enterprise Server, but not both at once.

To switch:
1. Sign out
2. Change settings (Settings → Advanced → GitHub Server)
3. Sign in to the other instance

### Can I automate Harbor with the CLI?

Yes! Harbor includes a full-featured CLI. Example use cases:
- **Scripting**: Generate daily reports, check CI status
- **Automation**: Auto-sync repos, check for updates
- **Integration**: Use in CI/CD pipelines, pre-commit hooks
- **Monitoring**: Check repo status from cron jobs

See [docs/cli.md](cli.md) for full CLI documentation.

### Can I export my Harbor configuration?

Settings are stored in JSON files:
- **macOS**: `~/Library/Application Support/Harbor/settings.json`
- **Windows**: `%APPDATA%\Harbor\settings.json`

You can manually back up this file. Automatic backup/export features are planned.

### Can I use Harbor with GitHub Apps instead of OAuth Apps?

Not currently. Harbor uses GitHub OAuth Apps for authentication. GitHub Apps support may be added in the future.

### How can I contribute to Harbor?

Harbor is open source! You can contribute by:
- **Reporting bugs**: [Open an issue](https://github.com/sriinnu/Harbor/issues)
- **Suggesting features**: [Start a discussion](https://github.com/sriinnu/Harbor/discussions)
- **Contributing code**: Fork the repo and submit a PR
- **Improving docs**: Fix typos, add examples, clarify sections
- **Spreading the word**: Star the repo, share with others

See [CONTRIBUTING.md](../CONTRIBUTING.md) for detailed guidelines.

### What's the difference between Harbor and browser extensions?

**Harbor**:
- Native desktop app
- Always accessible from menu bar/tray
- Works with local Git repositories
- Powerful CLI for automation
- Minimal resource usage
- Works offline (local features)

**Browser Extensions**:
- Only available in browser
- Tied to specific tab/page
- Limited local Git integration
- Limited automation capabilities
- Requires browser to be open

Both have their place - use what works for your workflow!

### Why is Harbor not available on Linux yet?

Linux support is planned and partially implemented. The platform abstraction layer is ready, but the Linux-specific implementation needs work. Planned features include:
- AppImage and .deb packages
- Support for Ubuntu, Debian, Fedora, Arch
- System tray integration

Contributions to the Linux implementation are welcome!

### Will there be a mobile version of Harbor?

An iOS companion app is planned for the roadmap (read-only, glanceable view). Android support may be added later.

Mobile apps will be complementary to the desktop app, not full replacements.

### Can I self-host Harbor or use it as a service?

Harbor is designed as a desktop application, not a web service. However:
- A web version is planned (PWA for cross-platform access)
- You can build and run Harbor from source
- The architecture supports future web deployment

Harbor will remain free and open source regardless of platform.

---

## Still Have Questions?

If your question isn't answered here:

1. **Check the User Guide**: [docs/user-guide.md](user-guide.md)
2. **Review Troubleshooting**: [docs/troubleshooting.md](troubleshooting.md)
3. **Search Issues**: [GitHub Issues](https://github.com/sriinnu/Harbor/issues)
4. **Ask the Community**: [GitHub Discussions](https://github.com/sriinnu/Harbor/discussions)
5. **Open an Issue**: [New Issue](https://github.com/sriinnu/Harbor/issues/new)

We're here to help!
