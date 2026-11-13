import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// Review cleanups: Tower reads the pull answer fresh, a linked worktree is not its own repo,
/// Tower's isolated git keeps only `safe.directory` and `url.*.insteadOf`, and the hotkey opens
/// the system menu when the theme has no panel.
struct TowerCleanupTests {
    // MARK: - helpers

    @MainActor
    private func wait(timeout: Duration = .seconds(20), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "tower", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    // MARK: - 1. Tower reads the store's pull answer

    @MainActor
    private final class Answer {
        var reads = 0
        var value: [String: Set<String>]? = [:]
    }

    /// Tower never searches: each pass reads the answer the store has right now, so there is no
    /// copy to go stale. A changed answer (`pullsChanged`) rescans; an unchanged one does not.
    @Test @MainActor
    func pulls_areReadFreshEveryPass_andAChangedAnswerRescans() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try fixture.git(["remote", "add", "origin", "https://github.com/o/r.git"])
        let ledger = fixture.root.appendingPathComponent("events.jsonl")
        try Data().write(to: ledger)
        let box = Answer()
        let model = TowerModel(
            tail: LedgerTail(url: ledger, firstRetryDelay: 0.05, maxRetryDelay: 0.2), home: fixture.root.path,
            pullFetch: { box.reads += 1; return box.value }
        )
        model.start(rootPaths: [fixture.root.path])
        defer { model.stop() }
        try await self.wait { model.isLoading == false && model.repos[fixture.repo.path]?.phase == .forecast }
        let clean = AgentLedger.normalizedPath(fixture.worktreeClean.path)
        #expect(model.row(id: clean)?.lane == .ready)
        let first = box.reads

        // The store gets an answer naming feat-clean: the same scan, now "in review".
        box.value = ["o/r": ["feat-clean"]]
        model.pullsChanged()
        try await self.wait { model.row(id: clean)?.lane == .inReview }

        // The pull request is merged or closed: the next answer drops it, with no event and no wait.
        let before = model.scanPasses
        box.value = [:]
        model.pullsChanged()
        try await self.wait { model.row(id: clean)?.lane == .ready && model.scanPasses > before }
        #expect(box.reads > first)

        // Unchanged answer: read, compared, no new pass.
        try await Task.sleep(for: .milliseconds(1500))
        let passes = model.scanPasses
        model.pullsChanged()
        try await Task.sleep(for: .milliseconds(900))
        #expect(model.scanPasses == passes)
    }

    // MARK: - 1b. account switch and folder removal

    @Test @MainActor
    func reset_dropsEverythingFoundForTheOldAccount_andStopDropsRemovedFolders() async throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        let ledger = fixture.root.appendingPathComponent("events.jsonl")
        try Data().write(to: ledger)
        let model = TowerModel(
            tail: LedgerTail(url: ledger, firstRetryDelay: 0.05, maxRetryDelay: 0.2), home: fixture.root.path,
            pullFetch: { [:] }
        )
        model.start(rootPaths: [fixture.root.path])
        try await self.wait { model.isLoading == false && model.repos[fixture.repo.path]?.phase == .forecast }
        #expect(model.repos.isEmpty == false)

        model.reset()
        #expect(model.repos.isEmpty)
        #expect(model.needsYouCount == 0)
        // It starts over for the new account.
        try await self.wait { model.repos[fixture.repo.path]?.phase == .forecast }

