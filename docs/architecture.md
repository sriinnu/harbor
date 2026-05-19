# Harbor Architecture

## Multi-Provider Source Control Platform

Harbor is a macOS menu bar app that provides unified access to GitHub, Azure DevOps, and GitLab repositories, pull requests, issues, and CI/CD pipelines.

> **Architecture Principles**
> - **Modular**: Clear separation of concerns by layer and provider
> - **Performant**: Actor-based concurrency, aggressive caching, rate-limit awareness
> - **Well-Documented**: Every public API has documentation, architecture decisions recorded
> - **Testable**: Dependency injection, protocol-based interfaces, actor isolation

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Harbor App                              │
│                                                              │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────┐  │
│  │   Menu Bar   │    │  Settings   │    │    About Panel  │  │
│  │    Dropdown   │    │    Views    │    │                 │  │
│  └──────┬──────┘    └──────┬──────┘    └─────────────────┘  │
│         │                   │                                  │
│         └─────────┬─────────┘                                  │
│                   ▼                                            │
│         ┌─────────────────────┐                                │
│         │     AppState        │◄─── Main State Container       │
│         │   (Observable)      │                                │
│         └──────────┬──────────┘                                │
│                    │                                           │
│         ┌──────────┴──────────┐                                │
│         │                     │                                │
│         ▼                     ▼                                │
│  ┌─────────────┐      ┌─────────────┐                         │
│  │  GitHub     │      │  Azure      │                         │
│  │  Client     │      │  DevOps     │                         │
│  │  (OAuth)    │      │  Client     │                         │
│  └─────────────┘      │  (PAT)      │                         │
│                       └─────────────┘                         │
│                              │                                 │
│         ┌────────────────────┴────────────────────┐           │
│         ▼                                          ▼           │
│  ┌─────────────┐                         ┌─────────────┐      │
│  │   GitLab    │                         │  Auth       │      │
│  │  Client     │                         │  Coordinator │      │
│  │  (Token)    │                         │  (OAuth)    │      │
│  └─────────────┘                         └─────────────┘      │
│         │                                          │          │
│         └────────────────────┬───────────────────┘          │
│                              ▼                               │
│         ┌─────────────────────────────────────────────────┐ │
│         │              HarborCore (Shared Logic)          │ │
│         │  ┌─────────────┐  ┌─────────────┐  ┌──────────┐│ │
│         │  │   Models    │  │   API       │  │  Auth    ││ │
│         │  │             │  │   Clients   │  │  (PAT)   ││ │
│         │  └─────────────┘  └─────────────┘  └──────────┘│ │
│         └─────────────────────────────────────────────────┘ │
│                            │                                  │
│                            ▼                                  │
│         ┌─────────────────────────────────────────────────┐ │
│         │              External APIs                      │ │
│         │  ┌───────────┐  ┌───────────┐  ┌─────────────┐ │ │
│         │  │  GitHub   │  │  Azure    │  │   GitLab    │ │ │
│         │  │  REST+    │  │  DevOps   │  │    REST     │ │ │
│         │  │  GraphQL  │  │  REST     │  │             │ │ │
│         │  └───────────┘  └───────────┘  └─────────────┘ │ │
│         └─────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Layer Structure

### Presentation Layer (`Sources/Harbor/`)
- **Views** - SwiftUI views for menu bar, settings, about
- **StatusBar** - Menu construction and management
- **ViewModels** - State binding for UI

### Application Layer (`Sources/Harbor/App/`)
- **AppState** - Main observable state container
- **Session** - User session data
- **Refresh** - Background refresh scheduling

### Domain Layer (`Sources/HarborCore/Models/`)
- **Shared Models** - Provider-agnostic types (Repository, PR, Issue)
- **Provider Models** - Provider-specific types (AzureDevOps, GitLab)
- **Enums** - ProviderType, CIStatus, etc.

### API Layer (`Sources/HarborCore/API/`)
- **Provider Clients** - Actor-based API clients
- **REST APIs** - Endpoint definitions
- **Request Runners** - HTTP execution with caching/rate-limiting
- **Decoders** - JSON decoding utilities

### Infrastructure Layer (`Sources/HarborCore/Infrastructure/`)
- **Keychain** - Secure token storage
- **Network** - HTTP utilities
- **FileSystem** - Local data persistence

---

## 3. Provider Client Architecture

### Pattern: Actor-Based Isolation

All provider clients use Swift actors for thread-safe async operations:

```swift
public actor GitHubClient {
    private let apiHost: URL
    private let requestRunner: GitHubRequestRunner
    private var prefetchedRepos: [Repository] = []

    public func defaultRepositories(limit: Int) async throws -> [Repository]
}
```

