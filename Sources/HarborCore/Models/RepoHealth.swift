import Foundation

// MARK: - Hardening

/// One default-branch protection, as the rules GitHub enforces on it. `nil` means "couldn't
/// see", never "off": a token without admin can't read classic branch protection.
public struct BranchProtectionState: Equatable, Sendable {
    public var pullRequestRequired: Bool?
    public var statusChecksRequired: Bool?
    public var forcePushBlocked: Bool?

    public init(pullRequestRequired: Bool? = nil, statusChecksRequired: Bool? = nil, forcePushBlocked: Bool? = nil) {
        self.pullRequestRequired = pullRequestRequired
        self.statusChecksRequired = statusChecksRequired
        self.forcePushBlocked = forcePushBlocked
    }
}

public enum CheckState: Equatable, Sendable {
    case pass, fail, unknown
}

/// The five hardening checks. Every field is optional so "not visible" stays distinct from "off".
public struct HardeningChecklist: Equatable, Sendable {
    public var branch: BranchProtectionState
    public var signedCommits: Bool?
    /// How many `uses:` lines aren't pinned to a full commit SHA; nil when workflows couldn't be read.
    public var unpinnedActions: Int?
    public var workflowDefaultsToRead: Bool?
    public var dependabotUpdates: Bool?

    public init(
        branch: BranchProtectionState = BranchProtectionState(),
        signedCommits: Bool? = nil,
        unpinnedActions: Int? = nil,
        workflowDefaultsToRead: Bool? = nil,
        dependabotUpdates: Bool? = nil
    ) {
        self.branch = branch
        self.signedCommits = signedCommits
        self.unpinnedActions = unpinnedActions
        self.workflowDefaultsToRead = workflowDefaultsToRead
        self.dependabotUpdates = dependabotUpdates
    }

    /// Protected means all three: PRs required, status checks required, force-push blocked.
    public var branchProtection: CheckState {
        let parts = [self.branch.pullRequestRequired, self.branch.statusChecksRequired, self.branch.forcePushBlocked]
        if parts.contains(false) { return .fail }
        return parts.contains(where: { $0 == nil }) ? .unknown : .pass
    }

    public var signedCommitsState: CheckState { Self.state(self.signedCommits) }
    public var workflowPermissionsState: CheckState { Self.state(self.workflowDefaultsToRead) }
    public var dependabotUpdatesState: CheckState { Self.state(self.dependabotUpdates) }

    public var pinnedActionsState: CheckState {
        guard let count = self.unpinnedActions else { return .unknown }
        return count == 0 ? .pass : .fail
    }

    private static func state(_ value: Bool?) -> CheckState {
        switch value {
        case true: .pass
        case false: .fail
        case nil: .unknown
        }
    }
}

/// Classic branch protection, as far as the token could read it.
public enum ClassicProtectionLookup: Equatable, Sendable {
    case present(requiresPullRequest: Bool, requiresStatusChecks: Bool, blocksForcePush: Bool, requiresSignatures: Bool)
    /// Admin token, and GitHub says the branch has no classic protection.
    case absent
    /// 403/404 without admin, or the call failed.
    case unknown
}

/// Folds rulesets (readable by anyone) and classic protection (admin only) into one answer.
public enum BranchProtectionEvaluator {
    /// `ruleTypes` is the set of rule `type`s GitHub applies to the branch
    /// (`GET /rules/branches/{branch}`), or nil when that lookup failed.
    public static func evaluate(
        ruleTypes: Set<String>?,
        classic: ClassicProtectionLookup
    ) -> (branch: BranchProtectionState, signedCommits: Bool?) {
        func fromRules(_ type: String) -> Bool? { ruleTypes.map { $0.contains(type) } }
        var pr: Bool?, checks: Bool?, force: Bool?, signed: Bool?
        switch classic {
        case let .present(requiresPR, requiresChecks, blocksForce, requiresSignatures):
            (pr, checks, force, signed) = (requiresPR, requiresChecks, blocksForce, requiresSignatures)
        case .absent:
            (pr, checks, force, signed) = (false, false, false, false)
        case .unknown:
            break
        }
        let state = BranchProtectionState(
            pullRequestRequired: either(fromRules("pull_request"), pr),
            statusChecksRequired: either(fromRules("required_status_checks"), checks),
            forcePushBlocked: either(fromRules("non_fast_forward"), force)
        )
        return (state, either(fromRules("required_signatures"), signed))
    }

    /// True when either source says yes; false only when both say no; otherwise unknown.
    static func either(_ first: Bool?, _ second: Bool?) -> Bool? {
        if first == true || second == true { return true }
        if first == false, second == false { return false }
        return nil
    }
}

// MARK: - Pinned actions

