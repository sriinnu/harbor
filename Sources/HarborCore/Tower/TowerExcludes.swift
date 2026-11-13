import Foundation

/// The user's global ignore file, found without letting the rest of their git config in.
///
/// Tower's git runs with `GIT_CONFIG_GLOBAL=/dev/null`, so `core.excludesFile` in `~/.gitconfig`
/// is lost and files like `.DS_Store` read as uncommitted work. Only the path of the ignore
/// file is taken from the user's config; it is handed to `status` as `-c core.excludesFile=`.
/// Nothing else of the user's config reaches git, and the merge forecast never gets this.
public enum TowerExcludes {
    /// The ignore file git would use for `home`: `core.excludesFile` from `~/.gitconfig`, else
    /// from `$XDG_CONFIG_HOME/git/config`, else `$XDG_CONFIG_HOME/git/ignore` (default
    /// `~/.config/git/ignore`) when that exists. nil when there is none.
    public static func path(
        git: TowerGit, home: String, xdgConfigHome: String? = nil, fileManager: FileManager = .default
    ) -> String? {
        let xdg = (xdgConfigHome?.isEmpty == false ? xdgConfigHome : nil) ?? home + "/.config"
        // `~/.gitconfig` overrides the XDG file, as it does in git itself.
        for config in [home + "/.gitconfig", xdg + "/git/config"] where fileManager.isReadableFile(atPath: config) {
            guard let result = git.run(
                ["config", "--file", config, "--includes", "--get", "core.excludesFile"], in: NSTemporaryDirectory()
            ), result.status == 0 else { continue }
            let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { return Self.expand(value, home: home) }
        }
        let fallback = xdg + "/git/ignore"
        return fileManager.isReadableFile(atPath: fallback) ? fallback : nil
    }

    /// `~/x` against `home`; a relative path is left alone (git resolves it against its own cwd).
    static func expand(_ value: String, home: String) -> String {
        if value == "~" { return home }
        if value.hasPrefix("~/") { return home + String(value.dropFirst(1)) }
        return value
    }

    /// The `status` arguments that honour `file`.
    public static func statusArguments(excludesFile: String?) -> [String] {
        let status = ["status", "--porcelain=v2", "--untracked-files=normal"]
        guard let excludesFile else { return status }
        return ["-c", "core.excludesFile=\(excludesFile)"] + status
    }
}

/// How old `origin/main` is: when the repo last fetched. Read from the files git leaves; Harbor
/// never fetches.
public enum TowerFetchAge {
    /// The newest modification time among `FETCH_HEAD` in the common directory, `FETCH_HEAD` in
    /// every linked worktree's own directory (`<common>/worktrees/<name>/FETCH_HEAD`: a fetch run
    /// inside a worktree writes there, not in the common one) and the base ref's reflog, for a
    /// remote tracking `base` such as `origin/main`. nil for a local base (no fetch applies) and
    /// when none of them exist (never fetched, reflogs off).
    public static func lastFetch(commonDirectory: String, base: String?, fileManager: FileManager = .default) -> Date? {
        guard let base, base.contains("/") else { return nil }
        var files = [commonDirectory + "/FETCH_HEAD"]
        let worktrees = commonDirectory + "/worktrees"
        for name in (try? fileManager.contentsOfDirectory(atPath: worktrees)) ?? [] {
            files.append(worktrees + "/" + name + "/FETCH_HEAD")
        }
        files.append(commonDirectory + "/logs/refs/remotes/" + base)
        return files.compactMap {
            (try? fileManager.attributesOfItem(atPath: $0))?[.modificationDate] as? Date
        }.max()
    }
}

/// The two kinds of the user's global config that a read needs and Tower's isolated git would
/// otherwise lose: `safe.directory` (without it git refuses a repo owned by another user) and
/// `url.<base>.insteadOf` (a remote written as a short alias reads as a different URL, and the
/// pull request lookup keys on the remote). Nothing else of the user's config comes through, and
/// the merge forecast is never given these.
public enum TowerGlobalConfig {
    /// `-c key=value` pairs for `~/.gitconfig` then `$XDG_CONFIG_HOME/git/config`, as git
    /// reads them (the XDG file first, so the home file's entries come last).
    public static func arguments(
        git: TowerGit, home: String, xdgConfigHome: String? = nil, fileManager: FileManager = .default
    ) -> [String] {
        let xdg = (xdgConfigHome?.isEmpty == false ? xdgConfigHome : nil) ?? home + "/.config"
        var result: [String] = []
        for config in [xdg + "/git/config", home + "/.gitconfig"] where fileManager.isReadableFile(atPath: config) {
            guard let out = git.run(
                ["config", "--file", config, "--includes", "-z", "--get-regexp", "^(safe\\.directory|url\\..+\\.insteadof)$"],
                in: NSTemporaryDirectory()
            ), out.status == 0 else { continue }
            result += Self.pairs(nullSeparated: out.stdout)
        }
        return result
    }

    /// `key\nvalue\0` records of `git config -z`, as `-c key=value` arguments. A key holding `=`
    /// can't be written as `-c` and is skipped.
    static func pairs(nullSeparated raw: String) -> [String] {
        var result: [String] = []
        for record in raw.split(separator: "\0", omittingEmptySubsequences: true) {
            let parts = record.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first, !key.contains("=") else { continue }
            result += ["-c", "\(key)=\(parts.count == 2 ? parts[1] : "")"]
        }
        return result
    }
}
