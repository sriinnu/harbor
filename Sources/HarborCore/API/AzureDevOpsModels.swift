import Foundation

// MARK: - Core Models

struct AzureDevOpsOrganization: Decodable, Sendable {
    let accountId: String
    let accountName: String
    let accountUri: String?

    enum CodingKeys: String, CodingKey {
        case accountId
        case accountName
        case accountUri
    }
}

public struct AzureDevOpsProject: Decodable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let description: String?
    public let url: String?
    public let state: String?
    public let visibility: String?
    public let lastUpdateTime: Date?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case url
        case state
        case visibility
        case lastUpdateTime
    }
}

public struct AzureDevOpsRepository: Decodable, Sendable {
    public let id: String
    public let name: String
    public let url: String?
    public let project: ProjectReference?
    public let defaultBranch: String?
    public let size: Int?
    public let remoteUrl: String?
    public let sshUrl: String?
    public let webUrl: String?
    public let isDisabled: Bool?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case project
        case defaultBranch
        case size
        case remoteUrl
        case sshUrl
        case webUrl
        case isDisabled
    }

    public struct ProjectReference: Decodable, Sendable {
        public let id: String
        public let name: String
    }
}

// MARK: - Pull Request Models

public struct AzureDevOpsPullRequest: Decodable, Sendable {
    public let pullRequestId: Int
    public let title: String
    public let description: String?
    public let status: String
    public let createdBy: IdentityRef?
    public let creationDate: Date?
    public let closedDate: Date?
    public let sourceRefName: String?
    public let targetRefName: String?
    public let mergeStatus: String?
    public let isDraft: Bool?
    public let url: String?
    public let repository: RepositoryReference?
    public let reviewers: [Reviewer]?
    public let labels: [Label]?

    public enum CodingKeys: String, CodingKey {
        case pullRequestId
        case title
        case description
        case status
        case createdBy
        case creationDate
        case closedDate
        case sourceRefName
        case targetRefName
        case mergeStatus
        case isDraft
        case url
        case repository
        case reviewers
        case labels
    }

    public struct RepositoryReference: Decodable, Sendable {
        public let id: String
        public let name: String
    }

    public struct Reviewer: Decodable, Sendable {
        public let vote: Int?
        public let isRequired: Bool?
        public let reviewerUrl: String?
        public let displayName: String?
        public let uniqueName: String?
        public let imageUrl: String?

        public enum CodingKeys: String, CodingKey {
            case vote
            case isRequired
            case reviewerUrl
            case displayName
            case uniqueName
            case imageUrl
        }
    }

    public struct Label: Decodable, Sendable {
        public let id: String?
        public let name: String
    }
}

// MARK: - Pipeline Models

public struct AzureDevOpsPipeline: Decodable, Sendable {
    public let id: Int
    public let name: String
    public let folder: String?
    public let url: String?
    public let revision: Int?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case folder
        case url
        case revision
    }
}

public struct AzureDevOpsPipelineRun: Decodable, Sendable {
    public let id: Int
    public let name: String?
    public let state: String?
    public let result: String?
    public let createdDate: Date?
    public let finishedDate: Date?
    public let url: String?
    public let pipeline: PipelineReference?
    public let resources: Resources?

    public enum CodingKeys: String, CodingKey {
        case id
        case name
        case state
        case result
        case createdDate
        case finishedDate
        case url
        case pipeline
        case resources
    }

    public struct PipelineReference: Decodable, Sendable {
        public let id: Int
        public let name: String?
        public let folder: String?
    }

    public struct Resources: Decodable, Sendable {
        public let repositories: [String: RepositoryResource]?

        public struct RepositoryResource: Decodable, Sendable {
            public let refName: String?
            public let version: String?
        }
    }
}

// MARK: - Work Item Models

