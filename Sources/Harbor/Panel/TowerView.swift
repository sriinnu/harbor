import AppKit
import HarborCore
import SwiftUI

/// The Tower tab: every agent worktree across repos, in lanes, one row each. Local data only;
/// rows appear as soon as git lists them and fill in as counts, status and forecasts arrive.
struct TowerView: View {
    let model: TowerModel
    let actions: HarborPanelActions
    @Environment(\.harborPanelSkin) private var skin
    @State private var expanded: Set<TowerLane> = [.needsYou, .working, .ready, .inReview]
    private static let leftoversCap = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = self.model.openRow, let row = self.model.row(id: id) {
                TowerDetailView(row: row, model: self.model, actions: self.actions)
            } else {
                self.summary
                if self.model.forecastNeedsNewerGit {
                    Text(TowerCopy.gitTooOld)
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.skin.tertiaryText)
                        .padding(.horizontal, self.skin.row.itemPadding)
                }
                ForEach(TowerLane.allCases, id: \.self) { lane in self.laneSection(lane) }
                self.repoSection
            }
        }
        .pinsPanelOpen(PanelPin.towerRetire, while: self.model.retirePending)
        .pinsPanelOpen(PanelPin.towerExecuting, while: self.model.retireExecuting)
    }

    private var summary: some View {
        let count = { (lane: TowerLane) in self.model.rows(in: lane).count }
        var parts = ["\(count(.working)) working", "\(count(.needsYou)) need you", "\(count(.ready)) ready"]
        if count(.inReview) > 0 { parts.append("\(count(.inReview)) in review") }
        return HStack(spacing: 6) {
            Text(parts.joined(separator: " · "))
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.secondaryText)
            if self.model.isLoading {
                ProgressView().controlSize(.mini)
                Text("reading git…")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
            }
            Spacer()
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func laneSection(_ lane: TowerLane) -> some View {
        let rows = self.model.rows(in: lane)
        if !rows.isEmpty {
            let isOpen = self.expanded.contains(lane)
            PanelRow(id: "tower:lane:\(lane.rawValue)", action: { self.toggle(lane) }) {
                HStack(spacing: 5) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .frame(width: 10)
                    Text("\(lane.title.uppercased())  \(rows.count)")
                        .font(.system(size: self.skin.row.sectionSize, weight: .semibold))
                        .tracking(0.6)
                    Spacer()
                }
                .foregroundStyle(MenuInk.section)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.vertical, 3)
            }
            .accessibilityLabel("\(lane.title), \(rows.count), \(isOpen ? "expanded" : "collapsed")")
            if isOpen {
                let shown = lane == .leftovers ? Array(rows.prefix(Self.leftoversCap)) : rows
                ForEach(shown) { row in
                    PanelRow(id: "tower:row:\(row.id)", showsChevron: true, action: { self.model.openRow = row.id }) {
                        TowerRowLine(row: row)
                    }
                }
                if shown.count < rows.count {
                    Text("+\(rows.count - shown.count) more")
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.skin.tertiaryText)
                        .padding(.horizontal, self.skin.row.itemPadding)
                }
            }
        }
    }

    private func toggle(_ lane: TowerLane) {
        if self.expanded.contains(lane) { self.expanded.remove(lane) } else { self.expanded.insert(lane) }
    }

    // MARK: - repos

    @ViewBuilder
    private var repoSection: some View {
        let repos = self.model.repos.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if !repos.isEmpty {
            PanelSeparator()
            MenuSectionHeader(title: "Repos · \(repos.count)")
            ForEach(repos) { repo in TowerRepoHeader(repo: repo, model: self.model) }
        } else if !self.model.isLoading {
            Text(self.model.gitMissing ? TowerCopy.gitMissing : TowerCopy.noRepos)
                .font(.system(size: 12))
                .foregroundStyle(self.skin.secondaryText)
                .padding(12)
        }
    }
}

// MARK: - row

struct TowerRowLine: View {
    let row: TowerRow
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                TowerAgentTag(name: self.row.agent ?? "you")
                Text("\(self.row.repoName) · \(self.row.branch ?? "detached")")
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                self.counts
                self.buildMark
                if let age = TowerFormat.age(self.row.lastActivity) {
                    Text(age)
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.secondary)
                        .frame(minWidth: 22, alignment: .trailing)
                }
            }
            HStack(spacing: 6) {
                Text(self.sentence)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !self.row.collisions.isEmpty {
                    Text("\(min(self.row.collisions.count, 99))\(self.row.collisions.count > 99 ? "+" : "") shared")
                        .font(.system(size: self.skin.row.detailSize - 1, weight: .semibold))
                        .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.warn.text)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(self.isHighlighted ? Color.clear : self.skin.warn.fill))
                        .help("Files also changed in another live worktree of this repo")
                }
            }
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var primary: Color { self.isHighlighted ? self.skin.selectionText : self.skin.text }
    private var secondary: Color { self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText }

    private var sentence: String {
        var parts = [self.row.reason]
        if let text = self.row.note ?? self.row.task { parts.append(text) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var counts: some View {
        if let ahead = self.row.ahead, let behind = self.row.behind, ahead > 0 || behind > 0 {
            Text("↑\(ahead) ↓\(behind)")
                .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                .foregroundStyle(self.secondary)
        }
        if let dirty = self.row.dirty, dirty > 0 {
            Text("±\(dirty)")
                .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                .foregroundStyle(self.secondary)
        }
    }

    @ViewBuilder
    private var buildMark: some View {
        switch self.row.build?.status {
        case "ok": Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(self.markColor(.pass))
        case "failed": Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(self.markColor(.fail))
        case "building": Image(systemName: "circle.dotted").font(.system(size: 9)).foregroundStyle(self.markColor(.pending))
        default: EmptyView()
        }
    }

    private func markColor(_ kind: StatusGlyph.Kind) -> Color {
        self.isHighlighted ? self.skin.selectionText : MenuInk.status(kind)
    }
}

struct TowerAgentTag: View {
    let name: String
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.menuRowStyle) private var rowStyle
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        let text = self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText
        Text(self.name)
            .font(.system(size: self.rowStyle.tagSize, weight: self.rowStyle.tagWeight, design: .monospaced))
            .foregroundStyle(text)
            .lineLimit(1)
            .padding(.horizontal, self.rowStyle.tagPaddingX)
            .padding(.vertical, 0.5)
            .background(RoundedRectangle(cornerRadius: self.rowStyle.tagRadius).fill(self.isHighlighted ? Color.clear : self.skin.segmentFill))
            .overlay(
                RoundedRectangle(cornerRadius: self.rowStyle.tagRadius)
                    .strokeBorder(self.isHighlighted ? text.opacity(0.4) : (self.skin.segmentEdge?.color ?? .clear), lineWidth: 1)
            )
            .accessibilityLabel("Agent \(self.name)")
    }
}

enum TowerFormat {
    /// The last two path components: enough to tell files apart in a narrow panel.
    static func shortPath(_ path: String) -> String {
        let parts = path.split(separator: "/")
        return parts.count <= 2 ? path : "…/" + parts.suffix(2).joined(separator: "/")
    }

    static func age(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }
}
