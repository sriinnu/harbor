import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// Tower without the private ledger: agents from path conventions, liveness from the process
/// table, and "waiting on you" from an event or an honest guess. Git fixtures run without the
/// developer's config; nothing here reads the real home folder or the real ledger. Nothing runs
/// on the main actor.
struct TowerNoLedgerTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    /// A probe that says which processes are inside which worktree.
    private struct FakeProcesses: ProcessProbe {
        var inside: [String: ProcessInside]
        func isAlive(pid _: Int) -> Bool { false }
        func processes(inside worktrees: [String]) -> [String: ProcessInside] {
            self.inside.filter { worktrees.contains($0.key) }
        }
    }

    // MARK: - agent from path

    @Test
    func agentFromPath_everyKnownConvention() {
        let home = "/Users/u"
        let cases: [(String, String?)] = [
            ("/Users/u/.codex/worktrees/a1b2/app", "codex"),
            ("/Users/u/Projects/app/.claude/worktrees/fix-x", "claude"),
            ("/Users/u/.cursor/worktrees/app/abc", "cursor"),
            ("/Users/u/Projects/app/.qwen/worktrees/t1", "qwen"),
            ("/Users/u/.ribhu/worktrees/key9/fork-2", "ribhu"),
            ("/Users/u/.local/share/opencode/worktree/proj123/bright-owl", "opencode"),
            ("/Users/u/Projects/app.worktrees/feature-y", "vscode"),
            ("/Users/u/.worktrees/harbor-x", nil),
            ("/Users/u/Projects/app", nil),
            // A repo that is merely named like the convention is not the convention.
            ("/Users/u/Projects/app.worktrees", nil)
        ]
        for (path, agent) in cases {
            #expect(AgentWorktrees.agentFromPath(path, home: home) == agent, "\(path)")
        }
        #expect(AgentWorktrees.normalizedAgent("opencode-cli") == "opencode")
    }

    // MARK: - agent.waiting

    private func line(_ event: String, agent: String = "claude-code", session: String = "s1", ts: String, data: String = "{}") -> String {
        #"{"event":"\#(event)","agent":"\#(agent)","worktree":"/w/a","session":"\#(session)","ts":"\#(ts)","data":\#(data),"repo":"/r"}"#
    }

    @Test
    func waiting_setByTheEventAndClearedBySameSessionActivityOrLeaving() {
        let joined = line("worktree.joined", ts: "2026-11-10T10:00:00+01:00")
        let waiting = line("agent.waiting", ts: "2026-11-10T10:05:00+01:00", data: #"{"reason":"needs a decision on the schema"}"#)

        let asked = AgentLedger.replay(lines: [joined, waiting])["/w/a"]
        #expect(asked?.waiting == LedgerWaiting(
            key: "claude-code:s1", reason: "needs a decision on the schema", since: date("2026-11-10T10:05:00+01:00")
        ))
        #expect(asked?.timeline.last?.text == "waiting: needs a decision on the schema")

        // No reason is fine.
        let bare = AgentLedger.replay(lines: [joined, line("agent.waiting", ts: "2026-11-10T10:05:00+01:00")])["/w/a"]
        #expect(bare?.waiting == LedgerWaiting(key: "claude-code:s1", reason: nil, since: date("2026-11-10T10:05:00+01:00")))

        // A later event from the same agent and session clears it.
        let noted = AgentLedger.replay(lines: [joined, waiting, line("worktree.noted", ts: "2026-11-10T10:06:00+01:00", data: #"{"note":"on it"}"#)])
        #expect(noted["/w/a"]?.waiting == nil)
        let resumed = AgentLedger.replay(lines: [joined, waiting, line("agent.resumed", ts: "2026-11-10T10:06:00+01:00")])
        #expect(resumed["/w/a"]?.waiting == nil)
        #expect(resumed["/w/a"]?.timeline.last?.text == "resumed")

        // Another session's event does not: that agent is not the one that asked.
        let other = AgentLedger.replay(lines: [
            joined, waiting, line("worktree.noted", agent: "codex", session: "s9", ts: "2026-11-10T10:06:00+01:00", data: #"{"note":"hi"}"#)
        ])
        #expect(other["/w/a"]?.waiting?.key == "claude-code:s1")

        // Leaving clears it, whoever's session it was.
        let left = AgentLedger.replay(lines: [joined, waiting, line("worktree.left", ts: "2026-11-10T10:07:00+01:00")])
        #expect(left["/w/a"]?.waiting == nil)
        // A waiting event on a worktree with no row makes one, with no session in it.
        let alone = AgentLedger.replay(lines: [waiting])
        #expect(alone["/w/a"]?.waiting?.reason == "needs a decision on the schema")
        #expect(alone["/w/a"]?.live == [])
    }

    @Test
    func waiting_laneAndReason() {
        let waiting = LedgerWaiting(key: "k", reason: "pick one", since: nil)
        #expect(TowerLanes.assign(TowerFacts(live: .window, waiting: waiting)) == (.needsYou, "waiting on you: pick one"))
        #expect(TowerLanes.assign(TowerFacts(waiting: LedgerWaiting(key: "k", reason: nil, since: nil))) == (.needsYou, "waiting on you"))
        // An ask nobody can still answer (no live session, older than a day) is not a standing alarm.
        #expect(TowerLanes.assign(TowerFacts(idleDays: 14, waiting: waiting)) == (.leftovers, "idle 14d"))
        #expect(TowerLanes.assign(TowerFacts(idleDays: 13, waiting: waiting)) == (.leftovers, "idle"))
        #expect(TowerLanes.assign(TowerFacts(idleDays: 0, waiting: waiting)) == (.needsYou, "waiting on you: pick one"))
        // A session the ledger still counts as live keeps the ask standing.
        #expect(TowerLanes.assign(TowerFacts(live: .pid(7), idleDays: 5, waiting: waiting)) == (.needsYou, "waiting on you: pick one"))
        // A missing worktree is still debris.
        #expect(TowerLanes.assign(TowerFacts(isPrunable: true, waiting: waiting)) == (.leftovers, "missing on disk"))
        // The process guess alone never reaches Needs you.
        #expect(TowerLanes.assign(TowerFacts(live: .process(pid: 7, name: "claude"))) == (.working, "process inside: claude"))
    }

    @Test
    func waitingWorktreeCountsTowardNeedsYou() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        let path = AgentLedger.normalizedPath(fixture.worktreeClean.path)
        var ledger = LedgerWorktree(path: path)
        ledger.agent = "claude"
        ledger.live = ["claude-code:s1"]
        ledger.waiting = LedgerWaiting(key: "claude-code:s1", reason: "which branch?", since: Date())
        ledger.lastEvent = Date()
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive())
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [path: ledger]) { _ in })
        let row = try #require(final.rows.first { $0.path == path })
        #expect(row.lane == .needsYou)
        #expect(row.reason == "waiting on you: which branch?")
        #expect(row.waiting?.reason == "which branch?")
        // feat-a and feat-b conflict with main (Needs you); the waiting worktree makes three.
        #expect(final.needsYouCount == 3)
    }

    // MARK: - ledger-free scan

    /// A repo under `<home>/Projects` with a Codex worktree at `<home>/.codex/worktrees/abc/app`
    /// and one in `<home>/.worktrees/plain`.
    private struct HomeFixture {
        let home: URL
        let repo: URL
        let codex: URL
        let plain: URL
    }

    private func homeWithWorktrees() throws -> HomeFixture {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("tower-home-\(UUID().uuidString)").resolvingSymlinksInPath()
        let repo = home.appendingPathComponent("Projects/app")
        let codex = home.appendingPathComponent(".codex/worktrees/abc/app")
        let plain = home.appendingPathComponent(".worktrees/plain")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: plain.deletingLastPathComponent(), withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.commit("a.txt", "base\n", "base", in: repo)
        try TowerFixture.runGit(["worktree", "add", codex.path, "-b", "codex/x"], in: repo)
        try TowerFixture.runGit(["worktree", "add", plain.path, "-b", "plain"], in: repo)
        return HomeFixture(home: home, repo: repo, codex: codex, plain: plain)
    }

    @Test
    func scan_withoutALedgerNamesTheAgentFromThePathAndTheProcess() throws {
        let fixture = try self.homeWithWorktrees()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let git = try #require(TowerGit())
        let plainPath = AgentLedger.normalizedPath(fixture.plain.path)
        let probe = FakeProcesses(inside: [
            plainPath: ProcessInside(pid: 4242, name: "2.1.139", executable: "/Users/u/.local/share/claude/versions/2.1.139")
        ])
        let scanner = TowerScanner(git: git, home: fixture.home.path, host: "h", now: Date(), probe: probe, xdgConfigHome: nil)
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })

        let byBranch = Dictionary(uniqueKeysWithValues: final.rows.map { ($0.branch ?? "", $0) })
        let codex = try #require(byBranch["codex/x"])
        let plain = try #require(byBranch["plain"])
        #expect(codex.agent == "codex")
        #expect(codex.agentLabel == "codex")
        #expect(codex.evidence == nil)
        #expect(plain.agent == "claude")
        #expect(plain.evidence == .process(pid: 4242, name: "2.1.139"))
        #expect(plain.lane == .working)
        #expect(plain.reason == "process inside: 2.1.139")
        #expect(plain.waiting == nil)
        // A ledger-free worktree no process names stays "unknown" rather than "you".
        let bare = TowerRow(
            repoPath: "/r", repoName: "r", path: "/x", branch: nil, agent: nil, task: nil, note: nil, evidence: nil, build: nil,
            delivered: nil, advice: nil, isLocked: false, isPrunable: false, ahead: nil, behind: nil, dirty: nil, forecast: nil,
            collisions: [], lastActivity: nil, timeline: [], lane: .leftovers, reason: "idle"
        )
        #expect(bare.agentLabel == "unknown")
    }

    @Test
    func scan_theLedgerWinsOverTheProcessTable() throws {
        let fixture = try self.homeWithWorktrees()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let git = try #require(TowerGit())
        let plainPath = AgentLedger.normalizedPath(fixture.plain.path)
        // The ledger knows this worktree and says nobody is in; a process there does not overrule it.
        var row = LedgerWorktree(path: plainPath)
        row.agent = "ribhu"
        row.lastEvent = Date()
        let probe = FakeProcesses(inside: [plainPath: ProcessInside(pid: 1, name: "claude")])
        let scanner = TowerScanner(git: git, home: fixture.home.path, host: "h", now: Date(), probe: probe, xdgConfigHome: nil)
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [plainPath: row]) { _ in })
        let plain = try #require(final.rows.first { $0.path == plainPath })
        #expect(plain.agent == "ribhu")
        #expect(plain.evidence == nil)
        #expect(plain.lane != .working)
    }

    // MARK: - idle guess

    @Test
    func lastChange_isTheNewestOfDirtyFilesAndTheWorktreeGitFiles() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let old = date("2026-11-10T09:00:00+01:00")
        let mid = date("2026-11-10T10:00:00+01:00")
        let new = date("2026-11-10T11:00:00+01:00")
        let worktree = fixture.worktreeA.path
        let gitDirectory = try #require(TowerIdle.gitDirectory(of: worktree))
        // git writes the physical /private/var form; the fixture holds the /var one.
        #expect(gitDirectory.hasSuffix("/repo/.git/worktrees/wt-a"))
        for name in ["HEAD", "index", "logs/HEAD"] {
            try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: gitDirectory + "/" + name)
        }
        #expect(TowerIdle.lastChange(worktree: worktree, dirtyPaths: []) == old)
        try Data("x".utf8).write(to: fixture.worktreeA.appendingPathComponent("edit.txt"))
        try FileManager.default.setAttributes([.modificationDate: mid], ofItemAtPath: worktree + "/edit.txt")
        #expect(TowerIdle.lastChange(worktree: worktree, dirtyPaths: ["edit.txt", "deleted.txt"]) == mid)
        try FileManager.default.setAttributes([.modificationDate: new], ofItemAtPath: gitDirectory + "/index")
        #expect(TowerIdle.lastChange(worktree: worktree, dirtyPaths: ["edit.txt"]) == new)
        #expect(TowerIdle.lastChange(worktree: "/no/such/worktree", dirtyPaths: ["a"]) == nil)
    }

    @Test
    func idleGuess_onlyForAProcessWithNoLedger_andNeverSaysWaitingOutright() throws {
        let fixture = try self.homeWithWorktrees()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let git = try #require(TowerGit())
        let plainPath = AgentLedger.normalizedPath(fixture.plain.path)
        let gitDirectory = try #require(TowerIdle.gitDirectory(of: plainPath))
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        for name in ["HEAD", "index", "logs/HEAD"] {
            try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: gitDirectory + "/" + name)
        }
        let probe = FakeProcesses(inside: [plainPath: ProcessInside(pid: 9, name: "claude")])
        let scanner = TowerScanner(git: git, home: fixture.home.path, host: "h", now: stamp.addingTimeInterval(3600), probe: probe, xdgConfigHome: nil)
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })
        let plain = try #require(final.rows.first { $0.path == plainPath })
        #expect(plain.lastChange == stamp)

        let ten = TowerIdle.threshold
        #expect(plain.idleMinutes(now: stamp.addingTimeInterval(ten - 1)) == nil)
        #expect(plain.idleMinutes(now: stamp.addingTimeInterval(ten)) == 10)
        #expect(plain.reasonText(now: stamp.addingTimeInterval(14 * 60)) == "process inside: claude, idle 14m — maybe waiting")
        #expect(plain.reasonText(now: stamp.addingTimeInterval(60)) == "process inside: claude")
        // The guess is not a "waiting": no lane change, no Needs you.
        #expect(plain.lane == .working)
        #expect(final.needsYouCount == 0)

        // The other worktree has no process: no guess, whatever its age.
        let codex = try #require(final.rows.first { $0.branch == "codex/x" })
        #expect(codex.idleMinutes(now: stamp.addingTimeInterval(99999)) == nil)
    }

    // MARK: - the real process table

    @Test
    func systemProbe_findsAProcessWhoseDirectoryIsInsideAWorktree_andSkipsShellsAndGit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-proc-\(UUID().uuidString)").resolvingSymlinksInPath()
        let inner = root.appendingPathComponent("wt/src")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        func spawn(_ path: String, _ arguments: [String]) throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.currentDirectoryURL = inner
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            return process
        }
        let agent = try spawn("/usr/bin/tail", ["-f", "/dev/null"])
        let shell = try spawn("/bin/sh", ["-c", "exec /bin/sh -c 'read x'"])
        defer { agent.terminate(); shell.terminate() }
        // proc_pidinfo answers once the child has exec'd; give it a moment, without a polling loop in the product.
        let worktree = root.appendingPathComponent("wt").path
        var found: ProcessInside?
        for _ in 0 ..< 100 where found == nil {
            found = SystemProcessProbe().processes(inside: [worktree])[worktree]
            if found == nil { Thread.sleep(forTimeInterval: 0.05) }
        }
        #expect(found?.pid == Int(agent.processIdentifier))
        #expect(found?.name == "tail")
        // A directory beside it, or a prefix that is not a path boundary, matches nothing.
        #expect(SystemProcessProbe().processes(inside: [root.appendingPathComponent("w").path]).isEmpty)
        #expect(SystemProcessProbe().processes(inside: []).isEmpty)
    }

    @Test
    func processFilter_ignoresShellsAndGit_andReadsTheAgentFromNameOrPath() {
        #expect(ProcessInside(pid: 1, name: "zsh").isIgnored)
        #expect(ProcessInside(pid: 1, name: "git").isIgnored)
        #expect(ProcessInside(pid: 1, name: "git-remote-https").isIgnored)
        #expect(!ProcessInside(pid: 1, name: "claude").isIgnored)
        #expect(!ProcessInside(pid: 1, name: "node").isIgnored)
        #expect(ProcessInside(pid: 1, name: "codex").agentHint == "codex")
        #expect(ProcessInside(pid: 1, name: "2.1.139", executable: "/u/.local/share/claude/versions/2.1.139").agentHint == "claude")
        #expect(ProcessInside(pid: 1, name: "node", executable: "/usr/local/bin/node").agentHint == nil)
    }

    // MARK: - empty state

    @Test
    func emptyState_saysWhatTowerShowsAndHowItFindsWorktrees() {
        #expect(TowerCopy.emptyTitle == "No agent worktrees yet")
        #expect(TowerCopy.emptyParagraphs.count == 3)
        #expect(TowerCopy.emptyParagraphs[1].contains("git worktree list"))
        #expect(TowerCopy.emptyParagraphs[1].contains("project folders"))
        #expect(TowerCopy.emptyParagraphs[2].contains("agent.waiting"))
    }
}
