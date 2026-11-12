import AppKit
import HarborCore
import SwiftUI

/// "Worktrees · N" in a repo's detail: the linked worktrees, who made them, and what state
/// they are in. A row opens the worktree in Terminal; the folder button reveals it in Finder.
struct HarborWorktreesSection: View {
    let snapshot: AgentWorktreeSnapshot
    let openTerminal: (URL) -> Void
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Worktrees · \(self.snapshot.total)")
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.bottom, 2)
            ForEach(self.snapshot.shown) { worktree in
                HStack(spacing: 0) {
                    PanelRow(id: "detail:wt:\(worktree.id)", action: { self.openTerminal(worktree.path) }) {
                        WorktreeLine(worktree: worktree)
                    }
                    Button(action: { Self.reveal(worktree.path) }) {
                        Image(systemName: "folder")
                            .font(.system(size: 11))
                            .foregroundStyle(self.skin.secondaryText)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                    .accessibilityLabel("Reveal \(worktree.path.lastPathComponent) in Finder")
                }
                .contextMenu {
                    Button("Reveal in Finder") { Self.reveal(worktree.path) }
                    Button("Open in Terminal") { self.openTerminal(worktree.path) }
                }
            }
            if self.snapshot.hiddenCount > 0 {
                Text("+\(self.snapshot.hiddenCount) more")
                    .font(.system(size: self.skin.row.detailSize))
                    .foregroundStyle(self.skin.tertiaryText)
                    .padding(.horizontal, self.skin.row.itemPadding)
                    .padding(.top, 2)
            }
        }
    }

    private static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private struct WorktreeLine: View {
    let worktree: AgentWorktree
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                AgentBadge(name: self.worktree.agent ?? "you")
                Text(self.worktree.branch ?? "detached")
                    .font(.system(size: self.skin.row.nameSize))
                    .foregroundStyle(self.isHighlighted ? self.skin.selectionText : self.skin.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if self.worktree.isLive {
                    Circle()
                        .fill(self.isHighlighted ? self.skin.selectionText : self.skin.ok.text)
                        .frame(width: 6, height: 6)
                        .help("An agent is working here now")
                        .accessibilityLabel("Live")
                }
                Spacer(minLength: 4)
                if let age = Self.age(self.worktree.lastActivity) {
                    Text(age)
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.secondary)
                }
            }
            Text(self.detail)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, self.skin.row.itemPadding)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private var secondary: Color {
        self.isHighlighted ? self.skin.selectionText : self.skin.secondaryText
    }

    private var detail: String {
        Self.detailLine(self.worktree)
    }

    static func detailLine(_ worktree: AgentWorktree) -> String {
        var parts: [String] = []
        if let note = worktree.note ?? worktree.task { parts.append(note) }
        if worktree.isPrunable {
            parts.append("missing on disk")
        } else if let dirty = worktree.dirtyCount {
            parts.append(dirty == 0 ? "clean" : "\(dirty) changed")
        }
        if let ahead = worktree.ahead, let behind = worktree.behind, ahead > 0 || behind > 0 {
            parts.append("↑\(ahead) ↓\(behind)")
        }
        if worktree.isLocked { parts.append("locked") }
        return parts.joined(separator: " · ")
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

/// The agent's name in the panel's tag styling: the row style's tag metrics and the skin's
/// segment colors.
private struct AgentBadge: View {
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
            .background(
                RoundedRectangle(cornerRadius: self.rowStyle.tagRadius)
                    .fill(self.isHighlighted ? Color.clear : self.skin.segmentFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: self.rowStyle.tagRadius)
                    .strokeBorder(self.isHighlighted ? text.opacity(0.4) : (self.skin.segmentEdge?.color ?? .clear), lineWidth: 1)
            )
            .accessibilityLabel("Agent \(self.name)")
    }
}
