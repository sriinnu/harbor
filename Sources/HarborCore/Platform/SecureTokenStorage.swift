import Foundation

/// Platform-agnostic protocol for securely storing OAuth tokens and client credentials.
///
/// Implementations:
/// - macOS: Uses Keychain Services
/// - Windows: Uses Windows Credential Manager (via Rust keyring crate)
/// - Web: Uses encrypted database storage
/// - Linux: Uses libsecret or gnome-keyring
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

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Security

/// macOS/iOS implementation using Keychain Services
public struct KeychainTokenStorage: SecureTokenStorage {
    private let service: String

    public init(service: String = "com.sriinnu.harbor.auth") {
        self.service = service
    }

    public func save(tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.saveFailed }
    }

    public func load() throws -> OAuthTokens? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default",
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw TokenStoreError.loadFailed }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(clientCredentials: OAuthClientCredentials) throws {
        let data = try JSONEncoder().encode(clientCredentials)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "client",
            kSecValueData: data
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw TokenStoreError.saveFailed }
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "client",
            kSecReturnData: true
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw TokenStoreError.loadFailed }
        return try JSONDecoder().decode(OAuthClientCredentials.self, from: data)
    }

    public func clear() {
        let tokenQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "default"
        ]
        SecItemDelete(tokenQuery as CFDictionary)

        let clientQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: "client"
        ]
        SecItemDelete(clientQuery as CFDictionary)
    }
}
#endif

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