/// Finds `uses:` lines that aren't pinned to a full 40-hex commit SHA.
public enum ActionPinChecker {
    /// Each unpinned `uses:` value in one workflow file, in file order. Local actions
    /// (`./…`) and `docker://` images are fine and not reported.
    public static func unpinnedUses(in workflow: String) -> [String] {
        workflow.split(whereSeparator: \.isNewline).compactMap { rawLine -> String? in
            guard let value = usesValue(String(rawLine)) else { return nil }
            return isPinned(value) ? nil : value
        }
    }

    public static func isPinned(_ reference: String) -> Bool {
        if reference == "." || reference.hasPrefix("./") || reference.hasPrefix("../") { return true }
        if reference.hasPrefix("docker://") { return true }
        guard let at = reference.lastIndex(of: "@") else { return false }
        let sha = reference[reference.index(after: at)...]
        return sha.count == 40 && sha.allSatisfy(\.isHexDigit)
    }

    /// The value of a `uses:` key on this line (with `- ` list prefix, quotes and trailing
    /// comment removed), or nil when the line isn't a `uses:` entry.
    static func usesValue(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("-") { text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces) }
        guard text.hasPrefix("uses:") else { return nil }
        var value = String(text.dropFirst("uses:".count))
        if let hash = value.range(of: " #") ?? (value.hasPrefix("#") ? value.startIndex ..< value.startIndex : nil) {
            value = String(value[..<hash.lowerBound])
        }
        value = value.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
        }
        return value.isEmpty ? nil : value
    }
}

// MARK: - Dependabot aggregation

public struct DependabotFinding: Equatable, Hashable, Sendable {
    public let package: String
    public let severity: String
    public let patchedVersion: String?

    public init(package: String, severity: String, patchedVersion: String?) {
        self.package = package
        self.severity = severity
        self.patchedVersion = patchedVersion
    }

    /// "lodash → 4.17.21", or "lodash → no patch" while none exists.
    public var line: String { "\(self.package) → \(self.patchedVersion ?? "no patch")" }
}

public enum DependabotAggregation {
    static let rank = ["critical": 4, "high": 3, "medium": 2, "low": 1]

    /// Counts per severity (unknown severities are ignored) and the worst `limit` findings,
    /// most severe first, then by package name. The same package and patch is listed once.
    public static func aggregate(_ findings: [DependabotFinding], limit: Int = 3) -> (tally: DependabotTally, worst: [DependabotFinding]) {
        func count(_ severity: String) -> Int { findings.count(where: { $0.severity == severity }) }
        let tally = DependabotTally(critical: count("critical"), high: count("high"), medium: count("medium"), low: count("low"))
        var seen = Set<String>()
        let ordered = findings
            .filter { rank[$0.severity] != nil }
            .sorted {
                let (left, right) = (rank[$0.severity] ?? 0, rank[$1.severity] ?? 0)
                return left != right ? left > right : $0.package < $1.package
            }
            .filter { seen.insert("\($0.package)|\($0.patchedVersion ?? "")").inserted }
        return (tally, Array(ordered.prefix(limit)))
    }
}

// MARK: - Settings URLs

/// What a failing check sends you to.
public enum HardeningFix: Equatable, Sendable {
    case branchProtection, signedCommits, pinnedActions, workflowPermissions, dependabotUpdates
    case securityPolicy, privateReporting
}

public enum RepoSettingsURL {
    /// The repository-relative page that fixes `fix`. Pinned actions are fixed in the
    /// workflow files themselves, so that one opens the workflows folder.
    public static func path(for fix: HardeningFix, defaultBranch: String) -> String {
        switch fix {
        case .branchProtection, .signedCommits: "settings/branches"
        case .workflowPermissions: "settings/actions"
        case .dependabotUpdates, .privateReporting: "settings/security_analysis"
        case .pinnedActions: "tree/\(defaultBranch)/.github/workflows"
        case .securityPolicy: "security/policy"
        }
    }

    /// The web origin for an API host: `api.github.com` is `github.com`, and an Enterprise
    /// `https://host/api/v3` is `https://host`.
    public static func webBase(fromAPIHost api: URL) -> URL {
        var parts = URLComponents()
        parts.scheme = "https"
        let host = api.host ?? "github.com"
        parts.host = host.hasPrefix("api.") ? String(host.dropFirst(4)) : host
        parts.port = api.port
        return parts.url ?? URL(string: "https://github.com")!
    }

    public static func url(webBase: URL, owner: String, name: String, fix: HardeningFix, defaultBranch: String) -> URL {
        webBase.appending(path: "\(owner)/\(name)/\(path(for: fix, defaultBranch: defaultBranch))")
    }
}

// MARK: - Flow

public enum PullReviewState: Equatable, Sendable {
    case draft, approved, changesRequested, reviewRequested, noReviews

    public var label: String {
        switch self {
        case .draft: "draft"
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .reviewRequested: "review requested"
        case .noReviews: "no reviews"
        }
    }

