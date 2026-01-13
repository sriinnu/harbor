import Foundation
import Security

/// Personal Access Token for Azure DevOps
public struct PATToken: Codable, Equatable, Sendable {
    public let token: String
    public let organization: String
    public let createdAt: Date
    public let expiresAt: Date?

    public init(token: String, organization: String, createdAt: Date = Date(), expiresAt: Date? = nil) {
        self.token = token
        self.organization = organization
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var isExpired: Bool {
        guard let expires = expiresAt else { return false }
        return expires < Date()
    }
}

/// Errors for PAT storage operations
public enum PATStoreError: Error, LocalizedError {
    case saveFailed
    case loadFailed
    case tokenNotFound
    case tokenExpired
    case invalidToken

    public var errorDescription: String? {
        switch self {
        case .saveFailed: return "Failed to save PAT to keychain"
        case .loadFailed: return "Failed to load PAT from keychain"
        case .tokenNotFound: return "PAT not found in keychain"
        case .tokenExpired: return "PAT has expired"
        case .invalidToken: return "PAT is invalid"
        }
    }
}

/// Manages Personal Access Tokens for Azure DevOps
public struct AzureDevOpsPATStore: Sendable {
    public static let shared = AzureDevOpsPATStore()

    private let service: String
    private let accountPrefix: String = "ado_pat_"

    public init(service: String = "com.sriinnu.athena.harbor.ado") {
        self.service = service
    }

    // MARK: - Save

    /// Save a PAT for a specific organization
    public func save(pat: PATToken) throws {
        let data = try JSONEncoder().encode(pat)
        let account = accountPrefix + pat.organization.lowercased()

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrComment: "Azure DevOps PAT for \(pat.organization)",
            kSecValueData: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw PATStoreError.saveFailed
        }
    }

    /// Save PAT with organization name string
    public func save(token: String, forOrganization organization: String, expiresAt: Date? = nil) throws {
        let pat = PATToken(token: token, organization: organization, expiresAt: expiresAt)
        try save(pat: pat)
    }

    // MARK: - Load

    /// Load PAT for a specific organization
    public func load(forOrganization organization: String) throws -> PATToken {
        let account = accountPrefix + organization.lowercased()

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            throw PATStoreError.tokenNotFound
        }

        guard status == errSecSuccess, let data = item as? Data else {
            throw PATStoreError.loadFailed
        }

        let pat = try JSONDecoder().decode(PATToken.self, from: data)

        if pat.isExpired {
            throw PATStoreError.tokenExpired
        }

        return pat
    }

    /// Get the token string for an organization (convenience method)
    public func token(forOrganization organization: String) throws -> String {
        let pat = try load(forOrganization: organization)
        return pat.token
    }

    /// Check if a PAT exists for an organization
    public func hasToken(forOrganization organization: String) -> Bool {
        let account = accountPrefix + organization.lowercased()

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    // MARK: - List

    /// List all stored PATs (metadata only, not the actual tokens)
    public func listOrganizations() throws -> [String] {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true
        ]

        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)

        if status == errSecItemNotFound {
            return []
        }

        guard status == errSecSuccess, let array = items as? [[CFString: Any]] else {
            throw PATStoreError.loadFailed
        }

        var organizations: [String] = []

        for item in array {
            if let account = item[kSecAttrAccount] as? String,
               account.hasPrefix(accountPrefix) {
                let org = String(account.dropFirst(accountPrefix.count))
                organizations.append(org)
            }
        }

        return organizations
    }

    // MARK: - Delete

    /// Delete PAT for a specific organization
    public func delete(forOrganization organization: String) {
        let account = accountPrefix + organization.lowercased()

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Delete all stored PATs
    public func clearAll() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]

        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Validate

    /// Validate a PAT by making a test API call
    public func validate(pat: PATToken, host: URL = URL(string: "https://dev.azure.com")!) async throws -> Bool {
        guard host.scheme == "https" else {
            throw PATStoreError.invalidToken
        }

        let orgURL = host.appendingPathComponent(pat.organization)
        let apiURL = orgURL.appendingPathComponent("_apis/connectionData")

        var request = URLRequest(url: apiURL)
        let credentials = ":\(pat.token)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("7.0", forHTTPHeaderField: "Accept-Version")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PATStoreError.invalidToken
        }

        return httpResponse.statusCode == 200
    }
}

// MARK: - Keychain Attributes Helper

extension AzureDevOpsPATStore {
    /// Get the access group for shared keychain access (for iOS app groups)
    #if os(iOS)
    private static var accessGroup: String? {
        Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    }
    #else
    private static var accessGroup: String? { nil }
    #endif

    /// Build keychain query with optional access group
    private func buildQuery(account: String, data: Data? = nil, includeAttributes: Bool = false) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        if let group = Self.accessGroup {
            query[kSecAttrAccessGroup] = group
        }

        if let data = data {
            query[kSecValueData] = data
        }

        if includeAttributes {
            query[kSecReturnAttributes] = true
        }

        return query
    }
}

// MARK: - Platform-Specific Extensions

#if os(macOS) || os(iOS)
import Security

/// Keychain-based PAT storage for Apple platforms
public extension AzureDevOpsPATStore {
    /// Save PAT to keychain (uses existing implementation)
    func saveToKeychain(_ pat: PATToken) throws {
        try save(pat: pat)
    }

    /// Load PAT from keychain
    func loadFromKeychain(forOrganization organization: String) throws -> PATToken {
        try load(forOrganization: organization)
    }
}

// MARK: - In-Memory Storage (Testing/Development)

/// In-memory implementation for testing using an actor for thread safety
public actor InMemoryPATStorage {
    private var pats: [String: PATToken] = [:]

    public init() {}

    public func save(pat: PATToken) {
        pats[pat.organization.lowercased()] = pat
    }

    public func load(forOrganization organization: String) throws -> PATToken {
        guard let pat = pats[organization.lowercased()] else {
            throw PATStoreError.tokenNotFound
        }
        return pat
    }

    public func delete(forOrganization organization: String) {
        pats.removeValue(forKey: organization.lowercased())
    }

    public func clearAll() {
        pats.removeAll()
    }

    public func hasToken(forOrganization organization: String) -> Bool {
        pats[organization.lowercased()] != nil
    }
}
#endif
