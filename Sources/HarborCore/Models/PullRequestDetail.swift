import Foundation

/// How a pull request would be merged. Raw values are GraphQL's `PullRequestMergeMethod`.
public enum PullMergeMethod: String, CaseIterable, Sendable, Equatable {
    case squash = "SQUASH"
    case merge = "MERGE"
    case rebase = "REBASE"

    public var label: String {
        switch self {
        case .squash: "Squash and merge"
        case .merge: "Create a merge commit"
        case .rebase: "Rebase and merge"
        }
    }
}

/// What one status check (a check run or a commit status) is doing.
public enum PullCheckState: Equatable, Sendable {
    case passed
    case failed
    /// Queued or running.
    case pending
    /// A required check nobody has reported yet.
    case expected
}

public struct PullCheck: Equatable, Sendable {
    public let name: String
    public let state: PullCheckState
    public let isRequired: Bool
    public let url: URL?

    public init(name: String, state: PullCheckState, isRequired: Bool, url: URL?) {
        self.name = name
        self.state = state
        self.isRequired = isRequired
        self.url = url
    }
}

/// An unresolved (or resolved) review conversation.
public struct PullReviewThread: Equatable, Sendable {
    public let id: String
    public let isResolved: Bool
    public let isOutdated: Bool
    public let path: String?
    public let line: Int?
    public let viewerCanResolve: Bool
    public let authorLogin: String?
    /// The first comment, flattened to one short line.
    public let excerpt: String
    public let url: URL?

    public init(
        id: String, isResolved: Bool, isOutdated: Bool, path: String?, line: Int?,
        viewerCanResolve: Bool, authorLogin: String?, excerpt: String, url: URL?
    ) {
        self.id = id
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.path = path
        self.line = line
        self.viewerCanResolve = viewerCanResolve
        self.authorLogin = authorLogin
        self.excerpt = excerpt
        self.url = url
    }

