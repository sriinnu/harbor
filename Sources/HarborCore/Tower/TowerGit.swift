import Foundation

/// Runs read-only git for the tower: `--no-optional-locks` first, no hooks, no user config, no
/// prompts. Blocking; call it off the main thread.
public struct TowerGit: Sendable {
    public struct Result: Sendable {
        public let status: Int32
        public let stdout: String
    }

    /// The longest one read-only git call may take (the merge forecast is the slowest by far).
    public static let defaultTimeout: TimeInterval = 60

    let gitURL: URL
    /// `-c key=value` pairs handed to every call after the fixed ones: the few keys of the
    /// user's global config that reads need (see `TowerGlobalConfig`). Empty by default.
    let passthrough: [String]
    /// How long a call may take unless it says otherwise.
    let timeout: TimeInterval

    private init(gitURL: URL, passthrough: [String], timeout: TimeInterval) {
        self.gitURL = gitURL
        self.passthrough = passthrough
        self.timeout = timeout
    }

    /// The same git, with `arguments` (from `TowerGlobalConfig`) added to every call.
    public func passingThrough(_ arguments: [String]) -> TowerGit {
        TowerGit(gitURL: self.gitURL, passthrough: arguments, timeout: self.timeout)
    }

    public init?(locator: ExecutableLocator? = nil, timeout: TimeInterval = TowerGit.defaultTimeout) {
        #if os(macOS)
        let locator = locator ?? MacOSExecutableLocator()
        #else
        let locator = locator ?? POSIXExecutableLocator()
        #endif
        guard let url = locator.locate(executable: "git") else { return nil }
        self.gitURL = url
        self.passthrough = []
        self.timeout = timeout
    }

    /// The exact argv after the executable.
    public static func arguments(_ arguments: [String]) -> [String] {
        ["--no-optional-locks", "-c", "core.hooksPath=/dev/null", "-c", "core.fsmonitor=false"] + arguments
    }

    /// nil when git could not be started; otherwise its exit status and stdout.
    ///
    /// `wrapper` runs git through another program (the forecast's `sandbox-exec`): `wrapper.url`
    /// is started with `wrapper.leading`, then git's path, then git's arguments.
    public func run(
        _ arguments: [String], in directory: String, environment: [String: String] = [:],
        wrapper: (url: URL, leading: [String])? = nil, timeout: TimeInterval? = nil
    ) -> Result? {
        let executable: URL
        let argv: [String]
        if let wrapper {
            executable = wrapper.url
            argv = wrapper.leading + [self.gitURL.path] + Self.arguments(self.passthrough + arguments)
        } else {
            executable = self.gitURL
            argv = Self.arguments(self.passthrough + arguments)
        }
        var env: [String: String] = [
            "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"
        ]
        for (key, value) in environment { env[key] = value }
        // The shared runner drains both pipes and stops a git that outlives `timeout`, so one hung
        // git can never leave a scan (and the menu bar badge behind it) waiting forever. A git
        // that timed out reads as "could not be run": nil.
        guard let result = try? GitProcess.run(
            gitURL: executable, arguments: argv, in: URL(fileURLWithPath: directory, isDirectory: true),
            timeout: timeout ?? self.timeout, environment: env
        ) else { return nil }
        return Result(status: result.status, stdout: result.stdout)
    }

    /// The first line of `git version`, e.g. `git version 2.54.0 (Apple Git-157)`; nil if git can't run.
    public func versionString() -> String? {
        self.output(["version"], in: NSTemporaryDirectory())?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// stdout on exit 0, else nil.
    public func output(_ arguments: [String], in directory: String) -> String? {
        guard let result = self.run(arguments, in: directory), result.status == 0 else { return nil }
        return result.stdout
    }
}

// MARK: - Parsers

public struct AheadBehind: Equatable, Sendable {
    public let ahead: Int
    public let behind: Int

    public init(ahead: Int, behind: Int) {
        self.ahead = ahead
        self.behind = behind
    }
}

public struct BranchTip: Equatable, Sendable {
    public let counts: AheadBehind
    public let committed: Date?
}

public enum TowerGitParse {
    /// The first git the merge forecast is allowed to run on: it needs the global `--attr-source`
    /// option (to ignore a repo's tracked `.gitattributes`) and `merge-tree --write-tree`. Both
    /// are in 2.41; git's release notes are not installed here, so whether `--attr-source`
    /// arrived a release earlier is unchecked, and 2.41 is simply the number known to work.
    /// `for-each-ref`'s `%(ahead-behind:)` also dates from 2.41, but the counts do not depend on
    /// this number: `TowerScanner` falls back to `rev-list` whenever that format is refused.
    public static let forecastMinimumGit = (major: 2, minor: 41)

