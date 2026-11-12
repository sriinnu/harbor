import Foundation

/// One workflow of a repo, as `GET /actions/workflows` lists it.
public struct WorkflowInfo: Equatable, Sendable {
    public let id: Int
    /// "active", or "deleted", "disabled_manually", "disabled_inactivity", "disabled_fork".
    public let state: String

    public init(id: Int, state: String) {
        self.id = id
        self.state = state
    }
}

/// One workflow run, as `GET /actions/runs` lists it.
public struct WorkflowRunInfo: Equatable, Sendable {
    public let id: Int
    public let workflowID: Int
    /// "completed", "queued", "in_progress", "waiting", "requested", "pending".
    public let status: String
    public let createdAt: Date

    public init(id: Int, workflowID: Int, status: String, createdAt: Date) {
        self.id = id
        self.workflowID = workflowID
        self.status = status
        self.createdAt = createdAt
    }
}

/// Which old workflow runs "Clean up old runs" would delete. Pure: the panel lists, asks,
/// then deletes exactly what this returns.
public enum RunCleanup {
    /// Completed runs kept per listed workflow, newest first.
    public static let keepPerWorkflow = 5
    /// Pause between two deletes. GitHub asks for about a second between mutating requests.
    public static let pacing: Duration = .seconds(1)

    /// What a scan found: the ids to delete (oldest first) and why each group is there.
    public struct Plan: Equatable, Sendable {
        public let ids: [Int]
        /// Completed runs whose workflow is not in the repo's workflow list at all: deleted
        /// workflows, or ones the repo doesn't list (for example org-required workflows).
        public let unlistedWorkflowRuns: Int
        /// Completed runs beyond the newest `keepPerWorkflow` of a listed workflow (active or
        /// disabled).
        public let olderRuns: Int

        public init(ids: [Int], unlistedWorkflowRuns: Int, olderRuns: Int) {
            self.ids = ids
            self.unlistedWorkflowRuns = unlistedWorkflowRuns
            self.olderRuns = olderRuns
        }
    }

    /// Run ids to delete, oldest first. See `plan`.
    public static func select(workflows: [WorkflowInfo], runs: [WorkflowRunInfo]) -> [Int] {
        self.plan(workflows: workflows, runs: runs).ids
    }

    /// Completed runs beyond the newest `keepPerWorkflow` of every workflow, whatever its
    /// state and whether or not it is in `workflows`. A disabled workflow (GitHub disables
    /// quiet scheduled ones on its own) and an unlisted one (deleted, or org-required and so
    /// missing from the repo's list) both keep their latest runs: Harbor can't tell a deleted
    /// workflow from an org-required one, and deleting the only history of a live one is the
    /// worse mistake. The plan still counts how many selected runs belong to unlisted workflows.
    /// A run that is not completed (queued, in progress, waiting) is never selected.
    public static func plan(workflows: [WorkflowInfo], runs: [WorkflowRunInfo]) -> Plan {
        let listedIDs = Set(workflows.map(\.id))
        let completed = runs.filter { $0.status == "completed" }
        var unlisted: [WorkflowRunInfo] = []
        var older: [WorkflowRunInfo] = []
        for workflowID in Set(completed.map(\.workflowID)) {
            let beyond = completed.filter { $0.workflowID == workflowID }.sorted(by: Self.newerFirst)
                .dropFirst(self.keepPerWorkflow)
            if listedIDs.contains(workflowID) { older += beyond } else { unlisted += beyond }
        }
        let ids = (unlisted + older).sorted { Self.newerFirst($1, $0) }.map(\.id)
        return Plan(ids: ids, unlistedWorkflowRuns: unlisted.count, olderRuns: older.count)
    }

    private static func newerFirst(_ lhs: WorkflowRunInfo, _ rhs: WorkflowRunInfo) -> Bool {
        lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.id > rhs.id
    }

    /// "Delete 37 old runs, 12 of them from deleted or unlisted workflows? The newest 5 of
    /// every workflow stay. This can't be undone."
    public static func confirmation(plan: Plan) -> String {
        let total = plan.ids.count
        var head = "Delete \(total) old run\(total == 1 ? "" : "s")"
        if plan.unlistedWorkflowRuns > 0 {
            let of = total == plan.unlistedWorkflowRuns ? "all" : "\(plan.unlistedWorkflowRuns) of them"
            head += ", \(of) from deleted or unlisted workflows"
        }
        return head + "? The newest \(self.keepPerWorkflow) of every workflow stay. This can't be undone."
    }

    /// The row's tooltip.
    public static let help = "Delete finished runs beyond the newest \(keepPerWorkflow) of every workflow"

    /// What to tell the user when a delete fails with `status`. The runner reports rate
    /// limits as their own error, so a 403 that reaches here is a permission failure.
    public static func failureMessage(status: Int?, fallback: String) -> String {
        status == 403 ? "Harbor's token can't delete runs here" : fallback
    }

    /// "Rate limited, deleted 80 of 212, resumes after 14:05"
    public static func rateLimitedMessage(deleted: Int, total: Int, until: Date?, timeZone: TimeZone = .current) -> String {
        var text = "Rate limited, deleted \(deleted) of \(total)"
        if let until {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "HH:mm"
            text += ", resumes after \(formatter.string(from: until))"
        }
        return text
    }

    /// When a refused delete may be retried, or nil when the refusal is a permission failure.
    /// A rate limit is a 429, or a 403 with `Retry-After`, `X-RateLimit-Remaining: 0`, or a
    /// body that mentions the secondary rate limit (or "rate limit" at all).
    public static func rateLimitResume(
        status: Int,
        retryAfter: String?,
        remaining: String?,
        resetEpoch: String?,
        body: String,
        now: Date = Date()
    ) -> Date? {
        guard status == 403 || status == 429 else { return nil }
        let retrySeconds = retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) }
        let exhausted = remaining.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } == 0
        let mentioned = body.lowercased().contains("rate limit")
        guard status == 429 || retrySeconds != nil || exhausted || mentioned else { return nil }
        if let retrySeconds { return now.addingTimeInterval(retrySeconds) }
        if exhausted, let epoch = resetEpoch.flatMap({ TimeInterval($0) }) { return Date(timeIntervalSince1970: epoch) }
        return now.addingTimeInterval(60)
    }
}
