import Foundation

/// The retire queue's only link to deletion: it builds the command line for the skill's own
/// `wtr_retire.py` and runs it. It never removes anything itself and never passes `--attest`.
public enum RetireCommand {
    public static var skillScripts: String {
        NSHomeDirectory() + "/.agents/skills/worktree-task-retirement/scripts"
    }

    /// `python3 -I wtr_retire.py worktree --repo R --path P`, dry-run unless `execute`.
    public static func arguments(scripts: String = skillScripts, repo: String, path: String, execute: Bool = false) -> [String] {
        var argv = ["-I", scripts + "/wtr_retire.py", "worktree", "--repo", repo, "--path", path]
        if execute { argv.append("--execute") }
        return argv
    }

    /// `python3 -I wtr_audit.py R --json`, read-only.
    public static func auditArguments(scripts: String = skillScripts, repo: String) -> [String] {
        ["-I", scripts + "/wtr_audit.py", repo, "--json"]
    }

    /// Audit and dry run are reads; a hang there is a bug in the script.
    public static let readTimeout: TimeInterval = 60
    /// `--execute` may remove a big worktree, so it gets longer; past this it is shown as a failure.
    public static let executeTimeout: TimeInterval = 300

    public struct Output: Equatable, Sendable {
        public let status: Int32
        public let text: String
        /// The process was killed for running past its timeout; `text` says so after any partial output.
        public var timedOut = false
    }

    /// Runs python3 with `arguments`; stdout and (unless `mergeStderr` is false) stderr together, verbatim.
    /// nil when python3 is missing. A run past `timeout` seconds is terminated (then killed) and
    /// comes back with `timedOut` set and a nonzero status, so callers show a failure.
    public static func run(
        _ arguments: [String], mergeStderr: Bool = true, timeout: TimeInterval = readTimeout,
        locator: ExecutableLocator? = nil
    ) -> Output? {
        #if os(macOS)
        let locator = locator ?? MacOSExecutableLocator()
        #else
        let locator = locator ?? POSIXExecutableLocator()
        #endif
        guard let python = locator.locate(executable: "python3") else { return nil }
        let process = Process()
        process.executableURL = python
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = mergeStderr ? pipe : FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timedOut = TimeoutFlag()
        let pid = process.processIdentifier
        let killer = DispatchWorkItem {
            guard process.isRunning else { return }
            timedOut.set()
            process.terminate()
            // A script that ignores SIGTERM is killed outright after a short grace.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(pid, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        var text = String(data: data, encoding: .utf8) ?? ""
        if timedOut.value {
            text += (text.isEmpty || text.hasSuffix("\n") ? "" : "\n") + "timed out after \(String(format: "%g", timeout))s"
            return Output(status: process.terminationStatus == 0 ? 124 : process.terminationStatus, text: text, timedOut: true)
        }
        return Output(status: process.terminationStatus, text: text)
    }
}

private final class TimeoutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool { self.lock.withLock { self.flag } }
    func set() { self.lock.withLock { self.flag = true } }
}

/// One worktree the audit calls a CANDIDATE.
public struct RetireCandidate: Equatable, Sendable, Identifiable {
    public var id: String { self.path }
    public let path: String
    public let branch: String?
    public let delivery: String?
    public let idleDays: Int?
}

public enum RetireAudit {
    /// The CANDIDATE rows of `wtr_audit.py --json` (a JSON array of row objects).
    public static func candidates(json: String) -> [RetireCandidate] {
        guard let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            guard row["verdict"] as? String == "CANDIDATE", let path = row["path"] as? String else { return nil }
            return RetireCandidate(
                path: path, branch: row["branch"] as? String, delivery: row["delivery"] as? String,
                idleDays: row["idle_days"] as? Int
            )
        }
    }
}
