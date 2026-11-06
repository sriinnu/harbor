import Foundation

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct OAuthClientCredentials: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum TokenStoreError: Error {
    case saveFailed
    case loadFailed
}

/// The app's GitHub token store, kept for existing call sites; same Keychain items
/// as `KeychainTokenStorage`, which does the work.
public struct TokenStore: Sendable {
    public static let shared = TokenStore()
    let service: String
    private var storage: KeychainTokenStorage { KeychainTokenStorage(service: self.service) }

    public init(service: String = "com.sriinnu.harbor.auth") {
        self.service = service
    }

    public func save(tokens: OAuthTokens) throws { try self.storage.save(tokens: tokens) }
    public func load() throws -> OAuthTokens? { try self.storage.load() }
    public func save(clientCredentials: OAuthClientCredentials) throws { try self.storage.save(clientCredentials: clientCredentials) }
    public func loadClientCredentials() throws -> OAuthClientCredentials? { try self.storage.loadClientCredentials() }
    public func clear() { self.storage.clear() }
}
