import HarborCore
import SwiftUI

/// A repo's line in the Tower: how many worktrees, the "main moved" forecast, the collision
/// list, and the retire queue.
struct TowerRepoHeader: View {
    let repo: TowerRepoSnapshot
    let model: TowerModel
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(self.repo.name)
                    .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                    .foregroundStyle(self.skin.text)
                Text("\(self.repo.rows.count) worktrees" + (self.repo.base.map { " · vs \($0)" } ?? ""))
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .lineLimit(1)
                Spacer()
            }
            if let fetched = self.repo.fetchText() {
                Text(fetched)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
                    .lineLimit(1)
            }
            if let moved = self.repo.mainMovedText {
                Text(moved)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.repo.mainMoved?.wouldConflict ?? 0 > 0 ? self.skin.warn.text : self.skin.secondaryText)
            } else if self.repo.phase != .forecast {
                Text("checking forecast…")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
            }
            ForEach(self.repo.collisions.prefix(5), id: \.file) { collision in
                Text("\(collision.file) is changed in \(collision.worktrees.count) worktrees: \(Self.names(collision))")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.warn.text)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            if self.repo.collisions.count > 5 {
                Text("+\(self.repo.collisions.count - 5) more shared files")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
            }
            TowerRetireView(repo: self.repo.path, model: self.model)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private static func names(_ collision: FileCollision) -> String {
        collision.worktrees.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
    }
}

/// The retire queue for one repo. Read-only until the last button: the audit and the dry run
/// change nothing; "Retire" runs the skill's `wtr_retire.py` with `--execute` after a confirm
/// that names the exact path.
struct TowerRetireView: View {
    let repo: String
    let model: TowerModel
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch self.model.retire[self.repo]?.phase {
            case nil:
                self.link("Retire queue…", help: "Run the read-only audit and list worktrees it calls CANDIDATE") {
                    self.model.runAudit(repo: self.repo)
                }
            case .auditing:
                self.busy("Auditing (read-only, can take a few seconds)…")
            case let .listed(candidates):
                self.listed(candidates)
            case let .running(_, candidate, execute):
                self.busy(execute ? "Retiring \(candidate.path)…" : "Dry run for \(candidate.path)…")
            case let .confirming(_, candidate, output, ok):
                self.confirming(candidate, output: output, ok: ok)
            case let .finished(output, ok):
                self.output(output, color: ok ? self.skin.text : MenuInk.status(.fail))
                self.link("OK") { self.model.cancelRetire(repo: self.repo) }
            case let .failed(message):
                self.output(message, color: MenuInk.status(.fail))
                self.link("OK") { self.model.cancelRetire(repo: self.repo) }
            }
        }
        .padding(.top, 2)
    }

    private func listed(_ candidates: [RetireCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(candidates.isEmpty ? "No retire candidates." : "Retire candidates · \(candidates.count)")
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
            ForEach(candidates) { candidate in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(candidate.branch ?? (candidate.path as NSString).lastPathComponent)
                            .font(.system(size: self.skin.row.nameSize))
                            .foregroundStyle(self.skin.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(candidate.delivery ?? "delivered")
                            .font(.system(size: self.skin.row.detailSize))
                            .foregroundStyle(self.skin.secondaryText)
                    }
                    Spacer()
                    self.link(
                        "Dry run…", help: "Shows what retiring this worktree would do. Changes nothing.",
                        spoken: "Dry run for \(candidate.branch ?? (candidate.path as NSString).lastPathComponent)"
                    ) {
                        self.model.dryRun(repo: self.repo, candidate: candidate)
                    }
                }
            }
            self.link("Close") { self.model.cancelRetire(repo: self.repo) }
        }
    }

    private func confirming(_ candidate: RetireCandidate, output: String, ok: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Dry run, nothing changed yet:")
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
            self.output(output, color: ok ? self.skin.text : MenuInk.status(.fail))
            if ok {
                Text("Retire \(candidate.path)? This removes the worktree folder and keeps the branch.")
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.skin.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if ok {
                    Button("Retire") { self.model.execute(repo: self.repo) }
                        .buttonStyle(PanelPrimaryButtonStyle())
                        .accessibilityLabel("Retire \(candidate.path)")
                        .accessibilityHint("Removes the worktree folder and keeps the branch")
                }
                self.link("Cancel") { self.model.cancelRetire(repo: self.repo) }
            }
        }
    }

    private func output(_ text: String, color: Color) -> some View {
        ScrollView {
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 140)
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini).accessibilityHidden(true)
            Text(text)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private func link(_ title: String, help: String? = nil, spoken: String? = nil, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: self.skin.row.detailSize, weight: .medium))
            .foregroundStyle(self.skin.accent)
            .help(help ?? title)
            .accessibilityLabel(spoken ?? title.replacingOccurrences(of: "…", with: ""))
            .accessibilityHint(help ?? "")
    }
}
