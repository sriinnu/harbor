import Foundation

public enum HealthGrade: String, Equatable, Sendable {
    case a = "A", b = "B", c = "C", d = "D", f = "F"
}

public struct HealthDrag: Equatable, Sendable {
    public let label: String
    public let points: Int

    public init(label: String, points: Int) {
        self.label = label
        self.points = points
    }
}

public struct RepoHealthScore: Equatable, Sendable {
    public let points: Int
    public let grade: HealthGrade
    /// Every penalty applied, largest first.
    public let drags: [HealthDrag]
    /// How many inputs couldn't be seen; they cost nothing.
    public let notVisible: Int

    /// "B · 2 high alerts, main not protected": the top three drags. Hidden inputs are
    /// noted at the end, never counted against the grade.
    public var reason: String {
        let top = self.drags.prefix(3).map(\.label)
        var text = "\(self.grade.rawValue) · " + (top.isEmpty ? "nothing dragging it down" : top.joined(separator: ", "))
        if self.notVisible > 0 { text += " · \(self.notVisible) not visible" }
        return text
    }
}

/// Everything the grade is computed from. `nil` is "not visible" and never counts against.
public struct RepoHealthInputs: Equatable, Sendable {
    public var defaultBranch: String
    public var alerts: RepoSecurity
    public var hasSecurityPolicy: Bool?
    public var privateReporting: Bool?
    public var hardening: HardeningChecklist
    public var latestRunFailing: Bool?
    public var stalePullRequests: Int?

    public init(
        defaultBranch: String,
        alerts: RepoSecurity,
        hasSecurityPolicy: Bool?,
        privateReporting: Bool?,
        hardening: HardeningChecklist,
        latestRunFailing: Bool?,
        stalePullRequests: Int?
    ) {
        self.defaultBranch = defaultBranch
        self.alerts = alerts
        self.hasSecurityPolicy = hasSecurityPolicy
        self.privateReporting = privateReporting
        self.hardening = hardening
        self.latestRunFailing = latestRunFailing
        self.stalePullRequests = stalePullRequests
    }
}

/// Pure, deterministic scoring. Start at 100 and subtract:
///
/// - secret scanning alerts, any: 30 (flat)
/// - Dependabot: critical 15 each (max 30), high 3 each (max 15), medium 1 each (max 5), low 0
/// - code scanning alerts: 2 each (max 10)
/// - default branch not protected (PRs not required, or force-push allowed): 10;
///   otherwise status checks not required: 4
/// - signed commits not required: 4
/// - unpinned actions: 2 each (max 6)
/// - workflow token defaults to write: 4
/// - Dependabot security updates off: 4
/// - no SECURITY.md: 2; private vulnerability reporting off: 2
/// - latest workflow run failing: 4
/// - stale open PRs: 1 each (max 3)
///
/// Grade: 90+ A, 80+ B, 70+ C, 60+ D, below F. An input that is `nil` is skipped entirely
/// and only counted in `notVisible`.
public enum RepoHealthScorer {
    public static func score(_ input: RepoHealthInputs) -> RepoHealthScore {
        var drags: [HealthDrag] = []
        var hidden = 0
        func add(_ label: String, _ points: Int) {
            if points > 0 { drags.append(HealthDrag(label: label, points: points)) }
        }
        func plural(_ count: Int, _ noun: String) -> String { "\(count) \(noun)\(count == 1 ? "" : "s")" }

        if let secrets = input.alerts.secretLeaks {
            if secrets > 0 { add(plural(secrets, "leaked secret"), 30) }
        } else { hidden += 1 }

        if let tally = input.alerts.dependabot {
            if tally.critical > 0 { add(plural(tally.critical, "critical alert"), min(tally.critical * 15, 30)) }
            if tally.high > 0 { add(plural(tally.high, "high alert"), min(tally.high * 3, 15)) }
            if tally.medium > 0 { add(plural(tally.medium, "medium alert"), min(tally.medium, 5)) }
        } else { hidden += 1 }

        if let code = input.alerts.codeScanning {
            if code > 0 { add(plural(code, "code alert"), min(code * 2, 10)) }
        } else { hidden += 1 }

        let branch = input.hardening.branch
        let branchName = input.defaultBranch
        if branch.pullRequestRequired == false || branch.forcePushBlocked == false {
            add("\(branchName) not protected", 10)
        } else if branch.statusChecksRequired == false {
            add("no required checks", 4)
        }
        if [branch.pullRequestRequired, branch.statusChecksRequired, branch.forcePushBlocked].contains(where: { $0 == nil }) { hidden += 1 }

        if let signed = input.hardening.signedCommits {
            if !signed { add("unsigned commits allowed", 4) }
        } else { hidden += 1 }

        if let unpinned = input.hardening.unpinnedActions {
            if unpinned > 0 { add("\(unpinned) unpinned action\(unpinned == 1 ? "" : "s")", min(unpinned * 2, 6)) }
        } else { hidden += 1 }

        if let readOnly = input.hardening.workflowDefaultsToRead {
            if !readOnly { add("workflows can write", 4) }
        } else { hidden += 1 }

        if let updates = input.hardening.dependabotUpdates {
            if !updates { add("Dependabot updates off", 4) }
        } else { hidden += 1 }

        if let policy = input.hasSecurityPolicy {
            if !policy { add("no SECURITY.md", 2) }
        } else { hidden += 1 }

        if let reporting = input.privateReporting {
            if !reporting { add("private reporting off", 2) }
        } else { hidden += 1 }

        if input.latestRunFailing == true { add("CI failing", 4) }

        if let stale = input.stalePullRequests, stale > 0 { add(plural(stale, "stale PR"), min(stale, 3)) }

        let points = max(0, 100 - drags.reduce(0) { $0 + $1.points })
        // Stable sort: equal penalties keep the order they were added in.
        let ordered = drags.enumerated().sorted { ($0.element.points, $1.offset) > ($1.element.points, $0.offset) }.map(\.element)
        return RepoHealthScore(points: points, grade: grade(for: points), drags: ordered, notVisible: hidden)
    }

    public static func grade(for points: Int) -> HealthGrade {
        switch points {
        case 90...: .a
        case 80...: .b
        case 70...: .c
        case 60...: .d
        default: .f
        }
    }
}
