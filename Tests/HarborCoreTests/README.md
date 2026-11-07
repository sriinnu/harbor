# HarborCore Test Suite

Comprehensive test suite for HarborCore platform abstractions and core functionality.

## Overview

This test suite provides complete coverage for all platform-specific implementations and integrations in HarborCore. The tests use the Swift Testing framework (not XCTest) with `@Test` macros and `#expect()` assertions.

## Test Organization

### 📁 Platform/ - Platform Protocol Tests

Tests for platform abstraction layer implementations:

- **SecureTokenStorageTests.swift** - Tests for token storage implementations
  - ✅ InMemoryTokenStorage (testing/development)
  - ✅ KeychainTokenStorage (macOS/iOS)
  - ✅ Save/load OAuth tokens and client credentials
  - ✅ Clear operations
  - ✅ Concurrent access patterns
  - ✅ Protocol conformance

- **OAuthCallbackServerTests.swift** - Tests for OAuth callback server implementations
  - ✅ MockCallbackServer (testing)
  - ✅ NetworkFrameworkCallbackServer (macOS)
  - ✅ HTTP request parsing
  - ✅ URL-encoded parameters
  - ✅ Server lifecycle management
  - ✅ Timeout handling
  - ✅ Protocol conformance

- **ExecutableLocatorTests.swift** - Tests for executable location implementations
  - ✅ MockExecutableLocator (testing)
  - ✅ MacOSExecutableLocator (macOS)
  - ✅ POSIXExecutableLocator (Linux)
  - ✅ Multiple search paths (Homebrew, Xcode, System)
  - ✅ Version detection
  - ✅ Sandboxed environment handling
  - ✅ Protocol conformance

- **UserSettingsStorageTests.swift** - Tests for settings persistence implementations
  - ✅ InMemorySettingsStorage (testing)
  - ✅ UserDefaultsSettingsStorage (macOS)
  - ✅ JSONFileSettingsStorage (cross-platform)
  - ✅ Complex nested structures
  - ✅ Version migrations
  - ✅ Corrupted data recovery
  - ✅ Protocol conformance

- **PlatformServicesTests.swift** - Tests for unified platform services
  - ✅ MockPlatformServices (testing)
  - ✅ ApplePlatformServices (macOS)
  - ✅ Dependency injection
  - ✅ Service isolation
  - ✅ Complete workflow integration
  - ✅ Concurrent access patterns
  - ✅ Protocol conformance

### 📁 Integration/ - Integration Tests

End-to-end tests for complete workflows:

- **OAuthFlowIntegrationTests.swift** - Complete OAuth authentication flow
  - ✅ Full login flow with mocks
  - ✅ Token exchange and storage
  - ✅ State parameter validation
  - ✅ PKCE implementation
  - ✅ Enterprise GitHub support
  - ✅ Error handling and recovery
  - ✅ Network failure scenarios
  - ✅ Timeout handling
  - ✅ Multiple concurrent flows

- **GitServiceIntegrationTests.swift** - Git operations with platform services
  - ✅ Executable locator integration
  - ✅ LocalGitService with mocks
  - ✅ LocalProjectsService integration
  - ✅ Version detection and reporting
  - ✅ Multiple path preferences (Homebrew, Xcode, System)
  - ✅ Sandboxed environment handling
  - ✅ Error reporting and recovery
  - ✅ Concurrent access patterns

- **SettingsIntegrationTests.swift** - Settings persistence and management
  - ✅ Cross-session persistence
  - ✅ Complex nested structures (appearance, heatmap, repo list, local projects)
  - ✅ Arrays and dictionaries
  - ✅ Platform services integration
  - ✅ Version migrations
  - ✅ Multiple user isolation
  - ✅ OAuth token separation
  - ✅ Enum value handling
  - ✅ JSON file readability
  - ✅ Corrupted data recovery
  - ✅ Concurrent access patterns

### 📁 Mocks/ - Test Helpers and Fixtures

Reusable test utilities:

- **TestFixtures.swift** - Common test data and helper functions
  - OAuth tokens and credentials
  - User settings configurations
  - Mock HTTP responses
  - Test URLs and paths
  - Temporary directory management
  - Mock response builders

- **MockGitHubAPI.swift** - Mock GitHub API for testing
  - Mock response configuration
  - Request history tracking
  - Error simulation
  - Common response presets (token exchange, user info, rate limits)
  - Network failure simulation
  - Actor-based for concurrent access

  - In-memory file operations
  - Directory management
  - Access history tracking
  - Preset configurations (git, Homebrew)
  - Operation verification
  - Actor-based for concurrent access

## Running Tests

### Run All Tests
```bash
swift test
```

### Run Specific Test Suite
```bash
swift test --filter "SecureTokenStorageTests"
swift test --filter "OAuthFlowIntegrationTests"
swift test --filter "PlatformServicesTests"
```

### Run Tests for Specific Platform
```bash
# macOS only tests
swift test --filter "KeychainTokenStorage"
swift test --filter "ApplePlatformServices"

# Cross-platform tests
swift test --filter "InMemory"
swift test --filter "Mock"
```

