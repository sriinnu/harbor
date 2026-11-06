import Foundation

// MARK: - SourceControlProvider Protocol

/// A unified protocol for source control providers (GitHub, Azure DevOps).
/// This abstraction enables seamless switching between providers while maintaining
/// a consistent API surface for common operations.
///
/// - Platform Considerations:
///   - macOS/iOS: Full support with Keychain for token storage
///   - Windows: Full support with appropriate credential storage
///   - Web: Limited support - no Keychain, tokens must be provided externally
///
/// - Thread Safety: All methods are marked with `@Sendable` for thread-safe async usage.
public protocol SourceControlProvider: Sendable {
    /// The type of this provider (GitHub or Azure DevOps)
    nonisolated var providerType: ProviderType { get }

    /// The API host URL for this provider
    nonisolated var apiHost: URL { get }

    // MARK: - User & Organization

    /// Fetches the currently authenticated user
    /// - Returns: The authenticated user's identity
    func currentUser() async throws -> UserIdentity

    /// Fetches organizations/projects accessible to the authenticated user
    /// - Returns: Array of accessible organizations/projects
    func organizations() async throws -> [any ProviderProject]

    // MARK: - Repositories

    /// Fetches repositories accessible to the user
    /// - Parameter limit: Maximum number of repositories to return
    /// - Returns: Array of repositories
    func repositories(limit: Int) async throws -> [Repository]

    /// Fetches a specific repository by owner and name
    /// - Parameters:
    ///   - owner: Repository owner or organization
    ///   - name: Repository name
    /// - Returns: The requested repository
    func repository(owner: String, name: String) async throws -> Repository

    /// Searches repositories matching a query
    /// - Parameter query: Search query string
    /// - Returns: Array of matching repositories
    func searchRepositories(matching query: String) async throws -> [Repository]

    // MARK: - Pull Requests

    /// Fetches pull requests for a repository
    /// - Parameters:
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - limit: Maximum number of PRs to return
    /// - Returns: Array of pull request summaries
    func pullRequests(owner: String, repo: String, limit: Int) async throws -> [RepoPullRequestSummary]

    // MARK: - Issues/Work Items

    /// Fetches issues/work items for a repository
    /// - Parameters:
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - limit: Maximum number of issues to return
    /// - Returns: Array of issue summaries
    func issues(owner: String, repo: String, limit: Int) async throws -> [RepoIssueSummary]

    // MARK: - CI/CD

    /// Fetches pipeline/workflow runs for a repository
    /// - Parameters:
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - limit: Maximum number of runs to return
    /// - Returns: Array of workflow run summaries
    func pipelineRuns(owner: String, repo: String, limit: Int) async throws -> [RepoWorkflowRunSummary]

    // MARK: - Commits & Branches

    /// Fetches recent commits for a repository
    /// - Parameters:
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - limit: Maximum number of commits to return
    /// - Returns: Array of commit summaries
    func commits(owner: String, repo: String, limit: Int) async throws -> [RepoCommitSummary]

    /// Fetches branches for a repository
    /// - Parameters:
    ///   - owner: Repository owner
    ///   - repo: Repository name
    ///   - limit: Maximum number of branches to return
    /// - Returns: Array of branch summaries
    func branches(owner: String, repo: String, limit: Int) async throws -> [RepoBranchSummary]

    // MARK: - Cache Management

    /// Clears all cached data for this provider
    func clearCache() async

    /// Returns diagnostic information about the provider's state
    /// - Returns: Summary of provider diagnostics
    func diagnostics() async -> DiagnosticsSummary
}

// MARK: - ProviderClientFactory

/// Factory for creating provider-specific clients based on `ProviderType`.
///
/// Usage:
/// ```swift
/// let githubClient = ProviderClientFactory.client(for: .github) as! GitHubClient
/// let azureClient = ProviderClientFactory.client(for: .azureDevOps) as! AzureDevOpsClient
/// let gitlabClient = ProviderClientFactory.client(for: .gitlab) as! GitLabClient
/// ```
///
/// - Note: For web platforms, additional configuration may be required
///         to provide authentication tokens since Keychain is not available.
public enum ProviderClientFactory {

    /// Creates a provider client for the given type
    /// - Parameter type: The provider type to create a client for
    /// - Returns: An actor for the provider (cast to appropriate type)
    /// - Throws: `ProviderError.unsupportedProvider` if the type is not supported
    public static func client(for type: ProviderType) -> Any {
        switch type {
        case .github:
            return GitHubClient()
        case .azureDevOps:
            return AzureDevOpsClient()
        case .gitlab:
            return GitLabClient(instanceURL: URL(string: "https://gitlab.com")!, token: "")
        }
    }

    /// Creates a GitLab client with custom instance URL
    /// - Parameters:
    ///   - instanceURL: The GitLab instance URL (e.g., https://gitlab.mycompany.com)
    ///   - token: The authentication token
    /// - Returns: A GitLab client configured for the instance
    public static func gitlabClient(instanceURL: String, token: String) -> GitLabClient {
        GitLabClient(instanceURLString: instanceURL, token: token)
    }
}

