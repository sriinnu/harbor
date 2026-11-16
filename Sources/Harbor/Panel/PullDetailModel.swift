import Foundation
import HarborCore
import Observation

/// One pull request, loaded when its pane opens and thrown away when it closes. In memory
/// only. Each action asks for a confirm, shows progress, shows GitHub's own message when it
/// fails, and re-reads the readiness afterwards.
@MainActor
@Observable
final class PullDetailModel {
    enum Action: Equatable {
        case resolve(threadID: String)
        case updateBranch
        case merge
    }

    /// The head commit and readiness shown when a confirm opened.
    struct ConfirmSnapshot: Equatable {
        let headOid: String
        let readiness: PullReadiness
    }

    /// Shown when a poll changed the pull request under an open confirm.
    static let changedMessage = "The pull request changed. Check it again."

    let owner: String
    let name: String
    let number: Int

    private(set) var detail: PullRequestDetail?
    private(set) var readiness: PullReadiness?
    private(set) var isLoading = true
    /// Why the read failed, when there is nothing to show.
    private(set) var loadError: String?
    /// The action waiting on an inline confirm. Open it with `beginConfirm`.
    private(set) var confirming: Action?
    /// What the user was looking at when the confirm opened. A poll that changes it cancels
    /// the confirm instead of merging something the user never saw.
    private var confirmSnapshot: ConfirmSnapshot?
    private(set) var running: Action?
    /// GitHub's message for the last failed action, shown until the next action or Dismiss.
    private(set) var actionError: String?
    private(set) var notice: String?
    var mergeMethod = PullMergeMethod.squash
    /// Off by default: the branch is only deleted when asked.
    var deleteBranchAfterMerge = false
    /// Set after Update branch, until the new head's checks have been seen to finish.
    private var watchingAfterUpdate: String?

    /// Debug snapshots only: a model that shows a fixed pull request and never touches GitHub.
    private var isPreview = false

    init(owner: String, name: String, number: Int) {
        self.owner = owner
        self.name = name
        self.number = number
    }

    /// Whether polling should run: checks are pending or expected, GitHub is still computing,
    /// or a branch update has not shown its new checks yet.
    var isWatching: Bool { self.watchingAfterUpdate != nil || self.readiness?.isWaiting == true }

    /// The merge button is live only when GitHub says the PR can merge and nothing is running.
    var canMerge: Bool {
        guard let detail, let readiness else { return false }
        return readiness.canMerge && self.running == nil && detail.allowedMergeMethods.contains(self.mergeMethod)
    }

    /// Why Merge is disabled, in the readiness's own words.
    var mergeBlockedReason: String? {
        guard let readiness, !readiness.canMerge else { return nil }
        return readiness.kind == .finished ? nil : readiness.headline
    }

    func load() async {
        guard !self.isPreview else { return }
        defer { if !Task.isCancelled { self.isLoading = false } }
        await self.refresh()
    }

    /// Re-reads the pull request. A failed read keeps what is on screen and shows the message.
    func refresh() async {
        guard let client = RepoHealthService.client else {
            self.loadError = "Sign in to GitHub to see this pull request."
            return
        }
        do {
            let fresh = try await client.pullRequestDetail(owner: self.owner, name: self.name, number: self.number)
            guard !Task.isCancelled else { return }
            self.apply(fresh)
            self.loadError = nil
        } catch {
            guard !Task.isCancelled, let message = error.reportableMessage else { return }
            if self.detail == nil { self.loadError = message } else if self.actionError == nil { self.actionError = message }
        }
    }

    func apply(_ fresh: PullRequestDetail) {
        let first = self.detail == nil
        self.detail = fresh
        self.readiness = PullReadiness.evaluate(fresh)
        if first || !fresh.allowedMergeMethods.contains(self.mergeMethod) { self.mergeMethod = fresh.defaultMergeMethod }
        if self.confirming != nil, !Self.confirmStillValid(
            self.confirming, snapshot: self.confirmSnapshot, detail: fresh, readiness: self.readiness
        ) {
            self.cancelConfirm()
            self.actionError = Self.changedMessage
        }
        if let old = self.watchingAfterUpdate, fresh.headOid != old, self.readiness?.isWaiting == false {
            self.watchingAfterUpdate = nil
        }
    }

