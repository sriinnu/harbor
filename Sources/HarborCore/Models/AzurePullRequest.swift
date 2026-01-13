import Foundation

/// Azure DevOps pull request status
public enum AzurePullRequestStatus: String, Codable, CaseIterable, Sendable {
    case active = "active"
    case abandoned = "abandoned"
    case completed = "completed"
    case notSet = "notSet"

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .abandoned: return "Abandoned"
        case .completed: return "Completed"
        case .notSet: return "Not Set"
        }
    }

    /// Whether this status indicates an open PR
    public var isOpen: Bool {
        self == .active || self == .notSet
    }

    /// Whether this status indicates a closed PR
    public var isClosed: Bool {
        self == .completed || self == .abandoned
    }
}

/// Azure DevOps pull request merge status
public enum AzureMergeStatus: String, Codable, CaseIterable, Sendable {
    case succeeded = "succeeded"
    case conflicts = "conflicts"
    case queued = "queued"
    case rejectedByPolicy = "rejectedByPolicy"
    case failure = "failure"
    case notSet = "notSet"

    public var displayName: String {
        switch self {
        case .succeeded: return "Succeeded"
        case .conflicts: return "Conflicts"
        case .queued: return "Queued"
        case .rejectedByPolicy: return "Rejected by Policy"
        case .failure: return "Failure"
        case .notSet: return "Not Set"
        }
    }

    /// Whether there are merge conflicts
    public var hasConflicts: Bool {
        self == .conflicts
    }

    /// Whether the merge can proceed
    public var canMerge: Bool {
        self == .succeeded || self == .queued
    }
}

/// Azure DevOps pull request
public struct AzurePullRequest: ProviderPullRequest {
    public let id: String
    public let pullRequestId: Int
    public let title: String
    public let description: String?
    public let status: AzurePullRequestStatus
    public let mergeStatus: AzureMergeStatus
    public let createdBy: AzureIdentity
    public let creationDate: Date
    public let closedDate: Date?
    public let sourceRefName: String
    public let targetRefName: String
    public let repository: AzureRepositoryRef
    public let url: URL
    public let isDraft: Bool
    public let reviewers: [AzureReviewer]
    public let labels: [AzureLabel]
    public let workItemRefs: [AzureWorkItemRef]

    public init(
        id: String,
        pullRequestId: Int,
        title: String,
        description: String? = nil,
        status: AzurePullRequestStatus,
        mergeStatus: AzureMergeStatus,
        createdBy: AzureIdentity,
        creationDate: Date,
        closedDate: Date? = nil,
        sourceRefName: String,
        targetRefName: String,
        repository: AzureRepositoryRef,
        url: URL,
        isDraft: Bool = false,
        reviewers: [AzureReviewer] = [],
        labels: [AzureLabel] = [],
        workItemRefs: [AzureWorkItemRef] = []
    ) {
        self.id = id
        self.pullRequestId = pullRequestId
        self.title = title
        self.description = description
        self.status = status
        self.mergeStatus = mergeStatus
        self.createdBy = createdBy
        self.creationDate = creationDate
        self.closedDate = closedDate
        self.sourceRefName = sourceRefName
        self.targetRefName = targetRefName
        self.repository = repository
        self.url = url
        self.isDraft = isDraft
        self.reviewers = reviewers
        self.labels = labels
        self.workItemRefs = workItemRefs
    }

    // MARK: - ProviderPullRequest Conformance

    public var number: Int {
        self.pullRequestId
    }

    public var state: String {
        self.status.rawValue
    }

    public var authorLogin: String? {
        self.createdBy.uniqueName ?? self.createdBy.displayName
    }

    public var authorAvatarURL: URL? {
        self.createdBy.imageURL
    }

    public var createdAt: Date {
        self.creationDate
    }

    public var updatedAt: Date {
        self.closedDate ?? self.creationDate
    }

    public var webURL: URL {
        self.url
    }

    public var providerType: ProviderType {
        .azureDevOps
    }

    // MARK: - Computed Properties

    /// The source branch name without the refs/heads/ prefix
    public var sourceBranch: String {
        self.sourceRefName.replacingOccurrences(of: "refs/heads/", with: "")
    }

    /// The target branch name without the refs/heads/ prefix
    public var targetBranch: String {
        self.targetRefName.replacingOccurrences(of: "refs/heads/", with: "")
    }

    /// Whether the PR is completed
    public var isCompleted: Bool {
        self.status == .completed
    }

    /// Whether the PR is abandoned
    public var isAbandoned: Bool {
        self.status == .abandoned
    }

    /// Whether the PR is active (open)
    public var isActive: Bool {
        self.status == .active
    }

    /// Whether the PR has merge conflicts
    public var hasConflicts: Bool {
        self.mergeStatus == .conflicts
    }

    /// Whether the PR can be merged
    public var canMerge: Bool {
        self.mergeStatus.canMerge
    }

