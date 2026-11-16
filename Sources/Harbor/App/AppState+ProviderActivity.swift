import Foundation
import HarborCore

/// Where a lazily fetched piece of activity stands. `failed` carries a short reason.
enum ActivityLoadState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

/// One non-GitHub provider's activity, how many days back it covers, and how it ended.
struct ProviderActivitySlice: Equatable {
    var state: ActivityLoadState = .idle
    var days: [ProviderDayActivity] = []
    var coveredDays = 0
    var partial = false
}

extension AppState {
    /// How far back GitLab and Azure DevOps are asked for. GitLab keeps three years of
    /// events, so "All time" stops there for them.
    static func lookbackDays(for range: ActivityRange) -> Int {
        switch range {
        case .week: 7
        case .month: 30
        case .quarter: 91
        case .year: 371
        case .allTime: 1096
        }
    }

    /// Providers other than GitHub that have a stored token. Never reads the token's value.
    func connectedActivityProviders() -> [ProviderType] {
        var providers: [ProviderType] = []
        if self.azureOrganization() != nil { providers.append(.azureDevOps) }
        if GitLabAuth.shared.hasToken(for: self.session.gitlabInstanceURL) { providers.append(.gitlab) }
        return providers
    }

    private func azureOrganization() -> String? {
        guard let org = UserDefaults.standard.string(forKey: "azureOrganization"), !org.isEmpty,
              AzureDevOpsPATStore.shared.hasToken(forOrganization: org) else { return nil }
        return org
    }

    /// Fetches what `range` needs, every time it is asked: the other providers' days (each
    /// independently, one failing never blocks another) and, for All time, GitHub's per-year
    /// totals. What is on screen stays up while the new request runs; only a request already
    /// in flight is joined.
    func loadActivity(range: ActivityRange) async {
        async let years: Void = self.loadContributionYearsIfNeeded(range: range)
        let needed = Self.lookbackDays(for: range)
        await withTaskGroup(of: Void.self) { group in
            for provider in self.connectedActivityProviders() {
                group.addTask { await self.loadProviderActivity(provider, days: needed) }
            }
        }
        await years
    }

    func loadContributionYearsIfNeeded(range: ActivityRange) async {
        guard range == .allTime, case let .loggedIn(user) = self.session.account else { return }
        if case .loading = self.session.contributionYearsState { return }
        self.session.contributionYearsState = .loading
        let epoch = self.scopeEpoch
        do {
            let years = try await self.contributionYearsLoader(user.username)
            guard epoch == self.scopeEpoch else { return }
            self.session.contributionYears = years
            self.session.contributionYearsState = .ready
        } catch {
            guard epoch == self.scopeEpoch else { return }
            // Cancelled mid-flight: back to idle so choosing All again retries.
            self.session.contributionYearsState = error.isCancellation ? .idle : .failed(error.userFacingMessage)
        }
    }

    func loadProviderActivity(_ provider: ProviderType, days needed: Int) async {
        var slice = self.session.providerActivity[provider] ?? ProviderActivitySlice()
        if case .loading = slice.state { return }
        let previous = slice
        slice.state = .loading
        self.session.providerActivity[provider] = slice

        let epoch = self.scopeEpoch
        let now = Date()
        let since = now.addingTimeInterval(-Double(needed) * 86400)
        do {
            let result = try await self.fetchActivity(provider, since: since, now: now)
            guard epoch == self.scopeEpoch else { return }
            self.session.providerActivity[provider] = ProviderActivitySlice(
                state: .ready, days: result.days, coveredDays: needed, partial: result.partial
            )
        } catch {
            guard epoch == self.scopeEpoch else { return }
            if error.isCancellation {
                self.session.providerActivity[provider] = previous
                return
            }
            // Keep what an earlier fetch found on screen; only the state says it failed.
            var failed = previous
            failed.state = .failed(Self.reason(error))
            self.session.providerActivity[provider] = failed
        }
    }

    private func fetchActivity(_ provider: ProviderType, since: Date, now: Date) async throws -> ProviderActivityResult {
        if let loader = self.providerActivityLoader { return try await loader(provider, since, now) }
        switch provider {
        case .gitlab:
            let instance = self.session.gitlabInstanceURL
            // `GitLabClient` traps on anything but HTTPS.
            guard URL(string: instance)?.scheme?.lowercased() == "https",
                  let token = try GitLabAuth.shared.loadToken(for: instance) else { throw GitLabAPIError.unauthorized }
            let client = GitLabClient(instanceURLString: instance, token: token)
            // 25 pages of 100 events; the oldest days are undercounted past that.
            return try await client.userActivity(since: since, until: now, maxPages: 25)
        case .azureDevOps:
            guard let org = self.azureOrganization() else { throw AzureDevOpsAPIError.unauthorized }
            let client = AzureDevOpsClient()
            try await client.setOrganization(org)
            return try await client.userActivity(since: since, now: now)
        case .github:
            return ProviderActivityResult(provider: .github, days: [])
        }
    }

    /// A short, secret-free reason for the strip's "unavailable" mark.
    static func reason(_ error: Error) -> String {
        if let error = error as? GitLabAPIError {
            switch error {
            case .rateLimited: return "rate limited"
            case .unauthorized: return "sign-in expired"
            default: return "unreachable"
            }
        }
        if let error = error as? AzureDevOpsAPIError {
            switch error {
            case .rateLimited: return "rate limited"
            case .unauthorized, .invalidPAT, .forbidden: return "sign-in expired"
            default: return "unreachable"
            }
        }
        return "unreachable"
    }
}
