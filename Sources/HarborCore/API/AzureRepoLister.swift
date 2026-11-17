import Foundation

/// Why an Azure DevOps listing came back empty-handed, in words for the person.
public enum AzureRepoListError: Error, Equatable, LocalizedError {
    /// 401, or 203 with Azure's sign-in page: the PAT expired or was revoked.
    case signInExpired(organization: String)
    case failed(organization: String, message: String)

    public var errorDescription: String? {
        switch self {
        case let .signInExpired(organization):
            "Azure DevOps sign-in for \(organization) has expired. Reconnect it in Settings → Accounts."
        case let .failed(organization, message):
            "Azure DevOps (\(organization)): \(message)"
        }
    }
}

/// Every repository in an Azure DevOps organization, from one request:
/// `GET {host}/{org}/_apis/git/repositories?api-version=7.0`. Azure answers with the whole organization at
/// once (it doesn't page this endpoint), so matching and ranking happen on the client.
public struct AzureRepoLister: Sendable {
    public static let defaultHost = URL(string: "https://dev.azure.com")!
    /// A slow Azure never holds a refresh for the default minute.
    public static let timeout: TimeInterval = 15

    private let host: URL
    private let runner: AzureDevOpsRequestRunner

    public init(host: URL = Self.defaultHost, session: URLSession = HarborURLSession.shared) {
        self.host = host
        self.runner = AzureDevOpsRequestRunner(session: session)
    }

    public func repositories(organization: String, pat: String) async throws -> [Repository] {
        var components = URLComponents(url: self.host, resolvingAgainstBaseURL: false)
        components?.path = "/\(organization)/_apis/git/repositories"
        components?.queryItems = [URLQueryItem(name: "api-version", value: "7.0")]
        guard let url = components?.url else { throw AzureRepoListError.failed(organization: organization, message: "Invalid organization name.") }
        let data: Data
        do {
            (data, _) = try await self.runner.get(url: url, pat: pat, timeout: Self.timeout)
        } catch AzureDevOpsAPIError.unauthorized {
            throw AzureRepoListError.signInExpired(organization: organization)
        } catch AzureDevOpsAPIError.badStatus(code: 203, _) {
            throw AzureRepoListError.signInExpired(organization: organization)
        } catch let error as AzureDevOpsAPIError {
            throw AzureRepoListError.failed(organization: organization, message: error.displayMessage)
        }
        // Anything else (offline, timed out, cancelled) passes through as it is.
        let list: AzureDevOpsListResponse<AzureDevOpsRepository>
        do {
            list = try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsRepository>.self, from: data)
        } catch {
            // A sign-in page that came back as 200 HTML is still a sign-in page; anything else
            // that won't decode is just an answer Harbor doesn't understand.
            if Self.looksLikeHTML(data) { throw AzureRepoListError.signInExpired(organization: organization) }
            throw AzureRepoListError.failed(organization: organization, message: "Unexpected response.")
        }
        let hostName = (self.host.host() ?? "dev.azure.com").lowercased()
        return list.value.compactMap { Self.repository(from: $0, host: hostName, organization: organization.lowercased()) }
    }

    static func looksLikeHTML(_ data: Data) -> Bool {
        guard let text = String(bytes: data.prefix(256), encoding: .utf8) else { return false }
        return text.drop(while: \.isWhitespace).hasPrefix("<")
    }

    /// A listed row. Counts Azure doesn't send are left unknown (`pullCountsKnown: false`),
    /// never shown as zero.
    static func repository(from item: AzureDevOpsRepository, host rawHost: String, organization rawOrganization: String) -> Repository? {
        let host = rawHost.lowercased()
        let organization = rawOrganization.lowercased()
        guard let project = item.project?.name, !project.isEmpty, !item.name.isEmpty else { return nil }
        let info = AzureRepoInfo(
            host: host,
            organization: organization,
            project: project,
            id: item.id,
            defaultBranch: item.defaultBranch,
            webURL: item.webUrl.flatMap(URL.init(string:)),
            isDisabled: item.isDisabled ?? false
        )
        let key = RepoKey.azure(host: host, organization: organization, project: project, name: item.name)
        return Repository(
            id: key.string,
            name: item.name,
            owner: organization,
            isArchived: info.isDisabled,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            openIssues: 0,
            openPulls: 0,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: [],
            pullCountsKnown: false
        ).withAzure(info)
    }
}
