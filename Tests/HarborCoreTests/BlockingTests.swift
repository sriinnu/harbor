import Foundation
@testable import HarborCore
import Testing

@Suite(.serialized)
struct BlockingTests {
    /// The bug this guards: Tower and the local repo refresh ran blocking git inside
    /// `Task.detached`, on the cooperative pool. With the pool full of waiting work, the next scan
    /// (and every timeout behind it) did not start until something else let go.
    @Test
    func blockingWorkStartsAtOnceWhileThePoolIsFull() async {
        let width = ProcessInfo.processInfo.activeProcessorCount * 2
        let gate = DispatchSemaphore(value: 0)
        // Let the blockers go after 3 s from a plain thread, so the test can't hang for good.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 3)
            for _ in 0 ..< width { gate.signal() }
        }
        let blockers = (0 ..< width).map { _ in Task.detached(priority: .userInitiated) { hold(gate) } }
        // Give the blockers a moment to take every pool thread. No await here: resuming from one
        // would itself need a pool thread, and the test would only go on once the gate opened.
        pause(0.3)

        let asked = Date()
        // The work itself lets the blockers go, so fixed code holds the pool for ~0.3 s; the 3 s
        // thread above is only the fallback that lets broken code fail instead of hanging.
        let ran = await Blocking.run {
            let now = Date()
            for _ in 0 ..< width { gate.signal() }
            return now
        }
        for blocker in blockers { await blocker.value }

        #expect(ran.timeIntervalSince(asked) < 1)
    }

    @Test
    func returnsTheValueOfTheWork() async {
        #expect(await Blocking.run { 6 * 7 } == 42)
    }
}

/// A plain (non-async) wait, so a test can deliberately hold a pool thread.
private func hold(_ gate: DispatchSemaphore) { gate.wait() }

private func pause(_ seconds: TimeInterval) { Thread.sleep(forTimeInterval: seconds) }
