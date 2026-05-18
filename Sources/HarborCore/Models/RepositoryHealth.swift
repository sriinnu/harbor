import Foundation

// MARK: - Repository Health Summary

/// Represents the overall health status of a repository
public struct RepositoryHealth: Sendable, Equatable {
    /// Overall health score (0-100)
    public let score: Int

    /// Detailed health metrics
    public let metrics: HealthMetrics

    /// Active issues requiring attention
    public let issues: [HealthIssue]

    /// Timestamp of the health assessment
    public let assessedAt: Date

    public init(
        score: Int,
        metrics: HealthMetrics,
        issues: [HealthIssue],
        assessedAt: Date = Date()
    ) {
        self.score = min(100, max(0, score))
        self.metrics = metrics
        self.issues = issues
        self.assessedAt = assessedAt
    }

    /// Health is good (score >= 80)
    public var isHealthy: Bool {
        score >= 80
    }

    /// Health needs attention (score 50-79)
    public var needsAttention: Bool {
        score >= 50 && score < 80
    }

    /// Health is critical (score < 50)
    public var isCritical: Bool {
        score < 50
    }

    /// Health status label
    public var statusLabel: String {
        if isHealthy { return "Healthy" }
        if needsAttention { return "Needs Attention" }
        return "Critical"
    }
}

// MARK: - Health Metrics

/// Detailed health metrics for a repository
public struct HealthMetrics: Sendable, Equatable {
    /// Stale pull requests count
    public let stalePRCount: Int

    /// Failed CI runs in a row
    public let failingCIStreak: Int

    /// Blocked work items
    public let blockedWorkCount: Int

    /// Open security alerts
    public let securityAlertCount: Int

    /// Outdated dependencies
    public let outdatedDependencyCount: Int

    /// Long-running branches (not merged in 30+ days)
    public let staleBranchCount: Int

    /// PRs waiting for review > 7 days
    public let awaitingReviewCount: Int

    public init(
        stalePRCount: Int = 0,
        failingCIStreak: Int = 0,
        blockedWorkCount: Int = 0,
        securityAlertCount: Int = 0,
        outdatedDependencyCount: Int = 0,
        staleBranchCount: Int = 0,
        awaitingReviewCount: Int = 0
    ) {
        self.stalePRCount = stalePRCount
        self.failingCIStreak = failingCIStreak
        self.blockedWorkCount = blockedWorkCount
        self.securityAlertCount = securityAlertCount
        self.outdatedDependencyCount = outdatedDependencyCount
        self.staleBranchCount = staleBranchCount
        self.awaitingReviewCount = awaitingReviewCount
    }

    /// Calculate a health score based on metrics
    public func calculateScore() -> Int {
        var deductions = 0

        // Stale PRs: -10 per PR, max -30
        deductions += min(30, stalePRCount * 10)

        // Failing CI streak: -15 per failure, max -30
        deductions += min(30, failingCIStreak * 15)

        // Blocked work: -10 per item, max -20
        deductions += min(20, blockedWorkCount * 10)

        // Security alerts: -20 per alert, max -40
        deductions += min(40, securityAlertCount * 20)

        // Outdated dependencies: -5 per dep, max -15
        deductions += min(15, outdatedDependencyCount * 5)

        // Stale branches: -5 per branch, max -15
        deductions += min(15, staleBranchCount * 5)

        // Awaiting review: -5 per PR, max -15
        deductions += min(15, awaitingReviewCount * 5)

        return max(0, 100 - deductions)
    }
}

// MARK: - Health Issue

/// A specific health issue detected in a repository
public struct HealthIssue: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: HealthIssueType
    public let severity: HealthIssueSeverity
    public let title: String
    public let description: String
    public let affectedItem: String?
    public let url: URL?
    public let detectedAt: Date

    public init(
        id: String = UUID().uuidString,
        type: HealthIssueType,
        severity: HealthIssueSeverity,
        title: String,
        description: String,
        affectedItem: String? = nil,
        url: URL? = nil,
        detectedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.severity = severity
        self.title = title
        self.description = description
        self.affectedItem = affectedItem
        self.url = url
        self.detectedAt = detectedAt
    }
}

/// Types of health issues
public enum HealthIssueType: String, Sendable, CaseIterable {
    case stalePR = "stale_pr"
    case failingCI = "failing_ci"
    case blockedWork = "blocked_work"
    case securityAlert = "security_alert"
    case outdatedDependency = "outdated_dependency"
    case staleBranch = "stale_branch"
    case awaitingReview = "awaiting_review"
    case rateLimitWarning = "rate_limit_warning"
}

/// Severity levels for health issues
public enum HealthIssueSeverity: String, Sendable, Comparable {
    case info
    case warning
    case critical

    public static func < (lhs: HealthIssueSeverity, rhs: HealthIssueSeverity) -> Bool {
        let order: [Self: Int] = [.info: 0, .warning: 1, .critical: 2]
        return (order[lhs] ?? 0) < (order[rhs] ?? 0)
    }
}

// MARK: - Health Configuration

/// Configuration for health checks
public struct HealthCheckConfig: Sendable, Equatable {
    /// Days before a PR is considered stale
    public let stalePRThresholdDays: Int

    /// Failed CI runs before alert
    public let failingCIThreshold: Int

    /// Days before a branch is considered stale
    public let staleBranchThresholdDays: Int

    /// Days before a review is considered waiting too long
    public let reviewWaitThresholdDays: Int

