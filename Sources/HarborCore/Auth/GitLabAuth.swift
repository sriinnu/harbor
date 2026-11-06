import Foundation

/// Errors that can occur during GitLab authentication
public enum GitLabAuthError: LocalizedError, Sendable {
    case noToken
    case invalidToken
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
    case loadFailed(OSStatus)
    case networkError(Error)

    public var errorDescription: String? {
        switch self {
        case .noToken:
            return "No authentication token available"
        case .invalidToken:
            return "Invalid authentication token"
        case let .saveFailed(status):
            return "Failed to save token: \(status)"
        case let .deleteFailed(status):
            return "Failed to delete token: \(status)"
        case let .loadFailed(status):
            return "Failed to load token: \(status)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

/// GitLab tokens, one per instance, in the platform `SecretStore` (the Keychain on
/// Apple platforms).
public final class GitLabAuth: @unchecked Sendable {
    #if canImport(Security)
    public static let shared = GitLabAuth(store: KeychainSecretStore.shared)
    #endif

    private let service = "com.sriinnu.harbor.gitlab"
    private let accountPrefix = "gitlab_token_"
    private let store: SecretStore

    init(store: SecretStore) {
        self.store = store
    }

    /// Saves the GitLab token for an instance (e.g. "https://gitlab.com").
    public func saveToken(_ token: String, for instanceURL: String) throws {
        do {
            try self.store.set(Data(token.utf8), service: self.service, account: self.accountName(for: instanceURL),
                               label: "GitLab token for \(instanceURL)")
        } catch let error as SecretStoreError {
            throw GitLabAuthError.saveFailed(error.status)
        }
    }

    /// The stored token, or nil if none.
    public func loadToken(for instanceURL: String) throws -> String? {
        do {
            return try self.store.data(service: self.service, account: self.accountName(for: instanceURL))
                .flatMap { String(data: $0, encoding: .utf8) }
        } catch let error as SecretStoreError {
            throw GitLabAuthError.loadFailed(error.status)
        }
    }

    public func deleteToken(for instanceURL: String) throws {
        do {
            try self.store.remove(service: self.service, account: self.accountName(for: instanceURL))
        } catch let error as SecretStoreError {
            throw GitLabAuthError.deleteFailed(error.status)
        }
    }

    public func hasToken(for instanceURL: String) -> Bool {
        (try? self.store.data(service: self.service, account: self.accountName(for: instanceURL))) != nil
    }

    public func clearAllTokens() {
        try? self.store.removeAll(service: self.service)
    }

    private func accountName(for instanceURL: String) -> String {
        // Normalize the instance URL to a safe account name
        let normalized = instanceURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return accountPrefix + normalized
    }
}
