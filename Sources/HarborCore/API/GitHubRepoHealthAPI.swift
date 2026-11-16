import Foundation

/// The reads behind a repository's health card. Everything here is read-only, in memory,
/// and goes through `authorizedGet`, so the shared rate-limit and backoff handling applies.
/// A 403 or 404 on an admin-only endpoint means "not visible" (nil), never an error. Any
/// other failure (offline, a 5xx, a body that does not decode) is "couldn't load": it is
/// thrown, so the section reports it instead of showing a value it never read.
extension GitHubRestAPI {
    // MARK: Plumbing

    private func repoURL(_ owner: String, _ name: String, _ path: String, query: [URLQueryItem] = []) async throws -> URL {
        let base = await self.apiHost()
        guard var components = URLComponents(
            url: base.appending(path: path.isEmpty ? "/repos/\(owner)/\(name)" : "/repos/\(owner)/\(name)/\(path)"),
            resolvingAgainstBaseURL: false
        ) else { throw URLError(.badURL) }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw URLError(.badURL) }
        return url
    }

    /// The body on 200, or the 403/404 that says "not visible" / "not there".
    private func probe(_ url: URL) async throws -> (status: Int, data: Data?) {
        let token = try await self.tokenProvider()
        do {
            let (data, _) = try await self.authorizedGet(url: url, token: token)
            return (200, data)
        } catch let GitHubAPIError.badStatus(code, _) where code == 403 || code == 404 {
            return (code, nil)
        }
    }

    /// Runs one lookup. A 403 or 404 means the token can't see it ("needs admin"): nil. Every
    /// other failure, a cancellation and a rate limit included, is thrown.
    private func soft<T>(_ lookup: () async throws -> T?) async throws -> T? {
        do {
            return try await lookup()
        } catch let GitHubAPIError.badStatus(code, _) where code == 403 || code == 404 {
            await self.diag.message("health lookup not visible (\(code))")
            return nil
        }
    }

    private func json<T: Decodable>(_: T.Type, _ data: Data) throws -> T {
        try GitHubDecoding.decode(T.self, from: data)
    }

    // MARK: Basics

    func healthBasics(owner: String, name: String) async throws -> RepoHealthBasics {
        let url = try await self.repoURL(owner, name, "")
        let (data, _) = try await self.authorizedGet(url: url, token: self.tokenProvider())
        let repo = try self.json(HealthRepoResponse.self, data)
        return RepoHealthBasics(defaultBranch: repo.defaultBranch, isAdmin: repo.permissions?.admin)
    }

    // MARK: Security

    /// `isAdmin` (from `healthBasics`) lets a 403 on code scanning mean what it means for an
    /// admin: the feature is not turned on, not "needs admin".
    func healthSecurity(owner: String, name: String, isAdmin: Bool? = nil) async throws -> RepoSecuritySection {
        async let dependabot = self.soft { try await self.dependabotFindings(owner: owner, name: name) }
        async let secrets = self.soft { try await self.openAlertCount(owner: owner, name: name, kind: "secret-scanning") }
        async let code = self.soft { try await self.codeScanningAlerts(owner: owner, name: name, isAdmin: isAdmin) }
        async let policy = self.soft { try await self.hasSecurityPolicy(owner: owner, name: name) }
        async let reporting = self.soft { try await self.privateReporting(owner: owner, name: name) }
        let findings = try await dependabot
        let aggregated = findings.map { DependabotAggregation.aggregate($0) }
        let codeScanning = try await code
        return try await RepoSecuritySection(
            alerts: RepoSecurity(dependabot: aggregated?.tally, secretLeaks: secrets, codeScanning: codeScanning?.count),
            topAlerts: aggregated?.worst ?? [],
            hasSecurityPolicy: policy,
            privateReporting: reporting,
            codeScanning: codeScanning?.availability
        )
    }

    /// The open code-scanning count, or why there is none: 404 means it was never set up, and
    /// so does a 403 for an admin (who could see the alerts if the feature were on).
    private func codeScanningAlerts(
        owner: String, name: String, isAdmin: Bool?
    ) async throws -> (count: Int?, availability: AlertAvailability) {
        switch try await self.alertPagesResult(owner: owner, name: name, kind: "code-scanning") {
        case let .pages(pages):
            return try (pages.reduce(0) { try $0 + self.json([AlertStub].self, $1).count }, .visible)
        case let .withheld(status):
            return (nil, status == 403 && isAdmin == true ? .notEnabled : AlertAvailability(withheldStatus: status))
        }
    }

    private func dependabotFindings(owner: String, name: String) async throws -> [DependabotFinding]? {
        guard let pages = try await self.openAlertPages(owner: owner, name: name, kind: "dependabot") else { return nil }
        return try pages.flatMap { try self.json([DependabotAlert].self, $0) }.map {
            DependabotFinding(
                package: $0.securityVulnerability.package?.name ?? "unknown package",
                severity: $0.securityVulnerability.severity,
                patchedVersion: $0.securityVulnerability.firstPatchedVersion?.identifier
            )
        }
    }

    /// SECURITY.md in the places GitHub looks. All 404 means there isn't one.
    private func hasSecurityPolicy(owner: String, name: String) async throws -> Bool? {
        var sawForbidden = false
        for path in ["SECURITY.md", ".github/SECURITY.md", "docs/SECURITY.md"] {
            let result = try await self.probe(self.repoURL(owner, name, "contents/\(path)"))
            if result.status == 200 { return true }
            if result.status == 403 { sawForbidden = true }
        }
        return sawForbidden ? nil : false
    }

    private func privateReporting(owner: String, name: String) async throws -> Bool? {
        let result = try await self.probe(self.repoURL(owner, name, "private-vulnerability-reporting"))
        guard let data = result.data else { return nil }
        return try self.json(EnabledResponse.self, data).enabled
    }

    // MARK: Hardening

    func healthHardening(owner: String, name: String, basics: RepoHealthBasics) async throws -> HardeningChecklist {
        async let rules = self.soft { try await self.ruleTypes(owner: owner, name: name, branch: basics.defaultBranch) }
        async let classic = self.classicProtection(owner: owner, name: name, basics: basics)
        async let unpinned = self.soft { try await self.unpinnedActionCount(owner: owner, name: name) }
        async let workflowRead = self.soft { try await self.workflowDefaultsToRead(owner: owner, name: name) }
        async let updates = self.soft { try await self.dependabotUpdatesEnabled(owner: owner, name: name) }
        let evaluated = try await BranchProtectionEvaluator.evaluate(ruleTypes: rules, classic: classic)
        return try await HardeningChecklist(
            branch: evaluated.branch,
            signedCommits: evaluated.signedCommits,
            unpinnedActions: unpinned,
            workflowDefaultsToRead: workflowRead,
            dependabotUpdates: updates
        )
    }

    private func ruleTypes(owner: String, name: String, branch: String) async throws -> Set<String>? {
        let url = try await self.repoURL(owner, name, "rules/branches/\(branch)")
        guard let data = try await self.probe(url).data else { return nil }
        return Set(try self.json([RuleResponse].self, data).map(\.type))
    }

    private func classicProtection(owner: String, name: String, basics: RepoHealthBasics) async throws -> ClassicProtectionLookup {
        let result = try await self.soft { () -> (status: Int, data: Data?)? in
            try await self.probe(self.repoURL(owner, name, "branches/\(basics.defaultBranch)/protection"))
        }
        guard let result else { return .unknown }
        if let data = result.data, let body = try? self.json(ProtectionResponse.self, data) {
            return .present(
                requiresPullRequest: body.requiredPullRequestReviews != nil,
                requiresStatusChecks: body.requiredStatusChecks != nil,
                blocksForcePush: body.allowForcePushes?.enabled == false,
                requiresSignatures: body.requiredSignatures?.enabled == true
            )
        }
        // An admin token gets 404 for "no protection". Anyone else can't tell.
        return result.status == 404 && basics.isAdmin == true ? .absent : .unknown
    }

    private func dependabotUpdatesEnabled(owner: String, name: String) async throws -> Bool? {
        let result = try await self.probe(self.repoURL(owner, name, "automated-security-fixes"))
        guard let data = result.data else { return nil }
        return try self.json(EnabledResponse.self, data).enabled
    }

    private func workflowDefaultsToRead(owner: String, name: String) async throws -> Bool? {
        let result = try await self.probe(self.repoURL(owner, name, "actions/permissions/workflow"))
        guard let data = result.data else { return nil }
        return try self.json(WorkflowPermissionsResponse.self, data).defaultWorkflowPermissions == "read"
    }

    /// Reads `.github/workflows/*.yml` through the contents API, a few at a time.
    private func unpinnedActionCount(owner: String, name: String) async throws -> Int? {
        let listing = try await self.probe(self.repoURL(owner, name, "contents/.github/workflows"))
        if listing.status == 404 { return 0 }
        guard let data = listing.data else { return nil }
        let files = try self.json([ContentEntry].self, data)
            .filter { $0.type == "file" && ($0.name.hasSuffix(".yml") || $0.name.hasSuffix(".yaml")) }
        var total: Int? = 0
        var index = 0
        try await withThrowingTaskGroup(of: Int?.self) { group in
            func launch() {
                guard index < files.count else { return }
                let file = files[index]
                index += 1
                group.addTask { try await self.unpinnedCount(owner: owner, name: name, path: file.path) }
            }
            for _ in 0 ..< Self.healthConcurrency { launch() }
            while let count = try await group.next() {
                // One workflow file that could not be read means the total is unknown, not lower.
                if let count, let sum = total { total = sum + count } else { total = nil }
                launch()
            }
        }
        return total
    }

    private func unpinnedCount(owner: String, name: String, path: String) async throws -> Int? {
        let result = try await self.probe(self.repoURL(owner, name, "contents/\(path)"))
        guard let data = result.data, let file = try? self.json(ContentFile.self, data),
              let text = file.decodedText else { return nil }
        return ActionPinChecker.unpinnedUses(in: text).count
    }

    static let healthConcurrency = 3

    // MARK: Flow

    func healthFlow(owner: String, name: String, basics: RepoHealthBasics, release: Release?) async throws -> RepoFlowSection {
        // Pull requests and runs are readable by anyone who can see the repo: a failed read
        // fails the section. It must never become an empty list that scores as healthy.
        async let pulls = self.flowPulls(owner: owner, name: name)
        async let runs = self.flowRuns(owner: owner, name: name)
        async let since = self.soft { try await self.commitsSince(owner: owner, name: name, release: release, branch: basics.defaultBranch) }
        return try await RepoFlowSection(
            pulls: pulls,
            runs: runs,
            release: release,
            commitsSinceRelease: since
        )
    }

    private func flowPulls(owner: String, name: String) async throws -> [FlowPullRequest] {
        let url = try await self.repoURL(owner, name, "pulls", query: [
            URLQueryItem(name: "state", value: "open"),
            URLQueryItem(name: "sort", value: "updated"),
            URLQueryItem(name: "direction", value: "desc"),
            URLQueryItem(name: "per_page", value: "5")
        ])
        let (data, _) = try await self.authorizedGet(url: url, token: self.tokenProvider())
        let pulls = try self.json([HealthPullResponse].self, data)
        var states: [Int: PullReviewState] = [:]
        try await withThrowingTaskGroup(of: (Int, PullReviewState).self) { group in
            for pull in pulls {
                group.addTask {
                    let reviews = try await self.soft { try await self.reviews(owner: owner, name: name, number: pull.number) } ?? []
                    let state = PullReviewState.derive(
                        isDraft: pull.draft ?? false,
                        reviews: reviews,
                        hasRequestedReviewers: !(pull.requestedReviewers ?? []).isEmpty || !(pull.requestedTeams ?? []).isEmpty
                    )
                    return (pull.number, state)
                }
            }
            while let (number, state) = try await group.next() { states[number] = state }
        }
        return pulls.map {
            FlowPullRequest(number: $0.number, title: $0.title, createdAt: $0.createdAt, review: states[$0.number] ?? .noReviews)
        }
    }

    private func reviews(owner: String, name: String, number: Int) async throws -> [(user: String, state: String)]? {
        let url = try await self.repoURL(owner, name, "pulls/\(number)/reviews", query: [URLQueryItem(name: "per_page", value: "100")])
        guard let data = try await self.probe(url).data else { return nil }
        return try self.json([ReviewResponse].self, data).map { ($0.user?.login ?? "?", $0.state) }
    }

    private func flowRuns(owner: String, name: String) async throws -> [FlowRun] {
        let url = try await self.repoURL(owner, name, "actions/runs", query: [URLQueryItem(name: "per_page", value: "5")])
        let (data, _) = try await self.authorizedGet(url: url, token: self.tokenProvider())
        return try self.json(HealthRunsResponse.self, data).workflowRuns.map { run in
            let finished = run.status == "completed"
            let duration = finished ? run.runStartedAt.map { max(0, run.updatedAt.timeIntervalSince($0)) } : nil
            return FlowRun(status: GitHubStatusMapper.ciStatus(fromStatus: run.status, conclusion: run.conclusion), duration: duration)
        }
    }

    private func commitsSince(owner: String, name: String, release: Release?, branch: String) async throws -> Int? {
        guard let release else { return nil }
        let url = try await self.repoURL(owner, name, "compare/\(release.tag)...\(branch)", query: [URLQueryItem(name: "per_page", value: "1")])
        guard let data = try await self.probe(url).data else { return nil }
        return try self.json(CompareResponse.self, data).aheadBy
    }
}

