import Foundation

/// What the panel can ask of a local clone. Fetch and switching branches run on one click;
/// everything else moves or rewrites commits and waits for an inline confirm.
public enum LocalGitCommand: Equatable, Sendable {
    case fetch
    case pullFastForward
    case sync
    case rebase
    case reset
    case switchBranch(String)

    public var needsConfirm: Bool {
        switch self {
        case .fetch, .switchBranch: false
        case .pullFastForward, .sync, .rebase, .reset: true
        }
    }

    /// Reset throws away local commits and changes; the confirm says so in red.
    public var isDestructive: Bool { self == .reset }

    public var title: String {
        switch self {
        case .fetch: "Fetch"
        case .pullFastForward: "Pull"
        case .sync: "Sync"
        case .rebase: "Rebase onto upstream"
        case .reset: "Reset to upstream"
        case let .switchBranch(name): "Switch to \(name)"
        }
    }

    public var busyText: String {
        switch self {
        case .fetch: "Fetching…"
        case .pullFastForward: "Pulling…"
        case .sync: "Syncing…"
        case .rebase: "Rebasing…"
        case .reset: "Resetting…"
        case let .switchBranch(name): "Switching to \(name)…"
        }
    }

    /// The sentence asked before running, in the clone's own words.
    public func confirmQuestion(branch: String, upstream: String?) -> String {
        let target = upstream ?? "its upstream"
        switch self {
        case .fetch, .switchBranch: return self.title
        case .pullFastForward: return "Fast-forward \(branch) to \(target)? Refuses if the histories diverged."
        case .sync: return "Sync \(branch)? Pulls with rebase (autostash), then pushes your commits."
        case .rebase: return "Rebase \(branch) onto \(target)? This rewrites your local commits."
        case .reset: return "Reset \(branch) to \(target)? Local commits and uncommitted changes are lost."
        }
    }
}

public extension LocalGitService {
    func perform(_ command: LocalGitCommand, at repoURL: URL) throws {
        switch command {
        case .fetch: try self.fetch(at: repoURL)
        case .pullFastForward: try self.pullFastForwardOnly(at: repoURL)
        case .sync: _ = try self.smartSync(at: repoURL)
        case .rebase: try self.rebaseOntoUpstream(at: repoURL)
        case .reset: try self.hardResetToUpstream(at: repoURL)
        case let .switchBranch(name): try self.switchBranch(at: repoURL, branch: name)
        }
    }
}

// MARK: - Presentation

public extension LocalRepoStatus {
    /// "↑2 ↓3", "in sync", or "no upstream" when git could not count.
    var aheadBehindText: String {
        guard let ahead = self.aheadCount, let behind = self.behindCount else { return "no upstream" }
        if ahead == 0, behind == 0 { return "in sync" }
        var parts: [String] = []
        if ahead > 0 { parts.append("↑\(ahead)") }
        if behind > 0 { parts.append("↓\(behind)") }
        return parts.joined(separator: " ")
    }

    /// "3 changed" or "clean".
    var dirtyText: String {
        if self.isClean { return "clean" }
        if let counts = self.dirtyCounts, !counts.isEmpty {
            return "\(counts.added + counts.modified + counts.deleted) changed"
        }
        return self.dirtyFiles.isEmpty ? "changed" : "\(self.dirtyFiles.count) changed"
    }

    /// The one line under the repo header: "main · 3 changed · ↑1 ↓2".
    var summaryLine: String {
        "\(self.branch) · \(self.dirtyText) · \(self.aheadBehindText)"
    }

    /// Fast-forward is offered only when it cannot lose anything: clean, behind, nothing ahead.
    var canFastForward: Bool {
        self.isClean && (self.behindCount ?? 0) > 0 && (self.aheadCount ?? 0) == 0 && self.branch != "detached"
    }
}
