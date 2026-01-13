import Foundation

// MARK: - GitLab Project

public struct GitLabProject: Codable, Sendable, Identifiable {
    public let id: Int
    public let name: String
    public let nameWithNamespace: String
    public let path: String
    public let pathWithNamespace: String
    public let webUrl: URL
    public let avatarUrl: URL?
    public let defaultBranch: String?
    public let visibility: String?
    public let starCount: Int
    public let forksCount: Int
    public let createdAt: Date?
    public let updatedAt: Date?

    public init(
        id: Int,
        name: String,
        nameWithNamespace: String,
        path: String,
        pathWithNamespace: String,
        webUrl: URL,
        avatarUrl: URL? = nil,
        defaultBranch: String? = nil,
        visibility: String? = nil,
        starCount: Int = 0,
        forksCount: Int = 0,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.nameWithNamespace = nameWithNamespace
        self.path = path
        self.pathWithNamespace = pathWithNamespace
        self.webUrl = webUrl
        self.avatarUrl = avatarUrl
        self.defaultBranch = defaultBranch
        self.visibility = visibility
        self.starCount = starCount
        self.forksCount = forksCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct GitLabNamespace: Codable, Sendable {
    public let id: Int
    public let name: String
    public let path: String
    public let kind: String?
    public let fullPath: String?
    public let parentId: Int?
}

// MARK: - GitLab Issue

public struct GitLabIssue: Codable, Sendable {
    public let iid: Int
    public let title: String
    public let description: String?
    public let state: String
    public let author: GitLabUser
    public let assignee: GitLabUser?
    public let labels: [String]
    public let webUrl: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let closedAt: Date?
    public let confidential: Bool
    public let discussionLocked: Bool?
    public let dueDate: Date?

    public var id: Int { iid }
    public var isOpen: Bool { state.lowercased() == "opened" }
    public var isClosed: Bool { state.lowercased() == "closed" }
}

// MARK: - GitLab Merge Request

public struct GitLabMergeRequest: Codable, Sendable {
    public let iid: Int
    public let title: String
    public let description: String?
    public let state: String
    public let sourceBranch: String
    public let targetBranch: String
    public let author: GitLabUser
    public let assignees: [GitLabUser]
    public let reviewers: [GitLabUser]
    public let webUrl: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let mergedAt: Date?
    public let closedAt: Date?
    public let draft: Bool
    public let mergeStatus: String?
    public let hasConflicts: Bool?
    public let blockingDiscussionsResolved: Bool?

    public var id: Int { iid }
    public var isOpen: Bool { state.lowercased() == "opened" }
    public var isClosed: Bool { state.lowercased() == "closed" }
    public var isMerged: Bool { state.lowercased() == "merged" }
    public var isDraft: Bool { draft }
    public var isMergeable: Bool { mergeStatus == "can_be_merged" }
}

// MARK: - GitLab Pipeline

public struct GitLabPipeline: Codable, Sendable, Identifiable {
    public let id: Int
    public let status: String
    public let ref: String
    public let sha: String
    public let webUrl: URL
    public let createdAt: Date
    public let finishedAt: Date?
    public let duration: Int?
    public let coverage: Double?

    public var isRunning: Bool { status.lowercased() == "running" }
    public var isSuccess: Bool { status.lowercased() == "success" }
    public var isFailed: Bool { status.lowercased() == "failed" }
    public var isPending: Bool { status.lowercased() == "pending" || status.lowercased() == "created" }
}

// MARK: - GitLab API Response Types

public struct GitLabListResponse<T: Codable>: Codable {
    public let items: [T]
    public let total: Int?
    public let nextPage: Int?
    public let perPage: Int?

    public enum CodingKeys: String, CodingKey {
        case items
        case total
        case nextPage = "next_page"
        case perPage = "per_page"
    }
}

// MARK: - GitLab Error Response

public struct GitLabErrorResponse: Codable {
    public let message: String?
    public let error: String?
    public let errorDescription: String?

    public enum CodingKeys: String, CodingKey {
        case message
        case error
        case errorDescription = "error_description"
    }
}