    /// (major, minor) out of `git version 2.54.0 (Apple Git-157)`; nil if it doesn't parse.
    public static func gitVersion(_ text: String) -> (major: Int, minor: Int)? {
        let words = text.split(separator: " ")
        guard words.count >= 3, words[0] == "git", words[1] == "version" else { return nil }
        let parts = words[2].split(separator: ".")
        guard parts.count >= 2, let major = Int(parts[0]), let minor = Int(parts[1]) else { return nil }
        return (major, minor)
    }

    /// True when this git can run the merge forecast. An unparseable version is treated as new
    /// enough: the forecast itself then says `.unknown` if the option is missing.
    public static func supportsForecast(versionText: String) -> Bool {
        guard let version = gitVersion(versionText) else { return true }
        return (version.major, version.minor) >= (forecastMinimumGit.major, forecastMinimumGit.minor)
    }

    /// The one `for-each-ref` that yields ahead/behind and the tip's commit time for every local branch.
    public static func branchArguments(base: String) -> [String] {
        ["for-each-ref", "--format=%(refname)%09%(ahead-behind:\(base))%09%(committerdate:unix)", "refs/heads"]
    }

    /// The fallback for a git without `%(ahead-behind:)`: every local branch's tip commit time.
    public static let branchDatesArguments = ["for-each-ref", "--format=%(refname)%09%(committerdate:unix)", "refs/heads"]

    /// `refs/heads/feat/x<TAB>1762800000` per line, as `branchDatesArguments` prints.
    public static func branchDates(_ raw: String) -> [String: Date] {
        var result: [String: Date] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, let seconds = TimeInterval(fields[1]) else { continue }
            let ref = String(fields[0])
            let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            result[name] = Date(timeIntervalSince1970: seconds)
        }
        return result
    }

    /// `refs/heads/feat/x<TAB>3 5<TAB>1762800000` per line (ahead, then behind). Lines that
    /// don't parse are skipped; the commit time is optional.
    public static func branchTips(_ raw: String) -> [String: BranchTip] {
        var result: [String: BranchTip] = [:]
        for line in raw.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 2 else { continue }
            let counts = fields[1].split(whereSeparator: \.isWhitespace)
            guard counts.count == 2, let ahead = Int(counts[0]), let behind = Int(counts[1]) else { continue }
            let ref = String(fields[0])
            let name = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            let committed = fields.count >= 3 ? TimeInterval(fields[2]).map(Date.init(timeIntervalSince1970:)) : nil
            result[name] = BranchTip(counts: AheadBehind(ahead: ahead, behind: behind), committed: committed)
        }
        return result
    }

    /// `rev-list --left-right --count base...HEAD` prints "behind<TAB>ahead".
    public static func leftRight(_ raw: String) -> AheadBehind? {
        let parts = raw.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, let behind = Int(parts[0]), let ahead = Int(parts[1]) else { return nil }
        return AheadBehind(ahead: ahead, behind: behind)
    }

    /// Changed paths from `status --porcelain=v2`: ordinary, renamed (new path) and untracked entries.
    public static func statusPaths(_ raw: String) -> [String] {
        var paths: [String] = []
        for line in raw.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("1 ") {
                // 1 XY sub mH mI mW hH hI path
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                if fields.count == 9 { paths.append(String(fields[8])) }
            } else if line.hasPrefix("2 ") {
                // 2 XY sub mH mI mW hH hI Xscore path<TAB>origPath
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                if fields.count == 10 {
                    paths.append(String(fields[9].split(separator: "\t", maxSplits: 1)[0]))
                }
            } else if line.hasPrefix("u ") {
                // u XY sub m1 m2 m3 mW h1 h2 h3 path
                let fields = line.split(separator: " ", maxSplits: 10, omittingEmptySubsequences: false)
                if fields.count == 11 { paths.append(String(fields[10])) }
            } else if line.hasPrefix("? ") {
                paths.append(String(line.dropFirst(2)))
            }
        }
        return paths
    }

    /// Files named in `merge-tree --write-tree --name-only` output: after the tree id, up to the
    /// first blank line. Deduplicated, in order.
    public static func conflictedFiles(_ raw: String) -> [String] {
        var files: [String] = []
        var seen = Set<String>()
        var lines = raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).makeIterator()
        _ = lines.next() // the tree id
        while let line = lines.next(), !line.isEmpty {
            if seen.insert(String(line)).inserted { files.append(String(line)) }
        }
        return files
    }
}
