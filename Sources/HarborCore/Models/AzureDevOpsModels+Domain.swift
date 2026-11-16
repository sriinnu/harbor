import Foundation

// MARK: - Azure DevOps Domain Models

/// Wrapper for Azure DevOps projects to conform to ProviderProject
public struct AzureDevOpsProjectDomain: ProviderProject {
    public let id: String
    public let name: String
    public let description: String?
    public let webURL: URL
    public let providerType: ProviderType

    public init(id: String, name: String, description: String?, webURL: URL) {
        self.id = id
        self.name = name
        self.description = description
        self.webURL = webURL
        self.providerType = .azureDevOps
    }

    /// Creates a domain project from an API model
    public static func from(apiModel: AzureDevOpsProject, organization: String) -> AzureDevOpsProjectDomain {
        let webURL = URL(string: "https://dev.azure.com/\(organization)/\(apiModel.name)")!
        return AzureDevOpsProjectDomain(
            id: apiModel.id,
            name: apiModel.name,
            description: apiModel.description,
            webURL: webURL
        )
    }
}

// MARK: - Repository Domain Models

/// Domain model for Azure DevOps repository with conversion support
public struct AzureRepositoryDomain: ProviderRepository {
    public let id: String
    public let name: String
    public let project: String
    public let organization: String
    public let defaultBranch: String?
    public let webURL: URL
    public let providerType: ProviderType

    public init(
        id: String,
        name: String,
        project: String,
        organization: String,
        defaultBranch: String?,
        webURL: URL
    ) {
        self.id = id
        self.name = name
        self.project = project
        self.organization = organization
        self.defaultBranch = defaultBranch
        self.webURL = webURL
        self.providerType = .azureDevOps
    }

    // MARK: - ProviderRepository Conformance

    public var ownerOrOrganization: String {
        organization
    }

    public var fullPath: String {
        "\(organization)/\(project)/\(name)"
    }

    // MARK: - Conversion to Common Model

    /// Converts to the common Repository domain model
    public func toRepository() -> Repository {
        Repository(
            id: id,
            name: name,
            owner: organization,
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
            heatmap: []
        )
    }
}

// MARK: - Pull Request Domain Models

/// Common PR state mapping for Azure DevOps
public enum AzurePRState: String, Sendable {
    case open
    case closed
    case merged

    public init(from status: AzurePullRequestStatus) {
        switch status {
        case .active:
            self = .open
        case .completed:
            self = .merged
        case .abandoned:
            self = .closed
        case .notSet:
            self = .open
        }
    }
}

/// Domain model for Azure DevOps pull request with conversion support
public struct AzurePullRequestDomain: ProviderPullRequest {
    public let id: String
    public let number: Int
    public let title: String
    public let state: String
    public let authorLogin: String?
    public let authorAvatarURL: URL?
    public let createdAt: Date
    public let updatedAt: Date
    public let webURL: URL
    public let providerType: ProviderType

    // Additional Azure-specific properties
    public let description: String?
    public let sourceBranch: String
    public let targetBranch: String
    public let isDraft: Bool
    public let azureStatus: AzurePullRequestStatus
    public let mergeStatus: AzureMergeStatus?

    public init(
        id: String,
        number: Int,
        title: String,
        state: String,
        authorLogin: String?,
        authorAvatarURL: URL?,
        createdAt: Date,
        updatedAt: Date,
        webURL: URL,
        description: String?,
        sourceBranch: String,
        targetBranch: String,
        isDraft: Bool,
        azureStatus: AzurePullRequestStatus,
        mergeStatus: AzureMergeStatus?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.webURL = webURL
        self.providerType = .azureDevOps
        self.description = description
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
        self.isDraft = isDraft
        self.azureStatus = azureStatus
        self.mergeStatus = mergeStatus
    }

    /// Creates a domain model from an API model
    public static func from(apiModel: AzurePullRequest) -> AzurePullRequestDomain {
        AzurePullRequestDomain(
            id: apiModel.id,
            number: apiModel.number,
            title: apiModel.title,
            state: apiModel.state,
            authorLogin: apiModel.authorLogin,
            authorAvatarURL: apiModel.authorAvatarURL,
            createdAt: apiModel.createdAt,
            updatedAt: apiModel.updatedAt,
            webURL: apiModel.webURL,
            description: apiModel.description,
            sourceBranch: apiModel.sourceBranch,
            targetBranch: apiModel.targetBranch,
            isDraft: apiModel.isDraft,
            azureStatus: apiModel.status,
            mergeStatus: apiModel.mergeStatus
        )
    }

