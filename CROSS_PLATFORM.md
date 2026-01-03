# Cross-Platform Architecture Guide

This document describes the platform abstraction layer that enables RepoBar to run on macOS, Windows, Web, and Linux with minimal code duplication.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Platform Protocols](#platform-protocols)
4. [Migration Guide](#migration-guide)
5. [Implementation Examples](#implementation-examples)
6. [Testing](#testing)

---

## Overview

RepoBarCore has been refactored to separate platform-specific code from business logic using a protocol-based abstraction layer. This enables:

- **65-75% code reuse** across all platforms
- **Single source of truth** for business logic
- **Easy testing** with mock implementations
- **Platform flexibility** without tight coupling

### Portability Score

| Component | Platform-Agnostic | Abstraction Needed | Platform-Specific |
|-----------|-------------------|-------------------|-------------------|
| Data Models | ✅ 100% | - | - |
| GitHub API | ✅ 95% | 5% (HTTP client) | - |
| Auth Logic | ✅ 80% | 20% (token storage, callback server) | - |
| Git Operations | ✅ 85% | 15% (executable locator) | - |
| Settings | ✅ 70% | 30% (persistence) | - |
| UI Layer | - | - | ❌ 100% |

---

## Architecture

### Before: Platform-Specific Dependencies

```swift
// Tightly coupled to macOS
import Security  // macOS Keychain
import Network   // macOS Network framework

struct TokenStore {
    func save() {
        // Hardcoded Keychain calls
        SecItemAdd(...)
    }
}
```

### After: Protocol-Based Abstraction

```swift
// Platform-agnostic protocol
protocol SecureTokenStorage: Sendable {
    func save(tokens: OAuthTokens) throws
    func load() throws -> OAuthTokens?
}

// Platform-specific implementations
#if os(macOS)
struct KeychainTokenStorage: SecureTokenStorage { ... }
#endif

// Rust implementation (Windows)
struct WindowsCredentialManagerStorage: SecureTokenStorage { ... }
```

---

## Platform Protocols

### 1. SecureTokenStorage

**Purpose**: Securely store OAuth tokens and credentials

**File**: `Sources/RepoBarCore/Platform/SecureTokenStorage.swift`

**Implementations**:
- **macOS/iOS**: `KeychainTokenStorage` (uses macOS Keychain)
- **Windows**: `WindowsCredentialManagerStorage` (Rust, uses Windows Credential Manager)
- **Web**: `DatabaseTokenStorage` (TypeScript, encrypted PostgreSQL storage)
- **Testing**: `InMemoryTokenStorage` (ephemeral storage)

**Example**:
```swift
// macOS
let storage: SecureTokenStorage = KeychainTokenStorage()
try await storage.save(tokens: oauthTokens)
let tokens = try await storage.load()
```

---

### 2. OAuthCallbackServer

**Purpose**: HTTP server for OAuth callbacks

**File**: `Sources/RepoBarCore/Platform/OAuthCallbackServer.swift`

**Implementations**:
- **macOS/iOS**: `NetworkFrameworkCallbackServer` (uses Network framework)
- **Windows**: `WinSockCallbackServer` (Rust, uses WinSock)
- **Web**: `NextJSCallbackHandler` (TypeScript, server-side route)
- **Testing**: `MockCallbackServer` (configurable mock)

**Example**:
```swift
// macOS
let server: OAuthCallbackServer = NetworkFrameworkCallbackServer(port: 53682)
let callbackURL = try server.start()
// Open browser to OAuth URL
let (code, state) = try await server.waitForCallback(timeout: 180)
server.stop()
```

---

### 3. ExecutableLocator

**Purpose**: Locate executable binaries (e.g., git)

**File**: `Sources/RepoBarCore/Platform/ExecutableLocator.swift`

**Implementations**:
- **macOS**: `MacOSExecutableLocator` (Homebrew, Xcode, system paths)
- **Windows**: `WindowsExecutableLocator` (Rust, Program Files, System32)
- **Linux**: `POSIXExecutableLocator` (/usr/bin, /usr/local/bin)
- **Testing**: `MockExecutableLocator` (returns configurable path)

**Example**:
```swift
// macOS
let locator: ExecutableLocator = MacOSExecutableLocator()
if let gitURL = locator.locate(executable: "git") {
    let (version, error) = locator.version(at: gitURL)
    print("Git: \(version ?? "unknown")")
}
```

---

### 4. UserSettingsStorage

**Purpose**: Persist user settings and preferences

**File**: `Sources/RepoBarCore/Platform/UserSettingsStorage.swift`

**Implementations**:
- **macOS/iOS**: `UserDefaultsSettingsStorage` (uses UserDefaults)
- **Windows/Linux**: `JSONFileSettingsStorage` (JSON file in AppData/~/.config)
- **Web**: `DatabaseSettingsStorage` (TypeScript, PostgreSQL)
- **Testing**: `InMemorySettingsStorage` (ephemeral storage)

**Example**:
```swift
// macOS
let storage: UserSettingsStorage = UserDefaultsSettingsStorage()
let settings = await storage.load()
var updated = settings
updated.appearance.accentTone = .systemAccent
await storage.save(updated)
```

---

### 5. PlatformServices (Unified Bundle)

**Purpose**: Single injection point for all platform dependencies

**File**: `Sources/RepoBarCore/Platform/PlatformServices.swift`

**Example**:
```swift
// macOS
let services: PlatformServices = ApplePlatformServices()

// Windows (via Rust FFI)
let services: PlatformServices = WindowsPlatformServices()

// Testing
let services: PlatformServices = MockPlatformServices()

// Use in RepoBarCore
let flow = OAuthLoginFlow(
    platform: services,
    openURL: { try NSWorkspace.shared.open($0) }
)
```

---

## Migration Guide

### Step 1: Update OAuthLoginFlow Usage

#### Before (macOS-only):
```swift
let flow = OAuthLoginFlow(
    tokenStore: .shared,
    openURL: { try NSWorkspace.shared.open($0) }
)
```

#### After (cross-platform):
```swift
let platform: PlatformServices = ApplePlatformServices()
let flow = OAuthLoginFlow(
    platform: platform,
    openURL: { try NSWorkspace.shared.open($0) }
)
```

### Step 2: Update Direct TokenStore Usage

#### Before:
```swift
let tokens = try TokenStore.shared.load()
try TokenStore.shared.save(tokens: newTokens)
```

#### After:
```swift
let storage = platform.tokenStorage
let tokens = try storage.load()
try storage.save(tokens: newTokens)
```

### Step 3: Update GitExecutable Usage

#### Before:
```swift
let gitURL = GitExecutableLocator.shared.url
let (version, _) = GitExecutableLocator.version(at: gitURL)
```

#### After:
```swift
let locator = platform.executableLocator
if let gitURL = locator.locate(executable: "git") {
    let (version, _) = locator.version(at: gitURL)
}
```

### Step 4: Update Settings Usage

#### Before:
```swift
let store = SettingsStore()
let settings = store.load()
store.save(updatedSettings)
```

#### After:
```swift
let storage = platform.settingsStorage
let settings = await storage.load()
await storage.save(updatedSettings)
```

---

## Implementation Examples

### Windows Implementation (Rust + Tauri)

```rust
// src-tauri/src/platform/token_storage.rs
use keyring::Entry;
use serde_json;

pub struct WindowsCredentialManagerStorage {
    service: String,
}

impl WindowsCredentialManagerStorage {
    pub fn new(service: String) -> Self {
        Self { service }
    }

    pub fn save_tokens(&self, tokens: &OAuthTokens) -> Result<()> {
        let entry = Entry::new(&self.service, "default")?;
        let json = serde_json::to_string(tokens)?;
        entry.set_password(&json)?;
        Ok(())
    }

    pub fn load_tokens(&self) -> Result<Option<OAuthTokens>> {
        let entry = Entry::new(&self.service, "default")?;
        match entry.get_password() {
            Ok(json) => {
                let tokens = serde_json::from_str(&json)?;
                Ok(Some(tokens))
            }
            Err(_) => Ok(None),
        }
    }
}

// Platform services bundle
pub struct WindowsPlatformServices {
    pub token_storage: WindowsCredentialManagerStorage,
    pub callback_server: WinSockCallbackServer,
    pub executable_locator: WindowsExecutableLocator,
    pub settings_storage: JSONFileSettingsStorage,
}

impl WindowsPlatformServices {
    pub fn new() -> Self {
        Self {
            token_storage: WindowsCredentialManagerStorage::new("com.repobar.auth".to_string()),
            callback_server: WinSockCallbackServer::new(53682),
            executable_locator: WindowsExecutableLocator::new(),
            settings_storage: JSONFileSettingsStorage::new("RepoBar".to_string()),
        }
    }
}
```

### Web Implementation (TypeScript + Next.js)

```typescript
// lib/platform/token-storage.ts
import { prisma } from '@/lib/db/prisma'
import { encrypt, decrypt } from '@/lib/crypto'

export class DatabaseTokenStorage {
  constructor(private userId: string) {}

  async saveTokens(tokens: OAuthTokens): Promise<void> {
    const encrypted = encrypt(JSON.stringify(tokens))
    await prisma.oauthToken.upsert({
      where: { userId: this.userId },
      create: { userId: this.userId, encryptedTokens: encrypted },
      update: { encryptedTokens: encrypted },
    })
  }

  async loadTokens(): Promise<OAuthTokens | null> {
    const record = await prisma.oauthToken.findUnique({
      where: { userId: this.userId },
    })
    if (!record) return null
    const decrypted = decrypt(record.encryptedTokens)
    return JSON.parse(decrypted)
  }
}

// Platform services bundle
export class WebPlatformServices {
  tokenStorage: DatabaseTokenStorage
  callbackServer: NextJSCallbackHandler
  executableLocator: NoOpExecutableLocator  // No local executables on web
  settingsStorage: DatabaseSettingsStorage

  constructor(userId: string) {
    this.tokenStorage = new DatabaseTokenStorage(userId)
    this.callbackServer = new NextJSCallbackHandler()
    this.executableLocator = new NoOpExecutableLocator()
    this.settingsStorage = new DatabaseSettingsStorage(userId)
  }
}
```

---

## Testing

### Unit Tests with Mocks

```swift
import Testing
@testable import RepoBarCore

@Test("OAuth flow saves tokens")
func testOAuthFlowSavesTokens() async throws {
    // Arrange
    let mockStorage = InMemoryTokenStorage()
    let mockServer = MockCallbackServer()
    await mockServer.configureMock(code: "test_code", state: "test_state")

    let mockServices = MockPlatformServices(
        tokenStorage: mockStorage,
        callbackServer: mockServer
    )

    let flow = OAuthLoginFlow(
        platform: mockServices,
        openURL: { _ in /* no-op */ }
    )

    // Act
    let tokens = try await flow.login(
        clientID: "test_id",
        clientSecret: "test_secret",
        host: URL(string: "https://github.com")!,
        loopbackPort: 53682
    )

    // Assert
    #expect(tokens.accessToken.isEmpty == false)
    let stored = try await mockStorage.load()
    #expect(stored?.accessToken == tokens.accessToken)
}
```

### Integration Tests

```swift
@Test("Keychain storage persists tokens")
func testKeychainPersistence() async throws {
    #if os(macOS)
    let storage = KeychainTokenStorage(service: "com.test.repobar")

    let testTokens = OAuthTokens(
        accessToken: "test_access",
        refreshToken: "test_refresh",
        expiresAt: Date().addingTimeInterval(3600)
    )

    try storage.save(tokens: testTokens)
    let loaded = try storage.load()

    #expect(loaded?.accessToken == "test_access")

    storage.clear()
    #expect(try storage.load() == nil)
    #endif
}
```

---

## Next Steps

1. **Complete Refactoring**:
   - ✅ TokenStore → SecureTokenStorage
   - ✅ LoopbackServer → OAuthCallbackServer
   - ✅ OAuthLoginFlow → PlatformServices
   - ⏳ GitExecutable → ExecutableLocator
   - ⏳ SettingsStore → UserSettingsStorage
   - ⏳ LocalGitService (inject ExecutableLocator)

2. **Platform Implementations**:
   - ✅ macOS (done)
   - ⏳ Windows (Rust/Tauri)
   - ⏳ Web (TypeScript/Next.js)
   - ⏳ Linux (Rust/native)

3. **Testing**:
   - ⏳ Unit tests for all protocols
   - ⏳ Integration tests per platform
   - ⏳ E2E tests for OAuth flow

4. **Documentation**:
   - ✅ Architecture guide (this document)
   - ⏳ API reference (code comments)
   - ⏳ Platform-specific setup guides

---

## Benefits Summary

✅ **65-75% code reuse** across platforms
✅ **Testable** with mock implementations
✅ **Flexible** - easy to add new platforms
✅ **Maintainable** - single source of truth
✅ **Type-safe** - protocol contracts enforced
✅ **Future-proof** - easy to migrate storage backends

---

## Questions?

See `/docs/architecture.md` for detailed system design or reach out to the team.
