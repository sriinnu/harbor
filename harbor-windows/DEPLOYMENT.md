# RepoBar Windows Deployment Guide

## Building for Distribution

### Prerequisites

1. **Rust toolchain**:
```bash
rustup target add x86_64-pc-windows-msvc
```

2. **Visual Studio Build Tools** with:
   - Windows 10 SDK
   - MSVC v142+ build tools

3. **Node.js** v18+

### Build Steps

1. Install dependencies:
```bash
npm install
```

2. Build the application:
```bash
npm run tauri:build
```

This creates:
- MSI installer: `src-tauri/target/release/bundle/msi/RepoBar_0.1.0_x64_en-US.msi`
- Portable exe: `src-tauri/target/release/repobar.exe`

### Code Signing (Optional)

For production releases, sign the executable:

```bash
# Install signtool (part of Windows SDK)
signtool sign /f certificate.pfx /p password /t http://timestamp.digicert.com src-tauri/target/release/repobar.exe
```

## Installation

### MSI Installer

The MSI installer will:
- Install to `C:\Program Files\RepoBar`
- Create Start Menu shortcuts
- Add to Windows Registry for uninstallation

### Portable Mode

Simply run `repobar.exe` - no installation required. Settings will be stored in `%APPDATA%\RepoBar`.

## Configuration

### Settings Location

User settings are stored at:
```
%APPDATA%\RepoBar\settings.json
```

### OAuth Credentials

Stored securely in Windows Credential Manager under:
- Service: `com.steipete.repobar.auth`
- Accounts: `default` (tokens), `client` (credentials)

### Git Detection

RepoBar searches for Git in:
1. `C:\Program Files\Git\cmd\git.exe`
2. `C:\Program Files\Git\bin\git.exe`
3. `PATH` environment variable
4. Custom path from settings

## Troubleshooting

### OAuth Callback Port in Use

If port 53682 is already in use:
1. Close other applications using that port
2. Or modify the port in `src-tauri/src/auth/oauth.rs` (line 31)

### Git Not Found

Install Git for Windows from [git-scm.com](https://git-scm.com/download/win) or specify a custom path in Settings > Advanced.

### Credential Manager Issues

If tokens aren't saving:
1. Check Windows Credential Manager is enabled
2. Run RepoBar as administrator once
3. Check antivirus isn't blocking access

### Build Errors

Common issues:

**Missing Windows SDK**:
```
error: linking with `link.exe` failed
```
Solution: Install Visual Studio Build Tools

**WebView2 Not Found**:
```
error: WebView2Loader.dll not found
```
Solution: Install [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)

## System Requirements

- Windows 10 version 1809 or later
- WebView2 Runtime (included with Windows 11)
- 50 MB disk space
- Git (optional, for local repository features)

## Automatic Updates

To implement auto-updates (future):

1. Set up update server with `appcast.xml`
2. Add Tauri updater plugin:
```toml
[dependencies]
tauri-plugin-updater = "2.0"
```

3. Configure in `tauri.conf.json`:
```json
{
  "updater": {
    "active": true,
    "endpoints": ["https://updates.repobar.com/windows.json"],
    "pubkey": "YOUR_PUBLIC_KEY"
  }
}
```

## CI/CD Integration

### GitHub Actions

Example workflow:

```yaml
name: Build Windows

on:
  push:
    tags:
      - 'v*'

jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Setup Rust
        uses: actions-rs/toolchain@v1
        with:
          toolchain: stable

      - name: Install dependencies
        run: npm install

      - name: Build
        run: npm run tauri:build

      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: windows-installer
          path: src-tauri/target/release/bundle/msi/*.msi
```

## Distribution Channels

### Microsoft Store

To publish to Microsoft Store:
1. Create MSIX package instead of MSI
2. Submit to Partner Center
3. Update `tauri.conf.json`:
```json
{
  "bundle": {
    "windows": {
      "wix": {
        "skip_webview_install": true
      }
    }
  }
}
```

### Winget

Create manifest for Windows Package Manager:

```yaml
PackageIdentifier: RepoBar.RepoBar
PackageVersion: 0.1.0
PackageName: RepoBar
Publisher: RepoBar Team
License: MIT
ShortDescription: GitHub repository manager for Windows
Installers:
  - Architecture: x64
    InstallerType: msi
    InstallerUrl: https://github.com/steipete/repobar/releases/download/v0.1.0/RepoBar_0.1.0_x64.msi
```

### Chocolatey

Create Chocolatey package:

```powershell
choco pack
choco push RepoBar.0.1.0.nupkg --source https://push.chocolatey.org/
```

## Support

For issues or questions, see the main RepoBar repository.
