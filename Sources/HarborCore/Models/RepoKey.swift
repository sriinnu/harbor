import Foundation

/// Which repository a pin, a hidden entry or a list row means, across providers.
///
/// The string form is what settings store. A github.com repository stays the bare
/// `owner/name` it has always been, so existing pins and hidden lists read back unchanged.
/// An Azure DevOps repository is `azure:{host}/{organization}/{project}/{name}`, which never
/// parses as a GitHub name (it has a scheme and four parts), so it can't reach a GitHub call.
public enum RepoKey: Hashable, Sendable {
    case github(owner: String, name: String)
    case azure(host: String, organization: String, project: String, name: String)

    public static let azurePrefix = "azure:"

    /// Nil for anything that is neither form, which callers leave as it is.
    public init?(_ string: String) {
        if string.hasPrefix(Self.azurePrefix) {
            let parts = string.dropFirst(Self.azurePrefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            // Host and organization compare without case (Azure's do, and the PAT store keys
            // organizations lowercased); project and repo names keep the case Azure gave them.
            self = .azure(host: parts[0].lowercased(), organization: parts[1].lowercased(), project: parts[2], name: parts[3])
            return
        }
        let parts = string.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), !parts[0].contains(":") else { return nil }
        self = .github(owner: parts[0], name: parts[1])
    }

    /// The stored form; `RepoKey(key.string) == key`.
    public var string: String {
        switch self {
        case let .github(owner, name): "\(owner)/\(name)"
        case let .azure(host, organization, project, name): "\(Self.azurePrefix)\(host)/\(organization)/\(project)/\(name)"
        }
    }

    public var isGitHub: Bool {
        if case .github = self { return true }
        return false
    }

    /// Names compare without case on both providers.
    public var dedupeID: String { self.string.lowercased() }

    /// Owner and name of a stored GitHub name; nil for an Azure key or anything that isn't
    /// exactly `owner/name`. Every place that turns a stored name into a GitHub request goes
    /// through this, so an Azure key can't become owner `azure:dev.azure.com`.
    public static func gitHubOwnerAndName(_ stored: String) -> (owner: String, name: String)? {
        guard case let .github(owner, name) = RepoKey(stored) else { return nil }
        return (owner, name)
    }

    /// Only the GitHub entries of a pin or hidden list, as stored. Azure and unparseable
    /// entries stay in settings; they just never reach a GitHub request.
    public static func githubOnly(_ stored: [String]) -> [String] {
        stored.filter { RepoKey($0)?.isGitHub == true }
    }

    /// True for a stored name that is an Azure DevOps key.
    public static func isAzure(_ stored: String) -> Bool {
        if case .azure = RepoKey(stored) { return true }
        return false
    }
}

/// What Azure DevOps says about one repository. Present only on Azure rows; GitHub rows
/// leave it nil. Counts Azure doesn't hand out in its listing are not guessed.
public struct AzureRepoInfo: Equatable, Sendable {
    public let host: String
    public let organization: String
    public let project: String
    /// Azure's repository GUID; names can be renamed, this can't.
    public let id: String
    public let defaultBranch: String?
    public let webURL: URL?
    public let isDisabled: Bool

    public init(host: String, organization: String, project: String, id: String, defaultBranch: String?, webURL: URL?, isDisabled: Bool) {
        self.host = host
        self.organization = organization
        self.project = project
        self.id = id
        self.defaultBranch = defaultBranch
        self.webURL = webURL
        self.isDisabled = isDisabled
    }

    /// `refs/heads/main` reads as `main`.
    public var branchName: String? {
        guard let ref = self.defaultBranch, !ref.isEmpty else { return nil }
        let prefix = "refs/heads/"
        return ref.hasPrefix(prefix) ? String(ref.dropFirst(prefix.count)) : ref
    }
}
