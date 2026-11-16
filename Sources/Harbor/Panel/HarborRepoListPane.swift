import AppKit
import HarborCore
import SwiftUI

/// One list of a repo (issues, pull requests, releases, runs, branches), slid in over the
/// repo detail. Rows open the item in the browser; pull requests open the in-panel pane.
struct HarborRepoListPane: View {
    let model: RepoListModel
    let onBack: () -> Void
    /// Opens a pull request's pane by number.
    var openPull: (Int) -> Void = { _ in }
    /// The list's page on the web (the header's ↗).
    var openWeb: () -> Void = {}
    @Environment(\.harborPanelSkin) private var skin
    @Environment(\.panelMaxHeight) private var maxHeight
    @Environment(\.panelNavigator) private var navigator
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let limit = self.maxHeight - 2 * self.skin.padding
        ScrollView(.vertical, showsIndicators: false) {
            self.content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: { self.contentHeight = $0 })
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: self.contentHeight > 0 ? min(self.contentHeight, limit) : nil)
        .task { await self.model.load() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            self.header
            PanelSeparator()
            switch self.model.state {
            case .loading:
                RepoListSkeleton()
            case let .failed(message):
                self.message(message, color: MenuInk.status(.fail))
                PanelRow(id: "list:retry", action: { Task { await self.model.load() } }) {
                    ListActionLine(title: "Try again", symbol: "arrow.clockwise")
                }
            case let .loaded(page):
                let query = self.navigator?.filter ?? ""
                let rows = NameFilter.filter(page.rows, query: query, name: \.title)
                if !NameFilter.tokens(query).isEmpty {
                    PanelFilterBar(query: query, matches: rows.count)
                }
                if page.rows.isEmpty {
                    self.message(self.model.kind.emptyText, color: self.skin.secondaryText)
                } else if rows.isEmpty {
                    self.message("Nothing matches “\(query)”.", color: self.skin.secondaryText)
                } else {
                    ForEach(rows) { row in self.rowView(row) }
                }
                if let note = page.truncationNote {
                    self.message(note, color: self.skin.tertiaryText)
                }
            }
            PanelSeparator()
            PanelRow(id: "list:web", action: self.openWeb) {
                ListActionLine(title: "Open on the web", symbol: "safari")
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: RepoListRow) -> some View {
        if let number = row.pullNumber {
            PanelRow(id: "list:\(row.id)", showsChevron: true, action: { self.openPull(number) }) {
                RepoListRowView(row: row)
            }
        } else {
            PanelRow(id: "list:\(row.id)", action: { Self.open(row.url) }) {
                RepoListRowView(row: row)
            }
        }
    }

    private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func message(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: self.skin.row.detailSize + 1))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.vertical, 6)
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
            .accessibilityHint("Returns to the repository")
            Text(self.model.kind.title)
                .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                .foregroundStyle(self.skin.text)
            Text("\(self.model.owner)/\(self.model.name)")
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if self.model.state == .loading {
                ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 14, height: 14)
                    .accessibilityLabel("Loading")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
}

/// Mark, title, and a line of facts.
private struct RepoListRowView: View {
    let row: RepoListRow
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            self.mark
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(self.row.title)
                    .font(.system(size: self.skin.row.nameSize, weight: .medium))
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(self.row.subtitle)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 3)
        .frame(minHeight: self.skin.itemHeight + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.spokenKind(self.row.mark)): \(self.row.title), \(self.row.subtitle)")
    }

    /// The mark is an icon or a status lamp, both hidden from VoiceOver: say what it is.
    static func spokenKind(_ mark: RepoListRow.Mark) -> String {
        switch mark {
        case .issue: "Issue"
        case .pull: "Pull request"
        case .draftPull: "Draft pull request"
        case .release: "Release"
        case .prerelease: "Pre-release"
        case .branch: "Branch"
        case .defaultBranch: "Default branch"
        case let .run(status): "Workflow run, \(StatusGlyph.Kind(status).spokenState)"
        }
    }

    @ViewBuilder
    private var mark: some View {
        switch self.row.mark {
        case let .run(status):
            StatusGlyph(kind: StatusGlyph.Kind(status), size: self.skin.row.glyphSize)
        default:
            Image(systemName: self.symbol)
                .font(.system(size: 11))
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.tint)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch self.row.mark {
        case .issue: "smallcircle.filled.circle"
        case .pull: "arrow.triangle.pull"
        case .draftPull: "arrow.triangle.pull"
        case .release: "tag"
        case .prerelease: "tag"
        case .branch: "arrow.triangle.branch"
        case .defaultBranch: "star"
        case .run: "play.circle"
        }
    }

    private var tint: Color {
        switch self.row.mark {
        case .issue, .pull: MenuInk.status(.pass)
        case .draftPull, .branch, .release: self.skin.secondaryText
        case .prerelease: MenuInk.status(.pending)
        case .defaultBranch: self.skin.accent
        case .run: self.skin.secondaryText
        }
    }
}

private struct RepoListSkeleton: View {
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(0 ..< 4, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(self.skin.tertiaryText.opacity(0.25))
                        .frame(width: index.isMultiple(of: 2) ? 250 : 190, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(self.skin.tertiaryText.opacity(0.15))
                        .frame(width: 140, height: 8)
                }
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

struct ListActionLine: View {
    let title: String
    let symbol: String
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: self.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText)
                .accessibilityHidden(true)
            Text(self.title).foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
            Spacer()
        }
        .font(.system(size: self.skin.row.nameSize))
        .padding(.horizontal, self.skin.row.itemPadding)
        .frame(height: self.skin.itemHeight + 2)
    }
}
