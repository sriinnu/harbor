import Foundation
@testable import Harbor
import HarborCore
import Testing

/// Run cleanup's Stop, cancel and failure paths, through a model whose GitHub calls are stand-ins.
@MainActor
struct RunCleanupModelTests {
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var ids: [Int] = []
        var deleted: [Int] { self.lock.withLock { self.ids } }
        func record(_ id: Int) { self.lock.withLock { self.ids.append(id) } }
    }

    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var open = false
        func wait() async {
            await withCheckedContinuation { continuation in
                let go = self.lock.withLock { () -> Bool in
                    if self.open { return true }
                    self.waiting.append(continuation)
                    return false
                }
                if go { continuation.resume() }
            }
        }
        func release() {
            let pending = self.lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                self.open = true
                defer { self.waiting = [] }
                return self.waiting
            }
            pending.forEach { $0.resume() }
        }
    }

    private nonisolated static let plan = RunCleanup.Plan(ids: [1, 2, 3, 4, 5], unlistedWorkflowRuns: 0, olderRuns: 5)

    private func model(
        deleting: @escaping RunCleanupModel.Deleter
    ) -> RunCleanupModel {
        RunCleanupModel(loadPlan: { _, _ in Self.plan }, deleteRun: deleting, pacing: .milliseconds(1))
    }

    private func wait(_ model: RunCleanupModel, until condition: (RunCleanupModel.Phase) -> Bool) async {
        for _ in 0 ..< 1000 where !condition(model.phase) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    private func confirmed(_ model: RunCleanupModel) async {
        model.scan(fullName: "o/r")
        await self.wait(model) { if case .confirming = $0 { true } else { false } }
        model.confirm(fullName: "o/r")
    }

    @Test
    func aCompleteRunDeletesEveryCandidateAndSaysSo() async {
        let recorder = Recorder()
        let model = self.model { _, _, id in recorder.record(id) }
        await self.confirmed(model)
        await self.wait(model) { $0 == .finished(deleted: 5) }
        #expect(model.phase == .finished(deleted: 5))
        #expect(recorder.deleted == [1, 2, 3, 4, 5])
    }

    @Test
    func stop_letsTheDeleteInFlightFinishThenStartsNoMore() async {
        let recorder = Recorder()
        let gate = Gate()
        let model = self.model { _, _, id in
            recorder.record(id)
            if id == 2 { await gate.wait() }
        }
        await self.confirmed(model)
        await self.wait(model) { $0 == .deleting(done: 1, total: 5) }
        // Run 2 is in flight (held at the gate). Stop now.
        for _ in 0 ..< 1000 where recorder.deleted.count < 2 { try? await Task.sleep(for: .milliseconds(5)) }
        model.stop()
        #expect(model.isStopping)
        gate.release()
        await self.wait(model) { if case .stopped = $0 { true } else { false } }
        #expect(model.phase == .stopped(deleted: 2))
        #expect(model.isStopping == false)
        #expect(recorder.deleted == [1, 2])
    }

    @Test
    func stop_isIgnoredWhenNothingIsDeleting() {
        let model = self.model { _, _, _ in }
        model.stop()
        #expect(model.isStopping == false)
        #expect(model.phase == .idle)
    }

    @Test
    func theRowDisappearingCancelsTheRestOfTheDeletes() async {
        let recorder = Recorder()
        let gate = Gate()
        let model = self.model { _, _, id in
            recorder.record(id)
            if id == 1 { await gate.wait() }
        }
        await self.confirmed(model)
        for _ in 0 ..< 1000 where recorder.deleted.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        model.viewDisappeared()
        #expect(model.phase == .idle)
        gate.release()
        try? await Task.sleep(for: .milliseconds(200))
        #expect(recorder.deleted == [1])
        #expect(model.phase == .idle)
    }

    @Test
    func disappearingWhileOnlyConfirmingChangesNothing() async {
        let model = self.model { _, _, _ in }
        model.scan(fullName: "o/r")
        await self.wait(model) { if case .confirming = $0 { true } else { false } }
        model.viewDisappeared()
        #expect(model.phase == .confirming(plan: Self.plan))
    }

    @Test
    func aFailureStopsTheRunAndIsShownInTheRow() async {
        let recorder = Recorder()
        let model = self.model { _, _, id in
            recorder.record(id)
            if id == 3 { throw GitHubAPIError.badStatus(code: 403, message: "Forbidden") }
        }
        await self.confirmed(model)
        await self.wait(model) { if case .failed = $0 { true } else { false } }
        guard case let .failed(deleted, message) = model.phase else {
            Issue.record("expected a failure, got \(model.phase)")
            return
        }
        #expect(deleted == 2)
        #expect(message == RunCleanup.failureMessage(status: 403, fallback: ""))
        #expect(recorder.deleted == [1, 2, 3])
    }

    @Test
    func aRateLimitStopsTheRunWithHowFarItGot() async {
        let until = Date(timeIntervalSince1970: 1_700_000_000)
        let model = self.model { _, _, id in
            if id == 2 { throw GitHubAPIError.rateLimited(until: until, message: "limited") }
        }
        await self.confirmed(model)
        await self.wait(model) { if case .rateLimited = $0 { true } else { false } }
        #expect(model.phase == .rateLimited(message: RunCleanup.rateLimitedMessage(deleted: 1, total: 5, until: until)))
    }

    @Test
    func pins_theCleanupPinHasOneNameSoThePanelCanRespectIt() {
        #expect(PanelPin.runCleanup == "run-cleanup")
    }
}