### Client Structure

```
┌─────────────────────────────────────────────┐
│           Provider Client (Actor)            │
│  - High-level operations                     │
│  - Business logic                            │
│  - Caching decisions                         │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│           REST API (Sendable struct)         │
│  - Endpoint definitions                      │
│  - URL construction                          │
│  - Parameter encoding                        │
└──────────────────┬──────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────┐
│         Request Runner (Actor)               │
│  - HTTP execution                            │
│  - Rate limiting                             │
│  - ETag caching                              │
│  - Retry logic                               │
└─────────────────────────────────────────────┘
```

### Client Comparison

| Aspect | GitHub | Azure DevOps | GitLab |
|--------|--------|--------------|--------|
| **Base URL** | `api.github.com` | `dev.azure.com/{org}` | `{instance}/api/v4` |
| **Auth** | OAuth (token) | PAT (basic auth) | PRIVATE-TOKEN |
| **API Type** | REST + GraphQL | REST | REST |
| **Caching** | ETag + RepoDetailCoordinator | ETag | None |
| **Rate Limiting** | Yes (RequestRunner) | Yes (RequestRunner) | No |
| **Pagination** | Link header | `$top`, `$skip` | `page`, `per_page` |
| **Special** | Contribution heatmap (GraphQL) | WIQL for work items | Self-hosted support |

---

## 4. File Organization

### By Layer

```
Sources/HarborCore/
├── API/
│   ├── Protocols/
│   │   └── SourceControlProvider.swift
│   ├── GitHub/
│   │   ├── GitHubClient.swift
│   │   ├── GitHubRestAPI.swift
│   │   ├── GitHubRequestRunner.swift
│   │   ├── GitHubDecoding.swift
│   │   └── GitHubRecentDecoders.swift
│   ├── AzureDevOps/
│   │   ├── AzureDevOpsClient.swift
│   │   ├── AzureDevOpsRestAPI.swift
│   │   ├── AzureDevOpsRequestRunner.swift
│   │   ├── AzureDevOpsDecoding.swift
│   │   ├── AzureDevOpsWIQL.swift
│   │   └── AzureDevOpsRecentDecoders.swift
│   ├── GitLab/
│   │   ├── GitLabClient.swift
│   │   └── GitLabDecoding.swift
│   └── Shared/
│       ├── RepoDetailCoordinator.swift
│       └── RateLimitSnapshot.swift
│
├── Models/
│   ├── Repository.swift
│   ├── RepoRecentItems.swift
│   ├── UserIdentity.swift
│   ├── ProviderType.swift
│   ├── AzureDevOpsModels+Domain.swift
│   ├── AzureDevOpsUser.swift
│   ├── GitLab.swift
│   └── (Provider-specific models)
│
└── Infrastructure/
    ├── Keychain/
    │   ├── TokenStore.swift
    │   └── AzureDevOpsPATStore.swift
    └── Auth/
        └── OAuthCoordinator.swift

Sources/Harbor/
├── App/
│   ├── AppState.swift
│   ├── Session.swift
│   └── AppState+Refresh.swift
├── Settings/
│   ├── AccountSettingsView.swift
│   └── About/
├── StatusBar/
│   ├── StatusBarMenuManager.swift
│   ├── StatusBarMenuBuilder.swift
│   └── ActivityMenuCoordinator.swift
└── Views/
    ├── HarborIconView.swift
    └── MultiProviderStatusView.swift
```

### By Provider

```
Sources/HarborCore/API/{Provider}/
├── {Provider}Client.swift          # Main actor
├── {Provider}RestAPI.swift         # Endpoints
├── {Provider}RequestRunner.swift   # HTTP layer
└── {Provider}Decoding.swift        # JSON decoding
```

---

## 5. Data Flow

### Refresh Flow

```
┌──────────────┐
│ Timer/Event  │
└──────┬───────┘
       ▼
┌──────────────┐
│ AppState     │◄─── Receives refresh trigger
│ .refresh()   │
└──────┬───────┘
       ▼
┌──────────────────────────────────────┐
│ 1. Fetch repositories for each       │
│    connected provider                 │
│    (GitHub, Azure, GitLab)           │
└──────┬───────────────────┬───────────┘
       │                   │
       ▼                   ▼
┌──────────────┐   ┌──────────────────┐
│ GitHubClient │   │ AzureDevOpsClient│
│ .activity    │   │ .fetchRepositories│
│ Repositories │   └──────────────────┘
└──────┬───────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 2. Hydrate with details              │
│    - Latest release                  │
│    - CI status                       │
│    - Recent activity                 │
└──────┬───────────────────┬───────────┘
       │                   │
       ▼                   ▼
┌──────────────┐   ┌──────────────────┐
│ Repository   │   │ Repository       │
│ DisplayModel │   │ DisplayModel     │
└──────┬───────┘   └──────────────────┘
       │
       ▼
┌──────────────────────────────────────┐
│ 3. Update menu with Repository       │
│    DisplayModels                     │
└──────────────────────────────────────┘
```

