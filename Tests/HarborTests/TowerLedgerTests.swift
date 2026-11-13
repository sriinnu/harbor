import Foundation
@testable import HarborCore
import Testing

struct TowerLedgerTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func line(
        _ event: String, agent: String = "claude-code", worktree: String = "/w/a", repo: String? = "/r",
        session: String = "s1", branch: String? = nil, task: String? = nil, pid: Int? = nil, host: String? = nil,
        ts: String = "2026-11-10T10:00:00+01:00", data: String = "{}"
    ) -> String {
        let fields = [
            "\"event\":\"\(event)\"", "\"agent\":\"\(agent)\"", "\"worktree\":\"\(worktree)\"",
            "\"session\":\"\(session)\"", "\"ts\":\"\(ts)\"", "\"data\":\(data)",
            "\"branch\":\(branch.map { "\"\($0)\"" } ?? "null")", "\"task\":\(task.map { "\"\($0)\"" } ?? "null")",
            "\"repo\":\(repo.map { "\"\($0)\"" } ?? "null")"
        ] + [pid.map { "\"pid\":\($0)" }, host.map { "\"host\":\"\($0)\"" }].compactMap { $0 }
        return "{" + fields.joined(separator: ",") + "}"
    }

    // MARK: - replay, every event type, exact state

    @Test
    func replay_bornJoinedBuildDeliveredFlaggedAdvice_exactState() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", branch: "feat/x", task: "t-1", ts: "2026-11-10T10:00:00+01:00",
                 data: #"{"purpose":"fix it"}"#),
            line("worktree.joined", pid: 42, host: "h1", ts: "2026-11-10T10:01:00+01:00"),
            line("build.recorded", ts: "2026-11-10T10:02:00+01:00", data: #"{"status":"failed","version":"1.2.3-dev.abc"}"#),
            line("build.recorded", ts: "2026-11-10T10:03:00+01:00", data: #"{"status":"ok","version":"1.2.3-dev.def"}"#),
            line("worktree.flagged", ts: "2026-11-10T10:04:00+01:00", data: #"{"reason":"build-cleanup"}"#),
            line("audit.advice", ts: "2026-11-10T10:05:00+01:00",
                 data: #"{"decision":"archive","abandoned":{"score":1.5,"normalized":0.5}}"#),
            line("task.delivered", ts: "2026-11-10T10:06:00+01:00", data: #"{"sha":"0123456789abcdef","base":"origin/main"}"#)
        ])
        let expected = LedgerWorktree(
            path: "/w/a", repo: "/r", agent: "claude", task: "t-1", branch: "feat/x", note: "fix it",
            live: ["claude-code:s1"],
            sessions: ["claude-code:s1": LedgerSession(pid: 42, host: "h1", since: date("2026-11-10T10:01:00+01:00"))],
            build: LedgerBuild(status: "ok", version: "1.2.3-dev.def", date: date("2026-11-10T10:03:00+01:00")),
            delivered: LedgerDelivery(sha: "0123456789abcdef", base: "origin/main", date: date("2026-11-10T10:06:00+01:00")),
            flagged: "build-cleanup",
            advice: LedgerAdvice(decision: "archive", abandoned: 0.5),
            lastEvent: date("2026-11-10T10:06:00+01:00"),
            timeline: [
                LedgerTimelineEntry(date: date("2026-11-10T10:00:00+01:00"), event: "worktree.born", agent: "claude", text: "born for t-1"),
                LedgerTimelineEntry(date: date("2026-11-10T10:01:00+01:00"), event: "worktree.joined", agent: "claude", text: "joined"),
                LedgerTimelineEntry(date: date("2026-11-10T10:02:00+01:00"), event: "build.recorded", agent: "claude", text: "build failed"),
                LedgerTimelineEntry(date: date("2026-11-10T10:03:00+01:00"), event: "build.recorded", agent: "claude", text: "build ok"),
                LedgerTimelineEntry(date: date("2026-11-10T10:04:00+01:00"), event: "worktree.flagged", agent: "claude", text: "flagged: build-cleanup"),
                LedgerTimelineEntry(date: date("2026-11-10T10:05:00+01:00"), event: "audit.advice", agent: "claude", text: "advice: archive"),
                LedgerTimelineEntry(date: date("2026-11-10T10:06:00+01:00"), event: "task.delivered", agent: "claude", text: "delivered 0123456")
            ]
        )
        #expect(rows["/w/a"] == expected)
    }

    @Test
    func replay_leftRemovesTheSessionAndRecordsTimeline() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", ts: "2026-11-10T10:00:00+01:00"),
            line("worktree.joined", pid: 7, host: "h", ts: "2026-11-10T10:01:00+01:00"),
            line("worktree.left", ts: "2026-11-10T10:02:00+01:00", data: #"{"key":"claude-code:s1"}"#)
        ])
        let row = rows["/w/a"]
        #expect(row?.live == [])
        #expect(row?.sessions == [:])
        #expect(row?.timeline.map(\.text) == ["born", "joined", "left"])
        #expect(row?.lastEvent == date("2026-11-10T10:02:00+01:00"))
    }

    @Test
    func replay_deliveredCreatesTheRowAndKeepsItsTask() {
        let rows = AgentLedger.replay(lines: [
            line("task.delivered", agent: "codex", task: "t-9", data: #"{"sha":"abc","base":"origin/main"}"#)
        ])
        #expect(rows["/w/a"] == LedgerWorktree(
            path: "/w/a", repo: "/r", agent: "codex", task: "t-9",
            delivered: LedgerDelivery(sha: "abc", base: "origin/main", date: date("2026-11-10T10:00:00+01:00")),
            lastEvent: date("2026-11-10T10:00:00+01:00"),
            timeline: [LedgerTimelineEntry(date: date("2026-11-10T10:00:00+01:00"), event: "task.delivered", agent: "codex", text: "delivered abc")]
        ))
    }

    @Test
    func replay_flaggedAdviceAndBuildNeverCreateARow() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.flagged", data: #"{"reason":"idle"}"#),
            line("audit.advice", worktree: "/w/b", data: #"{"decision":"keep_working"}"#),
            line("build.recorded", worktree: "/w/c", data: #"{"status":"ok"}"#)
        ])
        #expect(rows.isEmpty)
    }

    @Test
    func replay_retiredDropsTheTimelineToo() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", task: "t"), line("task.retired"), line("worktree.born", agent: "codex")
        ])
        #expect(rows["/w/a"]?.timeline.map(\.text) == ["born"])
        #expect(rows["/w/a"]?.agent == "codex")
    }

    @Test
    func replay_timelineKeepsTheNewestEntries() {
        var lines = [line("worktree.born")]
        for index in 0 ..< (LedgerWorktree.maxTimeline + 5) {
            lines.append(line("worktree.noted", data: "{\"note\":\"n\(index)\"}"))
        }
        let row = AgentLedger.replay(lines: lines)["/w/a"]
        #expect(row?.timeline.count == LedgerWorktree.maxTimeline)
        #expect(row?.timeline.last?.text == "noted: n\(LedgerWorktree.maxTimeline + 4)")
    }

    @Test
    func replay_readsEveryTimestampForm() {
        func last(_ ts: String) -> Date? {
            AgentLedger.replay(lines: [line("worktree.born", ts: ts)])["/w/a"]?.lastEvent
        }
        #expect(last("2026-11-10T09:00:00Z") == Date(timeIntervalSince1970: 1_794_301_200))
        #expect(last("2026-11-10T10:00:00+01:00") == Date(timeIntervalSince1970: 1_794_301_200))
        #expect(last("2026-11-10T10:00:00+0100") == Date(timeIntervalSince1970: 1_794_301_200))
        #expect(last("2026-11-10T10:00:00.500+01:00") == Date(timeIntervalSince1970: 1_794_301_200.5))
        #expect(last("yesterday") == nil)
    }

    // MARK: - streaming and offsets

    @Test
    func streaming_readsEverythingInSmallChunksAndHoldsBackAPartialLine() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        let first = line("worktree.born", worktree: "/w/a", data: #"{"purpose":"one"}"#)
        let second = line("worktree.born", worktree: "/w/b", data: #"{"purpose":"two"}"#)
        let third = line("worktree.born", worktree: "/w/c", data: #"{"purpose":"three"}"#)
        // The third line has no newline yet.
        try (first + "\n" + second + "\n" + third).write(to: file, atomically: true, encoding: .utf8)

        var replayer = LedgerReplayer()
        let offset = try #require(AgentLedger.replay(file: file, into: &replayer, chunkSize: 16))
        #expect(offset == UInt64((first + "\n" + second + "\n").utf8.count))
        #expect(Set(replayer.state.keys) == ["/w/a", "/w/b"])

        // The writer finishes the line; reading from the cursor picks it up exactly once.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n".utf8))
        try handle.close()
        let end = try #require(AgentLedger.replay(file: file, from: offset, into: &replayer, chunkSize: 16))
        #expect(end == UInt64((first + "\n" + second + "\n" + third + "\n").utf8.count))
        #expect(replayer.state["/w/c"]?.note == "three")
        #expect(replayer.state.count == 3)
    }

    @Test
    func streaming_readsPastTheOldFourMegabyteWindow() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        // The birth is first; padding after it pushes it out of a 4 MB tail.
        let pad = line("worktree.noted", worktree: "/w/pad", data: "{\"note\":\"\(String(repeating: "x", count: 4000))\"}")
        let body = line("worktree.born", data: #"{"purpose":"oldest"}"#) + "\n"
            + Array(repeating: pad, count: 1100).joined(separator: "\n") + "\n"
        try body.write(to: file, atomically: true, encoding: .utf8)
        #expect(body.utf8.count > 4 * 1024 * 1024)
        #expect(AgentLedger.replay(lines: AgentLedger.tailLines(of: file))["/w/a"] == nil)
        #expect(AgentLedger.replayAll(file: file)["/w/a"]?.note == "oldest")
    }

    @Test
    func tail_followsAppendsFromTheCursorAndSurvivesReplacement() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        let first = line("worktree.born", worktree: "/w/a", data: #"{"purpose":"one"}"#) + "\n"
        try first.write(to: file, atomically: true, encoding: .utf8)

        let tail = LedgerTail(url: file)
        tail.start {}
        defer { tail.stop() }
        #expect(tail.snapshot()["/w/a"]?.note == "one")
        #expect(tail.cursor == UInt64(first.utf8.count))

        // A half-written line moves nothing.
        let second = line("worktree.born", worktree: "/w/b", data: #"{"purpose":"two"}"#)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(second.prefix(20).utf8))
        try await Task.sleep(for: .milliseconds(300))
        #expect(tail.snapshot()["/w/b"] == nil)
        #expect(tail.cursor == UInt64(first.utf8.count))
        // The rest of it, and a newline.
        try handle.write(contentsOf: Data((String(second.dropFirst(20)) + "\n").utf8))
        try handle.close()
        try await Self.until { tail.snapshot()["/w/b"]?.note == "two" }
        #expect(tail.cursor == UInt64((first + second + "\n").utf8.count))

        // Replaced by a new file (atomic write renames over the old inode): replayed from zero.
        let replacement = line("worktree.born", worktree: "/w/z", data: #"{"purpose":"fresh"}"#) + "\n"
        try replacement.write(to: file, atomically: true, encoding: .utf8)
        try await Self.until { tail.snapshot()["/w/z"]?.note == "fresh" }
        #expect(tail.snapshot()["/w/a"] == nil)
        #expect(tail.cursor == UInt64(replacement.utf8.count))
    }

    private static func until(timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "tower", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - liveness

    private struct FakeProbe: ProcessProbe {
        let alive: Set<Int>
        func isAlive(pid: Int) -> Bool { self.alive.contains(pid) }
    }

    private func row(pid: Int?, host: String?, since: String = "2026-11-10T10:00:00+01:00") -> LedgerWorktree {
        LedgerWorktree(
            path: "/w/a", live: ["a:s"],
            sessions: ["a:s": LedgerSession(pid: pid, host: host, since: date(since))],
            lastEvent: date(since)
        )
    }

    @Test
    func liveness_runningPidOnThisHostProvesIt() {
        let now = date("2026-11-12T10:00:00+01:00") // two days later: the window alone would say no
        let evidence = LedgerLiveness.evidence(for: row(pid: 42, host: "h"), host: "h", now: now, probe: FakeProbe(alive: [42]))
        #expect(evidence == .pid(42))
    }

    @Test
    func liveness_deadPidFallsBackToTheWindow() {
        let soon = date("2026-11-10T12:00:00+01:00")
        let late = date("2026-11-12T10:00:00+01:00")
        let probe = FakeProbe(alive: [])
        #expect(LedgerLiveness.evidence(for: row(pid: 42, host: "h"), host: "h", now: soon, probe: probe) == .window)
        #expect(LedgerLiveness.evidence(for: row(pid: 42, host: "h"), host: "h", now: late, probe: probe) == nil)
    }

    @Test
    func liveness_otherHostPidIsNeverProbed() {
        let probe = FakeProbe(alive: [42])
        let now = date("2026-11-10T12:00:00+01:00")
        #expect(LedgerLiveness.evidence(for: row(pid: 42, host: "elsewhere"), host: "h", now: now, probe: probe) == .window)
        #expect(LedgerLiveness.evidence(for: row(pid: 42, host: "elsewhere"), host: "h",
                                        now: date("2026-11-12T10:00:00+01:00"), probe: probe) == nil)
    }

    @Test
    func liveness_noPidUsesTheWindowAndNoSessionIsNeverLive() {
        let probe = FakeProbe(alive: [])
        #expect(LedgerLiveness.evidence(for: row(pid: nil, host: nil), host: "h",
                                        now: date("2026-11-10T11:00:00+01:00"), probe: probe) == .window)
        #expect(LedgerLiveness.evidence(for: row(pid: nil, host: nil), host: "h",
                                        now: date("2026-11-11T10:00:00+01:00"), probe: probe) == nil) // exactly 24h
        #expect(LedgerLiveness.evidence(for: LedgerWorktree(path: "/w/a"), host: "h", probe: probe) == nil)
    }

    @Test
    func systemProbe_seesThisProcessAndNotAnExitedOne() throws {
        let probe = SystemProcessProbe()
        #expect(probe.isAlive(pid: Int(ProcessInfo.processInfo.processIdentifier)))
        #expect(probe.isAlive(pid: 0) == false)
        #expect(probe.isAlive(pid: -5) == false)
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try child.run()
        child.waitUntilExit()
        #expect(probe.isAlive(pid: Int(child.processIdentifier)) == false)
    }
}
