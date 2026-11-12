@testable import HarborCore
import Foundation
import Testing

/// A superseded refresh ends in `URLError.cancelled`, whose description is the bare word
/// "cancelled". That must never become text the user sees.
struct CancellationNeverSurfacedTests {
    @Test
    func accumulator_ignoresURLErrorCancelled() {
        var accumulator = RepoErrorAccumulator()
        accumulator.absorb(URLError(.cancelled))
        accumulator.absorb(CancellationError())
        #expect(accumulator.message == nil)
        #expect(accumulator.messages.isEmpty)
    }

    @Test
    func accumulator_stillReportsRealErrors() {
        var accumulator = RepoErrorAccumulator()
        accumulator.absorb(URLError(.cancelled))
        accumulator.absorb(URLError(.timedOut))
        #expect(accumulator.messages == ["Request timed out."])
    }

    @Test
    func reportableMessage_isNilForEveryFormOfCancellation() {
        let bridged = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        #expect((URLError(.cancelled) as Error).reportableMessage == nil)
        #expect((CancellationError() as Error).reportableMessage == nil)
        #expect((bridged as Error).reportableMessage == nil)
        #expect((URLError(.timedOut) as Error).reportableMessage == "Request timed out.")
    }
}
