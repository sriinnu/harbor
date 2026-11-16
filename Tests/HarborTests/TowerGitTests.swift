import Foundation
@testable import HarborCore
import Testing

struct TowerGitTests {
    // MARK: - parsing

    @Test
    func gitArguments_alwaysStartWithNoOptionalLocks() {
        #expect(TowerGit.arguments(["status"]) == [
            "--no-optional-locks", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false", "status"
        ])
        #expect(TowerGitParse.branchArguments(base: "origin/main") == [
            "for-each-ref", "--format=%(refname)%09%(ahead-behind:origin/main)%09%(committerdate:unix)", "refs/heads"
        ])
    }

    @Test
    func branchTips_parseAheadBehindAndCommitTime() {
        let raw = "refs/heads/main\t0 0\t1762800000\nrefs/heads/feat/x\t3 5\t1762800100\nrefs/heads/old\t1 20\nbad line\nrefs/heads/nan\tx y\t1\n"
        #expect(TowerGitParse.branchTips(raw) == [
            "main": BranchTip(counts: AheadBehind(ahead: 0, behind: 0), committed: Date(timeIntervalSince1970: 1_762_800_000)),
            "feat/x": BranchTip(counts: AheadBehind(ahead: 3, behind: 5), committed: Date(timeIntervalSince1970: 1_762_800_100)),
            "old": BranchTip(counts: AheadBehind(ahead: 1, behind: 20), committed: nil)
        ])
    }

    @Test
    func leftRight_isBehindThenAhead() {
        #expect(TowerGitParse.leftRight("7\t2\n") == AheadBehind(ahead: 2, behind: 7))
        #expect(TowerGitParse.leftRight("garbage") == nil)
    }

    @Test
    func statusPaths_coverOrdinaryRenamedUnmergedAndUntracked() {
        let raw = """
        # branch.oid abc
        # branch.head main
        1 .M N... 100644 100644 100644 aaa bbb Sources/a b.swift
        2 R. N... 100644 100644 100644 aaa bbb R100 new.swift\told.swift
        u UU N... 100644 100644 100644 100644 a b c conflict.txt
        ? notes/todo.md
        ! ignored.o
        """
        #expect(TowerGitParse.statusPaths(raw) == ["Sources/a b.swift", "new.swift", "conflict.txt", "notes/todo.md"])
    }

    @Test
    func conflictedFiles_stopAtTheMessageSectionAndDeduplicate() {
        let raw = "0123abcd\na.txt\nb.txt\na.txt\n\nAuto-merging a.txt\nCONFLICT (content): Merge conflict in a.txt\n"
        #expect(TowerGitParse.conflictedFiles(raw) == ["a.txt", "b.txt"])
        #expect(TowerGitParse.conflictedFiles("0123abcd\n") == [])
    }

    // MARK: - merge forecast against a repo with a real conflict

    @Test
    func forecast_reportsTheConflictAndNeverWritesTheRepo() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        let before = try fixture.objectFiles()
        let objects = fixture.repo.path + "/.git/objects"

        let conflict = ConflictForecast.run(git: git, repo: fixture.repo.path, objectsDirectory: objects, base: "main", head: "feat-a")
        #expect(conflict == .conflicts(["a.txt"]))
        // A branch that only adds a file merges clean.
        let clean = ConflictForecast.run(git: git, repo: fixture.repo.path, objectsDirectory: objects, base: "main", head: "feat-clean")
        #expect(clean == .clean)
        // An unknown revision is "unknown", not a crash or a false "clean".
        let unknown = ConflictForecast.run(git: git, repo: fixture.repo.path, objectsDirectory: objects, base: "main", head: "no-such-ref")
        #expect(unknown == .unknown)

        #expect(try fixture.objectFiles() == before)
        #expect(try fixture.git(["count-objects", "-v"]) == fixture.countsBefore)
    }

    @Test
    func forecast_removesItsTemporaryObjectDirectory() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        let scratchRoot = fixture.root.appendingPathComponent("scratch")
        try FileManager.default.createDirectory(at: scratchRoot, withIntermediateDirectories: true)
        let result = ConflictForecast.run(
            git: git, repo: fixture.repo.path, objectsDirectory: fixture.repo.path + "/.git/objects",
            base: "main", head: "feat-a", scratchRoot: scratchRoot
        )
        #expect(result == .conflicts(["a.txt"]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratchRoot.path) == [])
    }

    // MARK: - collisions

    @Test
    func collisions_listFilesChangedInTwoOrMoreWorktrees() {
        let result = CollisionMap.collisions(changes: [
            "/w/a": ["Sources/x.swift", "only-a.txt", "pnpm-lock.yaml"],
            "/w/b": ["Sources/x.swift", "only-b.txt", "pnpm-lock.yaml"],
            "/w/c": ["Sources/x.swift", "docs/y.md"],
            "/w/d": ["docs/y.md"]
        ])
        #expect(result == [
            FileCollision(file: "Sources/x.swift", worktrees: ["/w/a", "/w/b", "/w/c"]),
            FileCollision(file: "docs/y.md", worktrees: ["/w/c", "/w/d"])
        ].sorted { $0.file < $1.file })
        #expect(CollisionMap.collisions(changes: ["/w/a": ["x"], "/w/b": ["y"]]).isEmpty)
        #expect(CollisionMap.collisions(changes: [:]).isEmpty)
    }

    // MARK: - lanes

    @Test
    func lanes_firstMatchingRuleWins() {
        func lane(_ facts: TowerFacts) -> String {
            let result = TowerLanes.assign(facts)
            return "\(result.lane.title): \(result.reason)"
        }
        #expect(lane(TowerFacts(isPrunable: true, live: .window, buildStatus: "failed")) == "Leftovers: missing on disk")
        #expect(lane(TowerFacts(live: .pid(1), buildStatus: "failed")) == "Needs you: build failed")
        #expect(lane(TowerFacts(live: .pid(1), buildStatus: "ok", ahead: 3, dirty: 0)) == "Working: agent inside")
        #expect(lane(TowerFacts(live: .window, buildStatus: "building")) == "Working: building")
        #expect(lane(TowerFacts(buildStatus: "failed", isDelivered: true, ahead: 0, dirty: 0)) == "Leftovers: delivered")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts(["a", "b"]))) == "Needs you: would conflict with main in 2 files")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts([]))) == "Needs you: would conflict with main in 1 file")
        #expect(lane(TowerFacts(ahead: 0, forecast: .conflicts(["a"]))) == "Leftovers: nothing ahead of main")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts(["a"]), idleDays: 20)) == "Leftovers: idle 20d")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts(["a"]), idleDays: 13)) == "Leftovers: would conflict with main in 1 file, idle 13d")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts(["a"]), idleDays: 2)) == "Needs you: would conflict with main in 1 file")
        #expect(lane(TowerFacts(ahead: 2, behind: 1, dirty: 0, forecast: .conflicts(["a"]), idleDays: 3)) == "Leftovers: would conflict with main in 1 file, idle 3d")
        #expect(lane(TowerFacts(live: .window, idleDays: 30)) == "Working: agent inside")
        #expect(lane(TowerFacts(buildStatus: "failed", idleDays: 30)) == "Needs you: build failed")
        #expect(lane(TowerFacts(hasOpenPull: true, ahead: 1, dirty: 0)) == "In review: pull request open")
        #expect(lane(TowerFacts(buildStatus: "ok", ahead: 4, behind: 0, dirty: 0, forecast: .clean)) == "Ready: 4 ahead, clean")
        #expect(lane(TowerFacts(ahead: 4, dirty: 2)) == "Leftovers: 2 uncommitted")
        #expect(lane(TowerFacts(ahead: 0, dirty: 0)) == "Leftovers: nothing ahead of main")
        #expect(lane(TowerFacts()) == "Leftovers: idle")
    }

    // MARK: - scanner, end to end on a real repo

    @Test
    func scanner_paintsInPhasesAndFindsConflictsAndCollisions() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try Data("scratch".utf8).write(to: fixture.worktreeA.appendingPathComponent("scratch.txt"))
        let before = try fixture.objectFiles()
        let git = try #require(TowerGit())
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive())

        var phases: [TowerRepoSnapshot.Phase] = []
        var rowCounts: [Int] = []
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { snapshot in
            phases.append(snapshot.phase)
            rowCounts.append(snapshot.rows.count)
        })
        #expect(phases == [.listed, .counted, .detailed, .forecast])
        #expect(rowCounts == [3, 3, 3, 3])
        #expect(final.base == "main")

        let byBranch = Dictionary(uniqueKeysWithValues: final.rows.map { ($0.branch ?? "", $0) })
        let (a, b, clean) = try (#require(byBranch["feat-a"]), #require(byBranch["feat-b"]), #require(byBranch["feat-clean"]))
        #expect((a.ahead, a.behind, a.dirty) == (1, 1, 1))
        #expect((b.ahead, b.behind, b.dirty) == (1, 1, 0))
        #expect((clean.ahead, clean.behind, clean.dirty) == (1, 1, 0))
        #expect(a.forecast == .conflicts(["a.txt"]))
        #expect(b.forecast == .conflicts(["a.txt"]))
        #expect(clean.forecast == .clean)
        #expect(a.lane == .needsYou)
        #expect(a.reason == "would conflict with main in 1 file")
        #expect(clean.lane == .ready)
        #expect(clean.reason == "1 ahead, clean")
        // feat-a and feat-b both change a.txt; feat-clean adds one file nobody else touches.
        let paths = [fixture.worktreeA, fixture.worktreeB].map { AgentLedger.normalizedPath($0.path) }.sorted()
        #expect(final.collisions == [FileCollision(file: "a.txt", worktrees: paths)])
        #expect(a.collisions == ["a.txt"])
        #expect(b.collisions == ["a.txt"])
        #expect(clean.collisions == [])
        #expect(final.mainMovedText == "main moved: 3 behind, 2 would conflict")

        #expect(try fixture.objectFiles() == before)
    }

    @Test
    func scanner_skipsReposWithoutLinkedWorktrees() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: root)
        let git = try #require(TowerGit())
        #expect(TowerScanner(git: git).scan(repo: root.path, ledger: [:]) { _ in } == nil)
    }

    // MARK: - watcher

    @Test
    func watcher_firesOnRefChangesAndIgnoresObjectWrites() throws {
        #expect(GitDirWatcher.isRelevant("/r/.git/refs/heads/x", gitDir: "/r/.git"))
        #expect(GitDirWatcher.isRelevant("/r/.git/worktrees/a/HEAD", gitDir: "/r/.git"))
        #expect(GitDirWatcher.isRelevant("/r/.git/packed-refs", gitDir: "/r/.git"))
        #expect(GitDirWatcher.isRelevant("/r/.git/objects/ab/cdef", gitDir: "/r/.git") == false)
        #expect(GitDirWatcher.isRelevant("/r/.git/index.lock", gitDir: "/r/.git") == false)
        #expect(GitDirWatcher.isRelevant("/r/.git/logs/HEAD", gitDir: "/r/.git") == false)

        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let box = EventBox()
        let watcher = GitDirWatcher(gitDirs: [fixture.repo.path: fixture.repo.path + "/.git"], latency: 0.1) { box.add($0) }
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        _ = try fixture.git(["branch", "watched", "main"])
        #expect(box.wait(for: [fixture.repo.path], timeout: 5))
    }
}