    /// Creates a domain model from a summary
    public static func from(summary: AzurePullRequestSummary) -> AzurePullRequestDomain {
        AzurePullRequestDomain(
            id: "\(summary.pullRequestId)",
            number: summary.pullRequestId,
            title: summary.title,
            state: summary.status.rawValue,
            authorLogin: summary.createdBy,
            authorAvatarURL: summary.createdByImageURL,
            createdAt: summary.creationDate,
            updatedAt: summary.creationDate,
            webURL: summary.url,
            description: nil,
            sourceBranch: summary.sourceBranch,
            targetBranch: summary.targetBranch,
            isDraft: summary.isDraft,
            azureStatus: summary.status,
            mergeStatus: nil
        )
    }

    /// The mapped common state
    public var commonState: AzurePRState {
        AzurePRState(from: azureStatus)
    }

    /// Whether the PR is completed (merged or closed)
    public var isCompleted: Bool {
        azureStatus == .completed || azureStatus == .abandoned
    }

    /// Whether the PR has merge conflicts
    public var hasConflicts: Bool {
        mergeStatus == .conflicts
    }

    // MARK: - Conversion to Common Model

    /// Converts to the common RepoPullRequestSummary domain model
    public func toPullRequestSummary() -> RepoPullRequestSummary {
        RepoPullRequestSummary(
            number: number,
            title: title,
            url: webURL,
            updatedAt: updatedAt,
            authorLogin: authorLogin,
            authorAvatarURL: authorAvatarURL,
            isDraft: isDraft,
            commentCount: 0,
            reviewCommentCount: 0,
            labels: [],
            headRefName: sourceBranch,
            baseRefName: targetBranch
        )
    }
}

// MARK: - Work Item Domain Models

/// Domain model for Azure DevOps work item with conversion support
public struct AzureWorkItemDomain: ProviderWorkItem {
    public let id: String
    public let number: Int
    public let title: String
    public let state: String
    public let itemType: String
    public let assignedTo: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let webURL: URL
    public let providerType: ProviderType

    // Additional Azure-specific properties
    public let description: String?
    public let priority: Int?
    public let severity: String?
    public let tags: [String]
    public let assignedToAvatarURL: URL?

    public init(
        id: String,
        number: Int,
        title: String,
        state: String,
        itemType: String,
        assignedTo: String?,
        createdAt: Date,
        updatedAt: Date,
        webURL: URL,
        description: String?,
        priority: Int?,
        severity: String?,
        tags: [String],
        assignedToAvatarURL: URL?
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.itemType = itemType
        self.assignedTo = assignedTo
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.webURL = webURL
        self.providerType = .azureDevOps
        self.description = description
        self.priority = priority
        self.severity = severity
        self.tags = tags
        self.assignedToAvatarURL = assignedToAvatarURL
    }

    /// Creates a domain model from an API model
    public static func from(apiModel: AzureDevOpsWorkItem, project: String, organization: String) -> AzureWorkItemDomain? {
        guard let fields = apiModel.fields else { return nil }

        let webURL: URL
        if let urlString = apiModel.url, let url = URL(string: urlString) {
            webURL = url
        } else {
            webURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_workitems?id=\(apiModel.id)")!
        }

        let assignedToDisplay = fields.systemAssignedTo?.displayName
        let assignedToUnique = fields.systemAssignedTo?.uniqueName
        let assignedToAvatarURL = fields.systemAssignedTo?.imageUrl.flatMap { URL(string: $0) }

        return AzureWorkItemDomain(
            id: "\(apiModel.id)",
            number: apiModel.id,
            title: fields.systemTitle ?? "Untitled",
            state: fields.systemState ?? "Unknown",
            itemType: fields.systemWorkItemType ?? "Unknown",
            assignedTo: assignedToDisplay ?? assignedToUnique,
            createdAt: fields.systemCreatedDate ?? Date(),
            updatedAt: fields.systemChangedDate ?? fields.systemCreatedDate ?? Date(),
            webURL: webURL,
            description: fields.systemDescription,
            priority: fields.microsoftVSTSCommonPriority,
            severity: fields.microsoftVSTSCommonSeverity,
            tags: fields.systemTags?.split(separator: ";").map(String.init) ?? [],
            assignedToAvatarURL: assignedToAvatarURL
        )
    }

