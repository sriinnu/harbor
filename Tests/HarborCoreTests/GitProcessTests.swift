import Foundation
@testable import HarborCore
import Testing

/// The git runner must not hang on big output or a stuck process. Fake `git` scripts stand in
/// for git so each case is exact and fast; nothing here touches a real repository or git config.
struct GitProcessTests {
    private func fakeGit(_ script: String) throws -> (dir: URL, git: URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("harbor-gitprocess-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let git = dir.appendingPathComponent("git")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: git)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: git.path)
        return (dir, git)
    }

    @Test(.timeLimit(.minutes(1)))
    func outputLargerThanThePipeBufferIsReadInFull() throws {
        // 2 MB on stdout and 1 MB on stderr: far past the 64 KB pipe buffer.
        let fixture = try self.fakeGit("head -c 2097152 /dev/zero | tr '\\0' 'a'\nhead -c 1048576 /dev/zero | tr '\\0' 'b' >&2")
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let result = try GitProcess.run(gitURL: fixture.git, arguments: ["status"], in: fixture.dir, timeout: 30)
        #expect(result.status == 0)
        #expect(result.stdout.utf8.count == 2_097_152)
        #expect(result.stderr.utf8.count == 1_048_576)
    }

    @Test(.timeLimit(.minutes(1)))
    func aProcessThatOutlivesItsTimeoutIsStoppedWithAClearError() throws {
        let fixture = try self.fakeGit("sleep 60")
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let started = Date()
        do {
            _ = try GitProcess.run(gitURL: fixture.git, arguments: ["fetch", "--prune"], in: fixture.dir, timeout: 1)
            Issue.record("expected a timeout")
        } catch let error as GitProcessTimeout {
            #expect(error == GitProcessTimeout(command: "fetch", seconds: 1))
            #expect(error.errorDescription == "git fetch did not finish within 1 seconds and was stopped. It may be waiting for a credential, a lock or the network.")
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test(.timeLimit(.minutes(1)))
    func gitIsToldNeverToPromptAndStdinIsClosed() throws {
        let fixture = try self.fakeGit("echo \"prompt=$GIT_TERMINAL_PROMPT\"\nif read line; then echo stdin=open; else echo stdin=closed; fi")
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let result = try GitProcess.run(gitURL: fixture.git, arguments: [], in: fixture.dir, timeout: 30)
        #expect(result.stdout == "prompt=0\nstdin=closed\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func theLocalGitServiceReportsAStuckGitInsteadOfHangingTheRefresh() throws {
        let fixture = try self.fakeGit("sleep 60")
        defer { try? FileManager.default.removeItem(at: fixture.dir) }
        let service = LocalGitService(
            executableLocator: MockExecutableLocator(path: fixture.git.path),
            commandTimeout: 1
        )
        do {
            try service.fetch(at: fixture.dir)
            Issue.record("expected a timeout")
        } catch let error as GitProcessTimeout {
            #expect(error.command == "fetch")
        }
    }
}