// MARK: - Provider Errors

/// Errors that can occur during provider operations
public enum ProviderError: LocalizedError {
    case unsupportedProvider
    case notAuthenticated
    case networkError(Error)
    case decodingError(Error)
    case rateLimited(until: Date?)
    case notFound
    case permissionDenied
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            return "The requested provider is not supported"
        case .notAuthenticated:
            return "Authentication is required for this operation"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .rateLimited(let until):
            if let date = until {
                return "Rate limited until \(date)"
            }
            return "Rate limited. Please try again later."
        case .notFound:
            return "The requested resource was not found"
        case .permissionDenied:
            return "You do not have permission to perform this operation"
        case .unknown(let message):
            return "Unknown error: \(message)"
        }
    }
}

// MARK: - Repository Mapping Helpers

/// Helper utilities for converting provider-specific repositories to common models
public enum RepositoryMapper {

    /// Converts an Azure DevOps repository to the common Repository model
    /// - Parameter azureRepo: The Azure DevOps repository
    /// - Returns: A unified Repository model
    public static func map(_ azureRepo: AzureRepository) -> Repository {
        Repository(
            id: azureRepo.id,
            name: azureRepo.name,
            owner: azureRepo.organization,
            isFork: false,
            isArchived: azureRepo.isDisabled,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            forks: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: [],
            detailCacheState: nil
        )
    }

    /// Converts a provider-specific repository to the common Repository model
    /// - Parameter providerRepo: A provider repository conforming to `ProviderRepository`
    /// - Returns: A unified Repository model
    public static func map(_ providerRepo: any ProviderRepository) -> Repository {
        Repository(
            id: providerRepo.id,
            name: providerRepo.name,
            owner: providerRepo.ownerOrOrganization,
            isFork: false,
            isArchived: false,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            forks: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            activityEvents: [],
            traffic: nil,
            heatmap: [],
            detailCacheState: nil
        )
    }

    /// Maps an array of provider repositories to unified Repository models
    /// - Parameter repos: Array of provider-specific repositories
    /// - Returns: Array of unified Repository models
    public static func mapAll(_ repos: [any ProviderRepository]) -> [Repository] {
        repos.map { map($0) }
    }
}

// MARK: - Pull Request Mapping Helpers

/// Helper utilities for converting provider-specific pull requests to common models
public enum PullRequestMapper {

    /// Converts an Azure DevOps pull request summary to a common summary
    /// - Parameter azurePR: The Azure DevOps pull request summary
    /// - Returns: A unified pull request summary
    public static func map(_ azurePR: AzurePullRequestSummary) -> RepoPullRequestSummary {
        RepoPullRequestSummary(
            number: azurePR.pullRequestId,
            title: azurePR.title,
            url: azurePR.url,
            updatedAt: azurePR.creationDate,
            authorLogin: azurePR.createdBy,
            authorAvatarURL: azurePR.createdByImageURL,
            isDraft: azurePR.isDraft,
            commentCount: 0,
            reviewCommentCount: 0,
            labels: [],
            headRefName: azurePR.sourceBranch,
            baseRefName: azurePR.targetBranch
        )
    }

    /// Converts a provider pull request to a common summary
    /// - Parameter providerPR: A provider pull request conforming to `ProviderPullRequest`
    /// - Returns: A unified pull request summary
    public static func map(_ providerPR: any ProviderPullRequest) -> RepoPullRequestSummary {
        RepoPullRequestSummary(
            number: providerPR.number,
            title: providerPR.title,
            url: providerPR.webURL,
            updatedAt: providerPR.updatedAt,
            authorLogin: providerPR.authorLogin,
            authorAvatarURL: providerPR.authorAvatarURL,
            isDraft: false,
            commentCount: 0,
            reviewCommentCount: 0,
            labels: [],
            headRefName: nil,
            baseRefName: nil
        )
    }
}

// MARK: - Issue Mapping Helpers

/// Helper utilities for converting provider-specific work items to common models
public enum IssueMapper {

    /// Converts an Azure DevOps work item to an issue summary
    /// - Parameters:
    ///   - workItem: The Azure DevOps work item
    ///   - project: Project name for URL construction
    /// - Returns: A unified issue summary
    public static func mapAzureWorkItem(_ workItem: AzureDevOpsWorkItem, project: String) -> RepoIssueSummary? {
        guard let fields = workItem.fields else { return nil }

        let author = fields.systemCreatedBy?.displayName ?? fields.systemAssignedTo?.displayName
        let avatarURL = fields.systemCreatedBy?.imageUrl.flatMap { URL(string: $0) }
        let workItemURL = workItem.url.flatMap { URL(string: $0) } ?? URL(string: "https://dev.azure.com")!

        return RepoIssueSummary(
            number: workItem.id,
            title: fields.systemTitle ?? "Untitled",
            url: workItemURL,
            updatedAt: fields.systemChangedDate ?? fields.systemCreatedDate ?? Date(),
            authorLogin: author,
            authorAvatarURL: avatarURL,
            assigneeLogins: [],
            commentCount: 0,
            labels: []
        )
    }
}

