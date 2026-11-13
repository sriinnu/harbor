import Foundation
import HarborCore
import Observation

/// The signed-in user's own open pull requests, one GraphQL search each time it loads, kept in
/// memory for what is on screen and never written down. Needs you shows the ones that need
/// their author (`MyPullRequest.reasons`); the Tower's "In review" lane reads the same answer
/// instead of searching again. Only a search already in flight is joined; nothing is skipped
/// because one ran recently. The last list stays up while a new one loads.
@MainActor
@Observable
final class MyPullsStore {
    static let shared = MyPullsStore()

    private(set) var pulls: [MyPullRequest] = []
    /// Why the last search failed; nil when it worked (or none has run).
    private(set) var failure: String?
    /// True once a search has answered since launch or the last `clear()`.
    private(set) var hasAnswered = false
    /// Called with the items that newly need the user after an answer. The first answer after
    /// launch, sign-in or `clear()` is a baseline and calls nothing.
    /// Called after every answer and after `clear()`, so Tower can scan again when its input moved.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored var onEntered: (@MainActor ([NeedsYouWatcher.Item]) -> Void)?
    @ObservationIgnored private var watcher = NeedsYouWatcher()
    @ObservationIgnored private var inflight: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let fetch: @MainActor () async throws -> [MyPullRequest]?

    init(fetch: @escaping @MainActor () async throws -> [MyPullRequest]? = { try await RepoHealthService.client?.myPullRequests() }) {
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
                self.pulls = list
                self.failure = nil
                self.hasAnswered = true
                self.onChange?()
                let entered = self.watcher.observe(mine: list)
                if !entered.isEmpty { self.onEntered?(entered) }
            } catch {
                guard !Task.isCancelled, generation == self.generation, !error.isCancellation else { return }
                self.failure = error.userFacingMessage
                self.hasAnswered = true
                self.onChange?()
            }
        }
        self.inflight = task
        return task
    }

    /// The Tower's view of the same answer: lowercased `owner/name` to head branch names. Reads
    /// what the last search returned and never starts one; nil when there is no usable answer
    /// (none yet, or it failed), so no row is called "in review" on a guess.
    func branchesForTower() -> [String: Set<String>]? {
        guard self.failure == nil, self.hasAnswered else { return nil }
        var result: [String: Set<String>] = [:]
        for pull in self.pulls {
            guard let branch = pull.headBranch else { continue }
            result[pull.repoFullName.lowercased(), default: []].insert(branch)
        }
        return result
    }

    /// Sign-out or a different account: drop everything and let any search in flight land nowhere.
    func clear() {
        self.inflight?.cancel()
        self.inflight = nil
        self.generation += 1
        self.pulls = []
        self.failure = nil
        self.hasAnswered = false
        self.watcher.reset()
        self.onChange?()
    }
}

extension HarborPanelContent {
    /// The most of the user's own pull requests Needs you lists, so they never crowd out the rest.
    static let maxMyPullRows = 4

    /// One Needs-you row per pull request that has a reason, the most recently updated first as GitHub sorted them.
    static func myPullNeeds(_ pulls: [MyPullRequest]) -> [PanelNeed] {
        pulls.filter { !$0.reasons.isEmpty }.prefix(Self.maxMyPullRows).map { pull in
            let kind: StatusGlyph.Kind = pull.reasons.contains(.readyToMerge) ? .pass : .fail
            return PanelNeed(
                id: "mine:\(pull.id)", repo: nil, kind: kind, title: pull.title, detail: pull.detailLine, age: nil,
                pull: PanelPullTarget(fullName: pull.repoFullName, number: pull.number)
            )
        }
    }
}
