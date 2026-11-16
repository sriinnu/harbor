import Foundation

actor AzureDevOpsRequestRunner {
    private let backoff: BackoffTracker
    private let diag: DiagnosticsLogger
    private var lastRateLimitReset: Date?
    private var blockedUntil: Date?
    private var lastRateLimitError: String?
    private var latestRateLimit: RateLimitSnapshot?

    init(
        backoff: BackoffTracker = BackoffTracker(),
        diag: DiagnosticsLogger = .shared
    ) {
        self.backoff = backoff
        self.diag = diag
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

    func get(
        url: URL,
        pat: String,
        allowedStatuses: Set<Int> = [200]
    ) async throws -> (Data, HTTPURLResponse) {
        let startedAt = Date()
        await self.diag.message("GET \(url.absoluteString)")

        if let until = self.blockedUntil, until > Date() {
            await self.diag.message("Blocked by local rateLimit until \(until)")
            throw AzureDevOpsAPIError.rateLimited(
                until: until,
                message: "Azure DevOps rate limit hit; resets \(RelativeFormatter.string(from: until, relativeTo: Date()))."
            )
        }

        if let cooldown = await backoff.cooldown(for: url) {
            await self.diag.message("Cooldown active for \(url.absoluteString) until \(cooldown)")
            throw AzureDevOpsAPIError.serviceUnavailable(
                retryAfter: cooldown,
                message: "Cooling down until \(RelativeFormatter.string(from: cooldown, relativeTo: Date()))."
            )
        }

        var request = URLRequest(url: url)
        // Azure DevOps uses Basic Auth with empty username and PAT as password
        let credentials = ":\(pat)"
        if let encodedCredentials = credentials.data(using: .utf8)?.base64EncodedString() {
            request.addValue("Basic \(encodedCredentials)", forHTTPHeaderField: "Authorization")
        }
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("7.0", forHTTPHeaderField: "Accept-Version")

        let (data, responseAny) = try await HarborURLSession.shared.data(for: request)
        guard let response = responseAny as? HTTPURLResponse else { throw URLError(.badServerResponse) }

        await self.logResponse("GET", url: url, response: response, startedAt: startedAt)

        let status = response.statusCode
        // Handle Azure DevOps specific status codes
        if status == 401 {
            await self.diag.message("401 Unauthorized for \(url.lastPathComponent)")
            throw AzureDevOpsAPIError.unauthorized
        }

        if status == 403 {
            await self.diag.message("403 Forbidden for \(url.lastPathComponent)")
            throw AzureDevOpsAPIError.forbidden
        }

        if status == 429 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(60)
            self.lastRateLimitReset = retryAfter
            self.blockedUntil = retryAfter
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            self.lastRateLimitError = "Azure DevOps rate limit hit; resets " +
                "\(RelativeFormatter.string(from: retryAfter, relativeTo: Date()))."
            await self.diag.message("Rate limited on \(url.lastPathComponent); resets \(retryAfter)")
            throw AzureDevOpsAPIError.rateLimited(until: retryAfter, message: self.lastRateLimitError ?? "Rate limited.")
        }

        if status == 503 {
            let retryAfter = self.retryAfterDate(from: response) ?? Date().addingTimeInterval(90)
            await self.backoff.setCooldown(url: response.url ?? url, until: retryAfter)
            let retryText = RelativeFormatter.string(from: retryAfter, relativeTo: Date())
            let message = "Azure DevOps service temporarily unavailable. Will retry \(retryText)."
            await self.diag.message("503 for \(url.lastPathComponent); cooldown until \(retryAfter)")
            throw AzureDevOpsAPIError.serviceUnavailable(
                retryAfter: retryAfter,
                message: message
            )
        }

        guard allowedStatuses.contains(status) else {
            await self.diag.message("Unexpected status \(status) for \(url.lastPathComponent)")
            let errorMessage = try? self.parseErrorMessage(from: data)
            throw AzureDevOpsAPIError.badStatus(
                code: status,
                message: errorMessage ?? HTTPURLResponse.localizedString(forStatusCode: status)
            )
        }

        self.detectRateLimit(from: response)
        return (data, response)
    }

    func diagnosticsSnapshot() async -> AzureDevOpsRequestRunnerDiagnostics {
        let backoffCount = await self.backoff.count()
        return AzureDevOpsRequestRunnerDiagnostics(
            rateLimitReset: self.lastRateLimitReset,
            lastRateLimitError: self.lastRateLimitError,
            backoffEntries: backoffCount,
            rateLimit: self.latestRateLimit
        )
    }

    private func logResponse(
        _ method: String,
        url: URL,
        response: HTTPURLResponse,
        startedAt: Date
    ) async {
        let durationMs = Int((Date().timeIntervalSince(startedAt) * 1000).rounded())
        let retryAfter = response.value(forHTTPHeaderField: "Retry-After") ?? "n/a"
        let requestId = response.value(forHTTPHeaderField: "X-VSS-RequestId") ?? "n/a"

        await self.diag.message(
            "HTTP \(method) \(url.path) status=\(response.statusCode) reqId=\(requestId) retry=\(retryAfter) dur=\(durationMs)ms"
        )
    }

    private func retryAfterDate(from response: HTTPURLResponse) -> Date? {
        if let retryAfter = response.value(forHTTPHeaderField: "Retry-After") {
            // Try parsing as seconds first
            if let seconds = TimeInterval(retryAfter) {
                return Date().addingTimeInterval(seconds)
            }
            // Try parsing as HTTP date
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            if let date = dateFormatter.date(from: retryAfter) {
                return date
            }
        }
        return nil
    }

    private func detectRateLimit(from response: HTTPURLResponse) {
        // Azure DevOps doesn't always provide rate limit headers like GitHub
        // Monitor for 429 status codes instead
        if response.statusCode == 429 {
            self.lastRateLimitReset = self.retryAfterDate(from: response)
        } else if let reset = self.lastRateLimitReset, reset <= Date() {
            self.lastRateLimitReset = nil
            self.lastRateLimitError = nil
        }
    }

    private func parseErrorMessage(from data: Data) throws -> String? {
        let errorResponse = try? AzureDevOpsDecoding.decode(AzureDevOpsErrorResponse.self, from: data)
        return errorResponse?.message
    }
}

struct AzureDevOpsRequestRunnerDiagnostics: Sendable {
    let rateLimitReset: Date?
    let lastRateLimitError: String?
    let backoffEntries: Int
    let rateLimit: RateLimitSnapshot?
}
