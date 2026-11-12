import AppKit
import HarborCore
import SwiftUI

/// One worktree: where it is, what state and why, its ledger timeline, and the ways to open it.
struct TowerDetailView: View {
    let row: TowerRow
    let model: TowerModel
    let actions: HarborPanelActions
    @Environment(\.harborPanelSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PanelRow(id: "tower:back", action: { self.model.openRow = nil }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                    Text("Tower").font(.system(size: self.skin.row.nameSize))
                    Spacer()
                }
                .foregroundStyle(self.skin.accent)
                .padding(.horizontal, self.skin.row.itemPadding)
                .padding(.vertical, 3)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    TowerAgentTag(name: self.row.agent ?? "you")
                    Text("\(self.row.repoName) · \(self.row.branch ?? "detached")")
                        .font(.system(size: self.skin.row.nameSize, weight: .semibold))
                        .foregroundStyle(self.skin.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(self.row.path)
                    .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                    .foregroundStyle(self.skin.secondaryText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                self.fact("State", "\(self.row.lane.title.lowercased()): \(self.row.reason)")
                if let text = self.row.note ?? self.row.task { self.fact("Task", text) }
                self.fact("Session", self.session)
                self.fact("Against main", self.versusMain)
                if let build = self.row.build {
                    self.fact("Build", [build.status, build.version].compactMap { $0 }.joined(separator: " "))
                }
                if let delivered = self.row.delivered {
                    self.fact("Delivered", [delivered.sha.map { String($0.prefix(9)) }, delivered.base].compactMap { $0 }.joined(separator: " on "))
                }
                if case let .conflicts(files) = self.row.forecast {
                    self.fact("Would conflict", files.isEmpty ? "yes" : files.prefix(6).map(TowerFormat.shortPath).joined(separator: ", "))
                }
                if self.row.forecast == .unknown {
                    self.fact("Merge check", "couldn't check")
                }
                if !self.row.collisions.isEmpty {
                    self.fact("Also changed elsewhere", self.row.collisions.prefix(6).map(TowerFormat.shortPath).joined(separator: ", "))
                }
                if let advice = self.row.advice?.decision { self.fact("Advice", advice) }
                self.buttons
                self.timeline
            }
            .padding(.horizontal, self.skin.row.itemPadding)
            .padding(.vertical, 4)
        }
    }

    private var session: String {
        switch self.row.evidence {
        case let .pid(pid): "agent inside (pid \(pid) running)"
        case .window: "agent inside (joined in the last 24h, no running pid to confirm)"
        case nil: "nobody inside"
        }
    }

    private var versusMain: String {
        var parts: [String] = []
        if let ahead = self.row.ahead, let behind = self.row.behind { parts.append("↑\(ahead) ↓\(behind)") }
        if let dirty = self.row.dirty { parts.append(dirty == 0 ? "clean" : "\(dirty) uncommitted") }
        if self.row.isLocked { parts.append("locked") }
        return parts.isEmpty ? "reading…" : parts.joined(separator: " · ")
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.system(size: self.skin.row.detailSize))
                .foregroundStyle(self.skin.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var buttons: some View {
        let url = URL(fileURLWithPath: self.row.path, isDirectory: true)
        return HStack(spacing: 10) {
            self.button("Finder", "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            self.button("Terminal", "terminal") { self.actions.openTerminal(url) }
            if let editor = TowerEditor.application {
                self.button(editor.name, "chevron.left.forwardslash.chevron.right") {
                    NSWorkspace.shared.open([url], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration())
                }
            }
            self.button("Copy path", "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(self.row.path, forType: .string)
            }
        }
        .padding(.vertical, 2)
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: self.skin.row.detailSize, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(self.skin.accent)
    }

    @ViewBuilder
    private var timeline: some View {
        if !self.row.timeline.isEmpty {
            Text("Timeline")
                .font(.system(size: self.skin.row.detailSize, weight: .semibold))
                .foregroundStyle(self.skin.secondaryText)
                .padding(.top, 4)
            ForEach(Array(self.row.timeline.suffix(12).reversed().enumerated()), id: \.offset) { _, entry in
                HStack(spacing: 8) {
                    Text(TowerFormat.age(entry.date) ?? "")
                        .font(.system(size: self.skin.row.detailSize, design: .monospaced))
                        .foregroundStyle(self.skin.tertiaryText)
                        .frame(width: 28, alignment: .trailing)
                    Text([entry.agent, entry.text].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: self.skin.row.detailSize))
                        .foregroundStyle(self.skin.text)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// The editor "Open in editor" uses: the first of these that is installed.
enum TowerEditor {
    static let candidates: [(bundle: String, name: String)] = [
        ("com.microsoft.VSCode", "VS Code"), ("com.todesktop.230313mzl4w4u92", "Cursor"),
        ("dev.zed.Zed", "Zed"), ("com.apple.dt.Xcode", "Xcode")
    ]

    static var application: (url: URL, name: String)? {
        for candidate in self.candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundle) {
                return (url, candidate.name)
            }
        }
        return nil
    }
}
