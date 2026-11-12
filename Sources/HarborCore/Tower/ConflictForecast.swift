import Foundation

/// What merging a branch into main would do, worked out without touching the repo.
public enum MergeForecast: Equatable, Sendable {
    case clean
    case conflicts([String])
    /// git could not say (no merge base, too old for `merge-tree --write-tree`).
    case unknown

    public var conflictCount: Int {
        if case let .conflicts(files) = self { return max(files.count, 1) }
        return 0
    }
}

public enum ConflictForecast {
    public static let sandboxExec = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    /// `git merge-tree --write-tree --name-only base head` with its object writes sent to a
    /// temporary directory and the repo's own object store attached read-only as an alternate.
    /// The temporary directory is deleted afterwards.
    ///
    /// The merge runs under `sandbox-exec` with every file write denied except the scratch
    /// directory and `/dev/null`. Denying everything, not a list of repo paths, also covers an
    /// alternate object store named in `objects/info/alternates` (a `clone --reference` repo), a
    /// worktree and any path nobody thought of. So git's freshen `utime` on an identical loose
    /// object or pack, a merge driver's temp files (`.merge_file_*`) and a driver itself cannot
    /// touch anything of the user's. If the sandbox cannot start, the answer is `.unknown`: the
    /// forecast never runs unsandboxed.
    ///
    /// Attributes come from the empty tree (`--attr-source`), so a repo's `.gitattributes` cannot
    /// name a merge driver; every `merge.<name>.driver` in the repo's config is replaced by `false`;
    /// and a `merge=` in `.git/info/attributes` (which still applies under `--attr-source`) is
    /// `.unknown` without running the merge. `GIT_NO_LAZY_FETCH` keeps a partial clone from
    /// going to the network for missing blobs.
    public static func run(
        git: TowerGit, repo: String, objectsDirectory: String, base: String, head: String,
        scratchRoot: URL = FileManager.default.temporaryDirectory,
        sandbox: URL = ConflictForecast.sandboxExec
    ) -> MergeForecast {
        let commonDirectory = (objectsDirectory as NSString).deletingLastPathComponent
        if Self.infoAttributesAssignMerge(commonDirectory: commonDirectory) { return .unknown }
        guard FileManager.default.isExecutableFile(atPath: sandbox.path) else { return .unknown }
        let scratch = scratchRoot
            .appendingPathComponent("harbor-forecast-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)) != nil else {
            return .unknown
        }
        defer { try? FileManager.default.removeItem(at: scratch) }
        guard let emptyTree = Self.emptyTree(git: git, repo: repo) else { return .unknown }
        var arguments = ["--attr-source=\(emptyTree)"]
        for driver in Self.configuredMergeDrivers(git: git, repo: repo) {
            arguments += ["-c", "\(driver)=false"]
        }
        arguments += ["merge-tree", "--write-tree", "--name-only", base, head]
        let result = git.run(
            arguments, in: repo,
            environment: [
                "GIT_OBJECT_DIRECTORY": scratch.path,
                "GIT_ALTERNATE_OBJECT_DIRECTORIES": objectsDirectory,
                "GIT_NO_LAZY_FETCH": "1"
            ],
            wrapper: (sandbox, Self.sandboxArguments(allowingWritesTo: scratch.path))
        )
        switch result?.status {
        case 0: return .clean
        case 1:
            // A conflict prints the merged tree's id first; a refused merge (bad revision) prints none.
            let output = result?.stdout ?? ""
            let first = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            guard first.count >= 40, first.allSatisfy(\.isHexDigit) else { return .unknown }
            return .conflicts(TowerGitParse.conflictedFiles(output))
        default: return .unknown
        }
    }

    /// The `sandbox-exec` arguments (before the command): allow everything, then deny every file
    /// write and allow it again only under the scratch directory and on `/dev/null`. The path
    /// goes in as a `-D` parameter, so it needs no escaping in the profile.
    static func sandboxArguments(allowingWritesTo scratch: String) -> [String] {
        [
            "-D", "S=\(Self.realPath(scratch))", "-p",
            "(version 1)(allow default)(deny file-write*)(allow file-write* (subpath (param \"S\")) (literal \"/dev/null\"))"
        ]
    }

    /// `realpath(3)`, which the sandbox needs (`/var` is `/private/var`; `URL.resolvingSymlinksInPath`
    /// strips `/private`). A path that doesn't exist yet is resolved through its nearest parent.
    static func realPath(_ path: String) -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil, let resolved = buffer.withUnsafeBufferPointer({ $0.baseAddress.flatMap { String(validatingCString: $0) } }) {
            return resolved
        }
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent().path
        guard parent != path, parent != "/" else { return path }
        return URL(fileURLWithPath: Self.realPath(parent)).appendingPathComponent(url.lastPathComponent).path
    }

    /// True when `<common dir>/info/attributes` assigns a `merge=` attribute on any line. The
    /// override `-c merge.<name>.driver=false` can't be trusted for those (a name containing `=`
    /// escapes it, and a `false` driver reads as a conflict), so no forecast is made.
    static func infoAttributesAssignMerge(commonDirectory: String) -> Bool {
        let url = URL(fileURLWithPath: commonDirectory).appendingPathComponent("info/attributes")
        guard let data = try? Data(contentsOf: url) else { return false }
        let text = String(bytes: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).contains { line in
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("#") && line.contains("merge=")
        }
    }

    /// The id of the empty tree in the repo's hash algorithm (sha1 or sha256). Computed, not
    /// written: `hash-object` without `-w` stores nothing.
    static func emptyTree(git: TowerGit, repo: String) -> String? {
        guard let out = git.output(["hash-object", "-t", "tree", "/dev/null"], in: repo) else { return nil }
        let id = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.count >= 40 && id.allSatisfy(\.isHexDigit) ? id : nil
    }

    /// `merge.<name>.driver` keys set in the repo's own config.
    static func configuredMergeDrivers(git: TowerGit, repo: String) -> [String] {
        guard let out = git.output(["config", "--name-only", "--get-regexp", "^merge\\..+\\.driver$"], in: repo) else { return [] }
        return out.split(whereSeparator: \.isNewline).map(String.init)
    }
}