// MARK: - Branch Mapping Helpers

/// Helper utilities for converting provider-specific branches to common models
public enum BranchMapper {

    /// Converts an Azure DevOps branch to a common summary
    /// - Parameter azureBranch: The Azure DevOps branch
    /// - Returns: A unified branch summary
    public static func map(_ azureBranch: AzureBranch) -> RepoBranchSummary {
        RepoBranchSummary(
            name: azureBranch.name.replacingOccurrences(of: "refs/heads/", with: ""),
            commitSHA: azureBranch.objectId,
            isProtected: false
        )
    }
}

// MARK: - Commit Mapping Helpers

/// Helper utilities for converting provider-specific commits to common models
public enum CommitMapper {

    /// Converts an Azure DevOps commit to a common summary
    /// - Parameters:
    ///   - azureCommit: The Azure DevOps commit
    ///   - url: Optional web URL for the commit
    /// - Returns: A unified commit summary
    public static func map(_ azureCommit: AzureCommit, url: URL? = nil) -> RepoCommitSummary {
        let commitURL = azureCommit.url ?? url

        return RepoCommitSummary(
            sha: azureCommit.commitId,
            message: azureCommit.message,
            url: commitURL ?? URL(string: "https://dev.azure.com")!,
            authoredAt: azureCommit.author.date,
            authorName: azureCommit.author.name,
            authorLogin: nil,
            authorAvatarURL: nil,
            repoFullName: nil
        )
    }
}

// MARK: - Pipeline Mapping Helpers

/// Helper utilities for converting provider-specific pipelines to common models
public enum PipelineMapper {

    /// Converts an Azure DevOps pipeline run to a common workflow run summary
    /// - Parameter azureRun: The Azure DevOps pipeline run
    /// - Returns: A unified workflow run summary
    public static func map(_ azureRun: AzureDevOpsPipelineRun) -> RepoWorkflowRunSummary {
        let status = mapAzureStatus(azureRun.state)
        let conclusion = azureRun.result
        let pipelineURL = azureRun.url.flatMap { URL(string: $0) } ?? URL(string: "https://dev.azure.com")!

        return RepoWorkflowRunSummary(
            name: azureRun.name ?? "Pipeline #\(azureRun.id)",
            url: pipelineURL,
            updatedAt: azureRun.finishedDate ?? azureRun.createdDate ?? Date(),
            status: status,
            conclusion: conclusion,
            branch: nil,
            event: nil,
            actorLogin: nil,
            actorAvatarURL: nil,
            runNumber: azureRun.id
        )
    }

    private static func mapAzureStatus(_ state: String?) -> CIStatus {
        switch state?.lowercased() {
        case "completed":
            return .unknown // Would need to check result for actual status
        case "inprogress", "running":
            return .pending
        case "pending", "queued":
            return .pending
        case "cancelled", "skipped":
            return .unknown
        default:
            return .unknown
        }
    }
}

// MARK: - Supporting Types for Provider Conformance

/// Wrapper for Azure DevOps projects to conform to ProviderProject
public struct AzureDevOpsProjectWrapper: ProviderProject, Sendable {
    let project: AzureDevOpsProject
    let organization: String

    public var id: String { project.id }
    public var name: String { project.name }
    public var description: String? { project.description }
    public var webURL: URL {
        URL(string: "https://dev.azure.com/\(organization)/\(project.name)")!
    }
    public var providerType: ProviderType { .azureDevOps }
}

/// Wrapper for GitHub organizations to conform to ProviderProject
public struct GitHubOrganization: ProviderProject, Sendable {
    let login: String

    public var id: String { login }
    public var name: String { login }
    public var description: String? { nil }
    public var webURL: URL {
        URL(string: "https://github.com/\(login)")!
    }
    public var providerType: ProviderType { .github }
}

// MARK: - Multi-Platform Support

#if os(watchOS) || os(tvOS) || os(visionOS)
/// Platform-specific limitations for watchOS, tvOS, and visionOS
public enum PlatformLimitations {
    /// Keychain access is not available on these platforms
    public static let hasKeychain = false
    /// Push notifications are not available on these platforms
    public static let hasPushNotifications = false
}
#elseif os(macOS) || os(iOS)
/// Platform-specific capabilities for macOS and iOS
public enum PlatformCapabilities {
    /// Keychain access is available on these platforms
    public static let hasKeychain = true
    /// Push notifications are available on these platforms
    public static let hasPushNotifications = true
}
#endif

// MARK: - Web Utilities

#if canImport(JavaScriptKit)
/// Web-specific utilities when running in a browser environment
public enum WebUtilities {
    /// Checks if running in a web context
    public static var isWebContext: Bool {
        #if canImport(JavaScriptKit)
        return true
        #else
        return false
        #endif
    }

    /// Web-specific: Invalidate session when running in browser
    /// - Note: This is a no-op on non-web platforms
    public static func invalidateWebSession() async {
        #if canImport(JavaScriptKit)
        // Clear any JavaScript-side session data
        #endif
    }
}
#endif
