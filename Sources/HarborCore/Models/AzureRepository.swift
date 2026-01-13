import Foundation

/// Azure DevOps repository model
public struct AzureRepository: ProviderRepository {
    public let id: String
    public let name: String
    public let project: String
    public let organization: String
    public let defaultBranch: String?
    public let size: Int?
    public let isDisabled: Bool
    public let webURL: URL
    public let remoteURL: URL?

    public init(
        id: String,
        name: String,
        project: String,
        organization: String,
        defaultBranch: String? = nil,
        size: Int? = nil,
        isDisabled: Bool = false,
        webURL: URL,
        remoteURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.project = project
        self.organization = organization
        self.defaultBranch = defaultBranch
        self.size = size
        self.isDisabled = isDisabled
        self.webURL = webURL
        self.remoteURL = remoteURL
    }

    // MARK: - ProviderRepository Conformance

    public var ownerOrOrganization: String {
        self.organization
    }

    public var fullPath: String {
        "\(self.organization)/\(self.project)/\(self.name)"
    }

    public var providerType: ProviderType {
        .azureDevOps
    }

    // MARK: - Computed Properties

    /// The default branch name without the refs/heads/ prefix
    public var defaultBranchName: String? {
        guard let branch = defaultBranch else { return nil }
        return branch.replacingOccurrences(of: "refs/heads/", with: "")
    }

    /// Whether the repository is accessible
    public var isAccessible: Bool {
        !isDisabled
    }

    /// A human-readable size string
    public var sizeDescription: String? {
        guard let sizeBytes = size else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(sizeBytes))
    }

    // MARK: - Conversion to Domain Model

    /// Converts to the domain model
    public func toDomain() -> AzureRepositoryDomain {
        AzureRepositoryDomain(
            id: id,
            name: name,
            project: project,
            organization: organization,
            defaultBranch: defaultBranch,
            webURL: webURL
        )
    }

    /// Converts to the common Repository domain model
    public func toRepository() -> Repository {
        Repository(
            id: id,
            name: name,
            owner: organization,
            isFork: false,
            isArchived: isDisabled,
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

    // MARK: - Factory Methods

    /// Creates an AzureRepository from an API model
    public static func from(apiModel: AzureDevOpsRepository, organization: String) -> AzureRepository? {
        guard let webURLString = apiModel.webUrl,
              let webURL = URL(string: webURLString) else {
            return nil
        }

        return AzureRepository(
            id: apiModel.id,
            name: apiModel.name,
            project: apiModel.project?.name ?? "",
            organization: organization,
            defaultBranch: apiModel.defaultBranch,
            size: apiModel.size,
            isDisabled: apiModel.isDisabled ?? false,
            webURL: webURL,
            remoteURL: apiModel.remoteUrl.flatMap { URL(string: $0) }
        )
    }

    // MARK: - Equatable

    public static func == (lhs: AzureRepository, rhs: AzureRepository) -> Bool {
        lhs.id == rhs.id
    }
}

/// Azure DevOps repository statistics
public struct AzureRepositoryStats: Codable, Equatable, Sendable {
    public var pullRequestCount: Int
    public var activePullRequestCount: Int
    public var commitCount: Int?
    public var branchCount: Int?
    public var lastPushDate: Date?

    public init(
        pullRequestCount: Int = 0,
        activePullRequestCount: Int = 0,
        commitCount: Int? = nil,
        branchCount: Int? = nil,
        lastPushDate: Date? = nil
    ) {
        self.pullRequestCount = pullRequestCount
        self.activePullRequestCount = activePullRequestCount
        self.commitCount = commitCount
        self.branchCount = branchCount
        self.lastPushDate = lastPushDate
    }
}

/// Azure DevOps repository reference (lightweight)
public struct AzureRepositoryRef: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let url: URL?

    public init(id: String, name: String, url: URL? = nil) {
        self.id = id
        self.name = name
        self.url = url
    }
}

/// Azure DevOps repository branch
public struct AzureBranch: Codable, Equatable, Sendable {
    public let name: String
    public let objectId: String
    public let creator: AzureIdentity?
    public let isBaseVersion: Bool

    public init(
        name: String,
        objectId: String,
        creator: AzureIdentity? = nil,
        isBaseVersion: Bool = false
    ) {
        self.name = name
        self.objectId = objectId
        self.creator = creator
        self.isBaseVersion = isBaseVersion
    }

    /// The branch name without the refs/heads/ prefix
    public var shortName: String {
        name.replacingOccurrences(of: "refs/heads/", with: "")
    }

    /// Converts to a domain branch model
    public func toDomain() -> AzureBranchDomain {
        AzureBranchDomain.from(apiModel: self)
    }

    /// Converts to the common RepoBranchSummary domain model
    public func toBranchSummary() -> RepoBranchSummary {
        AzureBranchDomain.from(apiModel: self).toBranchSummary()
    }
}

/// Azure DevOps repository commit
public struct AzureCommit: Codable, Equatable, Sendable {
    public let commitId: String
    public let message: String
    public let author: AzureCommitAuthor
    public let committer: AzureCommitAuthor
    public let url: URL?
    public let changeCounts: AzureChangeCount?

    public init(
        commitId: String,
        message: String,
        author: AzureCommitAuthor,
        committer: AzureCommitAuthor,
        url: URL? = nil,
        changeCounts: AzureChangeCount? = nil
    ) {
        self.commitId = commitId
        self.message = message
        self.author = author
        self.committer = committer
        self.url = url
        self.changeCounts = changeCounts
    }

    /// Short commit ID (first 7 characters)
    public var shortId: String {
        String(commitId.prefix(7))
    }

    /// First line of the commit message
    public var firstLine: String {
        message.split(whereSeparator: \.isNewline).first.map(String.init) ?? message
    }

    /// Converts to a domain commit model
    public func toDomain() -> AzureCommitDomain {
        AzureCommitDomain.from(apiModel: self)
    }

    /// Converts to the common RepoCommitSummary domain model
    public func toCommitSummary() -> RepoCommitSummary {
        AzureCommitDomain.from(apiModel: self).toCommitSummary()
    }
}

/// Azure DevOps commit author/committer
public struct AzureCommitAuthor: Codable, Equatable, Sendable {
    public let name: String
    public let email: String
    public let date: Date

    public init(name: String, email: String, date: Date) {
        self.name = name
        self.email = email
        self.date = date
    }
}

/// Azure DevOps change count
public struct AzureChangeCount: Codable, Equatable, Sendable {
    public let add: Int
    public let edit: Int
    public let delete: Int

    public init(add: Int = 0, edit: Int = 0, delete: Int = 0) {
        self.add = add
        self.edit = edit
        self.delete = delete
    }

    /// Total changes
    public var total: Int {
        add + edit + delete
    }
}

/// Azure DevOps identity (user/group reference)
public struct AzureIdentity: Codable, Equatable, Sendable {
    public let id: String?
    public let displayName: String
    public let uniqueName: String?
    public let imageURL: URL?
    public let descriptor: String?

    public init(
        id: String? = nil,
        displayName: String,
        uniqueName: String? = nil,
        imageURL: URL? = nil,
        descriptor: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.uniqueName = uniqueName
        self.imageURL = imageURL
        self.descriptor = descriptor
    }

    /// The primary identifier (uniqueName or displayName)
    public var primaryIdentifier: String {
        uniqueName ?? displayName
    }
}
