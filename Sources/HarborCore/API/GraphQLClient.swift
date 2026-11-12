import Foundation

/// Minimal GraphQL helper (no codegen) to enrich repo data. Uses the same OAuth token as REST.
actor GraphQLClient {
    private var endpoint: URL = .init(string: "https://api.github.com/graphql")!
    private var tokenProvider: (@Sendable () async throws -> String)?
    private var rateLimit: RateLimitSnapshot?
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let diag = DiagnosticsLogger.shared
    private let session: URLSession
    /// Set when GitHub said the GraphQL budget is spent (or a secondary limit hit): every
    /// request fails fast until then, so a refresh does not resend its batches into a wall.
    private var blockedUntil: Date?
    private var lastRateLimitMessage: String?

    init(session: URLSession = HarborURLSession.shared) {
        self.session = session
    }

    /// Forgets the last account's limit: a new account must not wait out someone else's.
    func resetAccountScope() {
        self.blockedUntil = nil
        self.lastRateLimitMessage = nil
        self.rateLimit = nil
    }

    /// When the GraphQL limit lifts, or nil when it is not limited.
    func rateLimitReset(now: Date = Date()) -> Date? {
        guard let until = self.blockedUntil, until > now else {
            self.blockedUntil = nil
            self.lastRateLimitMessage = nil
            return nil
        }
        return until
    }

    func rateLimitMessage(now: Date = Date()) -> String? {
        self.rateLimitReset(now: now) == nil ? nil : self.lastRateLimitMessage
    }

    private func failFastIfLimited(now: Date = Date()) throws {
        guard let until = self.rateLimitReset(now: now) else { return }
        throw GitHubAPIError.rateLimited(until: until, message: Self.limitMessage(until: until, now: now))
    }

    private static func limitMessage(until: Date, now: Date) -> String {
        "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: now))."
    }

    /// Reads a response for a rate limit and, when there is one, remembers it and throws.
    /// Called with every GraphQL answer, before its body is parsed.
    private func throwIfLimited(_ http: HTTPURLResponse, data: Data, now: Date = Date()) throws {
        let answer = GraphQLRateLimit.Answer(
            status: http.statusCode,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
            remaining: http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            reset: http.value(forHTTPHeaderField: "X-RateLimit-Reset"),
            body: data
        )
        guard let until = GraphQLRateLimit.resetDate(answer, now: now) else { return }
        self.blockedUntil = until
        let message = Self.limitMessage(until: until, now: now)
        self.lastRateLimitMessage = message
        throw GitHubAPIError.rateLimited(until: until, message: message)
    }

    func setEndpoint(apiHost: URL) {
        // For GitHub.com apiHost is https://api.github.com
        // For GHE apiHost is https://host/api/v3 -> GraphQL lives at /api/graphql
        var components = URLComponents(url: apiHost, resolvingAgainstBaseURL: false)
        if apiHost.path.contains("/api/v3") {
            components?.path = "/api/graphql"
        } else {
            components?.path = "/graphql"
        }
        self.endpoint = components?.url ?? self.endpoint
    }

    func setTokenProvider(_ provider: @Sendable @escaping () async throws -> String) {
        self.tokenProvider = provider
    }

    func repoSummary(owner: String, name: String) async throws -> RepoSummary {
        try self.failFastIfLimited()
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL RepoSummary \(owner)/\(name)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query RepoSummary($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) {
                name
                releases(last: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
                  nodes { name tagName publishedAt url }
                }
                issues(states: OPEN) { totalCount }
                pullRequests(states: OPEN) { totalCount }
              }
            }
            """,
            variables: ["owner": owner, "name": name]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: "RepoSummary", startedAt: startedAt)
        try self.throwIfLimited(http, data: data)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for \(owner)/\(name)")
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(GraphQLResponse<RepoSummaryData>.self, from: data)
        guard let repo = decoded.data.repository else {
            await self.diag.message("GraphQL missing repository for \(owner)/\(name)")
            throw URLError(.cannotParseResponse)
        }

        let release: Release? = repo.releases.nodes?.first.flatMap {
            Release(name: $0.name ?? $0.tagName, tag: $0.tagName, publishedAt: $0.publishedAt, url: $0.url)
        }

        return RepoSummary(
            openIssues: repo.issues.totalCount,
            openPulls: repo.pullRequests.totalCount,
            release: release
        )
    }

    func userContributionHeatmap(login: String) async throws -> [HeatmapCell] {
        try self.failFastIfLimited()
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL UserContributions \(login)")
        let startedAt = Date()

        let body = GraphQLRequest(
            query: """
            query UserContributions($login: String!) {
              user(login: $login) {
                contributionsCollection {
                  contributionCalendar {
                    weeks {
                      contributionDays {
                        date
                        contributionCount
                      }
                    }
                  }
                }
              }
            }
            """,
            variables: ["login": login]
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: "UserContributions", startedAt: startedAt)
        try self.throwIfLimited(http, data: data)
        if let snapshot = RateLimitSnapshot.from(response: http) {
            self.rateLimit = snapshot
        }
        guard http.statusCode == 200 else {
            await self.diag.message("GraphQL status \(http.statusCode) for contributions \(login)")
            throw URLError(.badServerResponse)
        }

        let decoded = try decoder.decode(GraphQLResponse<UserContributionData>.self, from: data)
        guard let weeks = decoded.data.user?.contributionsCollection.contributionCalendar.weeks else {
            await self.diag.message("GraphQL missing contribution weeks for \(login)")
            return []
        }

        return weeks.flatMap { week in
            week.contributionDays.compactMap { day in
                HeatmapCell(date: day.date, count: day.contributionCount)
            }
        }
    }

    /// Totals per year, oldest first. Two requests: the years with activity, then one aliased
    /// query with a `contributionsCollection` window per year.
    func userContributionYears(login: String) async throws -> [ContributionYear] {
        let yearsData = try await self.post(
            query: """
            query ContributionYears($login: String!) {
              user(login: $login) { contributionsCollection { contributionYears } }
            }
            """,
            variables: ["login": login],
            label: "ContributionYears"
        )
        let years = try decoder.decode(GraphQLResponse<ContributionYearsData>.self, from: yearsData)
            .data.user?.contributionsCollection.contributionYears.sorted() ?? []
        guard !years.isEmpty else { return [] }

        let query = Self.contributionYearsQuery(years: years, now: Date())
        let data = try await self.post(query: query, variables: ["login": login], label: "ContributionTotals")
        let windows = try decoder.decode(GraphQLResponse<ContributionWindowsData>.self, from: data).data.user?.windows ?? [:]
        return years.compactMap { year in
            guard let window = windows["y\(year)"] else { return nil }
            let days = (window.contributionCalendar.weeks ?? []).flatMap(\.contributionDays)
                .map { (date: $0.date, count: $0.contributionCount) }
            return ContributionYear(
                year: year,
                total: window.contributionCalendar.totalContributions,
                commits: window.totalCommitContributions,
                pullRequests: window.totalPullRequestContributions,
                issues: window.totalIssueContributions,
                reviews: window.totalPullRequestReviewContributions,
                months: days.isEmpty ? [] : ContributionYear.monthlyTotals(year: year, days: days)
            )
        }
    }

    /// One aliased `contributionsCollection(from:to:)` per year; the current year ends now.
    static func contributionYearsQuery(years: [Int], now: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let currentYear = calendar.component(.year, from: now)
        let fields = years.map { year -> String in
            let end = year >= currentYear ? formatter.string(from: now) : "\(year)-12-31T23:59:59Z"
            return """
              y\(year): contributionsCollection(from: "\(year)-01-01T00:00:00Z", to: "\(end)") {
                contributionCalendar { totalContributions weeks { contributionDays { date contributionCount } } }
                totalCommitContributions
                totalPullRequestContributions
                totalIssueContributions
                totalPullRequestReviewContributions
              }
            """
        }
        return "query ContributionTotals($login: String!) {\n  user(login: $login) {\n"
            + fields.joined(separator: "\n") + "\n  }\n}"
    }

    /// Runs a query or mutation with typed variables. A GraphQL `errors` array (which arrives
    /// with status 200) or a refused request becomes `GitHubAPIError.badStatus` carrying
    /// GitHub's own message. Only the label is logged, never the token or the variables.
    func execute(query: String, variables: [String: GraphQLVariable], label: String) async throws -> Data {
        try self.failFastIfLimited()
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL \(label)")
        let startedAt = Date()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(TypedGraphQLRequest(query: query, variables: variables))
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: label, startedAt: startedAt)
        try self.throwIfLimited(http, data: data)
        if let message = GraphQLFailure.message(in: data) {
            throw GitHubAPIError.badStatus(code: http.statusCode, message: message)
        }
        guard http.statusCode == 200 else {
            throw GitHubAPIError.badStatus(code: http.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return data
    }

    private func post(query: String, variables: [String: String], label: String) async throws -> Data {
        try self.failFastIfLimited()
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL \(label)")
        let startedAt = Date()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: label, startedAt: startedAt)
        if let snapshot = RateLimitSnapshot.from(response: http) { self.rateLimit = snapshot }
        try self.throwIfLimited(http, data: data)
        guard http.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    /// One request for up to `GitHubRepoBatch.maxPerQuery` repositories. GitHub answers partial
    /// failures (a repo that is gone, an alert list that is withheld) with `errors` next to the
    /// data that did load, so only a non-200 or a missing `data` fails the batch.
    func repoBatch(_ repos: [RepoRef]) async throws -> [RepoRef: RepoSnapshot] {
        guard repos.isEmpty == false else { return [:] }
        try self.failFastIfLimited()
        let token = try await tokenProvider?() ?? { throw URLError(.userAuthenticationRequired) }()
        await diag.message("GraphQL RepoBatch x\(repos.count)")
        let startedAt = Date()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            TypedGraphQLRequest(query: GitHubRepoBatch.query(count: repos.count), variables: GitHubRepoBatch.variables(for: repos))
        )
        let (data, response) = try await self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logGraphQLResponse(http, label: "RepoBatch", startedAt: startedAt)
        try self.throwIfLimited(http, data: data)
        guard http.statusCode == 200 else {
            throw GitHubAPIError.badStatus(code: http.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return try GitHubRepoBatch.parse(data, repos: repos)
    }

    func rateLimitSnapshot() -> RateLimitSnapshot? {
        self.rateLimit
    }

    // MARK: - Logging

    private func logGraphQLResponse(_ response: HTTPURLResponse, label: String, startedAt: Date) async {
        await RequestTally.shared.recordGraphQL(label: label)
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot { self.rateLimit = snapshot }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? {
            if let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"), let epoch = TimeInterval(reset) {
                return Date(timeIntervalSince1970: epoch)
            }
            return nil
        }()
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "graphql"

        await self.diag.message(
            "GraphQL \(label) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }
}

struct RepoSummary {
    let openIssues: Int
    let openPulls: Int
    let release: Release?
}

// MARK: - Wire models

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: String]
}

enum GraphQLVariable: Encodable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        }
    }
}

private struct TypedGraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLVariable]
}

private struct GraphQLResponse<T: Decodable>: Decodable {
    let data: T
}

private struct RepoSummaryData: Decodable {
    let repository: RepoSummaryNode?
}

private struct RepoSummaryNode: Decodable {
    let releases: ReleaseConnection
    let issues: CountContainer
    let pullRequests: CountContainer
}

private struct ReleaseConnection: Decodable {
    let nodes: [ReleaseNode]?
}

private struct ReleaseNode: Decodable {
    let name: String?
    let tagName: String
    let publishedAt: Date
    let url: URL
}

private struct CountContainer: Decodable {
    let totalCount: Int
}

private struct UserContributionData: Decodable {
    let user: ContributionUser?
}

private struct ContributionYearsData: Decodable {
    struct User: Decodable {
        struct Collection: Decodable { let contributionYears: [Int] }
        let contributionsCollection: Collection
    }

    let user: User?
}

struct ContributionWindow: Decodable {
    struct Week: Decodable { let contributionDays: [ContributionDay] }
    struct Calendar: Decodable {
        let totalContributions: Int
        let weeks: [Week]?
    }
    let contributionCalendar: Calendar
    let totalCommitContributions: Int
    let totalPullRequestContributions: Int
    let totalIssueContributions: Int
    let totalPullRequestReviewContributions: Int
}

/// `user { y2023: contributionsCollection(...) { ... } y2024: ... }`: the keys are aliases.
private struct ContributionWindowsData: Decodable {
    struct User: Decodable {
        let windows: [String: ContributionWindow]

        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            var windows: [String: ContributionWindow] = [:]
            for key in container.allKeys { windows[key.stringValue] = try container.decode(ContributionWindow.self, forKey: key) }
            self.windows = windows
        }
    }

    let user: User?
}

private struct ContributionUser: Decodable {
    let contributionsCollection: ContributionsCollection
}

private struct ContributionsCollection: Decodable {
    let contributionCalendar: ContributionCalendar
}

private struct ContributionCalendar: Decodable {
    let weeks: [ContributionWeek]
}

private struct ContributionWeek: Decodable {
    let contributionDays: [ContributionDay]
}

struct ContributionDay: Decodable {
    let date: Date
    let contributionCount: Int

    private enum CodingKeys: String, CodingKey {
        case date
        case contributionCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawDate = try container.decode(String.self, forKey: .date)
        guard let parsedDate = Self.parseDate(rawDate) else {
            throw DecodingError.dataCorruptedError(
                forKey: .date,
                in: container,
                debugDescription: "Unsupported date format: \(rawDate)"
            )
        }
        self.date = parsedDate
        self.contributionCount = try container.decode(Int.self, forKey: .contributionCount)
    }

    private static func parseDate(_ raw: String) -> Date? {
        if raw.contains("T") {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: raw) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: raw)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

/// Tells a GraphQL rate limit from every other failure.
///
/// Two shapes: a primary limit is HTTP 200 with `errors[].type == "RATE_LIMITED"` and
/// `data: null`; a secondary limit is a 403 or 429 (with `Retry-After`, no quota left, or a
/// message that names the limit). A plain 403 (a permissions refusal) is not a limit.
enum GraphQLRateLimit {
    /// How long to hold off when GitHub gave no reset time.
    static let defaultWait: TimeInterval = 60

    /// What came back: the status, the three headers that matter, and the body.
    struct Answer {
        let status: Int
        let retryAfter: String?
        let remaining: String?
        let reset: String?
        let body: Data
    }

    static func resetDate(_ answer: Answer, now: Date) -> Date? {
        let (status, retryAfter, remaining, reset) = (answer.status, answer.retryAfter, answer.remaining, answer.reset)
        let parsed = Self.parse(answer.body)
        let limitedInBody = parsed.rateLimited && parsed.dataIsNull
        let limitedByStatus = (status == 403 || status == 429)
            && (status == 429 || retryAfter != nil || remaining.flatMap(Int.init) == 0 || parsed.mentionsLimit)
        guard limitedInBody || limitedByStatus else { return nil }
        if let seconds = retryAfter.flatMap(TimeInterval.init) { return now.addingTimeInterval(max(seconds, 1)) }
        if let epoch = reset.flatMap(TimeInterval.init) {
            let date = Date(timeIntervalSince1970: epoch)
            if date > now { return date }
        }
        return now.addingTimeInterval(self.defaultWait)
    }

    private struct Body {
        var rateLimited = false
        var dataIsNull = false
        var mentionsLimit = false
    }

    private static func parse(_ body: Data) -> Body {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return Body() }
        let errors = object["errors"] as? [[String: Any]] ?? []
        let rateLimited = errors.contains { ($0["type"] as? String) == "RATE_LIMITED" }
        let dataIsNull = object["data"] == nil || object["data"] is NSNull
        let messages = errors.compactMap { $0["message"] as? String } + [object["message"] as? String].compactMap { $0 }
        let mentionsLimit = messages.contains { $0.lowercased().contains("rate limit") }
        return Body(rateLimited: rateLimited, dataIsNull: dataIsNull, mentionsLimit: mentionsLimit)
    }
}
