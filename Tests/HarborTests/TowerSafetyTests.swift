import Foundation
@testable import HarborCore
import Testing

/// Review findings 1, 11, 12, 13, 15, 17 and 24: what the Tower must never do and must never claim.
struct TowerSafetyTests {
    // MARK: - #1 merge drivers never run

    /// A repo where `a.lock` conflicts between main and `f`, with a merge driver `probe` that
    /// creates `marker` when it runs. `attributes` says where `*.lock merge=probe` is declared.
    private func driverRepo(objectFormat: String? = nil, attributes: Attributes) throws -> DriverRepo {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-drv-\(UUID().uuidString)").resolvingSymlinksInPath()
        let repo = root.appendingPathComponent("repo")
        let marker = root.appendingPathComponent("DRIVER_RAN")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"] + (objectFormat.map { ["--object-format=\($0)"] } ?? []), in: repo)
        try TowerFixture.runGit(["config", "core.hooksPath", "/dev/null"], in: repo)
        try TowerFixture.runGit(["config", "commit.gpgsign", "false"], in: repo)
        if attributes == .committed {
            try TowerFixture.commit(".gitattributes", "*.lock merge=probe\n", "attrs", in: repo)
        }
        try TowerFixture.commit("a.lock", "base\n", "base", in: repo)
        try TowerFixture.runGit(["config", "merge.probe.driver", "touch '\(marker.path)'; cp %B %A"], in: repo)
        if attributes == .info {
            try Data("*.lock merge=probe\n".utf8).write(to: repo.appendingPathComponent(".git/info/attributes"))
        }
        try TowerFixture.runGit(["checkout", "-b", "f"], in: repo)
        try TowerFixture.commit("a.lock", "feature\n", "f", in: repo)
        try TowerFixture.runGit(["checkout", "main"], in: repo)
        try TowerFixture.commit("a.lock", "main\n", "m", in: repo)
        return DriverRepo(root: root, repo: repo, marker: marker)
    }

    private enum Attributes { case committed, info }

    private struct DriverRepo {
        let root: URL
        let repo: URL
        let marker: URL
    }

    @Test
    func forecast_neverRunsAMergeDriverFromCommittedAttributes() throws {
        let fixture = try driverRepo(attributes: .committed)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let git = try #require(TowerGit())
        let result = ConflictForecast.run(
            git: git, repo: fixture.repo.path, objectsDirectory: fixture.repo.path + "/.git/objects", base: "main", head: "f"
        )
        #expect(FileManager.default.fileExists(atPath: fixture.marker.path) == false)
        #expect(result == .conflicts(["a.lock"]))
    }

    @Test
    func forecast_infoAttributesAssigningMergeIsUnknownAndRunsNoDriver() throws {
        let fixture = try driverRepo(attributes: .info)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let git = try #require(TowerGit())
        let result = ConflictForecast.run(
            git: git, repo: fixture.repo.path, objectsDirectory: fixture.repo.path + "/.git/objects", base: "main", head: "f"
        )
        #expect(FileManager.default.fileExists(atPath: fixture.marker.path) == false)
        #expect(result == .unknown)
    }

