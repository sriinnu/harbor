# RepoBar Windows - Quick Start Guide

Get RepoBar running on Windows in 5 minutes!

## Prerequisites

Install the following tools:

1. **Node.js** (v18 or later): [nodejs.org](https://nodejs.org/)
2. **Rust**: Run this in PowerShell:
   ```powershell
   winget install Rustlang.Rustup
   # OR download from: https://rustup.rs/
   ```
3. **Visual Studio Build Tools**: [Download](https://visualstudio.microsoft.com/downloads/)
   - Select "Desktop development with C++"
   - Include Windows 10 SDK

## Installation

### Option 1: Development Mode

```bash
# Clone or navigate to the project
cd repobar-windows

# Install dependencies
npm install

# Run in development mode
npm run tauri:dev
```

The app will launch with hot-reload enabled!

### Option 2: Build Installer

```bash
# Install dependencies
npm install

# Build for production
npm run tauri:build
```

Installer will be created at:
```
src-tauri/target/release/bundle/msi/RepoBar_0.1.0_x64_en-US.msi
```

## First-Time Setup

### 1. Create GitHub OAuth App

1. Go to https://github.com/settings/developers
2. Click "New OAuth App"
3. Fill in:
   - **Application name**: RepoBar (or your choice)
   - **Homepage URL**: https://github.com/steipete/repobar
   - **Authorization callback URL**: `http://127.0.0.1:53682/callback`
4. Click "Register application"
5. Copy the **Client ID**
6. Click "Generate a new client secret"
7. Copy the **Client Secret** (you won't see it again!)

### 2. Login to RepoBar

1. Launch RepoBar
2. Enter your **Client ID** and **Client Secret**
3. Click "Sign in with GitHub"
4. A browser window will open
5. Click "Authorize" on GitHub
6. The browser will show "Authentication successful!"
7. RepoBar will now be authenticated

### 3. Check System Tray

Look for the RepoBar icon in your Windows system tray (bottom-right corner).

Right-click the icon to see:
- Show RepoBar
- Refresh
- Settings
- Quit RepoBar

## Project Structure (Quick Reference)

```
repobar-windows/
├── src/                    # React frontend
│   ├── components/         # UI components
│   ├── services/           # API wrappers
│   └── App.tsx            # Main app
├── src-tauri/             # Rust backend
│   ├── src/
│   │   ├── platform/      # Windows integrations
│   │   ├── auth/          # OAuth + PKCE
│   │   ├── commands/      # Tauri commands
│   │   └── tray/          # System tray
│   └── Cargo.toml         # Rust dependencies
└── package.json           # Node dependencies
```

## Common Commands

```bash
# Development mode (hot reload)
npm run tauri:dev

# Build production app
npm run tauri:build

# Run frontend only (no backend)
npm run dev

# Build frontend only
npm run build

# Run Rust tests
cd src-tauri && cargo test

# Format Rust code
cd src-tauri && cargo fmt

# Check Rust code
cd src-tauri && cargo clippy
```

## Configuration Files

### Tauri Configuration
`src-tauri/tauri.conf.json` - App metadata, window settings, bundle config

### Rust Dependencies
`src-tauri/Cargo.toml` - Rust crates and versions

### Frontend Dependencies
`package.json` - npm packages

### TypeScript Config
`tsconfig.json` - TypeScript compiler options

## Where Things Are Stored

### Settings
```
%APPDATA%\RepoBar\settings.json
```
Example: `C:\Users\YourName\AppData\Roaming\RepoBar\settings.json`

### OAuth Tokens
**Windows Credential Manager** (secure storage)
- Open: Control Panel → Credential Manager → Windows Credentials
- Service: `com.steipete.repobar.auth`

### Logs (Development)
Check the terminal where you ran `npm run tauri:dev`

## Troubleshooting

### Port Already in Use

If you see "Failed to start HTTP server on 127.0.0.1:53682":

1. Check if another app is using port 53682:
   ```powershell
   netstat -ano | findstr :53682
   ```
2. Close the app or restart your computer

### Git Not Found

If RepoBar can't find Git:

1. Install Git: [git-scm.com/download/win](https://git-scm.com/download/win)
2. Or set a custom path in Settings → Advanced → Git executable path

### Build Errors

**"error: linking with `link.exe` failed"**
- Install Visual Studio Build Tools (see Prerequisites)

**"WebView2Loader.dll not found"**
- Install WebView2: [Download](https://developer.microsoft.com/en-us/microsoft-edge/webview2/)

**"cargo: command not found"**
- Restart your terminal after installing Rust
- Or add Rust to PATH: `%USERPROFILE%\.cargo\bin`

### OAuth Callback Timeout

If the browser callback takes too long:

1. Check your firewall isn't blocking port 53682
2. Check the callback URL in your GitHub OAuth App matches exactly
3. Try localhost instead of 127.0.0.1 (or vice versa)

### Credentials Not Saving

If tokens don't persist:

1. Check Windows Credential Manager is enabled
2. Run RepoBar as administrator once
3. Check antivirus isn't blocking keyring access

## Development Tips

### Hot Reload

When running `npm run tauri:dev`:
- **Frontend changes**: Auto-reload
- **Rust changes**: Manual restart required

### Debugging

1. **Frontend**: Press F12 in the app window (Chromium DevTools)
2. **Rust**: Use `println!` or `dbg!` macros
3. **Logs**: Check terminal output

### VS Code Setup

Recommended extensions:
- rust-analyzer (Rust support)
- Tauri (Tauri support)
- Prettier (Code formatting)
- ESLint (TypeScript linting)

### Testing OAuth Locally

You can test without creating a real OAuth app:

1. Use the InMemoryTokenStorage for testing
2. Mock the OAuth flow in tests
3. See `src-tauri/src/auth/oauth.rs` tests

## Next Steps

1. **Explore the Code**: Start with `src/App.tsx` and `src-tauri/src/main.rs`
2. **Read Architecture**: See `ARCHITECTURE.md` for detailed design
3. **Add Features**: Check TODOs in code comments
4. **Run Tests**: `cd src-tauri && cargo test`
5. **Customize UI**: Edit `src/styles.css`

## Resources

- **Tauri Docs**: https://tauri.app/v1/guides/
- **React Docs**: https://react.dev/
- **Rust Book**: https://doc.rust-lang.org/book/
- **OAuth 2.0**: https://oauth.net/2/
- **GitHub API**: https://docs.github.com/en/rest

## Getting Help

1. Check existing issues in the main RepoBar repo
2. Search Tauri discussions: https://github.com/tauri-apps/tauri/discussions
3. Read the logs in your terminal
4. Enable verbose logging: Set `RUST_LOG=debug` environment variable

## Contributing

See the main RepoBar repository for contribution guidelines.

Happy coding! 🚀
