import Foundation
@testable import Harbor
@testable import HarborCore
import Testing

/// Auto-sync is opt-in, and "Synced" is announced only when a clone's HEAD actually moved.
struct AutoSyncOptInTests {
    @Test
    func autoSyncIsOffByDefaultAndWhenTheKeyIsMissing() throws {
        #expect(LocalProjectsSettings().autoSyncEnabled == false)
        let decoded = try JSONDecoder().decode(LocalProjectsSettings.self, from: Data("{}".utf8))
        #expect(decoded.autoSyncEnabled == false)
        let optedIn = try JSONDecoder().decode(LocalProjectsSettings.self, from: Data(#"{"autoSyncEnabled":true}"#.utf8))
        #expect(optedIn.autoSyncEnabled == true)
    }

    @Test
    func onlyAClonethatActuallyMovedIsAnnounced() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harbor-autosync-\(UUID().uuidString)", isDirectory: true)
        let scan = base.appendingPathComponent("scan", isDirectory: true)
        try FileManager.default.createDirectory(at: scan, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let origin = base.appendingPathComponent("origin.git", isDirectory: true)
        try self.git(["init", "--bare", origin.path], in: base)
        let upToDate = scan.appendingPathComponent("up-to-date", isDirectory: true)
        let behind = scan.appendingPathComponent("behind", isDirectory: true)
        try self.git(["clone", origin.path, upToDate.lastPathComponent], in: scan)
        try self.git(["switch", "-c", "main"], in: upToDate)
        try self.git(["config", "user.email", "harbor-tests@example.com"], in: upToDate)
        try self.git(["config", "user.name", "Harbor Tests"], in: upToDate)
        try Data("a\n".utf8).write(to: upToDate.appendingPathComponent("README.md"))
        try self.git(["add", "."], in: upToDate)
        try self.git(["commit", "-m", "init"], in: upToDate)
        try self.git(["push", "-u", "origin", "main"], in: upToDate)
        try self.git(["clone", origin.path, behind.lastPathComponent], in: scan)
        try self.git(["switch", "main"], in: behind)
        // Move origin ahead by one commit, then bring `up-to-date` level with it again.
        try Data("a\nb\n".utf8).write(to: upToDate.appendingPathComponent("README.md"))
        try self.git(["add", "."], in: upToDate)
        try self.git(["commit", "-m", "next"], in: upToDate)
        try self.git(["push"], in: upToDate)

        // Auto-sync pulls only where the fetch interval says it is time (`fetchTargets`), so a pass
        // that is due for every clone passes them all.
        let service = LocalProjectsService()
        let roots = service.discoverRepoRoots(rootPath: scan.path, maxDepth: 1)
        let due = Set(roots)

        // First pass: `behind` moves, `up-to-date` has nothing to pull.
        let first = await service.snapshot(repoRoots: roots, autoSyncEnabled: true, concurrencyLimit: 1, fetchTargets: due)
        #expect(Set(first.syncAttemptedStatuses.map(\.name)) == ["behind", "up-to-date"])
        #expect(LocalRepoManager.statusesToAnnounce(from: first).map(\.name) == ["behind"])

        // Second pass: both pulls succeed and neither moves anything, so nothing is announced.
        let second = await service.snapshot(repoRoots: roots, autoSyncEnabled: true, concurrencyLimit: 1, fetchTargets: due)
        #expect(second.syncAttemptedStatuses.count == 2)
        #expect(LocalRepoManager.statusesToAnnounce(from: second).isEmpty)
    }

    /// Auto-sync obeys the fetch interval: a clone the interval did not select is not pulled, even
    /// with auto-sync on and the clone clean and behind.
    @Test
    func autoSyncPullsOnlyWhereTheFetchIntervalIsDue() async throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harbor-autosync-due-\(UUID().uuidString)", isDirectory: true)
        let scan = base.appendingPathComponent("scan", isDirectory: true)
        try FileManager.default.createDirectory(at: scan, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let origin = base.appendingPathComponent("origin.git", isDirectory: true)
        try self.git(["init", "--bare", origin.path], in: base)
        let seed = scan.appendingPathComponent("seed", isDirectory: true)
        let follower = scan.appendingPathComponent("follower", isDirectory: true)
        try self.git(["clone", origin.path, "seed"], in: scan)
        try self.git(["switch", "-c", "main"], in: seed)
        try self.git(["config", "user.email", "harbor-tests@example.com"], in: seed)
        try self.git(["config", "user.name", "Harbor Tests"], in: seed)
        try Data("a\n".utf8).write(to: seed.appendingPathComponent("README.md"))
        try self.git(["add", "."], in: seed)
        try self.git(["commit", "-m", "init"], in: seed)
        try self.git(["push", "-u", "origin", "main"], in: seed)
        try self.git(["clone", origin.path, "follower"], in: scan)
        try self.git(["switch", "main"], in: follower)
        try Data("a\nb\n".utf8).write(to: seed.appendingPathComponent("README.md"))
        try self.git(["add", "."], in: seed)
        try self.git(["commit", "-m", "next"], in: seed)
        try self.git(["push"], in: seed)

        let service = LocalProjectsService()
        let roots = service.discoverRepoRoots(rootPath: scan.path, maxDepth: 1)
        let notDue = await service.snapshot(repoRoots: roots, autoSyncEnabled: true, concurrencyLimit: 1, fetchTargets: [])
        #expect(notDue.syncAttemptedStatuses.isEmpty)
        #expect(notDue.syncedStatuses.isEmpty)
        let followerURL = try #require(roots.first { $0.lastPathComponent == "follower" })
        let due = await service.snapshot(repoRoots: [followerURL], autoSyncEnabled: true, concurrencyLimit: 1, fetchTargets: [followerURL])
        #expect(due.syncAttemptedStatuses.map(\.name) == ["follower"])
        #expect(due.syncedStatuses.map(\.name) == ["follower"])
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = directory
        process.arguments = arguments
        // Fixtures must not inherit the developer's hooks or signing config.
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
        environment["GIT_CONFIG_NOSYSTEM"] = "1"
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "git", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: arguments.joined(separator: " ")])
        }
    }
}
