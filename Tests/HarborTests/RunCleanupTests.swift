import Foundation
@testable import HarborCore
import Testing

struct RunCleanupTests {
    private func run(_ id: Int, workflow: Int, _ status: String = "completed") -> WorkflowRunInfo {
        // A later id is a later run.
        WorkflowRunInfo(id: id, workflowID: workflow, status: status, createdAt: Date(timeIntervalSince1970: TimeInterval(id) * 60))
    }

    private let active = WorkflowInfo(id: 1, state: "active")

    @Test
    func keepsTheNewestFivePerActiveWorkflowAndSelectsTheRestOldestFirst() {
        // Listed newest first, as GitHub returns them.
        let runs = (1 ... 8).reversed().map { self.run($0, workflow: 1) }
        #expect(RunCleanup.select(workflows: [self.active], runs: runs) == [1, 2, 3])
    }

    @Test
    func fiveOrFewerCompletedRunsSelectNothing() {
        let runs = (1 ... 5).map { self.run($0, workflow: 1) }
        #expect(RunCleanup.select(workflows: [self.active], runs: runs) == [])
    }

    @Test
    func theLimitIsPerWorkflow() {
        let second = WorkflowInfo(id: 2, state: "active")
        let runs = (1 ... 7).map { self.run($0, workflow: 1) } + (11 ... 13).map { self.run($0, workflow: 2) }
        #expect(RunCleanup.select(workflows: [self.active, second], runs: runs) == [1, 2])
    }

    @Test
    func aRunThatIsNotCompletedIsNeverSelectedAndDoesNotUseUpAKeepSlot() {
        // Run 1 is the oldest and still going. Completed runs 2...7: keep 3...7, select 2.
        let runs = [self.run(1, workflow: 1, "in_progress")] + (2 ... 7).map { self.run($0, workflow: 1) }
        #expect(RunCleanup.select(workflows: [self.active], runs: runs) == [2])
        for status in ["queued", "in_progress", "waiting", "requested", "pending"] {
            let only = [self.run(1, workflow: 1, status)] + (2 ... 7).map { self.run($0, workflow: 1) }
            #expect(!RunCleanup.select(workflows: [self.active], runs: only).contains(1), "\(status)")
        }
    }

    @Test
    func anUnlistedWorkflowKeepsItsNewestFiveAndUnfinishedRunsAreNeverSelected() {
        // Workflow 9 is not in the list: deleted, or org-required. Either way its newest 5 stay.
        let runs = (1 ... 8).map { self.run($0, workflow: 9) }
            + [self.run(20, workflow: 9, "in_progress"), self.run(21, workflow: 9, "queued")]
        #expect(RunCleanup.select(workflows: [self.active], runs: runs) == [1, 2, 3])
    }

    @Test
    func aDisabledWorkflowKeepsItsNewestFiveLikeAnActiveOne() {
        for state in ["disabled_manually", "disabled_inactivity", "disabled_fork"] {
            let workflows = [WorkflowInfo(id: 3, state: state)]
            let runs = (1 ... 8).map { self.run($0, workflow: 3) }
            #expect(RunCleanup.select(workflows: workflows, runs: runs) == [1, 2, 3], "\(state)")
        }
    }

    @Test
    func planSeparatesUnlistedWorkflowRunsFromOlderRuns() {
        let workflows = [self.active, WorkflowInfo(id: 3, state: "disabled_inactivity")]
        let runs = (1 ... 7).map { self.run($0, workflow: 1) } + (11 ... 17).map { self.run($0, workflow: 3) }
            + (21 ... 27).map { self.run($0, workflow: 9) }
        let plan = RunCleanup.plan(workflows: workflows, runs: runs)
        #expect(plan == RunCleanup.Plan(ids: [1, 2, 11, 12, 21, 22], unlistedWorkflowRuns: 2, olderRuns: 4))
    }

    @Test
    func equalTimestampsBreakTiesByRunId() {
        let at = Date(timeIntervalSince1970: 0)
        let runs = (1 ... 6).map { WorkflowRunInfo(id: $0, workflowID: 1, status: "completed", createdAt: at) }
        #expect(RunCleanup.select(workflows: [self.active], runs: runs) == [1])
    }

    @Test
    func wordsForTheConfirmAndTheForbiddenCase() {
        let both = RunCleanup.Plan(ids: Array(1 ... 37), unlistedWorkflowRuns: 12, olderRuns: 25)
        #expect(RunCleanup.confirmation(plan: both) ==
            "Delete 37 old runs, 12 of them from deleted or unlisted workflows? The newest 5 of every workflow stay. This can't be undone.")
        let one = RunCleanup.Plan(ids: [1], unlistedWorkflowRuns: 0, olderRuns: 1)
        #expect(RunCleanup.confirmation(plan: one) == "Delete 1 old run? The newest 5 of every workflow stay. This can't be undone.")
        let gone = RunCleanup.Plan(ids: [1, 2], unlistedWorkflowRuns: 2, olderRuns: 0)
        #expect(RunCleanup.confirmation(plan: gone) ==
            "Delete 2 old runs, all from deleted or unlisted workflows? The newest 5 of every workflow stay. This can't be undone.")
        #expect(RunCleanup.help == "Delete finished runs beyond the newest 5 of every workflow")
        #expect(RunCleanup.failureMessage(status: 403, fallback: "Forbidden") == "Harbor's token can't delete runs here")
        #expect(RunCleanup.failureMessage(status: 500, fallback: "Server error") == "Server error")
        #expect(RunCleanup.failureMessage(status: nil, fallback: "Offline") == "Offline")
    }

    @Test
    func rateLimitedMessageNamesProgressAndResumeTime() {
        let utc = TimeZone(identifier: "UTC")!
        let until = Date(timeIntervalSince1970: 1_700_000_000) // 22:13:20 UTC
        #expect(RunCleanup.rateLimitedMessage(deleted: 80, total: 212, until: until, timeZone: utc) ==
            "Rate limited, deleted 80 of 212, resumes after 22:13")
        #expect(RunCleanup.rateLimitedMessage(deleted: 0, total: 5, until: nil, timeZone: utc) == "Rate limited, deleted 0 of 5")
    }

    @Test
    func aForbiddenDeleteIsARateLimitOnlyWhenGitHubSaysSo() {
        let now = Date(timeIntervalSince1970: 1000)
        func resume(
            _ status: Int = 403, retry: String? = nil, remaining: String? = nil, reset: String? = nil, body: String = ""
        ) -> Date? {
            RunCleanup.rateLimitResume(
                status: status, retryAfter: retry, remaining: remaining, resetEpoch: reset, body: body, now: now
            )
        }
        // Plain permission failure, even with quota left.
        #expect(resume(body: #"{"message":"Resource not accessible by integration"}"#) == nil)
        #expect(resume(remaining: "4000", reset: "5000") == nil)
        #expect(resume(404, remaining: "0") == nil)
        // Secondary limit: Retry-After, or the body.
        #expect(resume(retry: "30") == Date(timeIntervalSince1970: 1030))
        #expect(resume(body: "You have exceeded a secondary rate limit.") == Date(timeIntervalSince1970: 1060))
        // Primary limit: no quota left, reset header wins.
        #expect(resume(remaining: "0", reset: "5000") == Date(timeIntervalSince1970: 5000))
        #expect(resume(429) == Date(timeIntervalSince1970: 1060))
    }
}
