# RepoBar Windows Architecture

## Overview

RepoBar for Windows is built using Tauri 2.0, combining a Rust backend with a React frontend. It implements the same platform abstraction protocols as the macOS version, ensuring 65-75% code reuse for business logic.

## Technology Stack

### Backend (Rust)

- **Tauri 2.0**: Cross-platform framework
- **tokio**: Async runtime
- **reqwest**: HTTP client for GitHub API
- **keyring**: Windows Credential Manager integration
- **tiny_http**: OAuth callback server
- **serde**: Serialization/deserialization
- **sha2**: SHA-256 hashing for PKCE
- **base64**: Base64url encoding

### Frontend (React + TypeScript)

- **React 18**: UI framework
- **TypeScript**: Type-safe JavaScript
- **Vite**: Build tool and dev server
- **@tauri-apps/api**: Rust backend communication

## Architecture Layers

```
┌─────────────────────────────────────────────────────┐
│                  React Frontend                      │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────┐ │
│  │  AuthView    │  │  TrayWindow  │  │ Settings  │ │
│  └──────────────┘  └──────────────┘  └───────────┘ │
│         │                  │                │        │
│  ┌──────────────────────────────────────────────┐  │
│  │         Tauri Command Wrappers              │  │
│  │   (auth.ts, settings.ts, git.ts)            │  │
│  └──────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
┌───────▼────────┐ ┌───▼──────┐ ┌──────▼──────┐
│ Tauri Commands │ │   Tray   │ │    State    │
│  (Rust FFI)    │ │  System  │ │  Management │
└───────┬────────┘ └────────── └──────────────┘
        │
┌───────▼────────────────────────────────────────────┐
│              Platform Services Layer                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │ TokenStorage │  │   Callback   │  │Settings  │ │
│  │   (WinCred)  │  │    Server    │  │ Storage  │ │
│  └──────────────┘  └──────────────┘  └──────────┘ │
│  ┌──────────────┐  ┌──────────────┐               │
│  │  Executable  │  │     OAuth    │               │
│  │   Locator    │  │     Flow     │               │
│  └──────────────┘  └──────────────┘               │
└────────────────────────────────────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
┌───────▼────────┐ ┌───▼──────┐ ┌──────▼──────┐
│   Windows      │ │  GitHub  │ │  File       │
│  Credential    │ │   API    │ │  System     │
│   Manager      │ │          │ │             │
└────────────────┘ └──────────┘ └─────────────┘
```

## Module Breakdown

### Platform Services (`src-tauri/src/platform/`)

#### 1. Token Storage (`token_storage.rs`)

Implements secure credential storage using Windows Credential Manager.

**Key Features**:
- Save/load OAuth tokens
- Save/load client credentials
- Automatic JSON serialization
- Secure deletion

**Storage Location**: Windows Credential Manager
- Service: `com.steipete.repobar.auth`
- Accounts: `default` (tokens), `client` (credentials)

#### 2. Callback Server (`callback_server.rs`)

HTTP server for OAuth callbacks using tiny_http.

**Key Features**:
- Listens on `127.0.0.1:53682`
- Parses OAuth callback parameters
- Thread-based server with timeout
- Automatic cleanup

**Flow**:
1. Start server → Get callback URL
2. Open browser → User authorizes
3. GitHub redirects → Server receives code
4. Parse parameters → Return to OAuth flow
5. Stop server → Cleanup

#### 3. Executable Locator (`executable_locator.rs`)

Finds executables like Git on Windows.

**Search Order**:
1. `C:\Program Files\Git\{cmd,bin}\git.exe`
2. `C:\Program Files (x86)\Git\{cmd,bin}\git.exe`
3. `PATH` environment variable
4. `where` command
5. Custom path from settings

**Features**:
- Version detection via `--version`
- Automatic .exe extension
- Windows-specific path handling

#### 4. Settings Storage (`settings_storage.rs`)

JSON file storage for user preferences.

**Storage Location**: `%APPDATA%\RepoBar\settings.json`

