import Foundation

/// What a finished git process left behind.
struct GitProcessResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

/// A git process that was stopped because it ran past its time limit.
struct GitProcessTimeout: LocalizedError, Equatable {
    let command: String
    let seconds: TimeInterval

    var errorDescription: String? {
        "git \(self.command) did not finish within \(Int(self.seconds)) seconds and was stopped. "
            + "It may be waiting for a credential, a lock or the network."
    }
}

/// Runs one git process to completion. Both pipes are drained while it runs (a large listing
/// would otherwise fill a pipe and block git forever), stdin is closed, git is told never to
/// prompt, and a process that outlives `timeout` is terminated and then killed.
enum GitProcess {
    /// How long a terminated process gets to exit before it is killed.
    private static let graceSeconds: TimeInterval = 2

    static func run(
        gitURL: URL,
        arguments: [String],
        in directory: URL,
        timeout: TimeInterval,
        environment extra: [String: String] = [:]
    ) throws -> GitProcessResult {
        let process = Process()
        process.executableURL = gitURL
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var environment = ProcessInfo.processInfo.environment
        environment["GIT_TERMINAL_PROMPT"] = "0"
        for (key, value) in extra { environment[key] = value }
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        let stdout = PipeReader(outputPipe.fileHandleForReading)
        let stderr = PipeReader(errorPipe.fileHandleForReading)

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + self.graceSeconds) == .timedOut {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                _ = exited.wait(timeout: .now() + self.graceSeconds)
            }
        }
        // A grandchild (ssh, a credential helper) can keep a pipe open after git is gone; take what
        // has arrived rather than wait for it.
        let drainWait: TimeInterval = timedOut ? self.graceSeconds : 30
        let out = stdout.finish(waiting: drainWait)
        let err = stderr.finish(waiting: drainWait)

        if timedOut {
            throw GitProcessTimeout(command: arguments.first ?? "", seconds: timeout)
        }
        return GitProcessResult(
            status: process.terminationStatus,
            stdout: String(bytes: out, encoding: .utf8) ?? "",
            stderr: String(bytes: err, encoding: .utf8) ?? ""
        )
    }
}

/// Reads a pipe to end of file on its own thread, so the process never blocks on a full pipe.
final class PipeReader: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let done = DispatchSemaphore(value: 0)
    private let handle: FileHandle

    init(_ handle: FileHandle) {
        self.handle = handle
        Thread.detachNewThread { [self] in
            while true {
                let chunk = self.handle.availableData
                if chunk.isEmpty { break }
                self.lock.withLock { self.data.append(chunk) }
            }
            self.done.signal()
        }
    }

    func finish(waiting seconds: TimeInterval) -> Data {
        _ = self.done.wait(timeout: .now() + seconds)
        return self.lock.withLock { self.data }
    }
}