    /// The mapped common state
    public var commonState: AzurePRState {
        AzurePRState(from: self.status)
    }

    /// Required reviewer count
    public var requiredReviewerCount: Int {
        reviewers.filter { $0.isRequired }.count
    }

    /// Approved reviewer count
    public var approvedReviewerCount: Int {
        reviewers.filter { $0.voteStatus == .approved }.count
    }

    // MARK: - Conversion to Domain Model

    /// Converts to the domain model
    public func toDomain() -> AzurePullRequestDomain {
        AzurePullRequestDomain.from(apiModel: self)
    }

    /// Converts to the common RepoPullRequestSummary domain model
    public func toPullRequestSummary() -> RepoPullRequestSummary {
        toDomain().toPullRequestSummary()
    }

    // MARK: - Factory Methods

    /// Creates an AzurePullRequest from an API model
    public static func from(apiModel: AzureDevOpsPullRequest, repository: AzureRepositoryRef) -> AzurePullRequest? {
        guard let createdBy = apiModel.createdBy,
              let urlString = apiModel.url,
              let url = URL(string: urlString) else {
            return nil
        }

        let author = AzureIdentity(
            id: createdBy.id,
            displayName: createdBy.displayName ?? "Unknown",
            uniqueName: createdBy.uniqueName,
            imageURL: createdBy.imageUrl.flatMap { URL(string: $0) },
            descriptor: createdBy.descriptor
        )

        let reviewers = (apiModel.reviewers ?? []).compactMap { r -> AzureReviewer? in
            guard let displayName = r.displayName else { return nil }
            return AzureReviewer(
                id: r.reviewerUrl ?? UUID().uuidString,
                displayName: displayName,
                uniqueName: r.uniqueName,
                imageURL: r.imageUrl.flatMap { URL(string: $0) },
                vote: r.vote ?? 0,
                isRequired: r.isRequired ?? false,
                isFlagged: false
            )
        }

        let labels = (apiModel.labels ?? []).map { label in
            AzureLabel(id: label.id ?? UUID().uuidString, name: label.name)
        }

        return AzurePullRequest(
            id: "\(apiModel.pullRequestId)",
            pullRequestId: apiModel.pullRequestId,
            title: apiModel.title,
            description: apiModel.description,
            status: AzurePullRequestStatus(rawValue: apiModel.status) ?? .notSet,
            mergeStatus: AzureMergeStatus(rawValue: apiModel.mergeStatus ?? "") ?? .notSet,
            createdBy: author,
            creationDate: apiModel.creationDate ?? Date(),
            closedDate: apiModel.closedDate,
            sourceRefName: apiModel.sourceRefName ?? "",
            targetRefName: apiModel.targetRefName ?? "",
            repository: repository,
            url: url,
            isDraft: apiModel.isDraft ?? false,
            reviewers: reviewers,
            labels: labels
        )
    }

    // MARK: - Equatable

    public static func == (lhs: AzurePullRequest, rhs: AzurePullRequest) -> Bool {
        lhs.id == rhs.id
    }
}

/// Azure DevOps pull request reviewer
public struct AzureReviewer: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let uniqueName: String?
    public let imageURL: URL?
    public let vote: Int
    public let isRequired: Bool
    public let isFlagged: Bool

    public init(
        id: String,
        displayName: String,
        uniqueName: String? = nil,
        imageURL: URL? = nil,
        vote: Int = 0,
        isRequired: Bool = false,
        isFlagged: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.uniqueName = uniqueName
        self.imageURL = imageURL
        self.vote = vote
        self.isRequired = isRequired
        self.isFlagged = isFlagged
    }

    public var voteStatus: AzureReviewVote {
        AzureReviewVote(rawValue: self.vote) ?? .noVote
    }

    /// Whether this reviewer has approved
    public var hasApproved: Bool {
        self.voteStatus == .approved
    }

    /// Whether this reviewer has rejected
    public var hasRejected: Bool {
        self.voteStatus == .rejected
    }
}

/// Azure DevOps review vote
public enum AzureReviewVote: Int, Codable, CaseIterable, Sendable {
    case approved = 10
    case approvedWithSuggestions = 5
    case noVote = 0
    case waitingForAuthor = -5
    case rejected = -10

    public var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .approvedWithSuggestions: return "Approved with Suggestions"
        case .noVote: return "No Vote"
        case .waitingForAuthor: return "Waiting for Author"
        case .rejected: return "Rejected"
        }
    }

    public var symbolName: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .approvedWithSuggestions: return "checkmark.circle"
        case .noVote: return "circle"
        case .waitingForAuthor: return "clock.circle"
        case .rejected: return "xmark.circle.fill"
        }
    }
}

/// Azure DevOps pull request label
public struct AzureLabel: Codable, Equatable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let active: Bool

    public init(id: String, name: String, active: Bool = true) {
        self.id = id
        self.name = name
        self.active = active
    }
}

