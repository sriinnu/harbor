import Foundation

/// Derives a user's Azure DevOps activity, since the service has no contribution calendar:
/// commits by the user, pull requests they opened, and pull requests they were asked to
/// review. Requests are bounded: at most `maxProjects` projects, `maxRepositories`
/// repositories in total and `commitsPerRepository` commits per repository, so the cost is
/// at most about 2 + 3 × projects + repositories requests. `partial` reports any cap hit.
struct AzureDevOpsActivityFetcher {
    static let maxProjects = 8
    static let maxRepositories = 24
    static let commitsPerRepository = 500
    static let pullRequestsPerQuery = 200

    let apiHost: URL
    let organization: String
    let pat: String
    let runner: AzureDevOpsRequestRunner

    private struct Identity {
        let id: String
        let names: Set<String>
    }

    private struct ConnectionData: Decodable {
        struct User: Decodable {
            let id: String
            let providerDisplayName: String?
            let properties: [String: Property]?
        }

        struct Property: Decodable {
            let value: String?

            private enum CodingKeys: String, CodingKey { case value = "$value" }

            init(from decoder: Decoder) throws {
                // Properties are `{"$type": ..., "$value": ...}`; a few have other shapes.
                self.value = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .value)
            }
        }

        let authenticatedUser: User
    }

    func fetch(since: Date, now: Date, timeZone: TimeZone = .current) async throws -> ProviderActivityResult {
        let identity = try await self.identity()
        let projects = try await self.projects()
        var partial = projects.count > Self.maxProjects
        var opened: [Date] = []
        var reviewed: [Date] = []
        var commits: [Date] = []
        var repositories: [(project: String, id: String)] = []

        for project in projects.prefix(Self.maxProjects) {
            for (role, key) in [("creator", "creatorId"), ("reviewer", "reviewerId")] {
                do {
                    let pulls = try await self.pullRequests(project: project, filter: key, userID: identity.id, since: since)
                    partial = partial || pulls.count >= Self.pullRequestsPerQuery
                    for pull in pulls {
                        guard let date = pull.creationDate, date >= since else { continue }
                        // Reviewer queries include the user's own pull requests.
                        if role == "creator" {
                            opened.append(date)
                        } else if pull.createdBy?.id != identity.id {
                            reviewed.append(date)
                        }
                    }
                } catch where Self.isFatal(error) {
                    throw error
                } catch {
                    partial = true
                }
            }
            do {
                repositories += try await self.repositories(project: project).map { (project, $0) }
            } catch where Self.isFatal(error) {
                throw error
            } catch {
                partial = true
            }
        }

        partial = partial || repositories.count > Self.maxRepositories
        for repository in repositories.prefix(Self.maxRepositories) {
            do {
                let list = try await self.commits(project: repository.project, repository: repository.id, identity: identity, since: since)
                partial = partial || list.count >= Self.commitsPerRepository
                commits += list.compactMap { commit in
                    guard let date = commit.author?.date, date >= since, date <= now, Self.isMine(commit, identity) else { return nil }
                    return date
                }
            } catch where Self.isFatal(error) {
                throw error
            } catch {
                partial = true
            }
        }

        return ProviderActivityResult(
            provider: .azureDevOps,
            days: AzureActivityMapper.days(commits: commits, opened: opened, reviewed: reviewed, timeZone: timeZone),
            partial: partial
        )
    }

    // MARK: - Requests

    private func identity() async throws -> Identity {
        let data = try await self.get("\(self.organization)/_apis/connectionData", [])
        let user = try JSONDecoder().decode(ConnectionData.self, from: data).authenticatedUser
        var names = Set<String>()
        for name in [user.providerDisplayName, user.properties?["Account"]?.value] {
            if let name, !name.isEmpty { names.insert(name.lowercased()) }
        }
        return Identity(id: user.id, names: names)
    }

    private func projects() async throws -> [String] {
        let data = try await self.get(
            "\(self.organization)/_apis/projects", [URLQueryItem(name: "$top", value: String(Self.maxProjects + 1))]
        )
        return try AzureDevOpsRecentDecoders.decodeProjects(from: data).map(\.name)
    }

    private func repositories(project: String) async throws -> [String] {
        let data = try await self.get("\(self.organization)/\(project)/_apis/git/repositories", [])
        return try AzureDevOpsRecentDecoders.decodeRepositories(from: data).filter { $0.isDisabled != true }.map(\.id)
    }

    private func pullRequests(project: String, filter: String, userID: String, since: Date) async throws -> [AzureDevOpsPullRequest] {
        let data = try await self.get("\(self.organization)/\(project)/_apis/git/pullrequests", [
            URLQueryItem(name: "searchCriteria.\(filter)", value: userID),
            URLQueryItem(name: "searchCriteria.status", value: "all"),
            URLQueryItem(name: "searchCriteria.queryTimeRangeType", value: "created"),
            URLQueryItem(name: "searchCriteria.minTime", value: Self.timestamp(since)),
            URLQueryItem(name: "$top", value: String(Self.pullRequestsPerQuery))
        ])
        return try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsPullRequest>.self, from: data).value
    }

    private func commits(project: String, repository: String, identity: Identity, since: Date) async throws -> [AzureDevOpsCommit] {
        var items = [
            URLQueryItem(name: "searchCriteria.fromDate", value: Self.timestamp(since)),
            URLQueryItem(name: "$top", value: String(Self.commitsPerRepository))
        ]
        if let name = identity.names.first { items.append(URLQueryItem(name: "searchCriteria.author", value: name)) }
        let data = try await self.get("\(self.organization)/\(project)/_apis/git/repositories/\(repository)/commits", items)
        return try AzureDevOpsDecoding.decode(AzureDevOpsListResponse<AzureDevOpsCommit>.self, from: data).value
    }

    private func get(_ path: String, _ query: [URLQueryItem]) async throws -> Data {
        var components = URLComponents(url: self.apiHost, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = "/" + path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))) ?? String($0) }
            .joined(separator: "/")
        components?.queryItems = query + [URLQueryItem(name: "api-version", value: "7.0")]
        guard let url = components?.url else { throw URLError(.badURL) }
        return try await self.runner.get(url: url, pat: self.pat).0
    }

    // MARK: - Helpers

    /// Rate limits, outages and a bad PAT fail the whole provider; anything else (a
    /// repository the PAT cannot read, say) only makes the result partial.
    private static func isFatal(_ error: Error) -> Bool {
        guard let error = error as? AzureDevOpsAPIError else { return false }
        switch error {
        case .rateLimited, .serviceUnavailable, .unauthorized, .invalidPAT: return true
        default: return false
        }
    }

    private static func isMine(_ commit: AzureDevOpsCommit, _ identity: Identity) -> Bool {
        [commit.author?.name, commit.author?.email].contains { value in
            value.map { identity.names.contains($0.lowercased()) } ?? false
        }
    }

    private static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