struct NeverAlive: ProcessProbe {
    func isAlive(pid _: Int) -> Bool { false }
}

private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<String>()

    func add(_ paths: Set<String>) {
        self.lock.lock()
        self.seen.formUnion(paths)
        self.lock.unlock()
    }

    func wait(for paths: Set<String>, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            self.lock.lock()
            let done = paths.isSubset(of: self.seen)
            self.lock.unlock()
            if done { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}

/// A throwaway repo: `main` has moved on after three branches left it, two of which change
/// `a.txt` (conflicting with main and with each other) and one that only adds a file.
/// Git runs without the developer's config, hooks or signing.
struct TowerFixture {
    let root: URL
    let repo: URL
    let worktreeA: URL
    let worktreeB: URL
    let worktreeClean: URL
    private(set) var countsBefore = ""

    init() throws {
        self.root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)").resolvingSymlinksInPath()
        self.repo = self.root.appendingPathComponent("repo")
        self.worktreeA = self.root.appendingPathComponent("wt-a")
        self.worktreeB = self.root.appendingPathComponent("wt-b")
        self.worktreeClean = self.root.appendingPathComponent("wt-clean")
        try FileManager.default.createDirectory(at: self.repo, withIntermediateDirectories: true)
        try Self.runGit(["init", "-b", "main"], in: self.repo)
        try Self.commit("a.txt", "base\n", "base", in: self.repo)
        for (branch, dir) in [("feat-a", worktreeA), ("feat-b", worktreeB), ("feat-clean", worktreeClean)] {
            try Self.runGit(["worktree", "add", dir.path, "-b", branch], in: self.repo)
        }
        try Self.commit("a.txt", "A\n", "a", in: self.worktreeA)
        try Self.commit("a.txt", "B\n", "b", in: self.worktreeB)
        try Self.commit("c.txt", "new\n", "c", in: self.worktreeClean)
        try Self.commit("a.txt", "main\n", "main moves", in: self.repo)
        self.countsBefore = try Self.runGit(["count-objects", "-v"], in: self.repo)
    }

    func remove() { try? FileManager.default.removeItem(at: self.root) }

    @discardableResult
    func git(_ arguments: [String]) throws -> String {
        try Self.runGit(arguments, in: self.repo)
    }

    /// Every file under `.git/objects`, sorted: what a write to the object store would change.
    func objectFiles() throws -> [String] {
        let base = self.repo.appendingPathComponent(".git/objects")
        let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey])
        var files: [String] = []
        while let url = walker?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(String(url.path.dropFirst(base.path.count)))
            }
        }
        return files.sorted()
    }

    static func commit(_ file: String, _ content: String, _ message: String, in directory: URL) throws {
        try Data(content.utf8).write(to: directory.appendingPathComponent(file))
        try self.runGit(["add", file], in: directory)
        try self.runGit(["-c", "user.name=T", "-c", "user.email=t@example.com", "commit", "-m", message], in: directory)
    }

    @discardableResult
    static func runGit(_ arguments: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "git \(arguments.joined(separator: " ")) failed"
            ])
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
