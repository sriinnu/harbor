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
            if !self.model.uncheckedRepos.isEmpty {
                Text("· \(self.model.uncheckedRepos.count) couldn't check")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
            }
            if self.model.isLoading {
                ProgressView().controlSize(.mini).accessibilityHidden(true)
                Text("reading git…")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
            }
            Spacer()
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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
                        .accessibilityHidden(true)
                    Text("\(lane.title.uppercased())  \(rows.count)")
                        .font(.system(size: self.skin.row.sectionSize, weight: .semibold))
                        .tracking(0.6)
                    Spacer()
                }
                .foregroundStyle(MenuInk.section)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.vertical, 3)
            }
            .accessibilityLabel("\(lane.title), \(rows.count) \(rows.count == 1 ? "worktree" : "worktrees"), \(isOpen ? "expanded" : "collapsed")")
            .accessibilityHint(isOpen ? "Collapses this lane" : "Expands this lane")
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
        let unchecked = self.model.uncheckedRepos.sorted()
        if !unchecked.isEmpty {
            PanelSeparator()
            MenuSectionHeader(title: "Couldn't check · \(unchecked.count)")
            ForEach(unchecked, id: \.self) { path in
                Text("\(URL(fileURLWithPath: path).lastPathComponent): git didn't answer in time")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .accessibilityLabel("\(URL(fileURLWithPath: path).lastPathComponent), couldn't check")
            }
        }
        if !repos.isEmpty {
            if unchecked.isEmpty { PanelSeparator() }
            MenuSectionHeader(title: "Repos · \(repos.count)")
            ForEach(repos) { repo in TowerRepoHeader(repo: repo, model: self.model) }
        } else if !self.model.isLoading, unchecked.isEmpty {
            if self.model.gitMissing {
                Text(TowerCopy.gitMissing)
                    .font(.system(size: 12))
                    .foregroundStyle(self.skin.secondaryText)
                    .padding(12)
            } else {
                self.emptyState
            }
        }
    }
}

extension TowerView {
    /// What Tower is and how it finds worktrees, for a user with none to show yet.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(TowerCopy.emptyTitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(self.skin.text)
            ForEach(TowerCopy.emptyParagraphs, id: \.self) { paragraph in
                Text(paragraph)
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .accessibilityElement(children: .combine)
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
                TowerAgentTag(name: self.row.agentLabel)
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
                // The idle guess grows with the clock, so only this line re-reads it, once a minute
                // and only while the row is on screen. Nothing else in the row depends on the time.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(self.sentence(now: context.date))
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.spokenLabel(self.row))
        .accessibilityHint("Opens this worktree")
    }

    /// One sentence for VoiceOver: who, where, why, how far from main, build and age. The
    /// glyphs (arrows, plus-minus, the build tick) are read as words.
    static func spokenLabel(_ row: TowerRow, now: Date = Date()) -> String {
        var parts = ["\(row.agentLabel), \(row.repoName), \(row.branch ?? "detached")", row.reasonText(now: now)]
        if let text = row.note ?? row.task { parts.append(text) }
        if let ahead = row.ahead, let behind = row.behind, ahead > 0 || behind > 0 {
            parts.append("\(ahead) ahead, \(behind) behind main")
        }
        if let dirty = row.dirty, dirty > 0 { parts.append("\(dirty) uncommitted") }
        switch row.build?.status {
        case "ok": parts.append("build passed")
        case "failed": parts.append("build failed")
        case "building": parts.append("building")
        default: break
        }
        if !row.collisions.isEmpty { parts.append("\(row.collisions.count) files shared with another worktree") }
        if let age = TowerFormat.spokenAge(row.lastActivity, now: now) { parts.append(age) }
        return parts.joined(separator: ", ")
    }

    private var primary: Color { self.isHighlighted ? self.skin.selectionText : self.skin.text }
    private var secondary: Color { self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText }

    private func sentence(now: Date) -> String {
        var parts = [self.row.reasonText(now: now)]
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
    /// `age` as words: "5 minutes ago".
    static func spokenAge(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let (value, unit): (Int, String)
        switch seconds {
        case ..<60: return "active now"
        case ..<3600: (value, unit) = (seconds / 60, "minute")
        case ..<86400: (value, unit) = (seconds / 3600, "hour")
        default: (value, unit) = (seconds / 86400, "day")
        }
        return "\(value) \(unit)\(value == 1 ? "" : "s") ago"
    }

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
