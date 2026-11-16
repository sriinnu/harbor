import Foundation
@testable import HarborCore
import Synchronization
import Testing

struct InflightCoalescerTests {
    private final class Gate: Sendable {
        let runs = Atomic<Int>(0)
    }

    @Test
    func identicalCallsInFlight_shareOneRun() async throws {
        let coalescer = InflightCoalescer<String, Int>()
        let gate = Gate()
        let release = AsyncStream<Void>.makeStream()
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    try await coalescer.run(key: "k") {
                        gate.runs.add(1, ordering: .sequentiallyConsistent)
                        for await _ in release.stream { break }
                        return 42
                    }
                }
            }
            // Let all five reach the coalescer, then let the single run finish.
            while await coalescer.activeCount == 0 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(100))
            release.continuation.yield()
            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }
        #expect(results == [42, 42, 42, 42, 42])
        #expect(gate.runs.load(ordering: .sequentiallyConsistent) == 1)
    }

    @Test
    func aCallAfterCompletion_runsAgain_nothingIsStored() async throws {
        let coalescer = InflightCoalescer<String, Int>()
        let gate = Gate()
        for expected in 1 ... 3 {
            let value = try await coalescer.run(key: "k") { gate.runs.add(1, ordering: .sequentiallyConsistent).newValue }
            #expect(value == expected)
        }
        #expect(gate.runs.load(ordering: .sequentiallyConsistent) == 3)
        #expect(await coalescer.activeCount == 0)
    }

    @Test
    func differentKeys_doNotShare() async throws {
        let coalescer = InflightCoalescer<String, String>()
        async let first = coalescer.run(key: "a") { "A" }
        async let second = coalescer.run(key: "b") { "B" }
        #expect(try await [first, second] == ["A", "B"])
    }

    @Test
    func aFailure_reachesTheCaller_andClearsTheEntry() async {
        struct Boom: Error {}
        let coalescer = InflightCoalescer<String, Int>()
        await #expect(throws: Boom.self) { try await coalescer.run(key: "k") { throw Boom() } }
        #expect(await coalescer.activeCount == 0)
        #expect((try? await coalescer.run(key: "k") { 7 }) == 7)
    }
}