/// Azure DevOps work item reference (lightweight)
public struct AzureWorkItemRef: Codable, Equatable, Sendable {
    public let id: String
    public let url: URL?

    public init(id: String, url: URL? = nil) {
        self.id = id
        self.url = url
    }
}

/// Azure DevOps pull request thread
public struct AzurePullRequestThread: Codable, Equatable, Sendable {
    public let id: Int
    public let status: String
    public let publishedDate: Date?
    public let lastUpdatedDate: Date?
    public let comments: [AzurePullRequestComment]
    public let isDeleted: Bool

    public init(
        id: Int,
        status: String,
        publishedDate: Date? = nil,
        lastUpdatedDate: Date? = nil,
        comments: [AzurePullRequestComment] = [],
        isDeleted: Bool = false
    ) {
        self.id = id
        self.status = status
        self.publishedDate = publishedDate
        self.lastUpdatedDate = lastUpdatedDate
        self.comments = comments
        self.isDeleted = isDeleted
    }
}

/// Azure DevOps pull request comment
public struct AzurePullRequestComment: Codable, Equatable, Sendable {
    public let id: Int
    public let content: String
    public let author: AzureIdentity
    public let publishedDate: Date
    public let lastUpdatedDate: Date?
    public let commentType: String
    public let isDeleted: Bool

    public init(
        id: Int,
        content: String,
        author: AzureIdentity,
        publishedDate: Date,
        lastUpdatedDate: Date? = nil,
        commentType: String = "text",
        isDeleted: Bool = false
    ) {
        self.id = id
        self.content = content
        self.author = author
        self.publishedDate = publishedDate
        self.lastUpdatedDate = lastUpdatedDate
        self.commentType = commentType
        self.isDeleted = isDeleted
    }

    public var contentPreview: String {
        let trimmed = self.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(80))
        return prefix + (trimmed.count > 80 ? "..." : "")
    }
}

/// Azure DevOps pull request summary (lightweight for lists)
public struct AzurePullRequestSummary: Sendable, Hashable {
    public let pullRequestId: Int
    public let title: String
    public let status: AzurePullRequestStatus
    public let createdBy: String
    public let createdByImageURL: URL?
    public let creationDate: Date
    public let isDraft: Bool
    public let url: URL
    public let sourceBranch: String
    public let targetBranch: String

    public init(
        pullRequestId: Int,
        title: String,
        status: AzurePullRequestStatus,
        createdBy: String,
        createdByImageURL: URL? = nil,
        creationDate: Date,
        isDraft: Bool = false,
        url: URL,
        sourceBranch: String,
        targetBranch: String
    ) {
        self.pullRequestId = pullRequestId
        self.title = title
        self.status = status
        self.createdBy = createdBy
        self.createdByImageURL = createdByImageURL
        self.creationDate = creationDate
        self.isDraft = isDraft
        self.url = url
        self.sourceBranch = sourceBranch
        self.targetBranch = targetBranch
    }

    /// Creates a summary from an API model
    public static func from(apiModel: AzureDevOpsPullRequest) -> AzurePullRequestSummary? {
        guard let createdBy = apiModel.createdBy,
              let urlString = apiModel.url,
              let url = URL(string: urlString) else {
            return nil
        }

        let author = createdBy.displayName ?? createdBy.uniqueName ?? "Unknown"

        let sourceBranch = apiModel.sourceRefName?.replacingOccurrences(of: "refs/heads/", with: "") ?? ""
        let targetBranch = apiModel.targetRefName?.replacingOccurrences(of: "refs/heads/", with: "") ?? ""

        return AzurePullRequestSummary(
            pullRequestId: apiModel.pullRequestId,
            title: apiModel.title,
            status: AzurePullRequestStatus(rawValue: apiModel.status) ?? .notSet,
            createdBy: author,
            createdByImageURL: createdBy.imageUrl.flatMap { URL(string: $0) },
            creationDate: apiModel.creationDate ?? Date(),
            isDraft: apiModel.isDraft ?? false,
            url: url,
            sourceBranch: sourceBranch,
            targetBranch: targetBranch
        )
    }

    /// Converts to the domain model
    public func toDomain() -> AzurePullRequestDomain {
        AzurePullRequestDomain.from(summary: self)
    }

    /// Converts to the common RepoPullRequestSummary domain model
    public func toPullRequestSummary() -> RepoPullRequestSummary {
        toDomain().toPullRequestSummary()
    }

    /// Creates a summary from a common RepoPullRequestSummary
    public init(from summary: RepoPullRequestSummary) {
        self.pullRequestId = summary.number
        self.title = summary.title
        self.status = .notSet
        self.createdBy = summary.authorLogin ?? "Unknown"
        self.createdByImageURL = summary.authorAvatarURL
        self.creationDate = summary.updatedAt
        self.isDraft = summary.isDraft
        self.url = summary.url
        self.sourceBranch = summary.headRefName ?? ""
        self.targetBranch = summary.baseRefName ?? ""
    }
}
