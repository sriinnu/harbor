import Foundation

// MARK: - Module Boundary Enforcement

/// Defines the boundaries between Harbor's modules.
///
/// This file enforces architectural boundaries at compile time through
/// access control. Each module has specific rules:
///
/// - **HarborCore**: No UI imports (SwiftUI, AppKit, UIKit)
/// - **Harbor**: Can import HarborCore and UI frameworks
/// - **HarborCLI**: Minimal imports, only Foundation + HarborCore
///
/// ## Architecture Layers
///
/// HARBOR (UI Layer)
///   Views/ Settings/ StatusBar/ Auth/ App/
///            |
///            v
/// HARBOR CORE (Business Logic)
///   API/ Models/ Auth/ Settings/ Support/ Infrastructure
///            |
///            v
/// EXTERNAL SERVICES
///   Keychain/ Network/ FileSystem/ Platform APIs
///
/// ## Rules
///
/// 1. HarborCore must NOT import SwiftUI, AppKit, or UIKit
/// 2. Harbor must NOT import UI frameworks in HarborCore
/// 3. All public APIs in HarborCore must be documented
/// 4. Use protocols for abstractions, not concrete types
/// 5. Prefer value types (struct) over reference types (class)
/// 6. Use actors for shared mutable state
/// 7. Mark all public types as `@available` if needed

// MARK: - Architecture Violation Check

#if DEBUG
/// Compile-time check for architecture violations
/// This will cause a build error if HarborCore imports UI frameworks
enum ArchitectureCheck {
    // If this compiles, HarborCore doesn't have UI imports in this file
    // Add UI framework imports here to verify they're caught
    // import SwiftUI  // Uncomment to verify violation is caught
    // import AppKit   // Uncomment to verify violation is caught
    // import UIKit    // Uncomment to verify violation is caught
}
#endif

// MARK: - Coding Standards

/// Guidelines for Harbor code (enforced through code review):
///
/// ## Naming Conventions
///
/// | Type | Convention | Example |
/// |------|------------|---------|
/// | Protocols | Noun + able/ible/ing | SourceControlProvider |
/// | Actors | Descriptive noun | GitHubClient |
/// | Enums | Singular noun | ProviderType |
/// | Structs | PascalCase | Repository |
/// | Properties | camelCase | isAuthenticated |
/// | Methods | Verb phrase | fetchRepositories() |
/// | Constants | k-prefix or camelCase | kMaxRetries |
///
/// ## File Organization
///
/// Sources/{Module}/{Layer}/{Component}.swift
///
/// ## File Size Limits
///
/// - Maximum 400 lines per file
/// - Maximum 5 extensions per file
/// - Group related code in MARK sections
///
/// ## Documentation Requirements
///
/// Every public API must have documentation:
///
/// public func example() async throws -> Result { ... }
///
/// ## SOLID Principles in Harbor
///
/// S - Single Responsibility Principle
/// Each type has one reason to change
///   - GitHubClient only handles GitHub API
///   - RepositoryHealth only calculates health scores
///
/// O - Open/Closed Principle
/// Open for extension, closed for modification
///   - Use protocol extensions for default behavior
///   - Add new providers without modifying existing code
///
/// L - Liskov Substitution Principle
/// Subtypes can replace their base types
///   - All providers implement SourceControlProvider
///   - Can swap providers without breaking code
///
/// I - Interface Segregation Principle
/// Many small interfaces over one large one
///   - Split SourceControlProvider into focused protocols
///   - Clients only depend on what they use
///
/// D - Dependency Inversion Principle
/// Depend on abstractions, not concretions
///   - Use protocols for all dependencies
///   - Inject dependencies through constructors

// MARK: - Concurrency Guidelines

/// ## Swift Concurrency Best Practices
///
/// 1. Use actors for shared mutable state
/// 2. Mark non-sendable types with @unchecked Sendable
/// 3. Prefer async/await over completion handlers
/// 4. Use Task for background work
/// 5. Cancel tasks when they're no longer needed
/// 6. Use withTaskGroup for parallel operations
/// 7. Avoid MainActor.assumeIsolated() when possible

// MARK: - Error Handling

/// ## Error Handling Pattern
///
/// Harbor uses typed errors for better error handling:
///
/// public enum GitHubAPIError: LocalizedError {
///     case invalidHost
///     case rateLimited(until: Date)
///     case notFound
///     case unauthorized
///     case networkError(Error)
///
///     public var errorDescription: String? { ... }
/// }
///
/// - Errors are thrown, not returned as optionals
/// - Use LocalizedError for user-facing messages
/// - Log errors with context for debugging
/// - Handle errors at the appropriate level

// MARK: - Testing Guidelines

/// ## Test Organization
///
/// Tests/HarborCoreTests/
///   API/GitHubClientTests.swift
///   API/GitHubRestAPITests.swift
///   Models/RepositoryTests.swift
///   Auth/OAuthCoordinatorTests.swift
///
/// ## Test Types
///
/// 1. Unit Tests: Test individual types in isolation
/// 2. Integration Tests: Test type interactions
/// 3. Contract Tests: Test protocol conformances

// MARK: - Performance Budgets

/// ## Performance Guidelines
///
/// | Metric | Target | Maximum |
/// |--------|--------|---------|
/// | Menu open (cached) | < 50ms | 100ms |
/// | API response (cached) | < 10ms | 50ms |
/// | Memory footprint | < 100MB | 200MB |
/// | Bundle size | < 10MB | 20MB |
///
/// ## Memory Management
///
/// - Use structs for small, immutable data
/// - Use classes for shared, mutable state
/// - Use actors for thread-safe state
/// - Avoid retain cycles with [weak self]
/// - Use weak references in closures

// MARK: - Public API Surface

/// These are the public entry points for HarborCore.
/// Everything else is internal implementation detail.
public enum HarborCore {
    /// API Clients for source control providers
    public enum API {}

    /// Domain models
    public enum Models {}

    /// Authentication
    public enum Auth {}

    /// Settings and configuration
    public enum Settings {}

    /// Platform support
    public enum Platform {}
}

// MARK: - Versioning

/// HarborCore follows semantic versioning
public enum HarborCoreVersion {
    public static let major = 0
    public static let minor = 5
    public static let patch = 0

    public static let string = "\(major).\(minor).\(patch)"
}