// MARK: - Wire types

private struct HealthRepoResponse: Decodable {
    struct Permissions: Decodable { let admin: Bool? }
    let defaultBranch: String
    let permissions: Permissions?

    enum CodingKeys: String, CodingKey {
        case defaultBranch = "default_branch"
        case permissions
    }
}

private struct EnabledResponse: Decodable { let enabled: Bool }

private struct RuleResponse: Decodable { let type: String }

private struct ProtectionResponse: Decodable {
    struct Present: Decodable {}
    struct Toggle: Decodable { let enabled: Bool }
    let requiredPullRequestReviews: Present?
    let requiredStatusChecks: Present?
    let allowForcePushes: Toggle?
    let requiredSignatures: Toggle?

    enum CodingKeys: String, CodingKey {
        case requiredPullRequestReviews = "required_pull_request_reviews"
        case requiredStatusChecks = "required_status_checks"
        case allowForcePushes = "allow_force_pushes"
        case requiredSignatures = "required_signatures"
    }
}

private struct WorkflowPermissionsResponse: Decodable {
    let defaultWorkflowPermissions: String

    enum CodingKeys: String, CodingKey { case defaultWorkflowPermissions = "default_workflow_permissions" }
}

private struct ContentEntry: Decodable {
    let name: String
    let path: String
    let type: String
}

