import Foundation

/// Represents the source control provider type
public enum ProviderType: String, Codable, CaseIterable, Sendable {
    case github = "GitHub"
    case azureDevOps = "Azure DevOps"
    case gitlab = "GitLab"

    public var displayName: String {
        self.rawValue
    }

    public var baseURL: URL {
        switch self {
        case .github:
            return URL(string: "https://github.com")!
        case .azureDevOps:
            return URL(string: "https://dev.azure.com")!
        case .gitlab:
            return URL(string: "https://gitlab.com")!
        }
    }

    public var apiBaseURL: URL {
        switch self {
        case .github:
            return URL(string: "https://api.github.com")!
        case .azureDevOps:
            return URL(string: "https://dev.azure.com")!
        case .gitlab:
            return URL(string: "https://gitlab.com/api/v4")!
        }
    }
}

/// Protocol for provider-specific repository information
public protocol ProviderRepository: Identifiable, Equatable, Sendable {
    var id: String { get }
    var name: String { get }
    var ownerOrOrganization: String { get }
    var fullPath: String { get }
    var webURL: URL { get }
    var providerType: ProviderType { get }
}

/// Protocol for provider-specific pull request/merge request information
public protocol ProviderPullRequest: Identifiable, Equatable, Sendable {
    var id: String { get }
    var number: Int { get }
    var title: String { get }
    var state: String { get }
    var authorLogin: String? { get }
    var authorAvatarURL: URL? { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var webURL: URL { get }
    var providerType: ProviderType { get }
}

/// Protocol for provider-specific CI/CD pipeline information
public protocol ProviderPipeline: Identifiable, Equatable, Sendable {
    var id: String { get }
    var name: String { get }
    var status: CIStatus { get }
    var runNumber: Int? { get }
    var createdAt: Date? { get }
    var updatedAt: Date? { get }
    var webURL: URL { get }
    var providerType: ProviderType { get }
}

/// Protocol for provider-specific work item/issue information
public protocol ProviderWorkItem: Identifiable, Equatable, Sendable {
    var id: String { get }
    var number: Int { get }
    var title: String { get }
    var state: String { get }
    var itemType: String { get }
    var assignedTo: String? { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var webURL: URL { get }
    var providerType: ProviderType { get }
}

/// Protocol for provider-specific project/organization information
public protocol ProviderProject: Identifiable, Equatable, Sendable {
    var id: String { get }
    var name: String { get }
    var description: String? { get }
    var webURL: URL { get }
    var providerType: ProviderType { get }
}