    /// Latest verdict per reviewer wins; comments and pending reviews don't count. Any
    /// "changes requested" beats an approval.
    public static func derive(isDraft: Bool, reviews: [(user: String, state: String)], hasRequestedReviewers: Bool) -> Self {
        if isDraft { return .draft }
        var latest: [String: String] = [:]
        for review in reviews where ["APPROVED", "CHANGES_REQUESTED", "DISMISSED"].contains(review.state) {
            latest[review.user] = review.state
        }
        if latest.values.contains("CHANGES_REQUESTED") { return .changesRequested }
        if latest.values.contains("APPROVED") { return .approved }
        return hasRequestedReviewers ? .reviewRequested : .noReviews
    }
}

public struct FlowPullRequest: Equatable, Sendable {
    public let number: Int
    public let title: String
    public let createdAt: Date
    public let review: PullReviewState

    public init(number: Int, title: String, createdAt: Date, review: PullReviewState) {
        self.number = number
        self.title = title
        self.createdAt = createdAt
        self.review = review
    }

    public static let staleAfter: TimeInterval = 7 * 86400

    /// Stale means strictly older than seven days.
    public func isStale(now: Date) -> Bool { now.timeIntervalSince(self.createdAt) > Self.staleAfter }

    /// "3d", "5h", "12m": the biggest whole unit.
    public func ageLabel(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(self.createdAt)))
        if seconds >= 86400 { return "\(seconds / 86400)d" }
        if seconds >= 3600 { return "\(seconds / 3600)h" }
        return "\(max(1, seconds / 60))m"
    }
}

public struct FlowRun: Equatable, Sendable {
    public let status: CIStatus
    /// Wall time from start to last update; nil while the run is still going.
    public let duration: TimeInterval?

    public init(status: CIStatus, duration: TimeInterval?) {
        self.status = status
        self.duration = duration
    }

    /// "45s", "2m 14s", "1h 05m".
    public static func durationLabel(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 { return String(format: "%dh %02dm", total / 3600, total % 3600 / 60) }
        if total >= 60 { return "\(total / 60)m \(String(format: "%02d", total % 60))s" }
        return "\(total)s"
    }

    /// Mean duration of the finished runs; nil when none finished.
    public static func averageDuration(_ runs: [FlowRun]) -> TimeInterval? {
        let durations = runs.compactMap(\.duration)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
    }
}

// MARK: - Sections

public struct RepoHealthBasics: Equatable, Sendable {
    public let defaultBranch: String
    /// nil when GitHub didn't report permissions.
    public let isAdmin: Bool?

    public init(defaultBranch: String, isAdmin: Bool?) {
        self.defaultBranch = defaultBranch
        self.isAdmin = isAdmin
    }
}

/// Why an alerts endpoint gave no count.
public enum AlertAvailability: Equatable, Sendable {
    /// GitHub returned alerts (possibly zero).
    case visible
    /// 404: the feature was never set up for this repository.
    case notEnabled
    /// 403 (or any other refusal): the token can't see them without admin access.
    case needsAdmin

    /// What a withheld response means: 404 is "not set up", anything else is "needs admin".
    public init(withheldStatus status: Int) {
        self = status == 404 ? .notEnabled : .needsAdmin
    }
}

public struct RepoSecuritySection: Equatable, Sendable {
    /// Reuses `RepoSecurity`: a nil field is "not visible", never zero.
    public let alerts: RepoSecurity
    public let topAlerts: [DependabotFinding]
    public let hasSecurityPolicy: Bool?
    public let privateReporting: Bool?
    /// Why code scanning has no count; derived from `alerts` when not given.
    public let codeScanning: AlertAvailability

    public init(
        alerts: RepoSecurity, topAlerts: [DependabotFinding], hasSecurityPolicy: Bool?, privateReporting: Bool?,
        codeScanning: AlertAvailability? = nil
    ) {
        self.alerts = alerts
        self.topAlerts = topAlerts
        self.hasSecurityPolicy = hasSecurityPolicy
        self.privateReporting = privateReporting
        self.codeScanning = codeScanning ?? (alerts.codeScanning == nil ? .needsAdmin : .visible)
    }

    /// The Code scanning row's value.
    public var codeScanningValue: String {
        switch self.codeScanning {
        case .visible: alerts.codeScanning.map(String.init) ?? "not visible (needs admin)"
        case .notEnabled: "Not enabled"
        case .needsAdmin: "not visible (needs admin)"
        }
    }

    /// A line under the row that says what to do; only when code scanning is not set up.
    public var codeScanningHint: String? {
        self.codeScanning == .notEnabled ? "Turn on CodeQL in Settings → Code security" : nil
    }
}

public struct RepoFlowSection: Equatable, Sendable {
    public let pulls: [FlowPullRequest]
    public let runs: [FlowRun]
    public let release: Release?
    public let commitsSinceRelease: Int?

    public init(pulls: [FlowPullRequest], runs: [FlowRun], release: Release?, commitsSinceRelease: Int?) {
        self.pulls = pulls
        self.runs = runs
        self.release = release
        self.commitsSinceRelease = commitsSinceRelease
    }
}