**Settings Structure**:
```rust
struct UserSettings {
    appearance: AppearanceSettings,
    repositories: RepositorySettings,
    refresh: RefreshSettings,
    advanced: AdvancedSettings,
}
```

**Features**:
- Version migration support
- Pretty-printed JSON
- Defaults fallback
- Schema validation

### Authentication (`src-tauri/src/auth/`)

#### 1. OAuth Flow (`oauth.rs`)

Complete OAuth 2.0 flow with PKCE.

**Flow Steps**:
1. Generate PKCE challenge
2. Start callback server
3. Build authorization URL
4. Open browser
5. Wait for callback
6. Validate state parameter
7. Exchange code for tokens
8. Save tokens securely

**Security Features**:
- PKCE (SHA-256)
- State parameter validation
- HTTPS enforcement
- No token logging

#### 2. PKCE (`pkce.rs`)

Proof Key for Code Exchange implementation per RFC 7636.

**Implementation**:
- 32 random bytes → verifier
- SHA-256(verifier) → challenge
- Base64url encoding
- No padding

#### 3. Types (`types.rs`)

Shared data structures for OAuth.

**Key Types**:
- `OAuthTokens`: Access token, refresh token, expiry
- `OAuthClientCredentials`: Client ID and secret
- `TokenResponse`: OAuth server response

### Commands (`src-tauri/src/commands/`)

Tauri commands expose Rust functions to the frontend.

#### 1. Auth Commands (`auth.rs`)

- `start_oauth_login`: Initiate OAuth flow
- `load_oauth_tokens`: Load saved tokens
- `load_client_credentials`: Load saved credentials
- `logout`: Clear all auth data
- `is_authenticated`: Check auth status

#### 2. Settings Commands (`settings.rs`)

- `load_settings`: Load user settings
- `save_settings`: Save user settings
- `reset_settings`: Reset to defaults

#### 3. Git Commands (`git.rs`)

- `locate_git`: Find Git executable
- `get_executable_version`: Get version info

### System Tray (`src-tauri/src/tray/`)

Native Windows system tray integration.

**Menu Items**:
- Show RepoBar
- Refresh
- Settings
- Quit

**Features**:
- Right-click menu
- Event handling
- Icon management
- Window show/hide

### Frontend Components (`src/components/`)

#### 1. AuthView (`AuthView.tsx`)

OAuth login interface.

**Features**:
- GitHub host configuration
- Client ID/secret input
- Auto-load saved credentials
- Error handling
- OAuth instructions

#### 2. TrayWindow (`TrayWindow.tsx`)

Main repository list view.

**Features**:
- Repository list (placeholder)
- Refresh button
- Settings navigation
- Logout functionality
- External link opening

#### 3. SettingsView (`SettingsView.tsx`)

User preferences management.

**Sections**:
- Appearance (icons, theme)
- Repositories (filters, limits)
- Auto-refresh (interval)
- Advanced (git path, launch at login)

**Features**:
- Real-time updates
- Save/cancel
- Git detection display
- Validation

### Services (`src/services/`)

TypeScript wrappers for Tauri commands.

#### 1. Auth Service (`auth.ts`)

OAuth operations wrapper with TypeScript types.

#### 2. Settings Service (`settings.ts`)

Settings management with full type definitions.

#### 3. Git Service (`git.ts`)

Git executable operations.

## Data Flow Examples

### OAuth Login Flow

```
User clicks "Sign in"
   │
   ▼
AuthView.handleLogin()
   │
   ▼
services/auth.startOAuthLogin()
   │
   ▼
[Tauri IPC]
   │
   ▼
commands/auth::start_oauth_login
   │
   ▼
auth/oauth.rs::login()
   ├─► Start callback server (tiny_http)
   ├─► Generate PKCE challenge
   ├─► Build auth URL
   ├─► Open browser
   ├─► Wait for callback
   ├─► Validate state
   ├─► Exchange code (reqwest)
   └─► Save tokens (keyring)
   │
   ▼
Return OAuthTokens
   │
   ▼
AuthView.onLoginSuccess()
   │
   ▼
Navigate to TrayWindow
```

### Settings Save Flow

