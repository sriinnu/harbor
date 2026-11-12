import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

@MainActor
struct TowerPanelTests {
    @Test
    func pin_holdsThePanelOpenUntilEveryReasonIsReleased() {
        let navigator = PanelNavigator()
        #expect(navigator.isPinnedOpen == false)
        navigator.pin("run-cleanup", true)
        navigator.pin("tower-retire", true)
        #expect(navigator.isPinnedOpen)
        navigator.pin("run-cleanup", false)
        #expect(navigator.isPinnedOpen)
        navigator.pin("tower-retire", false)
        #expect(navigator.isPinnedOpen == false)
        // Releasing a reason that was never taken is harmless.
        navigator.pin("never", false)
        #expect(navigator.isPinnedOpen == false)
    }

    @Test
    func escape_isBlockedOnlyWhileExecuteRuns() {
        let navigator = PanelNavigator()
        #expect(navigator.blocksEscape == false)
        navigator.pin(PanelPin.towerRetire, true)
        #expect(navigator.isPinnedOpen)
        #expect(navigator.blocksEscape == false) // a confirm still lets Escape back out
        navigator.pin(PanelPin.towerExecuting, true)
        #expect(navigator.blocksEscape)
        navigator.pin(PanelPin.towerExecuting, false)
        #expect(navigator.blocksEscape == false)
    }

    // MARK: - model

    private func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tower-model-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func wait(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "tower", code: 1, userInfo: [NSLocalizedDescriptionKey: "timed out"]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test
    func model_saysGitIsMissingInsteadOfNoRepos() async throws {
        let root = try self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = TowerModel(
            tail: LedgerTail(url: root.appendingPathComponent("events.jsonl")), locator: FixedLocator(url: nil),
            home: root.path, pullFetch: { nil }
        )
        model.start(rootPaths: [root.path])
        defer { model.stop() }
        try await self.wait { model.isLoading == false }
        #expect(model.gitMissing)
        #expect(TowerCopy.gitMissing == "git not found. Tower needs git to read your repos.")
        #expect(model.repos.isEmpty)
    }

    @Test
    func model_noticesARepoWhoseFirstWorktreeAppearsWhileOpenAndWhenTheLedgerFileIsNew() async throws {
        let root = try self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("projects/app")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.commit("a.txt", "x\n", "base", in: repo)
        let ledger = root.appendingPathComponent("ledger/events.jsonl") // not created yet
        let model = TowerModel(tail: LedgerTail(url: ledger, firstRetryDelay: 0.05, maxRetryDelay: 0.2), home: root.path, pullFetch: { nil })
        model.start(rootPaths: [root.appendingPathComponent("projects").path])
        defer { model.stop() }
        try await self.wait { model.isLoading == false }
        #expect(model.repos.isEmpty)

        let worktree = root.appendingPathComponent("wt")
        try TowerFixture.runGit(["worktree", "add", worktree.path, "-b", "feat"], in: repo)
        try FileManager.default.createDirectory(at: ledger.deletingLastPathComponent(), withIntermediateDirectories: true)
        let event = #"{"event":"worktree.born","agent":"a","worktree":"\#(worktree.path)","session":"s","ts":"2026-11-10T10:00:00+01:00","data":{},"branch":"feat","task":null,"repo":"\#(repo.path)"}"# + "\n"
        try event.write(to: ledger, atomically: true, encoding: .utf8)
        try await self.wait { model.repos[repo.path] != nil }
        #expect(model.repos[repo.path]?.rows.map(\.branch) == ["feat"])
    }

    /// A `git` that fails `rev-parse --git-common-dir` while `flag` exists, and is git otherwise.
    private func flakyGit(in root: URL, flag: URL) throws -> FixedLocator {
        let script = root.appendingPathComponent("git")
        try Data("""
        #!/bin/sh
        case "$*" in
          *git-common-dir*) [ -e '\(flag.path)' ] && exit 1;;
        esac
        exec /usr/bin/git "$@"
        """.utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return FixedLocator(url: script)
    }

    @Test
    func model_aFailedRevParseIsNotWatchedAndIsRetriedOnTheNextRewatch() async throws {
        let root = try self.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("projects/app")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try TowerFixture.runGit(["init", "-b", "main"], in: repo)
        try TowerFixture.commit("a.txt", "x\n", "base", in: repo)
        let worktree = root.appendingPathComponent("wt")
        try TowerFixture.runGit(["worktree", "add", worktree.path, "-b", "feat"], in: repo)
        let flag = root.appendingPathComponent("fail")
        try Data().write(to: flag)
        let ledger = root.appendingPathComponent("events.jsonl")
        let locator = try self.flakyGit(in: root, flag: flag)
        let model = TowerModel(tail: LedgerTail(url: ledger, firstRetryDelay: 0.05, maxRetryDelay: 0.2), locator: locator, home: root.path, pullFetch: { nil })
        model.start(rootPaths: [root.appendingPathComponent("projects").path])
        defer { model.stop() }
        try await self.wait { model.isLoading == false && model.repos[repo.path] != nil }
        // The watch attempt has run (isLoading ends after it) and failed: nothing is watched.
        #expect(model.watchedRepos == [])
        try FileManager.default.removeItem(at: flag)
        // Any ledger line triggers a rescan and a rewatch, which must try the repo again.
        let event = #"{"event":"worktree.born","agent":"a","worktree":"\#(worktree.path)","session":"s","ts":"2026-11-10T10:00:00+01:00","data":{},"branch":"feat","task":null,"repo":"\#(repo.path)"}"# + "\n"
        try event.write(to: ledger, atomically: true, encoding: .utf8)
        try await self.wait { model.watchedRepos == [repo.path] }
    }

    @Test
    func controller_theIconRespectsThePinsLikeAnOutsideClick() {
        let controller = HarborPanelController()
        let navigator = PanelNavigator()
        controller.navigator = navigator
        navigator.pin(PanelPin.towerExecuting, true)
        #expect(controller.requestClose(reason: "icon") == false)
        #expect(controller.navigator === navigator)
        navigator.pin(PanelPin.towerExecuting, false)
        #expect(controller.requestClose(reason: "icon"))
        #expect(controller.navigator == nil)
    }

    @Test
    func age_usesTheLargestWholeUnit() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(TowerFormat.age(now.addingTimeInterval(-30), now: now) == "now")
        #expect(TowerFormat.age(now.addingTimeInterval(-300), now: now) == "5m")
        #expect(TowerFormat.age(now.addingTimeInterval(-7300), now: now) == "2h")
        #expect(TowerFormat.age(now.addingTimeInterval(-200_000), now: now) == "2d")
        #expect(TowerFormat.age(nil, now: now) == nil)
    }

    @Test
    func shortPath_keepsTheLastTwoComponents() {
        #expect(TowerFormat.shortPath("a/b/c/d.swift") == "…/c/d.swift")
        #expect(TowerFormat.shortPath("b/d.swift") == "b/d.swift")
        #expect(TowerFormat.shortPath("d.swift") == "d.swift")
    }
}
