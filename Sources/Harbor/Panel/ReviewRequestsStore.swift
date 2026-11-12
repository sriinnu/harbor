import Foundation
import HarborCore
import Observation

/// Pull requests waiting on the signed-in user's review: one GraphQL search each time the
/// panel opens, kept in memory for what is on screen and never written down. Nothing is
/// skipped because a search ran recently; only a search already in flight is joined. The last
/// list stays up while a new one loads, and a failed search is kept in `failure` so the panel
/// can say it could not check, instead of looking calm.
@MainActor
@Observable
final class ReviewRequestsStore {
    static let shared = ReviewRequestsStore()

    private(set) var requests: [ReviewRequest] = []
    /// GitHub's total, which can be more than `requests` (the search takes the first 20).
    private(set) var total: Int?
    /// Why the last search failed; nil when it worked (or none has run).
    private(set) var failure: String?
    /// True once a search has answered (list or failure) since launch or the last `clear()`: what is
    /// on screen is then an answer, not "not asked yet". In memory only; it never skips a search.
    private(set) var hasAnswered = false
    @ObservationIgnored private var inflight: Task<Void, Never>?
    /// Bumped by `clear()`, so a search that started for another account lands nowhere.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetch: @MainActor () async throws -> ReviewRequestList?

    init(fetch: @escaping @MainActor () async throws -> ReviewRequestList? = { try await RepoHealthService.client?.reviewRequests() }) {
        self.fetch = fetch
    }

    /// Starts a search, or joins the one in flight. Returns the task so a caller can wait.
    @discardableResult
    func load() -> Task<Void, Never>? {
        if let running = self.inflight { return running }
        self.generation += 1
        let generation = self.generation
        let task = Task { [fetch = self.fetch] in
            defer { if generation == self.generation { self.inflight = nil } }
            do {
                guard let list = try await fetch() else { return }
                guard !Task.isCancelled, generation == self.generation else { return }
                self.requests = list.requests
                self.total = list.total
                self.failure = nil
                self.hasAnswered = true
            } catch {
                guard !Task.isCancelled, generation == self.generation, !error.isCancellation else { return }
                self.failure = error.userFacingMessage
                self.hasAnswered = true
            }
        }
        self.inflight = task
        return task
    }

    /// Sign-out or a different account: drop everything and let any search in flight land nowhere.
    func clear() {
        self.inflight?.cancel()
        self.inflight = nil
        self.generation += 1
        self.requests = []
        self.total = nil
        self.failure = nil
        self.hasAnswered = false
    }
}

extension HarborPanelContent {
    /// The most review requests Needs you lists, so they never push the behind-clone rows out.
    static let maxReviewRows = 4

    /// One Needs-you row per review request: the pull request's title, then where it is.
    static func reviewNeeds(_ requests: [ReviewRequest], now: Date = Date()) -> [PanelNeed] {
        requests.prefix(Self.maxReviewRows).map { request in
            PanelNeed(
                id: "review:\(request.id)", repo: nil, kind: .review, title: request.title,
                detail: request.detailLine(now: now), age: nil, pull: PanelPullTarget(fullName: request.repoFullName, number: request.number)
            )
        }
    }
}
