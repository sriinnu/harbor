import Foundation

/// Platform-agnostic protocol for securely storing OAuth tokens and client credentials.
///
/// Backed by `SecretStore` (Keychain on Apple platforms; see its doc for the others).
public protocol SecureTokenStorage: Sendable {
    /// Save OAuth tokens securely
    /// - Parameter tokens: The OAuth tokens to store
    /// - Throws: TokenStoreError if save fails
    func save(tokens: OAuthTokens) throws

    /// Load OAuth tokens from secure storage
    /// - Returns: The stored tokens, or nil if none exist
    /// - Throws: TokenStoreError if load fails
    func load() throws -> OAuthTokens?

    /// Save client credentials securely
    /// - Parameter credentials: The OAuth client credentials to store
    /// - Throws: TokenStoreError if save fails
    func save(clientCredentials: OAuthClientCredentials) throws

    /// Load client credentials from secure storage
    /// - Returns: The stored credentials, or nil if none exist
    /// - Throws: TokenStoreError if load fails
    func loadClientCredentials() throws -> OAuthClientCredentials?

    /// Clear all stored tokens and credentials
    func clear()
}

// MARK: - Platform Implementations

/// OAuth tokens and client credentials in the platform `SecretStore` (the Keychain on
/// Apple platforms). Accounts "default" (tokens) and "client" (credentials).
public struct KeychainTokenStorage: SecureTokenStorage {
    private let service: String
    private let store: SecretStore

    #if canImport(Security)
    public init(service: String = "com.sriinnu.harbor.auth") {
        self.init(service: service, store: KeychainSecretStore.shared)
    }
    #endif

    public init(service: String, store: SecretStore) {
        self.service = service
        self.store = store
    }

    public func save(tokens: OAuthTokens) throws {
        do {
            try self.store.setValue(tokens, service: self.service, account: "default", label: "Harbor sign-in")
        } catch {
            throw TokenStoreError.saveFailed
        }
    }

    public func load() throws -> OAuthTokens? {
        do {
            return try self.store.value(OAuthTokens.self, service: self.service, account: "default")
        } catch {
            throw TokenStoreError.loadFailed
        }
    }

    public func save(clientCredentials: OAuthClientCredentials) throws {
        do {
            try self.store.setValue(clientCredentials, service: self.service, account: "client", label: "Harbor OAuth app")
        } catch {
            throw TokenStoreError.saveFailed
        }
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        do {
            return try self.store.value(OAuthClientCredentials.self, service: self.service, account: "client")
        } catch {
            throw TokenStoreError.loadFailed
        }
    }

    public func clear() {
        try? self.store.remove(service: self.service, account: "default")
        try? self.store.remove(service: self.service, account: "client")
    }
}

// MARK: - In-Memory Implementation (Testing/Development)

/// In-memory implementation for testing and development
/// WARNING: Not secure - tokens are stored in memory only
public struct InMemoryTokenStorage: SecureTokenStorage {
    private final class Storage: @unchecked Sendable {
        var tokens: OAuthTokens?
        var credentials: OAuthClientCredentials?
        let lock = NSLock()
    }

    private let storage = Storage()

    public init() {}

    public func save(tokens: OAuthTokens) throws {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.tokens = tokens
    }

    public func load() throws -> OAuthTokens? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.tokens
    }

    public func save(clientCredentials: OAuthClientCredentials) throws {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.credentials = clientCredentials
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        return storage.credentials
    }

    public func clear() {
        storage.lock.lock()
        defer { storage.lock.unlock() }
        storage.tokens = nil
        storage.credentials = nil
    }
}

// MARK: - Usage Example

/*
 Platform-specific instantiation:

 macOS/iOS:
 let storage: SecureTokenStorage = KeychainTokenStorage()

 Windows (Rust implementation via FFI):
 let storage: SecureTokenStorage = WindowsCredentialManagerStorage()

 Web/Testing:
 let storage: SecureTokenStorage = InMemoryTokenStorage()

 Then use the protocol:
 try await storage.save(tokens: oauthTokens)
 let stored = try await storage.load()
 */