    /// The mapped work item type
    public var workItemType: AzureWorkItemType {
        AzureWorkItemType(from: itemType)
    }

    /// Priority as a string (e.g., "1 - High", "2 - Medium")
    public var priorityDescription: String? {
        guard let priority = priority else { return nil }
        switch priority {
        case 1:
            return "1 - High"
        case 2:
            return "2 - Medium"
        case 3:
            return "3 - Low"
        default:
            return "\(priority)"
        }
    }

    /// Whether the work item is in an active state
    public var isActive: Bool {
        let activeStates = ["Active", "New", "Ready", "In Progress"]
        return activeStates.contains(state)
    }

    /// Whether the work item is closed/done
    public var isClosed: Bool {
        let closedStates = ["Closed", "Done", "Resolved", "Completed"]
        return closedStates.contains(state)
    }

    // MARK: - Conversion to Common Model

    /// Converts to the common RepoIssueSummary domain model
    public func toIssueSummary() -> RepoIssueSummary {
        RepoIssueSummary(
            number: number,
            title: title,
            url: webURL,
            updatedAt: updatedAt,
            authorLogin: assignedTo,
            authorAvatarURL: assignedToAvatarURL,
            assigneeLogins: [],
            commentCount: 0,
            labels: tags.map { RepoIssueLabel(name: $0, colorHex: "6e7681") }
        )
    }
}

// MARK: - Pipeline Domain Models

/// Common CI status mapping for Azure DevOps pipelines
public enum AzurePipelineStatus: Sendable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
    case unknown

    public init(from state: String?, result: String?) {
        let stateLower = state?.lowercased() ?? ""

        switch stateLower {
        case "pending", "queued":
            self = .pending
        case "inprogress", "running":
            self = .running
        case "completed":
            if result?.lowercased() == "succeeded" {
                self = .succeeded
            } else if result?.lowercased() == "failed" {
                self = .failed
            } else if result?.lowercased() == "canceled" || result?.lowercased() == "cancelled" {
                self = .cancelled
            } else {
                self = .unknown
            }
        case "cancelled", "canceled", "skipped":
            self = .cancelled
        default:
            self = .unknown
        }
    }

    /// Converts to common CIStatus
    public var toCIStatus: CIStatus {
        switch self {
        case .succeeded:
            return .passing
        case .failed:
            return .failing
        case .pending, .running:
            return .pending
        case .cancelled, .unknown:
            return .unknown
        }
    }
}

/// Domain model for Azure DevOps pipeline with conversion support
public struct AzurePipelineDomain: ProviderPipeline {
    public let id: String
    public let name: String
    public var status: CIStatus
    public let runNumber: Int?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let webURL: URL
    public let providerType: ProviderType

    // Additional Azure-specific properties
    public let azureStatus: AzurePipelineStatus
    public let result: String?
    public let branch: String?
    public let folder: String?

    public init(
        id: String,
        name: String,
        status: CIStatus,
        runNumber: Int?,
        createdAt: Date?,
        updatedAt: Date?,
        webURL: URL,
        azureStatus: AzurePipelineStatus,
        result: String?,
        branch: String?,
        folder: String?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.runNumber = runNumber
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.webURL = webURL
        self.providerType = .azureDevOps
        self.azureStatus = azureStatus
        self.result = result
        self.branch = branch
        self.folder = folder
    }

