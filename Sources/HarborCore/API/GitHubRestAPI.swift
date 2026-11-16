import Foundation

struct ActivitySnapshot: Sendable {
    let events: [ActivityEvent]
    let latest: ActivityEvent?
}

struct GitHubRestAPI: Sendable {
    let apiHost: @Sendable () async -> URL
    let tokenProvider: @Sendable () async throws -> String
    let requestRunner: GitHubRequestRunner
    let diag: DiagnosticsLogger

    func userReposSorted(limit: Int) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(url: baseURL.appending(path: "/user/repos"), resolvingAgainstBaseURL: false) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "per_page", value: "\(limit)"),
            URLQueryItem(name: "sort", value: "pushed"),
            URLQueryItem(name: "direction", value: "desc")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode([RepoItem].self, from: data)
    }

    /// Pulls paginated `/user/repos` in 100-item pages until the limit is reached or GitHub runs out.
    func userReposPaginated(limit: Int?) async throws -> [RepoItem] {
        try await self.fetchAllPages(
            path: "/user/repos",
            queryItems: [
                URLQueryItem(name: "sort", value: "pushed"),
                URLQueryItem(name: "direction", value: "desc"),
                // Everything the user works in: their own, ones they collaborate on, and every
                // organisation's they belong to (not only the orgs they administer).
                URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member")
            ],
            limit: limit,
            decode: { try GitHubDecoding.decode([RepoItem].self, from: $0) }
        )
    }

    /// The listing plus every pinned repo it lacks. A pinned repo can sit outside the listing
    /// (not a member, or past the limit), so each missing one is fetched by name, side by side.
    /// A pinned repo that cannot be read is left out and noted in the diagnostics log.
    func userReposIncludingPinned(limit: Int?, pinned: [String]) async throws -> [RepoItem] {
        let listed = try await self.userReposPaginated(limit: limit)
        var have = Set(listed.map { $0.fullName.lowercased() })
        var wanted: [(owner: String, name: String)] = []
        for full in pinned {
            let parts = full.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { continue }
            guard have.insert(full.lowercased()).inserted else { continue }
            wanted.append((parts[0], parts[1]))
        }
        guard !wanted.isEmpty else { return listed }
        let fetched: [Int: RepoItem] = await withTaskGroup(of: (Int, RepoItem?).self) { group in
            for (index, target) in wanted.enumerated() {
                group.addTask {
                    do {
                        return try await (index, self.repoDetails(owner: target.owner, name: target.name))
                    } catch {
                        await self.diag.message("Pinned repo \(target.owner)/\(target.name) could not be loaded: \(error.localizedDescription)")
                        return (index, nil)
                    }
                }
            }
            var found: [Int: RepoItem] = [:]
            for await (index, item) in group { if let item { found[index] = item } }
            return found
        }
        // A pin kept under an old name comes back under the repo's current one (GitHub follows
        // the rename), which the listing may already hold: dedupe on the name that came back.
        var present = Set(listed.map { $0.fullName.lowercased() })
        let extra = fetched.sorted { $0.key < $1.key }.map(\.value).filter { present.insert($0.fullName.lowercased()).inserted }
        return listed + extra
    }

    func fetchCurrentUser() async throws -> CurrentUser {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/user")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode(CurrentUser.self, from: data)
    }

    func searchRepositories(matching query: String) async throws -> [RepoItem] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/search/repositories"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "per_page", value: "5")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        let decoded = try GitHubDecoding.decode(SearchResponse.self, from: data)
        return decoded.items
    }

    func userEvents(username: String, scope: GlobalActivityScope) async throws -> [RepoEvent] {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        let path = scope == .allActivity
            ? "/users/\(username)/received_events"
            : "/users/\(username)/events"
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode([RepoEvent].self, from: data)
    }

    func repoDetails(owner: String, name: String) async throws -> RepoItem {
        let token = try await tokenProvider()
        let baseURL = await self.apiHost()
        let url = baseURL.appending(path: "/repos/\(owner)/\(name)")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode(RepoItem.self, from: data)
    }

    private struct DefaultBranchResponse: Decodable {
        let defaultBranch: String?

        enum CodingKeys: String, CodingKey { case defaultBranch = "default_branch" }
    }

    /// The repo's own default branch (`trunk`, `master`, ...), never an assumed `main`.
    func defaultBranch(owner: String, name: String) async throws -> String? {
        let token = try await tokenProvider()
        let url = await self.apiHost().appending(path: "/repos/\(owner)/\(name)")
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try GitHubDecoding.decode(DefaultBranchResponse.self, from: data).defaultBranch
    }

    /// The newest run on the default branch. Only a fallback for a repo whose check rollup says
    /// nothing; the batch's rollup is what the row shows when it has one.
    func ciStatus(owner: String, name: String) async throws -> CIStatusDetails {
        let branch = try await self.defaultBranch(owner: owner, name: name)
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/actions/runs"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
            + (branch.map { [URLQueryItem(name: "branch", value: $0)] } ?? [])
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        let runs = try GitHubDecoding.decode(ActionsRunsResponse.self, from: data)
        guard let run = runs.workflowRuns.first else { return CIStatusDetails(status: .unknown, runCount: runs.totalCount) }
        let status = GitHubStatusMapper.ciStatus(fromStatus: run.status, conclusion: run.conclusion)
        return CIStatusDetails(status: status, runCount: runs.totalCount)
    }

    func recentActivity(owner: String, name: String, limit: Int) async throws -> ActivitySnapshot {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/events"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "30")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        let events = try GitHubDecoding.decode([RepoEvent].self, from: data)
        let mapped = events.map { event in
            (event: event, activity: event.activityEvent(owner: owner, name: name))
        }
        let limited = Array(mapped.prefix(max(limit, 0)))
        let preferred = limited.first(where: { $0.event.hasRichPayload })?.activity
        return ActivitySnapshot(
            events: limited.map(\.activity),
            latest: preferred ?? limited.first?.activity
        )
    }

    func trafficStats(owner: String, name: String) async throws -> TrafficStats? {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let viewsURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/views")
            let clonesURL = baseURL.appending(path: "/repos/\(owner)/\(name)/traffic/clones")
            async let viewsPair = self.authorizedGet(url: viewsURL, token: token)
            async let clonesPair = self.authorizedGet(url: clonesURL, token: token)
            let views = try await GitHubDecoding.decode(TrafficResponse.self, from: viewsPair.0)
            let clones = try await GitHubDecoding.decode(TrafficResponse.self, from: clonesPair.0)
            let now = Date()
            return TrafficStats(
                uniqueVisitors: views.uniques, uniqueCloners: clones.uniques,
                views: views.count, clones: clones.count,
                viewsByDay: TrafficStats.dailySeries(views.points, endingOn: now),
                clonesByDay: TrafficStats.dailySeries(clones.points, endingOn: now)
            )
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Traffic endpoints forbidden for \(owner)/\(name); skipping")
                return nil
            }
            throw error
        }
    }

    func securitySummary(owner: String, name: String) async throws -> RepoSecurity {
        async let dependabot = self.openDependabotTally(owner: owner, name: name)
        async let secrets = self.openAlertCount(owner: owner, name: name, kind: "secret-scanning")
        async let code = self.openAlertCount(owner: owner, name: name, kind: "code-scanning")
        return try await RepoSecurity(dependabot: dependabot, secretLeaks: secrets, codeScanning: code)
    }

    private func openDependabotTally(owner: String, name: String) async throws -> DependabotTally? {
        guard let pages = try await self.openAlertPages(owner: owner, name: name, kind: "dependabot") else { return nil }
        let severities = try pages.flatMap { try GitHubDecoding.decode([DependabotAlert].self, from: $0) }
            .map(\.securityVulnerability.severity)
        func count(_ severity: String) -> Int { severities.count(where: { $0 == severity }) }
        return DependabotTally(critical: count("critical"), high: count("high"), medium: count("medium"), low: count("low"))
    }

    func openAlertCount(owner: String, name: String, kind: String) async throws -> Int? {
        guard let pages = try await self.openAlertPages(owner: owner, name: name, kind: kind) else { return nil }
        return try pages.reduce(0) { try $0 + GitHubDecoding.decode([AlertStub].self, from: $1).count }
    }

    /// Every page of a repository's open alerts, or `nil` when GitHub withholds them:
    /// 403 without admin access or with the feature off, 404 when it was never set up.
    func openAlertPages(owner: String, name: String, kind: String) async throws -> [Data]? {
        if case let .pages(pages) = try await self.alertPagesResult(owner: owner, name: name, kind: kind) { return pages }
        return nil
    }

    enum AlertPagesResult {
        case pages([Data])
        /// GitHub refused: 403 (no access, or the feature is off) or 404 (never set up).
        case withheld(status: Int)
    }

    func alertPagesResult(owner: String, name: String, kind: String) async throws -> AlertPagesResult {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/\(kind)/alerts"),
            resolvingAgainstBaseURL: false
        ) else { throw URLError(.badURL) }
        // Only `per_page` here: Dependabot rejects a `page` parameter, so later pages
        // come from the `next` link GitHub returns.
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: String(Self.alertsPerPage))
        ]
        var next = components.url
        var pages: [Data] = []
        do {
            while let url = next, pages.count < Self.maxAlertPages {
                let (data, response) = try await self.authorizedGet(url: url, token: token)
                pages.append(data)
                next = GitHubPagination.nextURL(from: response.value(forHTTPHeaderField: "Link") ?? "")
            }
            return .pages(pages)
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 || code == 404 {
                await self.diag.message("\(kind) alerts unavailable for \(owner)/\(name) (\(code))")
                return .withheld(status: code)
            }
            throw error
        }
    }

    private static let alertsPerPage = 100
    private static let maxAlertPages = 20

    func commitHeatmap(owner: String, name: String) async throws -> [HeatmapCell] {
        do {
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            let (data, _) = try await authorizedGet(
                url: baseURL.appending(path: "/repos/\(owner)/\(name)/stats/commit_activity"),
                token: token
            )
            let weeks = try GitHubDecoding.decode([CommitActivityWeek].self, from: data)
            return weeks.flatMap { week in
                zip(0 ..< 7, week.days).map { offset, count in
                    let date = Date(timeIntervalSince1970: TimeInterval(week.weekStart + offset * 86400))
                    return HeatmapCell(date: date, count: count)
                }
            }
        } catch let error as GitHubAPIError {
            if case let .badStatus(code, _) = error, code == 403 {
                await self.diag.message("Commit activity forbidden for \(owner)/\(name); skipping heatmap")
                return []
            }
            throw error
        }
    }

    func openPullRequestCount(owner: String, name: String) async throws -> Int {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/pulls"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "per_page", value: "1"),
            URLQueryItem(name: "page", value: "1")
        ]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await authorizedGet(url: url, token: token)
        let pulls = try GitHubDecoding.decode([PullRequestListItem].self, from: data)

        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }

        return pulls.count
    }

    func commitTotalCount(owner: String, name: String) async throws -> Int? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "1")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await authorizedGet(url: url, token: token)
        if let link = response.value(forHTTPHeaderField: "Link"), let last = GitHubPagination.lastPage(from: link) {
            return last
        }
        let items = try GitHubDecoding.decode([CommitRecentResponse].self, from: data)
        return items.count
    }

    func recentPullRequests(owner: String, name: String, limit: Int = 20) async throws -> [RepoPullRequestSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "pulls",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentPullRequests(from:)
        )
    }

    func recentIssues(owner: String, name: String, limit: Int = 20) async throws -> [RepoIssueSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "issues",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "state", value: "open"),
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentIssues(from:)
        )
    }

    func recentReleases(owner: String, name: String, limit: Int = 20) async throws -> [RepoReleaseSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "releases",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentReleases(from:)
        )
    }

    func recentWorkflowRuns(owner: String, name: String, limit: Int = 20) async throws -> [RepoWorkflowRunSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "actions/runs",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentWorkflowRuns(from:)
        )
    }

    func recentCommits(owner: String, name: String, limit: Int = 20) async throws -> RepoCommitList {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/commits"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "\(limit)")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        let items = try GitHubRecentDecoders.decodeRecentCommits(from: data)
        let totalCount = try await self.commitTotalCount(owner: owner, name: name)
        return RepoCommitList(items: items, totalCount: totalCount)
    }

    func recentDiscussions(owner: String, name: String, limit: Int = 20) async throws -> [RepoDiscussionSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "discussions",
            limit: limit,
            queryItems: [
                URLQueryItem(name: "sort", value: "updated"),
                URLQueryItem(name: "direction", value: "desc")
            ],
            decode: GitHubRecentDecoders.decodeRecentDiscussions(from:)
        )
    }

    func recentTags(owner: String, name: String, limit: Int = 20) async throws -> [RepoTagSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "tags",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentTags(from:)
        )
    }

    func recentBranches(owner: String, name: String, limit: Int = 20) async throws -> [RepoBranchSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "branches",
            limit: limit,
            decode: GitHubRecentDecoders.decodeRecentBranches(from:)
        )
    }

    func topContributors(owner: String, name: String, limit: Int = 20) async throws -> [RepoContributorSummary] {
        try await self.recentList(
            owner: owner,
            name: name,
            path: "contributors",
            limit: limit,
            decode: GitHubRecentDecoders.decodeContributors(from:)
        )
    }

    /// Most recent release (including prereleases) ordered by creation date; skips drafts.
    /// Returns `nil` if the repository has no releases.
    func latestReleaseAny(owner: String, name: String) async throws -> Release? {
        let token = try await tokenProvider()
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/releases"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "per_page", value: "20")]
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, response) = try await authorizedGet(url: url, token: token, allowedStatuses: [200, 404])
        guard response.statusCode != 404 else { throw URLError(.fileDoesNotExist) }
        let releases = try GitHubDecoding.decode([ReleaseResponse].self, from: data)
        return GitHubReleasePicker.latestRelease(from: releases)
    }

    private func recentList<T>(
        owner: String,
        name: String,
        path: String,
        limit: Int,
        queryItems: [URLQueryItem] = [],
        decode: (Data) throws -> [T]
    ) async throws -> [T] {
        let token = try await tokenProvider()
        let limit = max(1, min(limit, 100))
        let baseURL = await apiHost()
        guard var components = URLComponents(
            url: baseURL.appending(path: "/repos/\(owner)/\(name)/\(path)"),
            resolvingAgainstBaseURL: false
        ) else {
            throw URLError(.badURL)
        }
        var items = queryItems.filter { $0.name != "per_page" }
        items.append(URLQueryItem(name: "per_page", value: "\(limit)"))
        components.queryItems = items
        guard let url = components.url else { throw URLError(.badURL) }
        let (data, _) = try await authorizedGet(url: url, token: token)
        return try decode(data)
    }

    private func fetchAllPages<T>(
        path: String,
        queryItems: [URLQueryItem],
        limit: Int?,
        decode: @escaping (Data) throws -> [T]
    ) async throws -> [T] {
        let pageSize = 100 // GitHub maximum.
        var collected: [T] = []
        var page = 1

        while true {
            // Each page is a separate request; stop early if GitHub returns a short page.
            let token = try await tokenProvider()
            let baseURL = await apiHost()
            guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else {
                throw URLError(.badURL)
            }
            var items = queryItems.filter { $0.name != "per_page" && $0.name != "page" }
            items.append(URLQueryItem(name: "per_page", value: "\(pageSize)"))
            items.append(URLQueryItem(name: "page", value: "\(page)"))
            components.queryItems = items
            guard let url = components.url else { throw URLError(.badURL) }
            let (data, _) = try await authorizedGet(url: url, token: token)
            let itemsPage = try decode(data)
            collected.append(contentsOf: itemsPage)

            if let limit, collected.count >= limit {
                break
            }
            if itemsPage.count < pageSize {
                break // GitHub returned a short page.
            }
            page += 1
        }

        if let limit {
            return Array(collected.prefix(limit))
        }
        return collected
    }

    func authorizedGet(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200]
    ) async throws -> (Data, HTTPURLResponse) {
        try await self.requestRunner.get(url: url, token: token, allowedStatuses: allowedStatuses)
    }
}

private struct CommitRecentResponse: Decodable {
    let sha: String
}

private struct InstallationReposResponse: Decodable {
    let totalCount: Int
    let repositories: [RepoItem]

    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case repositories
    }
}
