import Foundation
import HarborCore

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

    public init(patStore: AzureDevOpsPATStore = .shared) {
        self.patStore = patStore
        self.session = URLSession.shared
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

        // Save PAT to keychain
        try patStore.save(token: pat, forOrganization: organization)

        // Validate PAT by fetching user profile
        let user = try await fetchUserProfile(organization: organization)

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

    /// Fetch user profile from Azure DevOps
    private func fetchUserProfile(organization: String) async throws -> AzureDevOpsUser {
        let pat = try patStore.token(forOrganization: organization)
        return try await fetchUserProfile(pat: pat, organization: organization)
    }

    /// Fetch user profile with explicit PAT
    private func fetchUserProfile(pat: String, organization: String) async throws -> AzureDevOpsUser {
        let baseURL = URL(string: "https://dev.azure.com/\(organization)")!
        let profileURL = baseURL.appendingPathComponent("_apis/profile/profiles/me")
        var urlComponents = URLComponents(url: profileURL, resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = [URLQueryItem(name: "api-version", value: "6.0")]
        guard let url = urlComponents.url else {
            throw AzureDevOpsAuthError.profileFetchFailed("Invalid URL")
        }

        var request = URLRequest(url: url)
        let credentials = ":\(pat)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw AzureDevOpsAuthError.profileFetchFailed("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                let message = httpResponse.statusCode == 401
                    ? "Invalid Personal Access Token"
                    : "HTTP \(httpResponse.statusCode)"
                throw AzureDevOpsAuthError.authenticationFailed(message)
            }

            // Decode profile response
            struct ProfileResponse: Decodable {
                let id: String
                let displayName: String?
                let emailAddress: String?
                let publicAlias: String?
            }

            let decoder = JSONDecoder()
            let profile = try decoder.decode(ProfileResponse.self, from: data)

            // Also fetch user identities to get uniqueName
            let user = try await fetchUserIdentities(pat: pat, organization: organization, profileId: profile.id)

            await self.diag.message("Azure DevOps user profile fetched: \(user.displayName)")

            return user
        } catch let error as AzureDevOpsAuthError {
            throw error
        } catch {
            throw AzureDevOpsAuthError.networkError(error)
        }
    }

    /// Fetch user identities to get uniqueName and avatar
    private func fetchUserIdentities(pat: String, organization: String, profileId: String) async throws -> AzureDevOpsUser {
        let baseURL = URL(string: "https://dev.azure.com/\(organization)")!
        let identitiesURL = baseURL.appendingPathComponent("_apis/identities")
        var urlComponents = URLComponents(url: identitiesURL, resolvingAgainstBaseURL: true)!
        urlComponents.queryItems = [
            URLQueryItem(name: "api-version", value: "7.0"),
            URLQueryItem(name: "ids", value: profileId)
        ]
        guard let url = urlComponents.url else {
            throw AzureDevOpsAuthError.profileFetchFailed("Invalid identities URL")
        }

        var request = URLRequest(url: url)
        let credentials = ":\(pat)"
        if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
            request.addValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Accept")

        struct IdentityResponse: Decodable {
            let value: [IdentityItem]
            let count: Int?
        }

        struct IdentityItem: Decodable {
            let id: String
            let displayName: String?
            let uniqueName: String?
            let properties: Properties?
        }

        struct Properties: Decodable {
            let Mail: String?
            let Account: String?
        }

        let (data, _) = try await session.data(for: request)
        let decoder = JSONDecoder()
        let response = try decoder.decode(IdentityResponse.self, from: data)

        guard let identity = response.value.first else {
            // Return basic user from profile
            return AzureDevOpsUser(
                id: profileId,
                displayName: "Azure User",
                uniqueName: "",
                emailAddress: nil,
                avatarUrl: nil
            )
        }

        return AzureDevOpsUser(
            id: identity.id,
            displayName: identity.displayName ?? "Azure User",
            uniqueName: identity.uniqueName ?? "",
            emailAddress: identity.properties?.Mail,
            avatarUrl: nil
        )
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