    /// Creates a domain model from an API pipeline run model
    public static func from(apiModel: AzureDevOpsPipelineRun, project: String, organization: String) -> AzurePipelineDomain {
        let azureStatus = AzurePipelineStatus(from: apiModel.state, result: apiModel.result)
        let status = azureStatus.toCIStatus
        let runNumber = apiModel.id

        let webURL: URL
        if let urlString = apiModel.url, let url = URL(string: urlString) {
            webURL = url
        } else {
            webURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_build/results?buildId=\(apiModel.id)")!
        }

        let branch = apiModel.resources?.repositories?["self"]?.refName?
            .replacingOccurrences(of: "refs/heads/", with: "")

        return AzurePipelineDomain(
            id: "\(apiModel.id)",
            name: apiModel.name ?? "Pipeline #\(apiModel.id)",
            status: status,
            runNumber: runNumber,
            createdAt: apiModel.createdDate,
            updatedAt: apiModel.finishedDate ?? apiModel.createdDate,
            webURL: webURL,
            azureStatus: azureStatus,
            result: apiModel.result,
            branch: branch,
            folder: apiModel.pipeline?.folder
        )
    }

    // MARK: - Conversion to Common Model

    /// Converts to the common RepoWorkflowRunSummary domain model
    public func toWorkflowRunSummary() -> RepoWorkflowRunSummary {
        RepoWorkflowRunSummary(
            name: name,
            url: webURL,
            updatedAt: updatedAt ?? createdAt ?? Date(),
            status: status,
            conclusion: result,
            branch: branch,
            event: nil,
            actorLogin: nil,
            actorAvatarURL: nil,
            runNumber: runNumber
        )
    }
}

// MARK: - Branch Domain Models

/// Domain model for Azure DevOps branch with conversion support
public struct AzureBranchDomain: Sendable {
    public let name: String
    public let commitSHA: String
    public let isProtected: Bool

    public init(name: String, commitSHA: String, isProtected: Bool) {
        self.name = name
        self.commitSHA = commitSHA
        self.isProtected = isProtected
    }

    /// Creates a domain model from an API model
    public static func from(apiModel: AzureBranch) -> AzureBranchDomain {
        AzureBranchDomain(
            name: apiModel.name.replacingOccurrences(of: "refs/heads/", with: ""),
            commitSHA: apiModel.objectId,
            isProtected: false
        )
    }

    /// Converts to the common RepoBranchSummary domain model
    public func toBranchSummary() -> RepoBranchSummary {
        RepoBranchSummary(
            name: name,
            commitSHA: commitSHA,
            isProtected: isProtected
        )
    }
}

// MARK: - Commit Domain Models

/// Domain model for Azure DevOps commit with conversion support
public struct AzureCommitDomain: Sendable {
    public let sha: String
    public let message: String
    public let url: URL?
    public let authoredAt: Date
    public let authorName: String?
    public let authorEmail: String?
    public let committerName: String?
    public let changes: AzureChangeCount?

    public init(
        sha: String,
        message: String,
        url: URL?,
        authoredAt: Date,
        authorName: String?,
        authorEmail: String?,
        committerName: String?,
        changes: AzureChangeCount?
    ) {
        self.sha = sha
        self.message = message
        self.url = url
        self.authoredAt = authoredAt
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.committerName = committerName
        self.changes = changes
    }

    /// Creates a domain model from an API model
    public static func from(apiModel: AzureCommit) -> AzureCommitDomain {
        AzureCommitDomain(
            sha: apiModel.commitId,
            message: apiModel.message,
            url: apiModel.url,
            authoredAt: apiModel.author.date,
            authorName: apiModel.author.name,
            authorEmail: apiModel.author.email,
            committerName: apiModel.committer.name,
            changes: apiModel.changeCounts.map {
                AzureChangeCount(add: $0.add, edit: $0.edit, delete: $0.delete)
            }
        )
    }

    /// Short SHA (first 7 characters)
    public var shortSHA: String {
        String(sha.prefix(7))
    }

    /// First line of the commit message
    public var firstLine: String {
        message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
    }

    /// Converts to the common RepoCommitSummary domain model
    public func toCommitSummary() -> RepoCommitSummary {
        RepoCommitSummary(
            sha: sha,
            message: message,
            url: url ?? URL(string: "https://dev.azure.com")!,
            authoredAt: authoredAt,
            authorName: authorName,
            authorLogin: nil,
            authorAvatarURL: nil,
            repoFullName: nil
        )
    }
}