```
User modifies settings
   │
   ▼
SettingsView.handleSave()
   │
   ▼
services/settings.saveSettings()
   │
   ▼
[Tauri IPC]
   │
   ▼
commands/settings::save_settings
   │
   ▼
platform/settings_storage.rs::save()
   ├─► Create envelope { version, settings }
   ├─► Serialize to JSON
   └─► Write to %APPDATA%\RepoBar\settings.json
   │
   ▼
Return success
   │
   ▼
SettingsView shows success message
```

## Security Model

### Token Storage

- **Windows Credential Manager**: Native, encrypted storage
- **Service namespace**: Prevents conflicts
- **User-scoped**: Per-Windows-user isolation
- **No plaintext**: Never stored unencrypted

### OAuth Security

- **PKCE**: Prevents authorization code interception
- **State parameter**: CSRF protection
- **HTTPS only**: TLS for all GitHub communication
- **Localhost callback**: 127.0.0.1 only
- **Short timeout**: 3-minute window

### Settings Security

- **User directory**: %APPDATA% is user-scoped
- **JSON schema**: Validated on load
- **No secrets**: Only preferences, never tokens
- **Safe defaults**: Fall back on parse errors

## Performance Considerations

### Rust Backend

- **Zero-cost abstractions**: No runtime overhead
- **Async I/O**: Non-blocking HTTP and file operations
- **Minimal dependencies**: Fast compile times
- **Small binary**: ~10MB installer

### React Frontend

- **Virtual DOM**: Efficient updates
- **Code splitting**: Lazy load components (future)
- **Memoization**: Prevent unnecessary renders
- **Local state**: Minimal re-renders

### IPC Communication

- **Tauri IPC**: Direct Rust ↔ JS bridge
- **Serialization**: Fast serde JSON
- **Async commands**: Non-blocking UI

## Error Handling

### Rust

- **Result types**: Explicit error propagation
- **anyhow**: Context-rich errors
- **Graceful degradation**: Continue on non-critical errors

### TypeScript

- **Try-catch**: Async error handling
- **User feedback**: Error messages in UI
- **Logging**: Console errors for debugging

## Testing Strategy

### Unit Tests

```rust
// Rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pkce_generation() {
        let pkce = PKCE::generate();
        assert_eq!(pkce.verifier.len(), 43);
        assert_eq!(pkce.challenge.len(), 43);
    }
}
```

### Integration Tests

```rust
// Test OAuth flow with mock server
#[tokio::test]
async fn test_oauth_flow() {
    let storage = WindowsCredentialManagerStorage::new(...);
    let flow = OAuthLoginFlow::new(storage);
    // Test complete flow
}
```

### E2E Tests (Future)

- Playwright for UI automation
- Test login flow
- Test settings persistence
- Test tray interactions

## Future Enhancements

1. **GitHub API Integration**
   - Repository fetching
   - Pull requests, issues
   - Notifications

2. **Caching Layer**
   - SQLite for local cache
   - ETag support
   - Offline mode

3. **Advanced Features**
   - Contribution graphs
   - Repository search
   - Multi-account support

4. **Windows Integration**
   - Jump lists
   - Live tiles (if Windows 10)
   - Notifications

5. **Performance**
   - Virtual scrolling for large lists
   - Background sync
   - Incremental updates

## Comparison with macOS Version

| Feature | macOS | Windows |
|---------|-------|---------|
| **UI Framework** | SwiftUI | React + Tauri |
| **Token Storage** | Keychain | Credential Manager |
| **HTTP Server** | Network framework | tiny_http |
| **Settings** | UserDefaults | JSON file |
| **Binary Size** | ~15MB | ~10MB |
| **Startup Time** | ~300ms | ~500ms |
| **Memory Usage** | ~50MB | ~80MB (WebView2) |

## Resources

- [Tauri Documentation](https://tauri.app)
- [Windows Credential Manager](https://docs.microsoft.com/en-us/windows/win32/secauthn/credentials-management)
- [OAuth 2.0 RFC](https://tools.ietf.org/html/rfc6749)
- [PKCE RFC](https://tools.ietf.org/html/rfc7636)
- [React Documentation](https://react.dev)
