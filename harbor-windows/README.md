# RepoBar for Windows

Windows version of RepoBar - a GitHub repository manager that lives in your system tray.

## Architecture

This Windows implementation uses:

- **Tauri 2.0**: Cross-platform desktop framework with Rust backend
- **React + TypeScript**: Modern frontend with type safety
- **Rust**: High-performance backend services
- **Windows Credential Manager**: Secure OAuth token storage via keyring crate
- **tiny_http**: Lightweight HTTP server for OAuth callbacks

## Platform Abstraction

The Windows implementation follows the platform abstraction protocols defined in the macOS version:

- **SecureTokenStorage**: Windows Credential Manager (`platform/token_storage.rs`)
- **OAuthCallbackServer**: HTTP server using tiny_http (`platform/callback_server.rs`)
- **ExecutableLocator**: Windows-specific path resolution (`platform/executable_locator.rs`)
- **UserSettingsStorage**: JSON file in %APPDATA% (`platform/settings_storage.rs`)

## Project Structure

```
repobar-windows/
├── src/                    # React frontend
│   ├── components/         # React components
│   │   ├── AuthView.tsx
│   │   ├── TrayWindow.tsx
│   │   └── SettingsView.tsx
│   ├── services/           # Tauri command wrappers
│   │   ├── auth.ts
│   │   ├── settings.ts
│   │   └── git.ts
│   ├── App.tsx
│   ├── main.tsx
│   └── styles.css
├── src-tauri/              # Rust backend
│   ├── src/
│   │   ├── platform/       # Platform services
│   │   │   ├── token_storage.rs
│   │   │   ├── callback_server.rs
│   │   │   ├── executable_locator.rs
│   │   │   └── settings_storage.rs
│   │   ├── auth/           # OAuth implementation
│   │   │   ├── oauth.rs
│   │   │   ├── pkce.rs
│   │   │   └── types.rs
│   │   ├── commands/       # Tauri commands
│   │   │   ├── auth.rs
│   │   │   ├── settings.rs
│   │   │   └── git.rs
│   │   ├── tray/           # System tray
│   │   │   ├── mod.rs
│   │   │   └── menu.rs
│   │   └── main.rs
│   ├── Cargo.toml
│   └── tauri.conf.json
├── package.json
└── README.md
```

## Prerequisites

1. **Node.js** (v18 or later)
2. **Rust** (1.70 or later)
3. **Visual Studio Build Tools** (for Windows)

Install Rust from [rustup.rs](https://rustup.rs/)

## Setup

1. Install dependencies:
```bash
npm install
```

2. Run in development mode:
```bash
npm run tauri:dev
```

3. Build for production:
```bash
npm run tauri:build
```

## OAuth Setup

To use RepoBar, you need to create a GitHub OAuth App:

1. Go to [GitHub Developer Settings](https://github.com/settings/developers)
2. Create a new OAuth App
3. Set the callback URL to: `http://127.0.0.1:53682/callback`
4. Copy the Client ID and Client Secret
5. Enter them in the RepoBar login screen

## Features Implemented

### Platform Services

- ✅ **Token Storage**: Windows Credential Manager integration
- ✅ **OAuth Flow**: PKCE-based OAuth 2.0 with callback server
- ✅ **Settings Storage**: JSON file in %APPDATA%\RepoBar
- ✅ **Git Detection**: Automatic Git executable location

### UI Components

- ✅ **Authentication View**: OAuth login with GitHub
- ✅ **Tray Window**: Repository list (placeholder)
- ✅ **Settings View**: User preferences management
- ✅ **System Tray**: Right-click menu with common actions

### Tauri Commands

- ✅ `start_oauth_login`: Initiate OAuth flow
- ✅ `load_oauth_tokens`: Load saved tokens
- ✅ `logout`: Clear stored credentials
- ✅ `is_authenticated`: Check auth status
- ✅ `load_settings` / `save_settings`: Settings management
- ✅ `locate_git`: Find Git executable
- ✅ `get_executable_version`: Get version info

## Next Steps

To complete the Windows implementation:

1. **GitHub API Integration**:
   - Add repository fetching
   - Implement repository caching
   - Add pull requests, issues, etc.

2. **Enhanced UI**:
   - Repository search/filter
   - Contribution graphs
   - Notification badges

3. **System Integration**:
   - Windows Registry for launch at login
   - Desktop notifications
   - Jump list integration

4. **Testing**:
   - Unit tests for Rust modules
   - Integration tests for OAuth flow
   - E2E tests for UI

## Development

### Running Tests

```bash
# Rust tests
cd src-tauri
cargo test

# Frontend tests (after adding test framework)
npm test
```

### Code Style

- Rust: Follow standard Rust formatting (`cargo fmt`)
- TypeScript: ESLint + Prettier (to be configured)

## Security Considerations

- OAuth tokens are stored securely in Windows Credential Manager
- PKCE is used for OAuth flow to prevent authorization code interception
- No tokens are logged or exposed in the UI
- Settings file in %APPDATA% is user-scoped

## Differences from macOS Version

- **Storage**: Windows Credential Manager instead of macOS Keychain
- **HTTP Server**: tiny_http instead of Network framework
- **Settings**: JSON file instead of UserDefaults
- **UI**: React/Tauri instead of SwiftUI
- **Git Detection**: Windows paths (Program Files, etc.) instead of Homebrew

## Contributing

This is part of the cross-platform RepoBar project. See the main repository for contribution guidelines.

## License

Same as the main RepoBar project.