public struct AzureDevOpsWorkItem: Decodable, Sendable {
    public let id: Int
    public let rev: Int?
    public let fields: WorkItemFields?
    public let url: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case rev
        case fields
        case url
    }

    public struct WorkItemFields: Decodable, Sendable {
        public let systemWorkItemType: String?
        public let systemTitle: String?
        public let systemState: String?
        public let systemAssignedTo: AssignedTo?
        public let systemCreatedDate: Date?
        public let systemChangedDate: Date?
        public let systemCreatedBy: CreatedBy?
        public let systemDescription: String?
        public let systemTags: String?
        public let microsoftVSTSCommonPriority: Int?
        public let microsoftVSTSCommonSeverity: String?

        public enum CodingKeys: String, CodingKey {
            case systemWorkItemType = "System.WorkItemType"
            case systemTitle = "System.Title"
            case systemState = "System.State"
            case systemAssignedTo = "System.AssignedTo"
            case systemCreatedDate = "System.CreatedDate"
            case systemChangedDate = "System.ChangedDate"
            case systemCreatedBy = "System.CreatedBy"
            case systemDescription = "System.Description"
            case systemTags = "System.Tags"
            case microsoftVSTSCommonPriority = "Microsoft.VSTS.Common.Priority"
            case microsoftVSTSCommonSeverity = "Microsoft.VSTS.Common.Severity"
        }

        public struct AssignedTo: Decodable, Sendable {
            public let displayName: String?
            public let uniqueName: String?
            public let imageUrl: String?
        }

        public struct CreatedBy: Decodable, Sendable {
            public let displayName: String?
            public let uniqueName: String?
            public let imageUrl: String?
        }
    }
}

// MARK: - Commit Models

public struct AzureDevOpsCommit: Decodable, Sendable {
    public let commitId: String
    public let comment: String?
    public let author: Author?
    public let committer: Committer?
    public let changeCounts: ChangeCounts?
    public let url: String?
    public let remoteUrl: String?

    public enum CodingKeys: String, CodingKey {
        case commitId
        case comment
        case author
        case committer
        case changeCounts
        case url
        case remoteUrl
    }

    public struct Author: Decodable, Sendable {
        public let name: String?
        public let email: String?
        public let date: Date?
    }

    public struct Committer: Decodable, Sendable {
        public let name: String?
        public let email: String?
        public let date: Date?
    }

    public struct ChangeCounts: Decodable, Sendable {
        public let add: Int?
        public let edit: Int?
        public let delete: Int?
    }
}

// MARK: - Branch Models

public struct AzureDevOpsBranch: Decodable, Sendable {
    public let name: String
    public let objectId: String?
    public let creator: IdentityRef?
    public let url: String?
    public let isBaseVersion: Bool?

    public enum CodingKeys: String, CodingKey {
        case name
        case objectId
        case creator
        case url
        case isBaseVersion
    }
}

// MARK: - Common Models

public struct IdentityRef: Decodable, Sendable {
    public let id: String?
    public let displayName: String?
    public let uniqueName: String?
    public let url: String?
    public let imageUrl: String?
    public let descriptor: String?

    public enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case uniqueName
        case url
        case imageUrl
        case descriptor
    }
}

public struct WebApiCreateTagRequestData: Decodable, Sendable {
    public let name: String
}

// MARK: - Response Wrappers

public struct AzureDevOpsListResponse<T: Decodable>: Decodable {
    public let count: Int?
    public let value: [T]

    public enum CodingKeys: String, CodingKey {
        case count
        case value
    }
}

public struct AzureDevOpsErrorResponse: Decodable {
    public let message: String?
    public let typeKey: String?
    public let errorCode: Int?

    public enum CodingKeys: String, CodingKey {
        case message
        case typeKey
        case errorCode
    }
}

// MARK: - Push Models

public struct AzureDevOpsPush: Decodable, Sendable {
    public let pushId: Int
    public let date: Date?
    public let pushedBy: IdentityRef?
    public let url: String?
    public let repository: RepositoryReference?
    public let commits: [CommitRef]?

    public enum CodingKeys: String, CodingKey {
        case pushId
        case date
        case pushedBy
        case url
        case repository
        case commits
    }

    public struct RepositoryReference: Decodable, Sendable {
        public let id: String
        public let name: String
    }

    public struct CommitRef: Decodable, Sendable {
        public let commitId: String
        public let comment: String?
    }
}

// MARK: - User Profile Models

public struct AzureDevOpsProfile: Decodable, Sendable {
    public let id: String
    public let displayName: String?
    public let emailAddress: String?
    public let publicAlias: String?
    public let coreRevision: Int?
    public let timeStamp: Date?

    public enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case emailAddress
        case publicAlias
        case coreRevision
        case timeStamp
    }
}
