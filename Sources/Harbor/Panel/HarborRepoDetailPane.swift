import HarborCore
import SwiftUI

/// A repo's detail, slid in over the list: what used to be its submenu.
struct HarborRepoDetailPane: View {
    let repo: RepositoryDisplayModel
    /// This repo's commit strip; nil hides it (no commits, or the lookup failed).
    var activity: PanelActivity?
    var activityNote: String?
    let isPinned: Bool
    let actions: HarborPanelActions
    let onBack: () -> Void
    /// Opens a pull request's pane by number.
    var openPull: (Int) -> Void = { _ in }
    /// Opens one of this repo's lists (issues, pull requests, ...) as a pane.
    var openList: (RepoListKind) -> Void = { _ in }
    /// This clone's Git actions; nil when the repo has no local clone.
    var localGit: LocalGitModel?
    @Environment(\.harborPanelSkin) private var skin
    /// This repo's linked worktrees, loaded when the detail opens. In memory only.
    @State private var worktrees: AgentWorktreeSnapshot?
    /// Health, security, hardening and flow, loaded when the detail opens. In memory only.
    @State private var health = RepoHealthModel()
    /// "Clean up old runs…", for this repo only. In memory only.
    @State private var cleanup = RunCleanupModel()
    @State private var contentHeight: CGFloat = 0
    @Environment(\.panelMaxHeight) private var maxHeight
    @State private var titleHovered = false

    var body: some View {
        // Scrolls inside the panel's tallest height; the panel's own padding comes off it.
        let limit = self.maxHeight - 2 * self.skin.padding
        ScrollView(.vertical, showsIndicators: false) {
            self.content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.contentHeight = $0 })
        }
        .frame(height: self.contentHeight > 0 ? min(self.contentHeight, limit) : limit)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            PanelSeparator()
            if let local = self.repo.localStatus, let localGit {
                HarborLocalGitSection(model: localGit, status: local, openTerminal: self.actions.openTerminal)
                PanelSeparator()
            }
            HarborRepoHealthView(
                model: self.health,
                cleanup: self.cleanup,
                repo: self.repo,
                open: { self.actions.openRepoPath(self.repo, $0) },
                openPull: self.openPull
            )
            if let activity {
                PanelActivitySection(
                    activity: activity,
                    title: "Commits",
                    selectRange: self.actions.selectActivityRange
                )
                PanelSeparator()
            } else if let note = self.activityNote {
                Text("Commit activity unavailable · \(note)")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .lineLimit(2)
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .padding(.bottom, 4)
                PanelSeparator()
            }
            PanelTrafficSection(traffic: self.repo.source.traffic)
            PanelSeparator()
            self.listRow(.pulls, symbol: "arrow.triangle.pull", value: "\(self.repo.pulls)")
            self.listRow(.issues, symbol: "smallcircle.filled.circle", value: "\(self.repo.issues)")
            self.listRow(.releases, symbol: "tag", value: self.repo.source.latestRelease?.tag ?? "–")
            self.listRow(.runs, symbol: "play.circle", value: self.ciLabel)
            self.listRow(.branches, symbol: "arrow.triangle.branch", value: self.repo.localStatus?.branch ?? "")
            if let alerts = self.repo.source.security?.openAlertCount, alerts > 0 {
                self.link("Security alerts", symbol: "exclamationmark.shield", value: "\(alerts)", path: "security")
            }
            PanelSeparator()
            if let worktrees, worktrees.total > 0 {
                HarborWorktreesSection(snapshot: worktrees, openTerminal: self.actions.openTerminal)
                PanelSeparator()
            }
            PanelRow(id: "detail:web", action: { self.actions.openRepo(self.repo) }) {
                DetailLine(title: "Open on the web", symbol: "safari", value: nil)
            }
            PanelRow(id: "detail:pin", action: { self.actions.togglePin(self.repo, !self.isPinned) }) {
                DetailLine(title: self.isPinned ? "Unpin" : "Pin", symbol: self.isPinned ? "pin.slash" : "pin", value: nil)
            }
        }
        .task(id: self.repo.localStatus?.path) { await self.loadWorktrees() }
        .task(id: self.repo.title) { await self.health.load(fullName: self.repo.title) }
    }

    /// Off the main thread; a repo with no local clone has no section.
    private func loadWorktrees() async {
        guard let path = self.repo.localStatus?.path else {
            self.worktrees = nil
            return
        }
        let snapshot = await Task.detached(priority: .utility) {
            AgentWorktreeLoader().load(repoURL: path)
        }.value
        guard !Task.isCancelled else { return }
        self.worktrees = snapshot
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: self.onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(self.skin.accent)
            .accessibilityLabel("Back")
            StatusGlyph(kind: StatusGlyph.Kind(self.repo.ciStatus), size: self.skin.row.glyphSize)
            Button { self.actions.openRepo(self.repo) } label: {
                Text(self.repo.title)
                    .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                    .underline(self.titleHovered)
                    .foregroundStyle(self.titleHovered ? self.skin.accent : self.skin.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .onHover { self.titleHovered = $0 }
            .help("Open \(self.repo.title) on the web")
            .accessibilityLabel("Open \(self.repo.title) on the web")
            if let tag = self.repo.source.latestRelease?.tag { ReleasePlate(tag: tag) }
            Spacer(minLength: 4)
            self.count(symbol: "star", value: self.repo.stars, label: "stars")
            self.count(symbol: "tuningfork", value: self.repo.forks, label: "forks")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func count(symbol: String, value: Int, label: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(value.formatted()).monospacedDigit()
        }
        .font(.system(size: self.skin.row.detailSize))
        .foregroundStyle(self.skin.secondaryText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }

    private var ciLabel: String {
        switch self.repo.ciStatus {
        case .passing: "Passing"
        case .failing: "Failing"
        case .pending: "Running"
        case .unknown: "No CI"
        }
    }

    private func listRow(_ kind: RepoListKind, symbol: String, value: String) -> some View {
        PanelRow(id: "detail:\(kind.webPath)", showsChevron: true, action: { self.openList(kind) }) {
            DetailLine(title: kind.title, symbol: symbol, value: value)
        }
    }

    private func link(_ title: String, symbol: String, value: String, path: String) -> some View {
        PanelRow(id: "detail:\(path)", action: { self.actions.openRepoPath(self.repo, path) }) {
            DetailLine(title: title, symbol: symbol, value: value)
        }
    }
}

private struct DetailLine: View {
    let title: String
    let symbol: String
    let value: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
            Text(self.title)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            Spacer()
            if let value {
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
            }
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight + 2)
    }
}