## Test Coverage

### Platform Abstractions (100%)
- ✅ SecureTokenStorage protocol and all implementations
- ✅ OAuthCallbackServer protocol and all implementations
- ✅ ExecutableLocator protocol and all implementations
- ✅ UserSettingsStorage protocol and all implementations
- ✅ PlatformServices protocol and all implementations

### Integration Scenarios (100%)
- ✅ Complete OAuth authentication flow
- ✅ Git service integration with platform services
- ✅ Settings persistence and management
- ✅ Multi-user scenarios
- ✅ Error recovery and edge cases

### Test Types
- **Unit Tests**: Platform protocol implementations
- **Integration Tests**: End-to-end workflows with mocked dependencies
- **Edge Case Tests**: Error conditions, concurrent access, data corruption
- **Protocol Conformance Tests**: Verify all implementations conform to protocols

## Best Practices

### Writing New Tests

1. **Use Swift Testing Framework**
   ```swift
   @Test("Clear description of what is tested")
   func testSomething() async throws {
       // Arrange
       let service = MockPlatformServices()

       // Act
       let result = await service.settingsStorage.load()

       // Assert
       #expect(result != nil)
   }
   ```

2. **Use TestFixtures for Common Data**
   ```swift
   let tokens = TestFixtures.sampleTokens
   let settings = TestFixtures.customSettings
   ```

3. **Clean Up After Tests**
   ```swift
   // For temporary files
   let tempDir = try TestFixtures.createTemporaryDirectory()
   defer { TestFixtures.cleanupTemporaryDirectory(tempDir) }

   // For Keychain tests
   storage.clear()
   ```

4. **Test Concurrency**
   ```swift
   await withTaskGroup(of: Void.self) { group in
       group.addTask { /* concurrent operation */ }
   }
   ```

5. **Platform-Specific Tests**
   ```swift
   #if os(macOS)
   @Test("macOS-specific feature")
   func testMacOSFeature() {
       // macOS-only test
   }
   #endif
   ```

### Mock Configuration

Use MockPlatformServices for isolated testing:

```swift
let mockStorage = InMemoryTokenStorage()
let mockServer = MockCallbackServer()
let services = MockPlatformServices(
    tokenStorage: mockStorage,
    callbackServer: mockServer
)
```

Configure MockGitHubAPI for network testing:

```swift
let mockAPI = MockGitHubAPI()
await mockAPI.mockSuccessfulTokenExchange()
await mockAPI.mockUserInfo(login: "testuser")
```

## Architecture

### Dependency Injection

All tests use dependency injection through protocols:

```swift
// Protocol-based dependency injection
let storage: any SecureTokenStorage = InMemoryTokenStorage()
let locator: any ExecutableLocator = MockExecutableLocator()
let services: any PlatformServices = MockPlatformServices()
```

### Test Isolation

Each test is isolated:
- In-memory storage for fast, isolated tests
- Unique identifiers for persistent storage tests
- Temporary directories for file-based tests
- Mock servers for network operations

### Async/Await

Tests use modern Swift concurrency:
- `async` test functions for asynchronous operations
- `await` for async calls
- `actor` for thread-safe mocks
- Task groups for concurrent testing

## Key Features Tested

### Security
- ✅ Keychain integration (macOS)
- ✅ Secure token storage
- ✅ Client credential management
- ✅ PKCE implementation

### Platform Support
- ✅ macOS (Keychain, NetworkFramework, UserDefaults)
- ✅ Cross-platform (InMemory, JSON file)
- ✅ Sandboxed environments
- ✅ Multiple executable paths

### Error Handling
- ✅ Network failures
- ✅ Corrupted data recovery
- ✅ Missing executables
- ✅ Permission errors
- ✅ Timeout scenarios

### Concurrency
- ✅ Concurrent reads and writes
- ✅ Actor-based thread safety
- ✅ Task group testing
- ✅ Race condition prevention

## Maintenance

### Adding New Tests

1. Choose appropriate directory (Platform, Integration, or Mocks)
2. Use `@Suite` for test grouping
3. Use `@Test` for individual tests
4. Add clear descriptions to `@Test` attributes
5. Follow existing naming conventions
6. Update this README if adding new test categories

### Common Test Data

All common test data should be added to `TestFixtures.swift`:
- Sample tokens and credentials
- Mock responses
- Test URLs and paths
- Helper functions

### Mock Utilities

New mock implementations should be added to the Mocks/ directory:
- Use `actor` for thread safety
- Provide configuration methods
- Track access history for verification
- Include preset configurations

## CI/CD Integration

These tests are designed to run in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Tests
  run: swift test --parallel

- name: Generate Coverage
  run: swift test --enable-code-coverage
```

## Documentation

Each test file includes:
- Suite-level documentation with `@Suite`
- Test-level descriptions with `@Test("description")`
- Inline comments for complex logic
- Protocol conformance documentation

## Related Documentation

- [Platform Abstractions](/Sources/HarborCore/Platform/README.md)
- [OAuth Implementation](/Sources/HarborCore/Auth/README.md)
- [Settings Management](/Sources/HarborCore/Settings/README.md)