    public init(
        stalePRThresholdDays: Int = 14,
        failingCIThreshold: Int = 3,
        staleBranchThresholdDays: Int = 30,
        reviewWaitThresholdDays: Int = 7
    ) {
        self.stalePRThresholdDays = stalePRThresholdDays
        self.failingCIThreshold = failingCIThreshold
        self.staleBranchThresholdDays = staleBranchThresholdDays
        self.reviewWaitThresholdDays = reviewWaitThresholdDays
    }

    /// Default configuration
    public static let `default` = HealthCheckConfig()
}

// MARK: - Repository Health Service

/// Service for calculating repository health
public actor RepositoryHealthService {
    private let config: HealthCheckConfig

    public init(config: HealthCheckConfig = .default) {
        self.config = config
    }

    /// Calculate health for a repository
    public func calculateHealth(
        for repository: Repository,
        pullRequests: [RepoPullRequestSummary],
        workflowRuns: [RepoWorkflowRunSummary],
        issues: [RepoIssueSummary] = []
    ) -> RepositoryHealth {
        var metrics = HealthMetrics()
        var issues: [HealthIssue] = []

        // Check stale PRs
        let stalePRs = pullRequests.filter { pr in
            guard pr.updatedAt != nil else { return false }
            let daysSinceUpdate = Calendar.current.dateComponents([.day], from: pr.updatedAt, to: Date()).day ?? 0
            return daysSinceUpdate > config.stalePRThresholdDays
        }

        if !stalePRs.isEmpty {
            metrics = HealthMetrics(
                stalePRCount: stalePRs.count,
                failingCIStreak: metrics.failingCIStreak,
                blockedWorkCount: metrics.blockedWorkCount,
                securityAlertCount: metrics.securityAlertCount,
                outdatedDependencyCount: metrics.outdatedDependencyCount,
                staleBranchCount: metrics.staleBranchCount,
                awaitingReviewCount: metrics.awaitingReviewCount
            )

            for pr in stalePRs.prefix(5) {
                let issue = HealthIssue(
                    type: .stalePR,
                    severity: .warning,
                    title: "Stale Pull Request",
                    description: "PR #\(pr.number) hasn't been updated in \(config.stalePRThresholdDays)+ days",
                    affectedItem: "PR #\(pr.number): \(pr.title)",
                    url: pr.url
                )
                issues.append(issue)
            }
        }

        // Check failing CI streak
        let failedRuns = workflowRuns.filter { $0.status == .failing || $0.conclusion == "failure" }
        if failedRuns.count >= config.failingCIThreshold {
            let failingCount = min(failedRuns.count, 10)
            metrics = HealthMetrics(
                stalePRCount: metrics.stalePRCount,
                failingCIStreak: failingCount,
                blockedWorkCount: metrics.blockedWorkCount,
                securityAlertCount: metrics.securityAlertCount,
                outdatedDependencyCount: metrics.outdatedDependencyCount,
                staleBranchCount: metrics.staleBranchCount,
                awaitingReviewCount: metrics.awaitingReviewCount
            )

            let latestFailed = failedRuns.first
            if let run = latestFailed {
                let severity: HealthIssueSeverity = run.status == .failing ? .warning : .critical
                let issue = HealthIssue(
                    type: .failingCI,
                    severity: severity,
                    title: "Failing CI Streak",
                    description: "\(failingCount) CI runs have failed in a row",
                    affectedItem: run.name,
                    url: run.url
                )
                issues.append(issue)
            }
        }

        // Check PRs awaiting review
        let awaitingReview = pullRequests.filter { pr in
            guard pr.updatedAt != nil else { return false }
            let daysSinceUpdate = Calendar.current.dateComponents([.day], from: pr.updatedAt, to: Date()).day ?? 0
            return daysSinceUpdate > config.reviewWaitThresholdDays && !pr.isDraft
        }

        if !awaitingReview.isEmpty {
            metrics = HealthMetrics(
                stalePRCount: metrics.stalePRCount,
                failingCIStreak: metrics.failingCIStreak,
                blockedWorkCount: metrics.blockedWorkCount,
                securityAlertCount: metrics.securityAlertCount,
                outdatedDependencyCount: metrics.outdatedDependencyCount,
                staleBranchCount: metrics.staleBranchCount,
                awaitingReviewCount: awaitingReview.count
            )

            for pr in awaitingReview.prefix(3) {
                let issue = HealthIssue(
                    type: .awaitingReview,
                    severity: .info,
                    title: "PR Awaiting Review",
                    description: "PR #\(pr.number) has been waiting for review for \(config.reviewWaitThresholdDays)+ days",
                    affectedItem: "PR #\(pr.number): \(pr.title)",
                    url: pr.url
                )
                issues.append(issue)
            }
        }

        let score = metrics.calculateScore()
        let severity: HealthIssueSeverity = score < 50 ? .critical : (score < 80 ? .warning : .info)
        let isHealthy = score >= 80

        // Add overall health issue if not healthy
        if !isHealthy {
            let overallIssue = HealthIssue(
                type: .failingCI, // Placeholder type
                severity: severity,
                title: "Repository Health: \(severity == .critical ? "Critical" : "Needs Attention")",
                description: "Repository health score is \(score)/100",
                affectedItem: repository.fullName
            )
            issues.append(overallIssue)
        }

        return RepositoryHealth(
            score: score,
            metrics: metrics,
            issues: issues
        )
    }
}
