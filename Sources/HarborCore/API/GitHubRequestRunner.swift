import CryptoKit
import Foundation

actor GitHubRequestRunner {
    private let backoff: BackoffTracker
    private let diag: DiagnosticsLogger
    private var lastRateLimitReset: Date?
    /// Set when GitHub answered 403/429 with no quota left: every request fails fast until then.
    private var blockedUntil: Date?
    private let coalescer = InflightCoalescer<String, Reply>()
    private var lastRateLimitError: String?
    private var latestRestRateLimit: RateLimitSnapshot?
    /// The session reads go through. Tests hand in one with a stub protocol.
    private let readSession: URLSession

    /// Reply handed to every caller that joined the same in-flight request.
    struct Reply: Sendable {
        let data: Data
        let response: HTTPURLResponse
    }

    /// URLSession for GitHub API requests: no URLCache, never reads local cache data.
    private static let session: URLSession = {
        let config = HarborURLSession.configuration()
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        // Header defaults for GitHub API
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "Harbor/1.0"
        ]
        return URLSession(configuration: config)
    }()

    init(
        backoff: BackoffTracker = BackoffTracker(),
        diag: DiagnosticsLogger = .shared,
        session: URLSession? = nil
    ) {
        self.backoff = backoff
        self.diag = diag
        self.readSession = session ?? Self.session
    }

    /// Forgets the last account's limit: a new account must not wait out someone else's. That
    /// includes the per-URL cooldowns, which are keyed by URL alone and would otherwise answer
    /// "Cooling down" for the exact URL the old account was limited on.
    func resetAccountScope() async {
        await self.backoff.clear()
        self.blockedUntil = nil
        self.lastRateLimitReset = nil
        self.lastRateLimitError = nil
        self.latestRestRateLimit = nil
    }

    func rateLimitReset(now: Date = Date()) -> Date? {
        guard let reset = self.lastRateLimitReset, reset > now else {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
            return nil
        }
        return reset
    }

    func rateLimitMessage(now: Date = Date()) -> String? {
        guard self.rateLimitReset(now: now) != nil else { return nil }
        return self.lastRateLimitError
    }

    /// GET. Identical requests in flight at the same moment share one network call.
    func get(
        url: URL,
        token: String,
        allowedStatuses: Set<Int> = [200]
    ) async throws -> (Data, HTTPURLResponse) {
        let key = Self.coalescingKey(url: url, allowedStatuses: allowedStatuses, token: token)
        let reply = try await self.coalescer.run(key: key) { [self] in
            let (data, response) = try await self.fetch(url: url, token: token, allowedStatuses: allowedStatuses)
            return Reply(data: data, response: response)
        }
        return (reply.data, reply.response)
    }

    /// Two GETs are the same request when the URL, the accepted statuses and the account match.
    /// The account is the token, reduced to a hash: two accounts asking for `/user/repos` at
    /// the same moment must never share one answer.
    static func coalescingKey(url: URL, allowedStatuses: Set<Int>, token: String) -> String {
        "\(allowedStatuses.sorted().map(String.init).joined(separator: ",")) \(self.accountFingerprint(token)) \(url.absoluteString)"
    }

    /// Eight hex digits of the token's SHA-256: enough to tell two accounts apart, and the
    /// token itself is never kept in a key.
    static func accountFingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private func blockedUntil(now: Date = Date()) -> Date? {
        guard let until = self.blockedUntil else { return nil }
        if until <= now {
            self.blockedUntil = nil
            return nil
        }
        return until
    }

    private func fetch(
        url: URL,
        token: String,
        allowedStatuses: Set<Int>
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()
        await self.diag.message("GET \(url.absoluteString)")
        await RequestTally.shared.recordREST(path: url.path)
        if let until = self.blockedUntil() {
            await self.diag.message("Blocked by local rateLimit until \(until)")
            throw GitHubAPIError.rateLimited(
                until: until,
                message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date()))."
            )
        }
        if let cooldown = await backoff.cooldown(for: url) {
            await self.diag.message("Cooldown active for \(url.absoluteString) until \(cooldown)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: cooldown,
                message: "Cooling down until \(RelativeFormatter.string(from: cooldown, relativeTo: Date()))."
            )
        }

        var request = URLRequest(url: url)
        // GitHub requires "Bearer" for OAuth access tokens; "token" is for classic tokens.
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, responseAny) = try await self.readSession.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logResponse("GET", url: url, response: response, startedAt: startedAt)

        let status = response.statusCode
        if status == 202 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(90)
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            let retryText = RelativeFormatter.string(from: retryAfter, relativeTo: Date())
            let message = "GitHub is generating repository stats; some numbers may be stale. Harbor will retry \(retryText)."
            await self.diag.message("202 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw GitHubAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message
            )
        }

        if status == 403 || status == 429 {
            // A limit is a 429, a 403 with `Retry-After`, no quota left, or a body that says "rate
            // limit" (the secondary limit, which arrives with quota to spare). Any other 403 with
            // quota left is a permissions failure. With no rate-limit headers at all, a 403 is
            // still read as a limit and waited out for a minute, as before.
            let remainingHeader = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            let resume = RunCleanup.rateLimitResume(
                status: status,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                remaining: remainingHeader,
                resetEpoch: response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                body: String(bytes: data.prefix(2048), encoding: .utf8) ?? ""
            ) ?? (Int(remainingHeader ?? "") == nil ? Date().addingTimeInterval(60) : nil)
            guard let resetDate = resume else {
                await self.diag.message("\(status) with remaining=\(remainingHeader ?? "?") on \(url.lastPathComponent); treating as bad status")
                throw GitHubAPIError.badStatus(code: status, message: HTTPURLResponse.localizedString(forStatusCode: status))
            }
            self.lastRateLimitReset = resetDate
            self.blockedUntil = resetDate
            await self.backoff.setCooldown(url: response.url ?? url, until: resetDate)
            self.lastRateLimitError = "GitHub rate limit hit; resets " +
                "\(RelativeFormatter.string(from: resetDate, relativeTo: Date()))."
            await self.diag.message("Rate limited on \(url.lastPathComponent); resets \(resetDate)")
            throw GitHubAPIError.rateLimited(until: resetDate, message: self.lastRateLimitError ?? "Rate limited.")
        }

        guard allowedStatuses.contains(status) else {
            await self.diag.message("Unexpected status \(status) for \(url.lastPathComponent)")
            throw GitHubAPIError.badStatus(
                code: status,
                message: HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }

        if let snapshot = RateLimitSnapshot.from(response: response) {
            self.latestRestRateLimit = snapshot
        }
        self.detectRateLimit(from: response)
        return (data, response)
    }

    /// DELETE with the same auth as `get`; only `expected` statuses (204 by default) succeed.
    /// A rate limit (429, or a 403 with `Retry-After`, no quota left or a "rate limit" body)
    /// sets `blockedUntil` and throws `.rateLimited`; any other 403 is a permissions failure
    /// (`.badStatus`). While blocked it throws without sending. The token is never logged.
    func delete(url: URL, token: String, expected: Set<Int> = [204]) async throws {
        if let until = self.blockedUntil() {
            throw GitHubAPIError.rateLimited(
                until: until,
                message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date()))."
            )
        }
        let startedAt = Date()
        await self.diag.message("DELETE \(url.path)")
        await RequestTally.shared.recordREST(path: url.path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, responseAny) = try await self.readSession.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        await self.logResponse("DELETE", url: url, response: response, startedAt: startedAt)
        guard expected.contains(response.statusCode) else {
            if let resume = RunCleanup.rateLimitResume(
                status: response.statusCode,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
                remaining: response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
                resetEpoch: response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
                body: String(bytes: data.prefix(2048), encoding: .utf8) ?? ""
            ) {
                self.blockedUntil = resume
                throw GitHubAPIError.rateLimited(
                    until: resume,
                    message: "GitHub rate limit hit; resets \(RelativeFormatter.string(from: resume, relativeTo: Date()))."
                )
            }
            throw GitHubAPIError.badStatus(
                code: response.statusCode, message: HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            )
        }
    }

    func diagnosticsSnapshot() async -> RequestRunnerDiagnostics {
        let backoffCount = await self.backoff.count()
        return RequestRunnerDiagnostics(
            rateLimitReset: self.lastRateLimitReset,
            lastRateLimitError: self.lastRateLimitError,
            backoffEntries: backoffCount,
            restRateLimit: self.latestRestRateLimit
        )
    }

    private func logResponse(
        _ method: String,
        url: URL,
        response: HTTPURLResponse,
        startedAt: Date
    ) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let snapshot = RateLimitSnapshot.from(response: response)
        if let snapshot { self.latestRestRateLimit = snapshot }

        let remaining = snapshot?.remaining.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Remaining") ?? "?"
        let limit = snapshot?.limit.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Limit") ?? "?"
        let used = snapshot?.used.map(String.init) ?? response.value(forHTTPHeaderField: "X-RateLimit-Used") ?? "?"
        let resetDate = snapshot?.reset ?? self.rateLimitDate(from: response)
        let resetText = resetDate.map { RelativeFormatter.string(from: $0, relativeTo: Date()) } ?? "n/a"
        let resource = snapshot?.resource ?? response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "rest"

        await self.diag.message(
            "HTTP \(method) \(url.path) status=\(response.statusCode) res=\(resource) lim=\(limit) rem=\(remaining) used=\(used) reset=\(resetText) dur=\(durationMs)ms"
        )
    }

    private func rateLimitDate(from response: HTTPURLResponse) -> Date? {
        guard let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let epoch = TimeInterval(reset) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    private func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After"), let seconds = TimeInterval(retryAfter) {
            return Date().addingTimeInterval(seconds)
        }
        return nil
    }

    private func detectRateLimit(from response: HTTPURLResponse) {
        guard
            let remainingText = response.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            let remaining = Int(remainingText)
        else { return }

        if remaining <= 0 {
            self.lastRateLimitReset = self.rateLimitDate(from: response)
        } else if let reset = self.lastRateLimitReset, reset <= Date() {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
        }
    }
}

struct RequestRunnerDiagnostics: Sendable {
    let rateLimitReset: Date?
    let lastRateLimitError: String?
    let backoffEntries: Int
    let restRateLimit: RateLimitSnapshot?
}