### Authentication Flow

```
┌──────────────┐
│ User clicks  │
│ "Sign In"    │
└──────┬───────┘
       ▼
┌──────────────────────────────────────┐
│ AccountSettingsView                  │
│ - Collects credentials               │
│ - Calls appState.auth.login()        │
└──────┬───────────────────┬───────────┘
       │                   │
       ▼                   ▼
┌──────────────┐   ┌──────────────────┐
│ GitHub:      │   │ Azure:           │
│ OAuth flow   │   │ PAT validation   │
│ + Keychain   │   │ + Keychain       │
└──────┬───────┘   └──────────────────┘
       │                   │
       ▼                   ▼
┌──────────────────────────────────────┐
│ Session.account = .loggedIn(user)    │
│ Session.isGitHubConnected = true     │
│ Session.isAzureConnected = true      │
└──────────────────────────────────────┘
```

---

## 6. Provider Integration Checklist

When adding a new provider, follow this checklist:

### 1. Models
- [ ] Create provider-specific models in `Sources/HarborCore/Models/`
- [ ] Implement `ProviderRepository`, `ProviderPullRequest`, etc. protocols
- [ ] Add to `ProviderType` enum
- [ ] Add mapper functions in `SourceControlProvider.swift`

### 2. API Client
- [ ] Create `{Provider}Client.swift` (actor-based)
- [ ] Create `{Provider}RestAPI.swift` (Sendable struct)
- [ ] Create `{Provider}RequestRunner.swift` (actor-based)
- [ ] Implement `fetchRepositories()`, `fetchPullRequests()`, `fetchIssues()`
- [ ] Add rate limiting and caching

### 3. AppState Integration
- [ ] Add client property to `AppState`
- [ ] Add connection state properties to `Session`
- [ ] Add refresh logic for the provider

### 4. UI Integration
- [ ] Add section to `AccountSettingsView`
- [ ] Add menu items to `StatusBarMenuBuilder`
- [ ] Add provider badge to `MultiProviderStatusView`

### 5. Testing
- [ ] Unit tests for API client
- [ ] Integration tests for auth flow
- [ ] Manual testing with real account

---

## 7. Key Design Decisions

### Why Actors?
- Thread-safe concurrent access
- No data races without explicit locks
- Natural isolation of per-provider state

### Why Protocol-Based Abstraction?
- Unified interface for common operations
- Easy to add new providers
- Enables provider-agnostic UI code

### Why Separate REST API from Client?
- Separation of concerns
- Easier testing of endpoint logic
- Reusable URL construction

### Why ETag Caching?
- Reduces API calls (rate limit friendly)
- 304 Not Modified = no data transfer
- Works with all providers

---

## 8. Anti-Patterns to Avoid

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Direct URLSession in view | No caching, hard to test | Use RequestRunner |
| Force unwrapping optionals | Crashes | Use `guard` + throw |
| Global state | Hard to test, race conditions | Use actors, dependency injection |
| Duplicate code | Maintenance burden | Extract to shared utilities |
| Any-typed returns | Lost type safety | Use associated types in protocols |
| Mixing sync/async | Deadlocks, confusion | Use `async/await` consistently |

---

## 9. Performance Considerations

### Caching Strategy
- **Repositories**: ETag + in-memory cache (1 hour)
- **Releases**: In-memory cache (30 minutes)
- **Heatmap**: Persistent cache (24 hours)

### Rate Limiting Handling
- **GitHub**: Handle 403 with `Retry-After`
- **Azure DevOps**: Monitor header-based limits
- **GitLab**: Respect `RateLimit-Limit` headers

### Background Refresh
- Every 5 minutes when menu is open
- Every 30 minutes when menu is closed
- Immediate refresh on window focus

---

## 10. Security

### Token Storage
- All tokens stored in macOS Keychain
- Never log or expose tokens
- Tokens cleared on disconnect

### Network Security
- HTTPS required for all providers
- Certificate validation enabled
- No HTTP mixed content

### Privacy
- No analytics or telemetry
- All data stays local
- No external tracking

---

## 11. Code Style Guidelines

### Swift Conventions

Harbor follows Swift API Design Guidelines with additional conventions:

```swift
// MARK: - Section Organization
// Every file should have MARK sections for logical groupings

// MARK: - Public Types
// Public enums, structs, classes first

// MARK: - Internal Types
// Private/internal helpers

// MARK: - Extensions
// Protocol conformances grouped together
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Protocols | PascalCase, singular noun | `SourceControlProvider` |
| Actors | PascalCase, descriptive | `GitHubClient` |
| Enums | PascalCase, singular | `ProviderType` |
| Structs | PascalCase | `Repository` |
| Properties | camelCase | `isAuthenticated` |
| Constants | camelCase, k-prefixed (rare) | `defaultTimeout` |
| Private vars | underscore prefix (optional) | `_cache` |

### Documentation Standards

Every public API must have documentation:

```swift
/// Fetches the authenticated user's identity.
///
/// - Returns: The user's identity including username and home URL
/// - Throws: `URLError.userAuthenticationRequired` if not authenticated
/// - Note: This method caches the result for the session lifetime
public func currentUser() async throws -> UserIdentity
```

### File Structure

```
Sources/HarborCore/API/{Provider}/
├── {Provider}Client.swift          # Main actor (100-300 lines)
├── {Provider}RestAPI.swift         # Endpoint definitions (100-200 lines)
├── {Provider}RequestRunner.swift   # HTTP layer (100-200 lines)
└── {Provider}Decoding.swift        # JSON decoding (100-200 lines)
```

**Maximum file size**: 400 lines. If exceeding, split into logical units.

---

## 12. Module Boundaries

### HarborCore (`HarborCore`)

Shared business logic with no UI dependencies:

```
Sources/HarborCore/
├── API/           # Provider clients, REST APIs
├── Auth/          # Authentication coordinators
├── Models/        # Domain models (provider-agnostic)
└── Settings/      # User settings storage
```

**Rules**:
- No `SwiftUI`, `AppKit`, or `UIKit` imports
- All public types marked with `public` and documentation
- Protocols use `@Sendable` for async compatibility
- No UI-specific logic

### Harbor App (`Harbor`)

macOS-specific UI and app logic:

```
Sources/Harbor/
├── App/           # App lifecycle, state management
├── Auth/          # OAuth flow coordination
├── Settings/      # Settings panels
├── StatusBar/     # Menu bar integration
├── Support/       # Utilities and helpers
└── Views/         # SwiftUI views
```

**Rules**:
- Can import `SwiftUI`, `AppKit`, HarborCore
- UI logic separated from business logic
- Use `@MainActor` for view models

### CLI (`harbor`)

Command-line interface:

```
Sources/HarborCLI/
├── Commands/      # CLI commands
└── Utilities/     # CLI helpers
```

**Rules**:
- Minimal imports (Commander, Foundation, HarborCore)
- Output formatting separated from business logic

---

## 13. Performance Budgets

| Operation | Target | Maximum |
|-----------|--------|---------|
| Menu open (cached) | < 50ms | 100ms |
| Menu open (refresh) | < 500ms | 2s |
| API request (cached) | < 50ms | 100ms |
| API request (fresh) | < 200ms | 5s |
| Memory footprint | < 100MB | 200MB |
| Disk cache size | < 200MB | 500MB |

### Performance Testing

```bash
# Profile app launch
 Instruments > App Launch

# Profile memory usage
 Instruments > Allocations > Track Living

# Profile API latency
# Check Diagnostics in Settings > Debug
```

---

## 14. Testing Strategy

### Unit Tests

Located in `Tests/` directory:

```
Tests/HarborCoreTests/
├── API/           # API client tests
├── Auth/          # Authentication tests
└── Models/        # Model tests

Tests/HarborTests/
├── App/           # AppState tests
└── Views/         # View tests
```

### Test Coverage Goals

| Component | Minimum | Target |
|-----------|---------|--------|
| API Clients | 70% | 85% |
| Models | 80% | 90% |
| Auth | 60% | 80% |
| Overall | 60% | 80% |

### Running Tests

```bash
# All tests
swift test

# Coverage report
swift test --enable-code-coverage

# Specific test
swift test --filter GitHubClientTests
```

---

## 15. References

- [Swift Concurrency](https://docs.swift.org/swift-book/documentation/swiftswift-language-guide/concurrency/)
- [GitHub REST API](https://docs.github.com/en/rest)
- [Azure DevOps REST API](https://learn.microsoft.com/en-us/rest/api/azure/devops/)
- [GitLab REST API](https://docs.gitlab.com/ee/api/rest/)
- [macOS Keychain](https://developer.apple.com/documentation/security/keychain_services)