        model.stop()
        #expect(model.repos.isEmpty)
        #expect(model.repoCount == 0)
    }

    // MARK: - 2. one Tower, shared

    @Test @MainActor
    func panel_showsTheModelItIsGivenInsteadOfScanningWithItsOwn() {
        let model = TowerModel(pullFetch: { nil })
        let view = HarborPanelView(session: Session(), content: { HarborPanelContent() }, actions: HarborPanelActions(), tower: model)
        #expect(view.tower === model)
    }

    // MARK: - 3. a linked worktree is not a repo of its own

    @Test
    func discover_listsARepoOnceEvenWhenItsWorktreeSitsInTheProjectFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-disc-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects")
        let app = projects.appendingPathComponent("app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: app)
        try TowerFixture.commit("a.txt", "x\n", "base", in: app)
        try TowerFixture.runGit(["worktree", "add", projects.appendingPathComponent("app-feat").path, "-b", "feat"], in: app)
        let git = try #require(TowerGit())
        // Before: the two are listed as separate repos.
        let raw = LocalProjectsService().discoverRepoRoots(rootPaths: [projects.path]).map(\.path).map(AgentLedger.normalizedPath).sorted()
        #expect(raw == [app.path, projects.appendingPathComponent("app-feat").path].sorted())
        #expect(TowerRepos.discover(rootPaths: [projects.path], ledger: [:], git: git) == [app.path])
    }

    @Test
    func discover_aWorktreeAloneStandsForItsMainCheckout() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-disc2-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("elsewhere/app")
        let scanned = root.appendingPathComponent("scanned")
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: scanned, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: main)
        try TowerFixture.commit("a.txt", "x\n", "base", in: main)
        try TowerFixture.runGit(["worktree", "add", scanned.appendingPathComponent("wt").path, "-b", "feat"], in: main)
        let git = try #require(TowerGit())
        #expect(TowerRepos.discover(rootPaths: [scanned.path], ledger: [:], git: git) == [main.path])
    }

    // MARK: - 4. global config passthrough

    private func plantConfig(_ root: URL) throws {
        try Data("""
        [user]
        \tname = Leaky
        [core]
        \tsshCommand = evil
        [alias]
        \tst = status
        [safe]
        \tdirectory = /srv/shared
        \tdirectory = *
        [url "git@github.com:"]
        \tinsteadOf = gh:
        [url "git@github.com:acme/"]
        \tinsteadOf = work:
        [merge "probe"]
        \tdriver = touch /tmp/never
        """.utf8).write(to: root.appendingPathComponent(".gitconfig"))
    }

    @Test
    func globalConfig_passesOnlySafeDirectoryAndInsteadOf() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try self.plantConfig(fixture.root)
        let git = try #require(TowerGit())
        #expect(TowerGlobalConfig.arguments(git: git, home: fixture.root.path) == [
            "-c", "safe.directory=/srv/shared", "-c", "safe.directory=*",
            "-c", "url.git@github.com:.insteadof=gh:", "-c", "url.git@github.com:acme/.insteadof=work:"
        ])
        // No config at all: nothing passes.
        let empty = fixture.root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(TowerGlobalConfig.arguments(git: git, home: empty.path).isEmpty)
    }

    /// A `git` that logs its argv, one line per call, then runs the real one. The forecast runs
    /// under a sandbox that denies the log, so for `merge-tree` it instead exits 99 when the
    /// passthrough keys leaked into its argv; a leak then shows as an unknown forecast.
    private func loggingGit(in root: URL) throws -> (locator: FixedLocator, log: URL) {
        let log = root.appendingPathComponent("argv.log")
        let script = root.appendingPathComponent("loggit")
        try Data("#!/bin/sh\ncase \"$*\" in *merge-tree*) case \"$*\" in *safe.directory*|*insteadof*) exit 99;; esac; exec /usr/bin/git \"$@\";; esac\necho \"$*\" >> '\(log.path)'\nexec /usr/bin/git \"$@\"\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (FixedLocator(url: script), log)
    }

    @Test
    func scan_statusAndListGetThePassthroughButTheForecastKeepsItsIsolation() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try self.plantConfig(fixture.root)
        let (locator, log) = try self.loggingGit(in: fixture.root)
        let git = try #require(TowerGit(locator: locator))
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive(), xdgConfigHome: nil)
        let final = try #require(scanner.scan(repo: fixture.repo.path, ledger: [:]) { _ in })
        #expect(final.phase == .forecast)
        let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
        let fixed = "--no-optional-locks -c core.hooksPath=/dev/null -c core.fsmonitor=false"
        let passed = "-c safe.directory=/srv/shared -c safe.directory=* -c url.git@github.com:.insteadof=gh: -c url.git@github.com:acme/.insteadof=work:"
        let status = lines.filter { $0.contains(" status ") }
        #expect(status.count == 3)
        for line in status { #expect(line.hasPrefix("\(fixed) \(passed) status --porcelain=v2")) }
        #expect(lines.contains("\(fixed) \(passed) worktree list --porcelain"))
        // The forecast got the isolated git: it ran (a leaked key would have made it exit 99).
        let forecasts = Dictionary(uniqueKeysWithValues: final.rows.map { ($0.branch ?? "", $0.forecast) })
        #expect(forecasts["feat-a"] == .conflicts(["a.txt"]))
        #expect(forecasts["feat-b"] == .conflicts(["a.txt"]))
        #expect(forecasts["feat-clean"] == .clean)
        // The helpers the forecast makes (empty tree, merge drivers) are as isolated as before.
        #expect(lines.contains { $0.contains("hash-object -t tree /dev/null") && !$0.contains("safe.directory") })
    }

    @Test
    func remoteSlugs_followsTheUsersInsteadOfAliases() throws {
        let fixture = try TowerFixture()
        defer { fixture.remove() }
        try self.plantConfig(fixture.root)
        try fixture.git(["remote", "add", "origin", "work:widgets.git"])
        let git = try #require(TowerGit())
        let scanner = TowerScanner(git: git, home: fixture.root.path, host: "h", now: Date(), probe: NeverAlive(), xdgConfigHome: nil)
        #expect(scanner.remoteSlugs(repo: fixture.repo.path) == ["acme/widgets"])
    }

    // MARK: - 5. the hotkey in system-menu mode

    @Test
    @MainActor func hotkey_opensThePanelOrTheStatusItemMenuByTheSurfaceInUse() {
        #expect(StatusItemController.hotkeySurface(usesPanel: true) == .panel)
        #expect(StatusItemController.hotkeySurface(usesPanel: false) == .menu)
    }
}
