import Foundation
@testable import HarborCore
import Testing

struct AgentWorktreesTests {
    // MARK: - porcelain

    @Test
    func porcelain_parsesPathHeadBranchAndFlags() {
        let raw = """
        worktree /r/main
        HEAD aaaaaaaa
        branch refs/heads/main

        worktree /r/.claude/worktrees/agent-ab12
        HEAD bbbbbbbb
        detached
        locked reason text

        worktree /r/gone
        HEAD cccccccc
        branch refs/heads/feat/x
        prunable gitdir file points to non-existent location

        worktree /r/bare.git
        bare

        """
        #expect(GitWorktreePorcelain.parse(raw) == [
            GitWorktreeEntry(path: "/r/main", head: "aaaaaaaa", branch: "main", isDetached: false,
                             isBare: false, isLocked: false, isPrunable: false),
            GitWorktreeEntry(path: "/r/.claude/worktrees/agent-ab12", head: "bbbbbbbb", branch: nil,
                             isDetached: true, isBare: false, isLocked: true, isPrunable: false),
            GitWorktreeEntry(path: "/r/gone", head: "cccccccc", branch: "feat/x", isDetached: false,
                             isBare: false, isLocked: false, isPrunable: true),
            GitWorktreeEntry(path: "/r/bare.git", head: nil, branch: nil, isDetached: false,
                             isBare: true, isLocked: false, isPrunable: false)
        ])
    }

    @Test
    func porcelain_lastBlockWithoutTrailingBlankLine() {
        let entries = GitWorktreePorcelain.parse("worktree /a\nHEAD 1\nbranch refs/heads/m")
        #expect(entries.map(\.path) == ["/a"])
        #expect(entries.first?.branch == "m")
    }

    // MARK: - path convention

    @Test
    func pathConvention_attributesByDirectory() {
        let home = "/Users/me"
        #expect(AgentWorktrees.agentFromPath("/Users/me/.codex/worktrees/ab12/Repo", home: home) == "codex")
        #expect(AgentWorktrees.agentFromPath("/Users/me/Code/Repo/.claude/worktrees/agent-1f2e3d", home: home) == "claude")
        #expect(AgentWorktrees.agentFromPath("/Users/me/.ribhu/worktrees/t1/Repo", home: home) == "ribhu")
        #expect(AgentWorktrees.agentFromPath("/Users/me/.cursor/worktrees/Repo/x", home: home) == "cursor")
        #expect(AgentWorktrees.agentFromPath("/Users/me/Code/Repo/.qwen/worktrees/q1", home: home) == "qwen")
        #expect(AgentWorktrees.agentFromPath("/Users/me/.worktrees/Repo-hotfix", home: home) == nil)
        // Another user's codex directory is not this home's.
        #expect(AgentWorktrees.agentFromPath("/Users/other/.codex/worktrees/a/Repo", home: home) == nil)
    }

    @Test
    func agentNames_normalize() {
        #expect(AgentWorktrees.normalizedAgent("claude-code") == "claude")
        #expect(AgentWorktrees.normalizedAgent("Codex-Deepika") == "codex")
        #expect(AgentWorktrees.normalizedAgent("pi") == "pi")
        #expect(AgentWorktrees.normalizedAgent("unknown") == nil)
        #expect(AgentWorktrees.normalizedAgent("/root/tring_priority_recovery") == nil)
    }

    // MARK: - ledger

    private func line(_ event: String, agent: String = "codex", worktree: String = "/w/a",
                      session: String = "s1", branch: String? = nil, task: String? = nil,
                      ts: String = "2026-11-10T10:00:00+01:00", data: String = "{}") -> String {
        let branchJSON = branch.map { "\"\($0)\"" } ?? "null"
        let taskJSON = task.map { "\"\($0)\"" } ?? "null"
        return """
        {"event":"\(event)","agent":"\(agent)","worktree":"\(worktree)","session":"\(session)",\
        "branch":\(branchJSON),"task":\(taskJSON),"ts":"\(ts)","data":\(data)}
        """
    }

    @Test
    func ledger_bornCarriesAgentTaskBranchPurpose() throws {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", agent: "claude-code", branch: "feat/x", task: "t-1",
                 data: #"{"name":"nm","purpose":"fix the thing"}"#)
        ])
        let row = try #require(rows["/w/a"])
        #expect(row.agent == "claude")
        #expect(row.task == "t-1")
        #expect(row.branch == "feat/x")
        #expect(row.note == "fix the thing")
        #expect(row.live.isEmpty)
        #expect(row.lastEvent == ISO8601DateFormatter().date(from: "2026-11-10T10:00:00+01:00"))
    }

    @Test
    func ledger_liveUntilMatchingLeft() {
        let born = line("worktree.born")
        let joinA = line("worktree.joined", agent: "codex", session: "s1")
        let joinB = line("worktree.joined", agent: "claude-code", session: "s2")
        #expect(AgentLedger.replay(lines: [born, joinA, joinB])["/w/a"]?.live == ["codex:s1", "claude-code:s2"])

        // A left with data.key removes exactly that session.
        let leftA = line("worktree.left", agent: "codex", session: "s1", data: #"{"key":"codex:s1"}"#)
        #expect(AgentLedger.replay(lines: [born, joinA, joinB, leftA])["/w/a"]?.live == ["claude-code:s2"])

        // Without data.key it falls back to agent:session.
        let leftB = line("worktree.left", agent: "claude-code", session: "s2")
        #expect(AgentLedger.replay(lines: [born, joinA, joinB, leftA, leftB])["/w/a"]?.live == [])

        // A leave for a session that never joined removes nobody.
        let stray = line("worktree.left", agent: "codex", session: "zzz")
        #expect(AgentLedger.replay(lines: [born, joinA, stray])["/w/a"]?.live == ["codex:s1"])
    }

    @Test
    func ledger_notedLatestWins() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", data: #"{"purpose":"first"}"#),
            line("worktree.noted", data: #"{"name":"n1","note":"second"}"#),
            line("worktree.noted", data: #"{"name":"n2","note":"third"}"#)
        ])
        #expect(rows["/w/a"]?.note == "third")
    }

    @Test
    func ledger_notedWithoutNoteFallsBackToName() {
        let rows = AgentLedger.replay(lines: [line("worktree.noted", data: #"{"name":"only-name"}"#)])
        #expect(rows["/w/a"]?.note == "only-name")
    }

    @Test
    func ledger_retiredRemovesThePathOnly() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", worktree: "/w/a"),
            line("worktree.born", worktree: "/w/b"),
            line("worktree.joined", worktree: "/w/a"),
            line("task.retired", worktree: "/w/a")
        ])
        #expect(rows["/w/a"] == nil)
        #expect(rows["/w/b"] != nil)
    }

    @Test
    func ledger_bornAgainAfterRetireStartsFresh() {
        let rows = AgentLedger.replay(lines: [
            line("worktree.born", data: #"{"purpose":"old"}"#),
            line("worktree.joined", session: "s1"),
            line("task.retired"),
            line("worktree.born", agent: "ribhu", data: #"{"purpose":"new"}"#)
        ])
        #expect(rows["/w/a"]?.agent == "ribhu")
        #expect(rows["/w/a"]?.note == "new")
        #expect(rows["/w/a"]?.live == [])
    }

    @Test
    func ledger_malformedLinesAreSkipped() {
        let rows = AgentLedger.replay(lines: [
            "not json at all",
            "{\"event\":\"worktree.born\"",
            "[1,2,3]",
            #"{"event":"worktree.born","agent":"codex"}"#,
            #"{"worktree":"/w/a"}"#,
            "",
            line("worktree.born", data: #"{"purpose":"survivor"}"#)
        ])
        #expect(rows.count == 1)
        #expect(rows["/w/a"]?.note == "survivor")
    }

    @Test
    func ledger_buildRecordedBumpsActivityButNeverCreatesARow() {
        let born = line("worktree.born", ts: "2026-11-10T10:00:00+01:00")
        let build = line("build.recorded", ts: "2026-11-10T12:00:00+01:00", data: #"{"status":"ok"}"#)
        let rows = AgentLedger.replay(lines: [born, build, line("build.recorded", worktree: "/w/other")])
        #expect(rows["/w/a"]?.lastEvent == ISO8601DateFormatter().date(from: "2026-11-10T12:00:00+01:00"))
        #expect(rows["/w/other"] == nil)
    }

    @Test
    func ledger_tailDropsTheCutFirstLineAndReadsTheRest() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        try "AAAAAAAAAA\nBBBBBBBBBB\nCCCCCCCCCC\n".write(to: file, atomically: true, encoding: .utf8)
        // 25 bytes from the end starts inside the A line; its cut remainder is dropped.
        #expect(AgentLedger.tailLines(of: file, maxBytes: 25) == ["BBBBBBBBBB", "CCCCCCCCCC"])
        // 14 bytes starts inside the B line.
        #expect(AgentLedger.tailLines(of: file, maxBytes: 14) == ["CCCCCCCCCC"])
        // 11 bytes starts exactly on the C line, which must be kept.
        #expect(AgentLedger.tailLines(of: file, maxBytes: 11) == ["CCCCCCCCCC"])
        // 12 bytes starts on the newline before it: C is whole too.
        #expect(AgentLedger.tailLines(of: file, maxBytes: 12) == ["CCCCCCCCCC"])
        #expect(AgentLedger.tailLines(of: file, maxBytes: 1000) == ["AAAAAAAAAA", "BBBBBBBBBB", "CCCCCCCCCC"])
        #expect(AgentLedger.tailLines(of: dir.appendingPathComponent("missing")) == [])
    }

    // MARK: - loader, against real git

    @Test
    func loader_findsLinkedWorktreesAttributesThemAndSkipsMainCheckout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("wt-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        let home = root.appendingPathComponent("home")
        let codexWT = home.appendingPathComponent(".codex/worktrees/ab12/repo")
        let ledgerWT = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexWT.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repo)
        try runGit(["config", "user.email", "t@example.com"], in: repo)
        try runGit(["config", "user.name", "T"], in: repo)
        try runGit(["commit", "--allow-empty", "-m", "init"], in: repo)
        try runGit(["worktree", "add", codexWT.path, "-b", "codex/one"], in: repo)
        try runGit(["worktree", "add", ledgerWT.path, "-b", "claude/two"], in: repo)
        try Data("x".utf8).write(to: ledgerWT.appendingPathComponent("dirty.txt"))
        try runGit(["commit", "--allow-empty", "-m", "ahead"], in: ledgerWT)

        let ledger = root.appendingPathComponent("events.jsonl")
        let now = Date()
        let ts = ISO8601DateFormatter().string(from: now)
        let rows = [
            line("worktree.born", agent: "claude-code", worktree: ledgerWT.path, ts: ts,
                 data: #"{"purpose":"ledger purpose"}"#),
            line("worktree.joined", agent: "claude-code", worktree: ledgerWT.path, session: "s9", ts: ts)
        ]
        try rows.joined(separator: "\n").appending("\n").write(to: ledger, atomically: true, encoding: .utf8)

        let snapshot = try #require(AgentWorktreeLoader(ledgerURL: ledger, home: home.path, now: now).load(repoURL: repo))
        #expect(snapshot.total == 2)
        #expect(snapshot.hiddenCount == 0)
        // Live first.
        let first = try #require(snapshot.shown.first)
        #expect(AgentLedger.normalizedPath(first.path.path) == AgentLedger.normalizedPath(ledgerWT.path))
        #expect(first.agent == "claude")
        #expect(first.note == "ledger purpose")
        #expect(first.isLive)
        #expect(first.branch == "claude/two")
        #expect(first.dirtyCount == 1)
        #expect(first.ahead == 1)
        #expect(first.behind == 0)
        let second = snapshot.shown[1]
        #expect(second.agent == "codex")
        #expect(second.branch == "codex/one")
        #expect(second.isLive == false)
        #expect(second.dirtyCount == 0)
        #expect(second.ahead == 0)
        #expect(second.lastActivity != nil)
    }

    @Test
    func loader_returnsNilOutsideAGitRepo() {
        let dir = FileManager.default.temporaryDirectory
        let missing = dir.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(AgentWorktreeLoader().load(repoURL: missing) == nil)
    }
}

/// Runs git in a throwaway repo without the developer's global config, hooks or signing.
private func runGit(_ arguments: [String], in directory: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = directory
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    process.environment = environment
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [
            NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"
        ])
    }
}