    /// A driver whose name contains `=` escapes the `-c merge.<name>.driver=false` override, and
    /// `core.attributesFile` in the repo's own config is not covered by `--attr-source`. The
    /// driver lists the checkout, so a `.merge_file_*` there shows that git ran it.
    @Test
    func forecast_createsNoMergeFileInTheCheckoutAndRunsNoDriver() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-drv-\(UUID().uuidString)").resolvingSymlinksInPath()
        let repo = root.appendingPathComponent("repo")
        let dump = root.appendingPathComponent("listing.txt")
        let attributes = root.appendingPathComponent("attrs")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.runGit(["config", "core.hooksPath", "/dev/null"], in: repo)
        try TowerFixture.runGit(["config", "commit.gpgsign", "false"], in: repo)
        try TowerFixture.commit("a.lock", "base\n", "base", in: repo)
        try TowerFixture.runGit(["checkout", "-b", "f"], in: repo)
        try TowerFixture.commit("a.lock", "feature\n", "f", in: repo)
        try TowerFixture.runGit(["checkout", "main"], in: repo)
        try TowerFixture.commit("a.lock", "main\n", "m", in: repo)
        try Data("*.lock merge=a=b\n".utf8).write(to: attributes)
        try TowerFixture.runGit(["config", "core.attributesFile", attributes.path], in: repo)
        try TowerFixture.runGit(["config", "merge.a=b.driver", "ls -a . > '\(dump.path)'; cp %B %A"], in: repo)
        let git = try #require(TowerGit())
        let result = ConflictForecast.run(
            git: git, repo: repo.path, objectsDirectory: repo.path + "/.git/objects", base: "main", head: "f"
        )
        #expect(FileManager.default.fileExists(atPath: dump.path) == false)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: repo.path).filter { $0.hasPrefix(".merge_file_") }
        #expect(leftovers == [])
        #expect(result == .unknown)
    }

    @Test
    func forecast_withoutAWorkingSandboxIsUnknownNeverUnsandboxed() throws {
        let fixture = try driverRepo(attributes: .committed)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let git = try #require(TowerGit())
        let objects = fixture.repo.path + "/.git/objects"
        // Missing, and present but failing to apply (exits 71 like a refused profile).
        let refusing = fixture.root.appendingPathComponent("sandbox-exec")
        try Data("#!/bin/sh\nexit 71\n".utf8).write(to: refusing)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: refusing.path)
        for sandbox in [fixture.root.appendingPathComponent("nope"), refusing] {
            #expect(ConflictForecast.run(git: git, repo: fixture.repo.path, objectsDirectory: objects, base: "main", head: "f", sandbox: sandbox) == .unknown)
        }
    }

    @Test
    func git_versionGateForTheForecast() {
        #expect(TowerGitParse.supportsForecast(versionText: "git version 2.54.0 (Apple Git-157)"))
        #expect(TowerGitParse.supportsForecast(versionText: "git version 2.41.0"))
        #expect(TowerGitParse.supportsForecast(versionText: "git version 3.0.1"))
        #expect(TowerGitParse.supportsForecast(versionText: "git version 2.39.5 (Apple Git-154)") == false)
        #expect(TowerGitParse.supportsForecast(versionText: "git version 2.9.0") == false)
        #expect(TowerGitParse.supportsForecast(versionText: "garbled"))
    }

    @Test
    func forecast_worksInASha256RepoAndFindsItsEmptyTree() throws {
        let fixture: DriverRepo
        do { fixture = try driverRepo(objectFormat: "sha256", attributes: .committed) } catch { return } // git without sha256
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let git = try #require(TowerGit())
        #expect(ConflictForecast.emptyTree(git: git, repo: fixture.repo.path)
            == "6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321")
        let result = ConflictForecast.run(
            git: git, repo: fixture.repo.path, objectsDirectory: fixture.repo.path + "/.git/objects", base: "main", head: "f"
        )
        #expect(result == .conflicts(["a.lock"]))
        #expect(FileManager.default.fileExists(atPath: fixture.marker.path) == false)
    }

    @Test
    func forecast_emptyTreeInASha1RepoIsTheWellKnownId() throws {
        let fixture = try driverRepo(attributes: .committed)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let git = try #require(TowerGit())
        #expect(ConflictForecast.emptyTree(git: git, repo: fixture.repo.path) == "4b825dc642cb6eb9a060e54bf8d69288fbee4904")
        #expect(ConflictForecast.configuredMergeDrivers(git: git, repo: fixture.repo.path) == ["merge.probe.driver"])
    }

    @Test
    func forecast_leavesEveryObjectModificationTimeAlone() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let git = try #require(TowerGit())
        func mtimes() -> [String: Date] {
            let base = fixture.repo.appendingPathComponent(".git/objects")
            let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
            var result: [String: Date] = [:]
            while let url = walker?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == true, let date = values?.contentModificationDate { result[url.path] = date }
            }
            return result
        }
        let before = mtimes()
        Thread.sleep(forTimeInterval: 1.1)
        for head in ["feat-a", "feat-clean"] {
            _ = ConflictForecast.run(
                git: git, repo: fixture.repo.path, objectsDirectory: fixture.repo.path + "/.git/objects", base: "main", head: head
            )
        }
        #expect(mtimes() == before)
    }

    /// A branch that is only ahead merges into a tree git already has, so the merge "writes" an
    /// object that exists, and git freshens it (`utime`) in the user's store: loose or packed.
    @Test
    func forecast_identicalObjectMergeLeavesLooseAndPackedMtimesAlone() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-id-\(UUID().uuidString)").resolvingSymlinksInPath()
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.runGit(["config", "core.hooksPath", "/dev/null"], in: repo)
        try TowerFixture.runGit(["config", "commit.gpgsign", "false"], in: repo)
        try TowerFixture.commit("a.txt", "base\n", "base", in: repo)
        try TowerFixture.runGit(["checkout", "-b", "packed"], in: repo)
        try TowerFixture.commit("b.txt", "packed\n", "p", in: repo)
        try TowerFixture.runGit(["repack", "-a", "-d", "-q"], in: repo)
        try TowerFixture.runGit(["checkout", "-b", "loose", "main"], in: repo)
        try TowerFixture.commit("c.txt", "loose\n", "l", in: repo)
        try TowerFixture.runGit(["checkout", "main"], in: repo)
        let objects = repo.appendingPathComponent(".git/objects")
        func mtimes() -> [String: Date] {
            let walker = FileManager.default.enumerator(at: objects, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey])
            var result: [String: Date] = [:]
            while let url = walker?.nextObject() as? URL {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
                if values?.isRegularFile == true, let date = values?.contentModificationDate { result[url.path] = date }
            }
            return result
        }
        let before = mtimes()
        #expect(before.keys.contains { $0.hasSuffix(".pack") })
        #expect(before.keys.contains { !$0.contains("/pack/") })
        Thread.sleep(forTimeInterval: 1.1)
        let git = try #require(TowerGit())
        for head in ["packed", "loose"] {
            let result = ConflictForecast.run(git: git, repo: repo.path, objectsDirectory: objects.path, base: "main", head: head)
            #expect(result == .clean)
        }
        #expect(mtimes() == before)
    }

    // MARK: - #24 lazy fetch off

    @Test
    func forecast_setsNoLazyFetchSoPartialClonesNeverGoToTheNetwork() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-fake-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("git")
        // Answers `hash-object` with a tree id; on `merge-tree` it exits 0 (clean) when the lazy-fetch
        // variable is 1 and 2 (unknown) otherwise. The sandbox allows no write outside the scratch
        // directory, so the answer travels in the exit status, not in a file.
        try Data("""
        #!/bin/sh
        for a in "$@"; do
          case "$a" in
            hash-object) echo 4b825dc642cb6eb9a060e54bf8d69288fbee4904; exit 0;;
            config) exit 1;;
            merge-tree) if [ "$GIT_NO_LAZY_FETCH" = 1 ]; then exit 0; else exit 2; fi;;
          esac
        done
        exit 3
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let git = try #require(TowerGit(locator: FixedLocator(url: script)))
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let result = ConflictForecast.run(git: git, repo: repo.path, objectsDirectory: repo.path + "/objects", base: "main", head: "x", scratchRoot: root)
        #expect(result == .clean)
    }

    // MARK: - #11 reused pid

    private struct ReusedProbe: ProcessProbe {
        let started: Date?
        func isAlive(pid _: Int) -> Bool { true }
        func startTime(pid _: Int) -> Date? { self.started }
    }

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    private func joined(at value: String) -> LedgerWorktree {
        LedgerWorktree(
            path: "/w/a", live: ["a:s"],
            sessions: ["a:s": LedgerSession(pid: 42, host: "h", since: date(value))],
            lastEvent: date(value)
        )
    }

    @Test
    func liveness_aPidThatStartedAfterTheJoinIsAReusedNumber() {
        let join = "2026-11-10T10:00:00+01:00"
        let probe = ReusedProbe(started: date("2026-11-10T10:30:00+01:00"))
        // Inside the window: only the window vouches for it, not the pid.
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: date("2026-11-10T12:00:00+01:00"), probe: probe) == .window)
        // Past the window: nothing does.
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: date("2026-11-12T10:00:00+01:00"), probe: probe) == nil)
    }

    @Test
    func liveness_aPidThatStartedBeforeTheJoinStillProvesIt() {
        let join = "2026-11-10T10:00:00+01:00"
        let now = date("2026-11-12T10:00:00+01:00")
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: now,
                                        probe: ReusedProbe(started: date("2026-11-10T09:59:58+01:00"))) == .pid(42))
        // Within the slack of a truncated timestamp.
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: now,
                                        probe: ReusedProbe(started: date("2026-11-10T10:00:03+01:00"))) == .pid(42))
        // An unreadable start time falls back to the age bound alone.
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: now, probe: ReusedProbe(started: nil)) == .pid(42))
    }

    @Test
    func liveness_aLiveFlagIsNotProofOnceTheJoinIsOlderThanTheAgeBound() {
        let join = "2026-11-01T10:00:00+01:00"
        let now = date("2026-11-20T10:00:00+01:00") // 19 days
        #expect(LedgerLiveness.pidAgeBound == 7 * 24 * 3600)
        #expect(LedgerLiveness.evidence(for: joined(at: join), host: "h", now: now,
                                        probe: ReusedProbe(started: date("2026-11-01T09:00:00+01:00"))) == nil)
    }

    @Test
    func systemProbe_readsTheStartTimeOfARealProcess() throws {
        let probe = SystemProcessProbe()
        let mine = try #require(probe.startTime(pid: Int(ProcessInfo.processInfo.processIdentifier)))
        #expect(mine < Date())
        #expect(mine > Date().addingTimeInterval(-7 * 24 * 3600))
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["5"]
        let spawned = Date()
        try child.run()
        defer { child.terminate(); child.waitUntilExit() }
        let started = try #require(probe.startTime(pid: Int(child.processIdentifier)))
        #expect(abs(started.timeIntervalSince(spawned)) < 3)
        #expect(probe.startTime(pid: 0) == nil)
    }

    // MARK: - #12 ledger watch

    private func ledgerLine(_ worktree: String, note: String) -> String {
        #"{"event":"worktree.born","agent":"a","worktree":"\#(worktree)","session":"s","ts":"2026-11-10T10:00:00+01:00","data":{"purpose":"\#(note)"},"branch":null,"task":null,"repo":null}"# + "\n"
    }

    private func settle(timeout: Duration = .seconds(8), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "tower", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test
    func tail_attachesWhenTheFileAppearsAfterStart() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        let tail = LedgerTail(url: file, firstRetryDelay: 0.05, maxRetryDelay: 0.2)
        tail.start {}
        defer { tail.stop() }
        #expect(tail.snapshot().isEmpty)
        try ledgerLine("/w/a", note: "one").write(to: file, atomically: true, encoding: .utf8)
        try await settle { tail.snapshot()["/w/a"]?.note == "one" }
        // And it keeps following appends from there.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(ledgerLine("/w/b", note: "two").utf8))
        try handle.close()
        try await settle { tail.snapshot()["/w/b"]?.note == "two" }
    }

    @Test
    func tail_survivesRemoveThenRecreate() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("events.jsonl")
        try ledgerLine("/w/a", note: "one").write(to: file, atomically: true, encoding: .utf8)
        let tail = LedgerTail(url: file, firstRetryDelay: 0.05, maxRetryDelay: 0.2)
        tail.start {}
        defer { tail.stop() }
        #expect(tail.snapshot()["/w/a"]?.note == "one")
        try FileManager.default.removeItem(at: file)
        try await Task.sleep(for: .milliseconds(400)) // gone for a while, not an atomic swap
        try ledgerLine("/w/z", note: "fresh").write(to: file, atomically: true, encoding: .utf8)
        try await settle { tail.snapshot()["/w/z"]?.note == "fresh" }
        #expect(tail.snapshot()["/w/a"] == nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(ledgerLine("/w/y", note: "later").utf8))
        try handle.close()
        try await settle { tail.snapshot()["/w/y"]?.note == "later" }
    }

    // MARK: - #13 watcher path matching

    @Test
    func watcher_onlyIgnoresObjectsAndLogsInsideTheGitDir() {
        let gitDir = "/Users/me/work/logs/api/.git"
        #expect(GitDirWatcher.isRelevant(gitDir + "/refs/heads/x", gitDir: gitDir))
        #expect(GitDirWatcher.isRelevant(gitDir + "/worktrees/a/HEAD", gitDir: gitDir))
        #expect(GitDirWatcher.isRelevant(gitDir + "/objects/ab/cdef", gitDir: gitDir) == false)
        #expect(GitDirWatcher.isRelevant(gitDir + "/logs/HEAD", gitDir: gitDir) == false)
        #expect(GitDirWatcher.isRelevant(gitDir + "/worktrees/a/logs/HEAD", gitDir: gitDir) == false)
        let objectsRepo = "/Users/me/objects/lib/.git"
        #expect(GitDirWatcher.isRelevant(objectsRepo + "/refs/heads/x", gitDir: objectsRepo))
    }

    @Test
    func watcher_firesForARepoWhosePathContainsLogs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-\(UUID().uuidString)").resolvingSymlinksInPath()
        let repo = root.appendingPathComponent("logs/api")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.commit("a.txt", "x\n", "base", in: repo)
        let box = SafetyEventBox()
        let watcher = GitDirWatcher(gitDirs: [repo.path: repo.path + "/.git"], latency: 0.1) { box.add($0) }
        defer { watcher.stop() }
        Thread.sleep(forTimeInterval: 0.5)
        try TowerFixture.runGit(["branch", "watched", "main"], in: repo)
        #expect(box.wait(for: [repo.path], timeout: 5))
    }

    // MARK: - #15 unknown is not ready

    @Test
    func lanes_anUnknownForecastIsNotReadyAndSaysSo() {
        let unknown = TowerLanes.assign(TowerFacts(buildStatus: "ok", ahead: 3, behind: 1, dirty: 0, forecast: .unknown))
        #expect("\(unknown.lane.title): \(unknown.reason)" == "Needs you: 3 ahead, couldn't check merge with main")
        let clean = TowerLanes.assign(TowerFacts(buildStatus: "ok", ahead: 3, behind: 1, dirty: 0, forecast: .clean))
        #expect(clean.reason == "3 ahead, clean")
    }

    @Test
    func lanes_aMissingForecastBehindMainIsNotCleanButStaysReady() {
        let notYet = TowerLanes.assign(TowerFacts(buildStatus: "ok", ahead: 3, behind: 1, dirty: 0, forecast: nil))
        #expect("\(notYet.lane.title): \(notYet.reason)" == "Ready: 3 ahead, merge not checked yet")
        // Not behind main: nothing to merge, so "clean" is true without a forecast.
        let level = TowerLanes.assign(TowerFacts(buildStatus: "ok", ahead: 3, behind: 0, dirty: 0, forecast: nil))
        #expect("\(level.lane.title): \(level.reason)" == "Ready: 3 ahead, clean")
    }

    @Test
    func liveness_aJoinWithNoTimestampIsNotProvenByItsPid() {
        let worktree = LedgerWorktree(
            path: "/w/a", live: ["a:s"],
            sessions: ["a:s": LedgerSession(pid: 42, host: "h", since: nil)],
            lastEvent: date("2026-11-01T10:00:00+01:00")
        )
        let now = date("2026-11-20T10:00:00+01:00")
        #expect(LedgerLiveness.evidence(for: worktree, host: "h", now: now, probe: ReusedProbe(started: nil)) == nil)
    }

    // MARK: - #17 retire timeout

    @Test
    func retire_aHungPythonIsKilledAndComesBackAsAFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-fake-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("python3")
        try Data("#!/bin/sh\necho partial\nexec sleep 30\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let started = Date()
        let out = try #require(RetireCommand.run(["x"], timeout: 0.5, locator: FixedLocator(url: script)))
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(out.timedOut)
        #expect(out.status != 0)
        #expect(out.text == "partial\ntimed out after 0.5s")
    }

    @Test
    func retire_aFinishedRunIsNotMarkedTimedOut() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-fake-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = root.appendingPathComponent("python3")
        try Data("#!/bin/sh\necho done\nexit 7\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let out = try #require(RetireCommand.run(["x"], locator: FixedLocator(url: script)))
        #expect(out == RetireCommand.Output(status: 7, text: "done\n"))
    }
}

struct FixedLocator: ExecutableLocator {
    let url: URL?
    func locate(executable _: String) -> URL? { self.url }
    func version(at _: URL) -> (version: String?, error: String?) { (nil, nil) }
    var isSandboxed: Bool { false }
}

private final class SafetyEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<String>()

    func add(_ paths: Set<String>) { self.lock.withLock { self.seen.formUnion(paths) } }

    func wait(for paths: Set<String>, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if self.lock.withLock({ paths.isSubset(of: self.seen) }) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}
