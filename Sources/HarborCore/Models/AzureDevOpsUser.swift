import Foundation

/// Represents an Azure DevOps user profile
public struct AzureDevOpsUser: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let uniqueName: String
    public let emailAddress: String?
    public let avatarUrl: String?

    public init(
        id: String,
        displayName: String,
        uniqueName: String,
        emailAddress: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.uniqueName = uniqueName
        self.emailAddress = emailAddress
        self.avatarUrl = avatarUrl
    }
}

/// Represents a GitLab user profile
public struct GitLabUser: Codable, Hashable, Sendable {
    public let id: Int
    public let username: String
    public let name: String
    public let email: String?
    public let avatarUrl: String?
    public let webUrl: String?

    public init(
        id: Int,
        username: String,
        name: String,
        email: String? = nil,
        avatarUrl: String? = nil,
        webUrl: String? = nil
    ) {
        self.id = id
        self.username = username
        self.name = name
        self.email = email
        self.avatarUrl = avatarUrl
        self.webUrl = webUrl
    }
}
