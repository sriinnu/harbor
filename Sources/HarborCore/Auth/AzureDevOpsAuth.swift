import Foundation

/// Authentication result for Azure DevOps connection
public struct AzureDevOpsAuthResult: Sendable {
    public let user: AzureDevOpsUser
    public let organization: String

    public init(user: AzureDevOpsUser, organization: String) {
        self.user = user
        self.organization = organization
    }
}

/// Errors for Azure DevOps authentication
public enum AzureDevOpsAuthError: Error, LocalizedError {
    case invalidOrganization
    case invalidPAT
    case authenticationFailed(String)
    case networkError(Error)
    case profileFetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOrganization:
            return "Organization name is required"
        case .invalidPAT:
            return "Personal Access Token is invalid or empty"
        case let .authenticationFailed(message):
            return message
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case let .profileFetchFailed(message):
            return "Failed to fetch user profile: \(message)"
        }
    }
}

/// Azure DevOps authentication coordinator
/// Handles PAT validation, user profile fetching, and logout
public actor AzureDevOpsAuth {
    public static let shared = AzureDevOpsAuth()

    /// Keychain service identifier
    private static let keychainService = "com.sriinnu.harbor.ado"

    /// Keychain account prefix for PAT storage
    private static let keychainAccountPrefix = "ado_pat_"

    private let patStore: AzureDevOpsPATStore
    private let session: URLSession
    private let diag = DiagnosticsLogger.shared

    /// Currently connected organization (loaded from settings)
    private(set) var currentOrganization: String?

    /// Where organizations live: `https://dev.azure.com`. Tests point it at a stub host.
    private let host: URL

    public init(
        patStore: AzureDevOpsPATStore = .shared,
        host: URL = URL(string: "https://dev.azure.com")!,
        session: URLSession = HarborURLSession.shared
    ) {
        self.patStore = patStore
        self.host = host
        self.session = session
    }

    // MARK: - Connection

    /// Connect to Azure DevOps with a PAT
    /// - Parameters:
    ///   - pat: Personal Access Token
    ///   - organization: Azure DevOps organization name
    /// - Returns: Authentication result with user profile
    public func connect(pat: String, organization: String) async throws -> AzureDevOpsAuthResult {
        // Validate inputs
        guard !organization.isEmpty else {
            throw AzureDevOpsAuthError.invalidOrganization
        }

        guard !pat.isEmpty else {
            throw AzureDevOpsAuthError.invalidPAT
        }

        // Check the PAT first, so a token Azure rejects is never stored.
        let user = try await fetchUserProfile(pat: pat, organization: organization)
        try patStore.save(token: pat, forOrganization: organization)

        // Store organization in settings
        self.currentOrganization = organization

        await self.diag.message("Azure DevOps connected successfully for organization: \(organization)")

        return AzureDevOpsAuthResult(user: user, organization: organization)
    }

    /// Validate a PAT without saving
    /// - Parameters:
    ///   - pat: Personal Access Token to validate
    ///   - organization: Azure DevOps organization name
    /// - Returns: User profile if valid
    public func validate(pat: String, organization: String) async throws -> AzureDevOpsUser {
        guard !organization.isEmpty else {
            throw AzureDevOpsAuthError.invalidOrganization
        }

        guard !pat.isEmpty else {
            throw AzureDevOpsAuthError.invalidPAT
        }

        // Validate by fetching user profile
        return try await fetchUserProfile(pat: pat, organization: organization)
    }

    /// Disconnect from Azure DevOps
    public func disconnect() {
        guard let org = currentOrganization else { return }

        patStore.delete(forOrganization: org)
        currentOrganization = nil

        Task {
            await self.diag.message("Azure DevOps disconnected")
        }
    }

    /// Check if connected to Azure DevOps
    public func isConnected() -> Bool {
        guard let org = currentOrganization else { return false }
        return patStore.hasToken(forOrganization: org)
    }

    /// Get the current PAT for API calls
    public func getCurrentPAT() throws -> String {
        guard let org = currentOrganization else {
            throw AzureDevOpsAuthError.authenticationFailed("Not connected to Azure DevOps")
        }
        return try patStore.token(forOrganization: org)
    }

    /// Get the current organization
    public func getCurrentOrganization() -> String? {
        currentOrganization
    }

    // MARK: - User Profile

    /// Who the PAT belongs to, from `GET {org}/_apis/connectionData`.
    ///
    /// This is the org-scoped endpoint every PAT can read, whatever its scopes. The profile API
    /// (`_apis/profile/profiles/me`) lives only on app.vssps.visualstudio.com, so asking for it
    /// under dev.azure.com/{org} answered 404 for every token.
    private func fetchUserProfile(pat: String, organization: String) async throws -> AzureDevOpsUser {
        var components = URLComponents(url: self.host, resolvingAgainstBaseURL: false)
        components?.path = "/\(organization)/_apis/connectionData"
        guard let url = components?.url else {
            throw AzureDevOpsAuthError.invalidOrganization
        }

        var request = URLRequest(url: url)
        request.addValue("Basic \(Data(":\(pat)".utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            throw AzureDevOpsAuthError.networkError(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw AzureDevOpsAuthError.profileFetchFailed("Invalid response")
        }

        switch http.statusCode {
        case 200:
            break
        // Azure answers a rejected PAT with 401, or with 203 and its sign-in page.
        case 401, 203:
            throw AzureDevOpsAuthError.authenticationFailed("Azure DevOps rejected this token. Check it hasn't expired and was made for this organization.")
        case 404:
            throw AzureDevOpsAuthError.authenticationFailed("No organization named \"\(organization)\" on Azure DevOps. Use the name from dev.azure.com/{name}.")
        default:
            throw AzureDevOpsAuthError.authenticationFailed("HTTP \(http.statusCode)")
        }

        let user: ConnectionUser
        do {
            user = try JSONDecoder().decode(ConnectionData.self, from: data).authenticatedUser
        } catch {
            throw AzureDevOpsAuthError.profileFetchFailed("Unexpected response from Azure DevOps")
        }
        let account = user.properties?["Account"]?.value ?? ""
        await self.diag.message("Azure DevOps user verified for organization: \(organization)")
        return AzureDevOpsUser(
            id: user.id,
            displayName: user.providerDisplayName ?? "Azure User",
            uniqueName: account,
            emailAddress: account.contains("@") ? account : nil,
            avatarUrl: nil
        )
    }

    private struct ConnectionData: Decodable {
        let authenticatedUser: ConnectionUser
    }

    private struct ConnectionUser: Decodable {
        let id: String
        let providerDisplayName: String?
        let properties: [String: Property]?
    }

    private struct Property: Decodable {
        let value: String?

        private enum CodingKeys: String, CodingKey { case value = "$value" }

        init(from decoder: Decoder) throws {
            // Properties are `{"$type": ..., "$value": ...}`; a few have other shapes.
            self.value = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .value)
        }
    }

    // MARK: - Keychain Access

    /// Check if a PAT exists for an organization
    public func hasStoredToken(forOrganization organization: String) -> Bool {
        patStore.hasToken(forOrganization: organization)
    }

    /// Load stored user profile for an organization
    public func loadStoredUser(forOrganization organization: String) throws -> AzureDevOpsUser? {
        guard patStore.hasToken(forOrganization: organization) else { return nil }

        // We can't return the user without making an API call
        // Return nil to indicate we need to validate
        return nil
    }

    /// List all stored organizations
    public func listOrganizations() throws -> [String] {
        try patStore.listOrganizations()
    }

    /// Clear all stored tokens
    public func clearAllTokens() {
        patStore.clearAll()
        currentOrganization = nil
    }
}

// MARK: - Non-Actor Helpers

extension AzureDevOpsAuth {
    /// Non-actor helper to check connection status (returns immediately)
    public static func isConfigured() -> Bool {
        let store = AzureDevOpsPATStore()
        do {
            let orgs = try store.listOrganizations()
            return !orgs.isEmpty
        } catch {
            return false
        }
    }
}
