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

    // MARK: Several GitHub accounts

    /// The key of the active account (`github:<login>@<host>`), or nil when none is chosen
    /// yet. With none, `load()` and `save(tokens:)` use the legacy single item.
    var activeAccount: String? { get }

    /// Makes `key` the active account; nil clears the choice.
    func setActiveAccount(_ key: String?) throws

    /// Saves tokens under one account key, whether or not it is active.
    func save(tokens: OAuthTokens, account: String) throws

    func load(account: String) throws -> OAuthTokens?

    /// Removes one account's tokens. Nothing else changes.
    func remove(account: String)

    /// The keys of every per-account token (`github:` items), sorted. Throws when the store
    /// cannot be listed (locked Keychain, denied prompt): that is not the same as "no accounts".
    func storedAccountKeys() throws -> [String]

    /// Credentials of the OAuth app that issued one account's token. Per account: another
    /// account's sign-in never replaces them.
    func save(clientCredentials: OAuthClientCredentials, account: String) throws
    func loadClientCredentials(account: String) throws -> OAuthClientCredentials?
}

public extension SecureTokenStorage {
    /// `storedAccountKeys()`, or an empty list when the store cannot be listed. Only for display;
    /// anything that deletes or rewrites state on the strength of the list must use `storedAccountKeys()`.
    func accountKeys() -> [String] { (try? self.storedAccountKeys()) ?? [] }
}

// MARK: - Platform Implementations

/// OAuth tokens and client credentials in the platform `SecretStore` (the Keychain on
/// Apple platforms). Each GitHub account's tokens sit under `github:<login>@<host>`; the account
/// "active" names the one in use, "client:<key>" holds the credentials of the OAuth app that issued that account's token
/// (plain "client" belongs to the legacy item), and "default" is the single item older versions
/// wrote (read while no account is active).
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

    /// The account `load()` and `save(tokens:)` use: the active one, else the legacy item.
    private var currentAccount: String { self.activeAccount ?? GitHubAccountKey.legacy }

    public func save(tokens: OAuthTokens) throws {
        try self.save(tokens: tokens, account: self.currentAccount)
    }

    public func load() throws -> OAuthTokens? {
        try self.load(account: self.currentAccount)
    }

    public func save(tokens: OAuthTokens, account: String) throws {
        do {
            try self.store.setValue(tokens, service: self.service, account: account, label: "Harbor sign-in")
        } catch {
            throw TokenStoreError.saveFailed
        }
    }

    public func load(account: String) throws -> OAuthTokens? {
        do {
            return try self.store.value(OAuthTokens.self, service: self.service, account: account)
        } catch {
            throw TokenStoreError.loadFailed
        }
    }

    /// Removes the account's tokens and the credentials of its OAuth app.
    public func remove(account: String) {
        try? self.store.remove(service: self.service, account: account)
        try? self.store.remove(service: self.service, account: GitHubAccountKey.clientItem(for: account))
    }

    public func storedAccountKeys() throws -> [String] {
        do {
            return try self.store.accounts(service: self.service)
                .filter { $0.hasPrefix(GitHubAccountKey.prefix) }
                .sorted()
        } catch {
            throw TokenStoreError.loadFailed
        }
    }

    public var activeAccount: String? {
        guard let data = try? self.store.data(service: self.service, account: GitHubAccountKey.activePointer),
              let key = String(data: data, encoding: .utf8), key.isEmpty == false
        else { return nil }
        return key
    }

    public func setActiveAccount(_ key: String?) throws {
        do {
            if let key {
                try self.store.set(Data(key.utf8), service: self.service, account: GitHubAccountKey.activePointer, label: "Harbor active account")
            } else {
                try self.store.remove(service: self.service, account: GitHubAccountKey.activePointer)
            }
        } catch {
            throw TokenStoreError.saveFailed
        }
    }

    /// Credentials of the OAuth app behind the account `load()` and `save(tokens:)` use.
    public func save(clientCredentials: OAuthClientCredentials) throws {
        try self.save(clientCredentials: clientCredentials, account: self.currentAccount)
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        try self.loadClientCredentials(account: self.currentAccount)
    }

    public func save(clientCredentials: OAuthClientCredentials, account: String) throws {
        do {
            try self.store.setValue(
                clientCredentials, service: self.service,
                account: GitHubAccountKey.clientItem(for: account), label: "Harbor OAuth app"
            )
        } catch {
            throw TokenStoreError.saveFailed
        }
    }

    public func loadClientCredentials(account: String) throws -> OAuthClientCredentials? {
        do {
            return try self.store.value(
                OAuthClientCredentials.self, service: self.service, account: GitHubAccountKey.clientItem(for: account)
            )
        } catch {
            throw TokenStoreError.loadFailed
        }
    }

    /// Everything Harbor keeps for GitHub: every account, the active pointer, the staging slot,
    /// the legacy item and every OAuth app's credentials.
    public func clear() {
        let listed = (try? self.store.accounts(service: self.service)) ?? []
        for name in listed where name.hasPrefix(GitHubAccountKey.prefix) || name.hasPrefix(GitHubAccountKey.clientPrefix) {
            try? self.store.remove(service: self.service, account: name)
        }
        for name in [GitHubAccountKey.legacy, GitHubAccountKey.staging, GitHubAccountKey.activePointer, GitHubAccountKey.legacyClient] {
            try? self.store.remove(service: self.service, account: name)
        }
    }
}

// MARK: - In-Memory Implementation (Testing/Development)

/// In-memory implementation for testing and development: the same account logic as the Keychain
/// storage, over `InMemorySecretStore`.
/// WARNING: Not secure - tokens are stored in memory only
public struct InMemoryTokenStorage: SecureTokenStorage {
    private let inner = KeychainTokenStorage(service: "in-memory", store: InMemorySecretStore())

    public init() {}

    public func save(tokens: OAuthTokens) throws { try self.inner.save(tokens: tokens) }
    public func load() throws -> OAuthTokens? { try self.inner.load() }
    public func save(clientCredentials: OAuthClientCredentials) throws { try self.inner.save(clientCredentials: clientCredentials) }
    public func loadClientCredentials() throws -> OAuthClientCredentials? { try self.inner.loadClientCredentials() }
    public func clear() { self.inner.clear() }
    public var activeAccount: String? { self.inner.activeAccount }
    public func setActiveAccount(_ key: String?) throws { try self.inner.setActiveAccount(key) }
    public func save(tokens: OAuthTokens, account: String) throws { try self.inner.save(tokens: tokens, account: account) }
    public func load(account: String) throws -> OAuthTokens? { try self.inner.load(account: account) }
    public func remove(account: String) { self.inner.remove(account: account) }
    public func storedAccountKeys() throws -> [String] { try self.inner.storedAccountKeys() }
    public func save(clientCredentials: OAuthClientCredentials, account: String) throws {
        try self.inner.save(clientCredentials: clientCredentials, account: account)
    }
    public func loadClientCredentials(account: String) throws -> OAuthClientCredentials? {
        try self.inner.loadClientCredentials(account: account)
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
