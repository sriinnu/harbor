import Foundation
@testable import HarborCore
import XCTest

final class LocalGitCommandTests: XCTestCase {
    private func status(
        branch: String = "main", clean: Bool = true, ahead: Int? = 0, behind: Int? = 0,
        counts: LocalDirtyCounts? = nil, files: [String] = [], upstream: String? = "origin/main"
    ) -> LocalRepoStatus {
        LocalRepoStatus(
            path: URL(fileURLWithPath: "/tmp/r"), name: "r", fullName: "o/r", branch: branch, isClean: clean,
            aheadCount: ahead, behindCount: behind,
            syncState: LocalSyncState.resolve(isClean: clean, ahead: ahead, behind: behind),
            dirtyCounts: counts, dirtyFiles: files, upstreamBranch: upstream
        )
    }

    // MARK: Presentation

    func testAheadBehindText() {
        XCTAssertEqual(self.status(ahead: 0, behind: 0).aheadBehindText, "in sync")
        XCTAssertEqual(self.status(ahead: 2, behind: 0).aheadBehindText, "↑2")
        XCTAssertEqual(self.status(ahead: 0, behind: 3).aheadBehindText, "↓3")
        XCTAssertEqual(self.status(ahead: 1, behind: 4).aheadBehindText, "↑1 ↓4")
        XCTAssertEqual(self.status(ahead: nil, behind: nil, upstream: nil).aheadBehindText, "no upstream")
    }

    func testSummaryLine() {
        XCTAssertEqual(self.status(ahead: 1, behind: 2).summaryLine, "main · clean · ↑1 ↓2")
        let dirty = self.status(
            branch: "feat/x", clean: false, ahead: 0, behind: 0,
            counts: LocalDirtyCounts(added: 1, modified: 2, deleted: 1)
        )
        XCTAssertEqual(dirty.summaryLine, "feat/x · 4 changed · in sync")
        XCTAssertEqual(self.status(clean: false, files: ["a", "b"]).dirtyText, "2 changed")
        XCTAssertEqual(self.status(clean: false).dirtyText, "changed")
    }

    func testFastForwardIsOfferedOnlyWhenItCannotLoseAnything() {
        XCTAssertTrue(self.status(ahead: 0, behind: 2).canFastForward)
        XCTAssertFalse(self.status(ahead: 0, behind: 0).canFastForward)
        XCTAssertFalse(self.status(ahead: 1, behind: 2).canFastForward)
        XCTAssertFalse(self.status(clean: false, ahead: 0, behind: 2).canFastForward)
        XCTAssertFalse(self.status(branch: "detached", ahead: 0, behind: 2).canFastForward)
        XCTAssertFalse(self.status(ahead: nil, behind: nil).canFastForward)
    }

    func testOnlyFetchAndSwitchRunWithoutAsking() {
        XCTAssertEqual(
            [LocalGitCommand.fetch, .pullFastForward, .sync, .rebase, .reset, .switchBranch("x")].map(\.needsConfirm),
            [false, true, true, true, true, false]
        )
        XCTAssertEqual(
            [LocalGitCommand.fetch, .pullFastForward, .sync, .rebase, .reset, .switchBranch("x")].map(\.isDestructive),
            [false, false, false, false, true, false]
        )
    }

    func testConfirmQuestionsNameTheBranchAndTheCost() {
        XCTAssertEqual(
            LocalGitCommand.pullFastForward.confirmQuestion(branch: "main", upstream: "origin/main"),
            "Fast-forward main to origin/main? Refuses if the histories diverged."
        )
        XCTAssertEqual(
            LocalGitCommand.reset.confirmQuestion(branch: "main", upstream: nil),
            "Reset main to its upstream? Local commits and uncommitted changes are lost."
        )
        XCTAssertEqual(
            LocalGitCommand.rebase.confirmQuestion(branch: "feat", upstream: "origin/feat"),
            "Rebase feat onto origin/feat? This rewrites your local commits."
        )
    }
}

/// Real repositories in a temp folder. The environment hides the user's global and system
/// git config, so their hooks and commit signing never run in a fixture.
final class LocalGitFastForwardTests: XCTestCase {
    private var root = URL(fileURLWithPath: "/")
    private var saved: [String: String?] = [:]
    private static let isolation = [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
        "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com"
    ]

    override func setUpWithError() throws {
        for (key, value) in Self.isolation {
            self.saved[key] = ProcessInfo.processInfo.environment[key]
            setenv(key, value, 1)
        }
        self.root = FileManager.default.temporaryDirectory.appending(path: "harbor-ff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        for (key, value) in self.saved {
            if let value { setenv(key, value, 1) } else { unsetenv(key) }
        }
        try? FileManager.default.removeItem(at: self.root)
    }

    @discardableResult
    private func git(_ args: [String], in dir: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, "git \(args.joined(separator: " ")): \(out)")
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commit(_ file: String, in dir: URL) throws {
        try file.write(to: dir.appending(path: file), atomically: true, encoding: .utf8)
        try self.git(["add", file], in: dir)
        try self.git(["commit", "-m", file], in: dir)
    }

    /// A bare origin, a working clone, and a second clone that pushes ahead of the first.
    private struct Repos {
        let origin: URL
        let mine: URL
        let other: URL
    }

    private func makeRepos() throws -> Repos {
        let origin = self.root.appending(path: "origin.git")
        let mine = self.root.appending(path: "mine")
        let other = self.root.appending(path: "other")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try self.git(["init", "--bare", "--initial-branch=main"], in: origin)
        try self.git(["clone", origin.path, mine.path], in: self.root)
        try self.commit("a", in: mine)
        try self.git(["push", "origin", "main"], in: mine)
        try self.git(["clone", origin.path, other.path], in: self.root)
        try self.commit("b", in: other)
        try self.git(["push", "origin", "main"], in: other)
        return Repos(origin: origin, mine: mine, other: other)
    }

    func testFetchThenFastForwardMovesTheBranch() throws {
        let repos = try self.makeRepos()
        let service = LocalGitService()
        let before = try self.git(["rev-parse", "HEAD"], in: repos.mine)
        try service.perform(.fetch, at: repos.mine)
        XCTAssertEqual(try self.git(["rev-parse", "HEAD"], in: repos.mine), before, "fetch must not move HEAD")
        try service.perform(.pullFastForward, at: repos.mine)
        XCTAssertEqual(
            try self.git(["rev-parse", "HEAD"], in: repos.mine), try self.git(["rev-parse", "HEAD"], in: repos.other)
        )
    }

    func testFastForwardRefusesADivergedBranch() throws {
        let repos = try self.makeRepos()
        try self.commit("mine-only", in: repos.mine)
        let before = try self.git(["rev-parse", "HEAD"], in: repos.mine)
        let service = LocalGitService()
        try service.perform(.fetch, at: repos.mine)
        XCTAssertThrowsError(try service.perform(.pullFastForward, at: repos.mine))
        XCTAssertEqual(try self.git(["rev-parse", "HEAD"], in: repos.mine), before, "a refused pull leaves HEAD alone")
    }

    func testFastForwardRefusesADirtyTree() throws {
        let repos = try self.makeRepos()
        try "x".write(to: repos.mine.appending(path: "a"), atomically: true, encoding: .utf8)
        try self.git(["fetch"], in: repos.mine)
        XCTAssertThrowsError(try LocalGitService().perform(.pullFastForward, at: repos.mine)) { error in
            XCTAssertEqual(error.localizedDescription, "Working tree has uncommitted changes.")
        }
    }
}
