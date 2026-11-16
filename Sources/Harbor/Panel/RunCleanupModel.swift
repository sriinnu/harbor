import Foundation
import HarborCore
import Observation

/// "Clean up old runs" for one repo: scan, confirm with the exact count, then delete one
/// run at a time. Nothing is cached; closing the detail drops it.
@MainActor
@Observable
final class RunCleanupModel {
    enum Phase: Equatable {
        case idle
        case scanning
        case nothingToDelete
        case confirming(plan: RunCleanup.Plan)
        case deleting(done: Int, total: Int)
        case finished(deleted: Int)
        /// The user pressed Stop: the current delete finished, no further one started.
        case stopped(deleted: Int)
        /// Stopped on the first error; `deleted` runs were removed before it.
        case failed(deleted: Int, message: String)
        /// Stopped on a primary or secondary rate limit; `message` says how far it got and when
        /// deleting can resume.
        case rateLimited(message: String)
    }

    typealias PlanLoader = @Sendable (_ owner: String, _ name: String) async throws -> RunCleanup.Plan
    typealias Deleter = @Sendable (_ owner: String, _ name: String, _ id: Int) async throws -> Void

    private(set) var phase = Phase.idle
    /// Stop was pressed and the delete in flight is finishing; the next one will not start.
    private(set) var isStopping = false
    private var candidates: [Int] = []
    private var task: Task<Void, Never>?
    private let loadPlan: PlanLoader
    private let deleteRun: Deleter
    private let pacing: Duration

    /// The app's GitHub client by default; tests hand in their own loader, deleter and pacing.
    init(
        loadPlan: @escaping PlanLoader = { owner, name in
            guard let client = await MainActor.run(body: { RepoHealthService.client }) else { throw URLError(.userAuthenticationRequired) }
            return try await client.cleanupCandidates(owner: owner, name: name)
        },
        deleteRun: @escaping Deleter = { owner, name, id in
            guard let client = await MainActor.run(body: { RepoHealthService.client }) else { throw URLError(.userAuthenticationRequired) }
            try await client.deleteWorkflowRun(owner: owner, name: name, id: id)
        },
        pacing: Duration = RunCleanup.pacing
    ) {
        self.loadPlan = loadPlan
        self.deleteRun = deleteRun
        self.pacing = pacing
    }

    var isBusy: Bool {
        switch self.phase {
        case .scanning, .deleting: true
        default: false
        }
    }

    func scan(fullName: String) {
        guard !self.isBusy, let (owner, name) = Self.split(fullName) else { return }
        self.phase = .scanning
        let loadPlan = self.loadPlan
        self.task = Task {
            do {
                let plan = try await loadPlan(owner, name)
                guard !Task.isCancelled else { return }
                self.candidates = plan.ids
                self.phase = plan.ids.isEmpty ? .nothingToDelete : .confirming(plan: plan)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                self.phase = .failed(deleted: 0, message: Self.message(for: error))
            }
        }
    }

    func confirm(fullName: String) {
        guard case .confirming = self.phase, let (owner, name) = Self.split(fullName) else { return }
        let ids = self.candidates
        let deleteRun = self.deleteRun
        let pacing = self.pacing
        self.isStopping = false
        self.phase = .deleting(done: 0, total: ids.count)
        self.task = Task {
            var done = 0
            for id in ids {
                guard !Task.isCancelled else { return }
                if done > 0 {
                    try? await Task.sleep(for: pacing)
                    guard !Task.isCancelled else { return }
                }
                if self.isStopping {
                    self.finishStopped(deleted: done)
                    return
                }
                do {
                    try await deleteRun(owner, name, id)
                } catch {
                    guard !error.isCancellation, !Task.isCancelled else { return }
                    if case let GitHubAPIError.rateLimited(until, _) = error {
                        self.candidates = []
                        self.phase = .rateLimited(
                            message: RunCleanup.rateLimitedMessage(deleted: done, total: ids.count, until: until)
                        )
                        return
                    }
                    self.phase = .failed(deleted: done, message: Self.message(for: error))
                    return
                }
                done += 1
                guard !Task.isCancelled else { return }
                self.phase = .deleting(done: done, total: ids.count)
            }
            guard !Task.isCancelled else { return }
            self.candidates = []
            self.phase = .finished(deleted: done)
        }
    }

    /// Stop after the delete in flight: that request is never abandoned half-sent, and the row
    /// then says how many runs were removed.
    func stop() {
        guard case .deleting = self.phase else { return }
        self.isStopping = true
    }

    private func finishStopped(deleted: Int) {
        self.candidates = []
        self.isStopping = false
        self.phase = .stopped(deleted: deleted)
    }

    /// Back to the plain row. A running delete stops before its next run.
    func dismiss() {
        self.task?.cancel()
        self.task = nil
        self.candidates = []
        self.isStopping = false
        self.phase = .idle
    }

    /// The row left the screen (the detail closed, the panel went away): nothing is watching
    /// any more, so a scan or delete still running is cancelled before its next request.
    func viewDisappeared() {
        if self.isBusy { self.dismiss() }
    }

    private static func split(_ fullName: String) -> (String, String)? {
        let parts = fullName.split(separator: "/").map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private static func message(for error: Error) -> String {
        var status: Int?
        if case let GitHubAPIError.badStatus(code, _) = error { status = code }
        return RunCleanup.failureMessage(status: status, fallback: error.userFacingMessage)
    }
}
