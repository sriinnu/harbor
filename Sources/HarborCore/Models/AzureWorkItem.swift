import Foundation

/// Azure DevOps work item domain model with ProviderWorkItem conformance
public struct AzureWorkItem: ProviderWorkItem {
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
    public let createdBy: String?
    public let createdByAvatarURL: URL?
    public let revision: Int?

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
        assignedToAvatarURL: URL?,
        createdBy: String?,
        createdByAvatarURL: URL?,
        revision: Int?
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
        self.createdBy = createdBy
        self.createdByAvatarURL = createdByAvatarURL
        self.revision = revision
    }

    // MARK: - ProviderWorkItem Conformance

    /// The mapped work item type
    public var workItemType: AzureWorkItemType {
        AzureWorkItemType(from: itemType)
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

    // MARK: - Conversion to Domain Model

    /// Converts to the domain model
    public func toDomain() -> AzureWorkItemDomain? {
        AzureWorkItemDomain(
            id: id,
            number: number,
            title: title,
            state: state,
            itemType: itemType,
            assignedTo: assignedTo,
            createdAt: createdAt,
            updatedAt: updatedAt,
            webURL: webURL,
            description: description,
            priority: priority,
            severity: severity,
            tags: tags,
            assignedToAvatarURL: assignedToAvatarURL
        )
    }

    /// Converts to the common RepoIssueSummary domain model
    public func toIssueSummary() -> RepoIssueSummary {
        RepoIssueSummary(
            number: number,
            title: title,
            url: webURL,
            updatedAt: updatedAt,
            authorLogin: createdBy ?? assignedTo,
            authorAvatarURL: createdByAvatarURL ?? assignedToAvatarURL,
            assigneeLogins: assignedTo.map { [$0] } ?? [],
            commentCount: 0,
            labels: tags.map { RepoIssueLabel(name: $0, colorHex: "6e7681") }
        )
    }

    // MARK: - Factory Methods

    /// Creates an AzureWorkItem from an API model
    public static func from(apiModel: AzureDevOpsWorkItem, project: String, organization: String) -> AzureWorkItem? {
        guard let fields = apiModel.fields else { return nil }

        let fallbackURL = URL(string: "https://dev.azure.com/\(organization)/\(project)/_workitems?id=\(apiModel.id)")!
        let webURL = apiModel.url.flatMap { URL(string: $0) } ?? fallbackURL

        let assignedToDisplay = fields.systemAssignedTo?.displayName
        let assignedToUnique = fields.systemAssignedTo?.uniqueName
        let createdByDisplay = fields.systemCreatedBy?.displayName
        let createdByUnique = fields.systemCreatedBy?.uniqueName

        let tagList = fields.systemTags?.split(separator: ";").map { String($0).trimmingCharacters(in: .whitespaces) } ?? []

        return AzureWorkItem(
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
            tags: tagList,
            assignedToAvatarURL: fields.systemAssignedTo?.imageUrl.flatMap { URL(string: $0) },
            createdBy: createdByDisplay ?? createdByUnique,
            createdByAvatarURL: fields.systemCreatedBy?.imageUrl.flatMap { URL(string: $0) },
            revision: apiModel.rev
        )
    }

    // MARK: - Equatable

    public static func == (lhs: AzureWorkItem, rhs: AzureWorkItem) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision
    }
}

/// Azure DevOps work item type
public enum AzureWorkItemType: String, Sendable, CaseIterable {
    case bug = "Bug"
    case task = "Task"
    case userStory = "User Story"
    case feature = "Feature"
    case epic = "Epic"
    case issue = "Issue"
    case testCase = "Test Case"
    case unknown = "Unknown"

    public init(from rawValue: String) {
        switch rawValue.lowercased() {
        case "bug":
            self = .bug
        case "task":
            self = .task
        case "user story":
            self = .userStory
        case "feature":
            self = .feature
        case "epic":
            self = .epic
        case "issue":
            self = .issue
        case "test case":
            self = .testCase
        default:
            self = .unknown
        }
    }

    public var displayName: String {
        rawValue
    }

    public var iconName: String {
        switch self {
        case .bug:
            return "ladybug.fill"
        case .task:
            return "checkmark.circle"
        case .userStory:
            return "book.fill"
        case .feature:
            return "star.fill"
        case .epic:
            return "bolt.fill"
        case .issue:
            return "exclamationmark.circle"
        case .testCase:
            return "testpipe.2"
        case .unknown:
            return "questionmark.circle"
        }
    }

    public var colorHex: String {
        switch self {
        case .bug:
            return "d73a49"
        case .task:
            return "0052cc"
        case .userStory:
            return "0075ca"
        case .feature:
            return "795ada"
        case .epic:
            return "6e7681"
        case .issue:
            return "e4e669"
        case .testCase:
            return "0e6a00"
        case .unknown:
            return "6a737d"
        }
    }
}

/// Azure DevOps work item query result
public struct AzureWorkItemQueryResult: Codable, Sendable {
    public let workItems: [AzureWorkItemReference]
    public let queryType: String?
    public let queryResultType: String?

    public init(workItems: [AzureWorkItemReference], queryType: String? = nil, queryResultType: String? = nil) {
        self.workItems = workItems
        self.queryType = queryType
        self.queryResultType = queryResultType
    }
}

/// Azure DevOps work item reference (lightweight)
public struct AzureWorkItemReference: Codable, Sendable {
    public let id: Int
    public let url: URL?
    public let webURL: URL?

    public init(id: Int, url: URL? = nil, webURL: URL? = nil) {
        self.id = id
        self.url = url
        self.webURL = webURL
    }
}

/// Azure DevOps work item comment
public struct AzureWorkItemComment: Codable, Sendable {
    public let id: Int
    public let text: String
    public let createdDate: Date
    public let createdBy: AzureIdentity?
    public let modifiedDate: Date?
    public let isDeleted: Bool

    public init(
        id: Int,
        text: String,
        createdDate: Date,
        createdBy: AzureIdentity?,
        modifiedDate: Date? = nil,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.text = text
        self.createdDate = createdDate
        self.createdBy = createdBy
        self.modifiedDate = modifiedDate
        self.isDeleted = isDeleted
    }

    public var textPreview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed.prefix(200))
        return prefix + (trimmed.count > 200 ? "..." : "")
    }
}

/// Extension to AzureDevOpsWorkItem for easier conversion
extension AzureDevOpsWorkItem {
    /// Converts to an AzureWorkItem domain model
    public func toWorkItem(project: String, organization: String) -> AzureWorkItem? {
        AzureWorkItem.from(apiModel: self, project: project, organization: organization)
    }
}