private struct ContentFile: Decodable {
    let content: String?
    let encoding: String?

    var decodedText: String? {
        guard encoding == "base64", let content,
              let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct HealthPullResponse: Decodable {
    struct Reviewer: Decodable { let login: String }
    struct Team: Decodable { let slug: String }
    let number: Int
    let title: String
    let createdAt: Date
    let draft: Bool?
    let requestedReviewers: [Reviewer]?
    let requestedTeams: [Team]?

    enum CodingKeys: String, CodingKey {
        case number, title, draft
        case createdAt = "created_at"
        case requestedReviewers = "requested_reviewers"
        case requestedTeams = "requested_teams"
    }
}

private struct ReviewResponse: Decodable {
    struct User: Decodable { let login: String }
    let state: String
    let user: User?
}

private struct HealthRunsResponse: Decodable {
    struct Run: Decodable {
        let status: String?
        let conclusion: String?
        let runStartedAt: Date?
        let updatedAt: Date

        enum CodingKeys: String, CodingKey {
            case status, conclusion
            case runStartedAt = "run_started_at"
            case updatedAt = "updated_at"
        }
    }

    let workflowRuns: [Run]

    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
}

private struct CompareResponse: Decodable {
    let aheadBy: Int

    enum CodingKeys: String, CodingKey { case aheadBy = "ahead_by" }
}
