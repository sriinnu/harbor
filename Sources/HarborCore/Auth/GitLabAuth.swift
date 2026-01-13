import Foundation
import Security

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

/// Manages GitLab authentication with secure Keychain storage
public final class GitLabAuth: @unchecked Sendable {
    public static let shared = GitLabAuth()

    private let service = "com.sriinnu.athena.harbor.gitlab"
    private let accountPrefix = "gitlab_token_"

    private init() {}

    /// Saves the GitLab token to Keychain
    /// - Parameters:
    ///   - token: The GitLab private token or OAuth token
    ///   - instanceURL: The GitLab instance URL (used as account suffix)
    public func saveToken(_ token: String, for instanceURL: String) throws {
        let account = accountName(for: instanceURL)
        let data = Data(token.utf8)

        // Delete any existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw GitLabAuthError.saveFailed(status)
        }
    }

    /// Loads the GitLab token from Keychain
    /// - Parameter instanceURL: The GitLab instance URL
    /// - Returns: The stored token, or nil if not found
    public func loadToken(for instanceURL: String) throws -> String? {
        let account = accountName(for: instanceURL)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw GitLabAuthError.loadFailed(status)
        }

        guard let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    /// Deletes the GitLab token from Keychain
    /// - Parameter instanceURL: The GitLab instance URL
    public func deleteToken(for instanceURL: String) throws {
        let account = accountName(for: instanceURL)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitLabAuthError.deleteFailed(status)
        }
    }

    /// Checks if a token exists for the given instance
    public func hasToken(for instanceURL: String) -> Bool {
        let account = accountName(for: instanceURL)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Clears all GitLab tokens from Keychain
    public func clearAllTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
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