    /// The comment text on one line, cut at a word-ish boundary with an ellipsis.
    public static func excerpt(from body: String, limit: Int = 140) -> String {
        let flat = body.split(whereSeparator: \.isNewline).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard flat.count > limit else { return flat }
        return String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// Everything the pull request pane needs, from one GraphQL read. Never cached.
public struct PullRequestDetail: Equatable, Sendable {
    public enum State: String, Sendable { case open = "OPEN", closed = "CLOSED", merged = "MERGED" }

    public let id: String
    public let number: Int
    public let title: String
    public let url: URL?
    public let state: State
    public let isDraft: Bool
    public let authorLogin: String?
    public let baseRef: String
    public let headRef: String
    public let headOid: String
    public let isCrossRepository: Bool
    /// Node id of the head branch, for deleting it after a merge; nil once it is gone.
    public let headRefID: String?
    /// `MERGEABLE`, `CONFLICTING` or `UNKNOWN`.
    public let mergeable: String
    /// `CLEAN`, `BEHIND`, `BLOCKED`, `DIRTY`, `UNSTABLE`, `HAS_HOOKS`, `DRAFT` or `UNKNOWN`.
    public let mergeStateStatus: String
    /// `APPROVED`, `CHANGES_REQUESTED`, `REVIEW_REQUIRED`, or nil when reviews aren't required.
    public let reviewDecision: String?
    public let viewerCanUpdateBranch: Bool
    public let checks: [PullCheck]
    public let threads: [PullReviewThread]
    public let squashMergeAllowed: Bool
    public let mergeCommitAllowed: Bool
    public let rebaseMergeAllowed: Bool
    /// GitHub's own count of checks and review threads. The read fetches the first 50 of each,
    /// so these can exceed `checks.count` and `threads.count`.
    public let checksTotal: Int
    public let threadsTotal: Int

    public init(
        id: String, number: Int, title: String, url: URL?, state: State, isDraft: Bool, authorLogin: String?,
        baseRef: String, headRef: String, headOid: String, isCrossRepository: Bool, headRefID: String?,
        mergeable: String, mergeStateStatus: String, reviewDecision: String?, viewerCanUpdateBranch: Bool,
        checks: [PullCheck], threads: [PullReviewThread],
        squashMergeAllowed: Bool, mergeCommitAllowed: Bool, rebaseMergeAllowed: Bool,
        checksTotal: Int? = nil, threadsTotal: Int? = nil
    ) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.state = state
        self.isDraft = isDraft
        self.authorLogin = authorLogin
        self.baseRef = baseRef
        self.headRef = headRef
        self.headOid = headOid
        self.isCrossRepository = isCrossRepository
        self.headRefID = headRefID
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.reviewDecision = reviewDecision
        self.viewerCanUpdateBranch = viewerCanUpdateBranch
        self.checks = checks
        self.threads = threads
        self.squashMergeAllowed = squashMergeAllowed
        self.mergeCommitAllowed = mergeCommitAllowed
        self.rebaseMergeAllowed = rebaseMergeAllowed
        self.checksTotal = max(checksTotal ?? checks.count, checks.count)
        self.threadsTotal = max(threadsTotal ?? threads.count, threads.count)
    }

    /// More checks exist than were fetched, so counts of them are lower bounds.
    public var checksTruncated: Bool { self.checksTotal > self.checks.count }
    public var threadsTruncated: Bool { self.threadsTotal > self.threads.count }

    public var unresolvedThreads: [PullReviewThread] { self.threads.filter { !$0.isResolved } }

    /// The repo's allowed methods, squash first.
    public var allowedMergeMethods: [PullMergeMethod] {
        var methods: [PullMergeMethod] = []
        if self.squashMergeAllowed { methods.append(.squash) }
        if self.mergeCommitAllowed { methods.append(.merge) }
        if self.rebaseMergeAllowed { methods.append(.rebase) }
        return methods
    }

    /// Whether "delete branch after merge" would act: not for a fork's branch or one already gone.
    public var canDeleteHeadBranch: Bool { !self.isCrossRepository && self.headRefID != nil }

    /// The merge confirm, naming the branch when it will be deleted too:
    /// "Squash and merge #12 into main and delete branch develop?"
    public func mergeConfirmation(method: PullMergeMethod, deleteBranch: Bool) -> String {
        let base = "\(method.label) #\(self.number) into \(self.baseRef)"
        return deleteBranch && self.canDeleteHeadBranch ? "\(base) and delete branch \(self.headRef)?" : "\(base)?"
    }

    public var defaultMergeMethod: PullMergeMethod { self.allowedMergeMethods.first ?? .squash }
}

/// The merge readiness block, in plain words. Pure: same input, same output.
public struct PullReadiness: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case ready
        case blocked
        /// Waiting on something that resolves by itself (checks, GitHub's own computation).
        case waiting
        /// Merged or closed: nothing left to do.
        case finished
    }

    public let kind: Kind
    public let headline: String
    /// Every reason the merge is not available, in the order to fix them. Empty when ready.
    public let reasons: [String]
    public let canMerge: Bool
    public let canUpdateBranch: Bool
    /// True while a poll could change the answer: checks running or expected, or GitHub
    /// has not worked out mergeability yet.
    public let isWaiting: Bool

    public static func evaluate(_ pull: PullRequestDetail) -> PullReadiness {
        switch pull.state {
        case .merged: return Self.finished("Merged")
        case .closed: return Self.finished("Closed without merging")
        case .open: break
        }
        let failing = pull.checks.count { $0.state == .failed }
        let running = pull.checks.count { $0.state == .pending }
        let expected = pull.checks.count { $0.state == .expected }
        let unresolved = pull.unresolvedThreads.count
        let behind = pull.mergeStateStatus == "BEHIND"
        let mergeable = ["CLEAN", "UNSTABLE", "HAS_HOOKS"].contains(pull.mergeStateStatus)
            && pull.mergeable == "MERGEABLE" && !pull.isDraft

        var reasons: [String] = []
        if pull.isDraft { reasons.append("Draft pull request") }
        if pull.mergeable == "CONFLICTING" || pull.mergeStateStatus == "DIRTY" { reasons.append("Merge conflicts to resolve") }
        if behind { reasons.append("Branch is behind base") }
        // Past the 50 fetched, the counts below are lower bounds: "50+".
        let threadMore = pull.threadsTruncated ? "+" : ""
        let checkMore = pull.checksTruncated ? "+" : ""
        if unresolved > 0 {
            reasons.append(unresolved == 1 && threadMore.isEmpty ? "1 conversation to resolve" : "\(unresolved)\(threadMore) conversations to resolve")
        }
        if failing > 0 { reasons.append(failing == 1 && checkMore.isEmpty ? "1 check failing" : "\(failing)\(checkMore) checks failing") }
        if running > 0 { reasons.append(running == 1 && checkMore.isEmpty ? "1 check running" : "\(running)\(checkMore) checks running") }
        if expected > 0 { reasons.append(expected == 1 && checkMore.isEmpty ? "1 check expected" : "\(expected)\(checkMore) checks expected") }
        switch pull.reviewDecision {
        case "REVIEW_REQUIRED": reasons.append("Review required")
        case "CHANGES_REQUESTED": reasons.append("Changes requested")
        default: break
        }
        let unknown = pull.mergeStateStatus == "UNKNOWN" || pull.mergeable == "UNKNOWN"
        if reasons.isEmpty, unknown { reasons.append("GitHub is still working out mergeability") }
        if reasons.isEmpty, !mergeable { reasons.append("Blocked by branch protection") }

        let waiting = running > 0 || expected > 0 || unknown
        let canUpdate = behind && pull.viewerCanUpdateBranch
        if mergeable {
            // Unresolved conversations only block when the branch asks for them to be
            // resolved, which GitHub already folded into the merge state.
            let note = pull.mergeStateStatus == "UNSTABLE" ? "Ready to merge (a check that isn't required is failing or still running)" : "Ready to merge"
            return PullReadiness(
                kind: .ready, headline: note, reasons: [], canMerge: true, canUpdateBranch: false, isWaiting: false
            )
        }
        return PullReadiness(
            kind: waiting && failing == 0 && unresolved == 0 && !behind ? .waiting : .blocked,
            headline: reasons[0], reasons: reasons, canMerge: false, canUpdateBranch: canUpdate, isWaiting: waiting
        )
    }

    private static func finished(_ headline: String) -> PullReadiness {
        PullReadiness(kind: .finished, headline: headline, reasons: [], canMerge: false, canUpdateBranch: false, isWaiting: false)
    }
}
