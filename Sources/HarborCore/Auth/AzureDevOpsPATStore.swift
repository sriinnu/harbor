import Foundation

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

/// Azure DevOps Personal Access Tokens, one per organization, in the platform
/// `SecretStore` (the Keychain on Apple platforms).
public struct AzureDevOpsPATStore: Sendable {
    #if canImport(Security)
    public static let shared = AzureDevOpsPATStore()
    #endif

    private let service: String
    private let store: SecretStore
    private let accountPrefix: String = "ado_pat_"

    #if canImport(Security)
    public init(service: String = "com.sriinnu.harbor.ado") {
        self.init(service: service, store: KeychainSecretStore.shared)
    }
    #endif

    public init(service: String, store: SecretStore) {
        self.service = service
        self.store = store
    }

    private func account(_ organization: String) -> String {
        self.accountPrefix + organization.lowercased()
    }

    // MARK: - Save

    /// Save a PAT for a specific organization
    public func save(pat: PATToken) throws {
        do {
            try self.store.setValue(pat, service: self.service, account: self.account(pat.organization),
                                    label: "Azure DevOps PAT for \(pat.organization)")
        } catch {
            throw PATStoreError.saveFailed
        }
    }

    /// Save PAT with organization name string
    public func save(token: String, forOrganization organization: String, expiresAt: Date? = nil) throws {
        try self.save(pat: PATToken(token: token, organization: organization, expiresAt: expiresAt))
    }

    // MARK: - Load

    /// Load PAT for a specific organization
    public func load(forOrganization organization: String) throws -> PATToken {
        let pat: PATToken?
        do {
            pat = try self.store.value(PATToken.self, service: self.service, account: self.account(organization))
        } catch {
            throw PATStoreError.loadFailed
        }
        guard let pat else { throw PATStoreError.tokenNotFound }
        if pat.isExpired { throw PATStoreError.tokenExpired }
        return pat
    }

    /// Get the token string for an organization (convenience method)
    public func token(forOrganization organization: String) throws -> String {
        try self.load(forOrganization: organization).token
    }

    /// Check if a PAT exists for an organization
    public func hasToken(forOrganization organization: String) -> Bool {
        (try? self.store.data(service: self.service, account: self.account(organization))) != nil
    }

    // MARK: - List

    /// Organizations with a stored PAT (names only, never the tokens)
    public func listOrganizations() throws -> [String] {
        do {
            return try self.store.accounts(service: self.service)
                .filter { $0.hasPrefix(self.accountPrefix) }
                .map { String($0.dropFirst(self.accountPrefix.count)) }
        } catch {
            throw PATStoreError.loadFailed
        }
    }

    // MARK: - Delete

    /// Delete PAT for a specific organization
    public func delete(forOrganization organization: String) {
        try? self.store.remove(service: self.service, account: self.account(organization))
    }

    /// Delete all stored PATs
    public func clearAll() {
        try? self.store.removeAll(service: self.service)
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

        let (_, response) = try await HarborURLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PATStoreError.invalidToken
        }

        return httpResponse.statusCode == 200
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

    /// Lower-cased organization names with a stored PAT, sorted.
    public func listOrganizations() -> [String] {
        pats.keys.sorted()
    }
}