    /// Re-reads every ~15 seconds while `isWatching`; the caller's task is cancelled when the
    /// pane closes or the watch ends. Gives up after 60 reads (15 minutes).
    func poll() async {
        guard !self.isPreview else { return }
        var reads = 0
        while !Task.isCancelled, self.isWatching, reads < 60 {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            reads += 1
            await self.refresh()
        }
    }

    func dismissMessage() {
        self.actionError = nil
        self.notice = nil
    }

    func beginConfirm(_ action: Action) {
        guard self.running == nil else { return }
        self.confirming = action
        self.confirmSnapshot = self.detail.flatMap { detail in
            self.readiness.map { ConfirmSnapshot(headOid: detail.headOid, readiness: $0) }
        }
    }

    func cancelConfirm() {
        self.confirming = nil
        self.confirmSnapshot = nil
    }

    /// Whether the confirm for `action` still describes what is on GitHub: same head commit,
    /// same readiness, and the action is still allowed. Resolving a thread does not depend on
    /// either.
    static func confirmStillValid(
        _ action: Action?, snapshot: ConfirmSnapshot?, detail: PullRequestDetail?, readiness: PullReadiness?
    ) -> Bool {
        guard let action else { return false }
        if case .resolve = action { return true }
        guard let snapshot, let detail, let readiness,
              snapshot.headOid == detail.headOid, snapshot.readiness == readiness else { return false }
        return action == .merge ? readiness.canMerge : readiness.canUpdateBranch
    }

    func perform(_ action: Action) {
        guard self.running == nil, let detail, let client = RepoHealthService.client else { return }
        let confirmed = action == self.confirming ? action : nil
        let valid = Self.confirmStillValid(confirmed, snapshot: self.confirmSnapshot, detail: detail, readiness: self.readiness)
        if !valid {
            self.cancelConfirm()
            self.actionError = Self.changedMessage
            return
        }
        if action == .merge, !self.canMerge {
            self.cancelConfirm()
            self.actionError = Self.changedMessage
            return
        }
        self.cancelConfirm()
        self.running = action
        self.actionError = nil
        self.notice = nil
        let method = self.mergeMethod
        let deleteBranch = self.deleteBranchAfterMerge
        Task {
            do {
                switch action {
                case let .resolve(threadID):
                    try await client.resolveReviewThread(id: threadID)
                case .updateBranch:
                    try await client.updatePullRequestBranch(detail)
                    self.watchingAfterUpdate = detail.headOid
                    self.notice = "Branch updated. Watching the checks."
                case .merge:
                    try await client.mergePullRequest(detail, method: method)
                    self.notice = "Merged."
                    if deleteBranch, detail.canDeleteHeadBranch, let ref = detail.headRefID {
                        do { try await client.deleteBranch(refID: ref) } catch {
                            self.actionError = "Merged, but the branch was not deleted: \(error.reportableMessage ?? "unknown error")"
                        }
                    }
                }
            } catch {
                self.actionError = error.reportableMessage
            }
            self.running = nil
            await self.refresh()
        }
    }
}

#if DEBUG
    extension PullDetailModel {
        /// A pull request that is behind, with a conversation to resolve and a check expected:
        /// the morning's failure, for rendering the actions without a live pull request.
        static func preview() -> PullDetailModel {
            let model = PullDetailModel(owner: "sriinnu", name: "harbor", number: 31)
            let thread = PullReviewThread(
                id: "T1", isResolved: false, isOutdated: false, path: "Sources/HarborCore/API/GitHubRestAPI.swift", line: 176,
                viewerCanResolve: true, authorLogin: "copilot-pull-request-reviewer",
                excerpt: "securitySummary starts async let tasks but then returns without awaiting those values.",
                url: URL(string: "https://github.com/sriinnu/harbor/pull/31#discussion_r1")
            )
            let detail = PullRequestDetail(
                id: "PR_1", number: 31, title: "Finish a pull request from the panel", url: nil, state: .open, isDraft: false,
                authorLogin: "sriinnu", baseRef: "main", headRef: "feat/pull-pane", headOid: "abc", isCrossRepository: false,
                headRefID: "REF_1", mergeable: "MERGEABLE", mergeStateStatus: "BEHIND", reviewDecision: nil,
                viewerCanUpdateBranch: true,
                checks: [PullCheck(name: "macOS (Xcode 26.1)", state: .expected, isRequired: true, url: nil)],
                threads: [thread], squashMergeAllowed: true, mergeCommitAllowed: true, rebaseMergeAllowed: false
            )
            model.isPreview = true
            model.isLoading = false
            model.apply(detail)
            return model
        }
    }
#endif
